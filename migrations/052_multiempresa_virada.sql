-- ============================================================
-- HUB — 052: A VIRADA — isolamento por workspace (ETAPA 3 de 3)
--
-- ⚠️ DRAFT — NÃO APLICAR. Só depois do /grill-me de banco e com janela
-- combinada com ela (é a única etapa que muda comportamento). Testada só
-- em PGlite, com 2 workspaces — ver tests/multi-empresa/.
--
-- A ideia em 1 parágrafo: as ~65 RPCs existentes continuam iguais. O que
-- muda é QUEM elas são no banco. Hoje são SECURITY DEFINER do `postgres`,
-- que tem BYPASSRLS — a RLS não vale dentro delas, e a única trava é o
-- `if not hub.is_admin()` (e-mail chumbado). Aqui elas passam a pertencer
-- ao papel `hub_rpc`, que NÃO tem BYPASSRLS. A partir daí toda leitura e
-- escrita dentro de qualquer RPC passa pela RLS por workspace, sem
-- reescrever uma por uma. `hub.is_admin()` vira "tem workspace válido
-- nesta requisição"; o papel (Dono/Operador/Consulta) é cobrado pela RLS
-- de escrita.
--
-- Pro uso dela não muda nada: ela é dono do único workspace que tem, o
-- workspace é resolvido sozinho, e as automações sem canal caem no
-- workspace 1 (compat, sai na etapa 5 — docs §8).
-- Reverter: migrations/rollback/052_down.sql
-- ============================================================

-- ---------- 0) trava: 050 e 051 precisam ter rodado ----------
do $$
begin
  if to_regclass('hub.workspace_membros') is null then raise exception '052 exige 050'; end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema='hub' and table_name='recebiveis' and column_name='workspace_id') then
    raise exception '052 exige 051';
  end if;
  if not exists (select 1 from hub.workspace_membros m join hub.workspaces w on w.id=m.workspace_id
                 where w.slug='luhpanda' and m.papel='dono' and m.ativo) then
    raise exception '052: workspace 1 sem dono ativo — ela ficaria trancada fora';
  end if;
end $$;

-- ---------- 1) papel dono das RPCs, sem BYPASSRLS ----------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'hub_rpc') then
    create role hub_rpc nologin noinherit nobypassrls;
  end if;
end $$;
-- postgres precisa poder "virar" hub_rpc pra transferir a posse (PG16+)
grant hub_rpc to postgres with set true;
grant usage on schema hub to hub_rpc;
grant usage on schema extensions to hub_rpc;
grant select, insert, update, delete on all tables in schema hub to hub_rpc;
grant usage, select on all sequences in schema hub to hub_rpc;
grant execute on all functions in schema hub to hub_rpc;
grant usage on schema auth to hub_rpc;

-- ---------- 2) unicidade passa a ser POR workspace ----------
-- (o mesmo telefone/slug pode existir em 2 empresas assinantes)
alter table hub.clientes        drop constraint clientes_slug_key,
                                add constraint clientes_ws_slug_key unique (workspace_id, slug);
alter table hub.servicos        drop constraint servicos_slug_key,
                                add constraint servicos_ws_slug_key unique (workspace_id, slug);
alter table hub.conversas       drop constraint conversas_fone_norm_key,
                                add constraint conversas_ws_fone_norm_key unique (workspace_id, fone_norm);
alter table hub.mensagens       drop constraint mensagens_evolution_msg_id_key,
                                add constraint mensagens_ws_evolution_msg_id_key unique (workspace_id, evolution_msg_id);
alter table hub.cobranca_mensagens drop constraint cobranca_mensagens_etapa_key,
                                add constraint cobranca_mensagens_ws_etapa_key unique (workspace_id, etapa);
alter table hub.eventos_agenda  drop constraint eventos_agenda_google_event_id_key,
                                add constraint eventos_agenda_ws_google_event_id_key unique (workspace_id, google_event_id);
alter table hub.reunioes        drop constraint reunioes_meetily_meeting_id_key,
                                add constraint reunioes_ws_meetily_meeting_id_key unique (workspace_id, meetily_meeting_id);
alter table hub.config          drop constraint config_pkey,
                                add constraint config_pkey primary key (workspace_id, chave);
-- docuseal_submission_id continua global: é por ele que o webhook ACHA o workspace.

-- ---------- 3) as 5 RPCs com ON CONFLICT na chave que mudou ----------
-- Texto idêntico ao de produção (lido em 07/10), só troca a lista do
-- ON CONFLICT pra incluir workspace_id. rpc_registrar_mensagem ganha a
-- leitura opcional de p->>'instancia'.
CREATE OR REPLACE FUNCTION hub.rpc_registrar_mensagem(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_direcao text;
  v_corpo text;
  v_tipo text;
  v_enviada_em timestamptz;
  v_eh_grupo boolean;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  -- multi-empresa (052): a automação diz de qual instância veio; sem isso,
  -- cai no workspace 1 (compat da etapa 3).
  if p ? 'instancia' then
    perform hub.ingestor_definir_workspace('evolution_instancia', p->>'instancia');
  end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  if not hub.fone_no_crm(v_fone) then
    return null;
  end if;

  v_direcao := coalesce(p->>'direcao', 'entrada');
  v_corpo := p->>'corpo';
  v_tipo := coalesce(p->>'tipo', 'texto');
  v_enviada_em := coalesce((p->>'enviada_em')::timestamptz, now());
  v_eh_grupo := coalesce((p->>'eh_grupo')::boolean, false);

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao, eh_grupo)
  values (
    v_fone,
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid,
    p->>'nome_exibicao',
    v_eh_grupo
  )
  on conflict (workspace_id, fone_norm) do update set
    prospect_id   = coalesce(excluded.prospect_id, hub.conversas.prospect_id),
    cliente_id    = coalesce(excluded.cliente_id, hub.conversas.cliente_id),
    nome_exibicao = coalesce(excluded.nome_exibicao, hub.conversas.nome_exibicao)
  returning id into v_conversa_id;

  insert into hub.mensagens (
    conversa_id, direcao, corpo, tipo, transcrito, enviada_em, evolution_msg_id,
    remetente_fone, remetente_nome
  )
  values (
    v_conversa_id, v_direcao, v_corpo, v_tipo,
    coalesce((p->>'transcrito')::boolean, false),
    v_enviada_em,
    p->>'evolution_msg_id',
    p->>'remetente_fone', p->>'remetente_nome'
  )
  on conflict (workspace_id, evolution_msg_id) do nothing
  returning id into v_msg_id;

  if v_msg_id is not null then
    update hub.conversas
    set ultima_msg_em = v_enviada_em,
        ultima_msg_previa = left(coalesce(v_corpo, '[' || v_tipo || ']'), 200),
        ultima_msg_direcao = v_direcao
    where id = v_conversa_id;
  end if;

  return v_conversa_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_eventos_agenda_vincular(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_google_id text;
  v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_google_id := nullif(btrim(coalesce(p->>'google_event_id', '')), '');
  if v_google_id is null then raise exception 'google_event_id é obrigatório'; end if;

  insert into hub.eventos_agenda (google_event_id, cliente_id, prospect_id, criado_por)
  values (
    v_google_id,
    (p->>'cliente_id')::uuid,
    (p->>'prospect_id')::uuid,
    coalesce(p->>'criado_por', 'hub')
  )
  on conflict (workspace_id, google_event_id) do update set
    cliente_id  = excluded.cliente_id,
    prospect_id = excluded.prospect_id
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_enfileirar_saida(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_corpo text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;
  v_corpo := p->>'corpo';

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao, eh_grupo)
  values (
    v_fone, (p->>'prospect_id')::uuid, (p->>'cliente_id')::uuid, p->>'nome_exibicao',
    coalesce((p->>'eh_grupo')::boolean, false)
  )
  on conflict (workspace_id, fone_norm) do update set
    prospect_id = coalesce(excluded.prospect_id, hub.conversas.prospect_id),
    cliente_id  = coalesce(excluded.cliente_id, hub.conversas.cliente_id)
  returning id into v_conversa_id;

  insert into hub.mensagens (conversa_id, direcao, corpo, tipo, status)
  values (v_conversa_id, 'saida', v_corpo, coalesce(p->>'tipo', 'texto'), 'enviando')
  returning id into v_msg_id;

  update hub.conversas
  set ultima_msg_em = now(),
      ultima_msg_previa = left(coalesce(v_corpo, ''), 200),
      ultima_msg_direcao = 'saida'
  where id = v_conversa_id;

  return v_msg_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_criar_rascunho_reuniao_agenda(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_google_id text;
  v_mid text;
  v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_google_id := nullif(btrim(coalesce(p->>'google_event_id', '')), '');
  if v_google_id is null then raise exception 'google_event_id é obrigatório'; end if;
  v_mid := 'agenda-' || v_google_id;

  insert into hub.reunioes (meetily_meeting_id, titulo, realizada_em, prospect_id, cliente_id)
  values (
    v_mid,
    nullif(btrim(coalesce(p->>'titulo', '')), ''),
    (p->>'realizada_em')::timestamptz,
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid
  )
  on conflict (workspace_id, meetily_meeting_id) do nothing
  returning id into v_id;

  if v_id is null then
    select r.id into v_id from hub.reunioes r where r.meetily_meeting_id = v_mid;
  end if;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_registrar_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_ok boolean;
  v_mid text;
  v_id uuid;
begin
  v_ok := coalesce(hub.check_bot_secret(p->>'secret'), false) or hub.is_ingestor();
  p := p - 'secret';
  if not v_ok then raise exception 'acesso negado'; end if;

  v_mid := nullif(btrim(coalesce(p->>'meetily_meeting_id', '')), '');
  if v_mid is null then
    raise exception 'meetily_meeting_id é obrigatório';
  end if;

  insert into hub.reunioes (
    meetily_meeting_id, titulo, realizada_em,
    transcricao, resumo, key_points, action_items,
    prospect_id, cliente_id
  )
  values (
    v_mid,
    nullif(btrim(coalesce(p->>'titulo', '')), ''),
    (p->>'realizada_em')::timestamptz,
    nullif(p->>'transcricao', ''),
    nullif(p->>'resumo', ''),
    nullif(p->>'key_points', ''),
    nullif(p->>'action_items', ''),
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid
  )
  on conflict (workspace_id, meetily_meeting_id) do update set
    titulo       = coalesce(excluded.titulo,       hub.reunioes.titulo),
    realizada_em = coalesce(excluded.realizada_em, hub.reunioes.realizada_em),
    transcricao  = coalesce(excluded.transcricao,  hub.reunioes.transcricao),
    resumo       = coalesce(excluded.resumo,       hub.reunioes.resumo),
    key_points   = coalesce(excluded.key_points,   hub.reunioes.key_points),
    action_items = coalesce(excluded.action_items, hub.reunioes.action_items),
    prospect_id  = coalesce(hub.reunioes.prospect_id, excluded.prospect_id),
    cliente_id   = coalesce(hub.reunioes.cliente_id,  excluded.cliente_id)
  where
    hub.reunioes.titulo       is distinct from coalesce(excluded.titulo,       hub.reunioes.titulo)
    or hub.reunioes.realizada_em is distinct from coalesce(excluded.realizada_em, hub.reunioes.realizada_em)
    or hub.reunioes.transcricao  is distinct from coalesce(excluded.transcricao,  hub.reunioes.transcricao)
    or hub.reunioes.resumo       is distinct from coalesce(excluded.resumo,       hub.reunioes.resumo)
    or hub.reunioes.key_points   is distinct from coalesce(excluded.key_points,   hub.reunioes.key_points)
    or hub.reunioes.action_items is distinct from coalesce(excluded.action_items, hub.reunioes.action_items)
    or hub.reunioes.prospect_id  is distinct from coalesce(hub.reunioes.prospect_id, excluded.prospect_id)
    or hub.reunioes.cliente_id   is distinct from coalesce(hub.reunioes.cliente_id,  excluded.cliente_id)
  returning id into v_id;

  if v_id is null then
    select r.id into v_id from hub.reunioes r where r.meetily_meeting_id = v_mid;
  end if;

  return v_id;
end;
$function$
;

-- ---------- 4) helpers que mudam de sentido ----------
-- is_admin(): "tem workspace válido nesta requisição" (qualquer papel).
-- Escrita de Consulta é barrada pela RLS (pode_escrever), não por aqui.
create or replace function hub.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$ select hub.pode_ler() $$;

create or replace function hub.is_ingestor()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$ select hub.pode_ler() and (hub.eh_automacao() or hub.pode_escrever()) $$;

-- segredo do bot agora é POR workspace e, quando bate, diz de qual é
create or replace function hub.check_bot_secret(p_secret text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, extensions
as $$
declare v_ws uuid;
begin
  select workspace_id into v_ws from hub.config
    where chave = 'bot_secret'
      and valor_hash = encode(digest(coalesce(p_secret,''), 'sha256'), 'hex');
  if v_ws is null then return false; end if;
  perform set_config('hub.bot_ok', '1', true);
  perform set_config('hub.workspace_id', v_ws::text, true);
  return true;
end;
$$;
revoke all on function hub.check_bot_secret(text) from public;
grant execute on function hub.check_bot_secret(text) to anon, authenticated, service_role, hub_rpc;

-- Porta do bot. ACHADO 07/10: em produção os wrappers public.hub_bot_* são
-- SECURITY INVOKER, o anon NÃO tem USAGE no schema hub (guarda documentada
-- no .gitignore) e o service_role não tem EXECUTE nas bot_* — ou seja, o
-- bot de cobrança não roda por automação nenhuma hoje (está inativo, por
-- isso ninguém viu). Aqui só liberamos o service_role, que já é dono de
-- tudo; a escolha da porta definitiva é a pergunta P11 do docs.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'hub'::regnamespace and p.proname like 'bot\_%'
  loop
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;

-- empresa padrão = a 1ª empresa DO workspace (era: nome = 'Luh Panda')
create or replace function hub.default_empresa_id()
returns uuid
language sql
stable
set search_path = pg_catalog
as $$
  select id from hub.empresas where workspace_id = hub.current_workspace_id()
  order by (nome = 'Luh Panda') desc, created_at limit 1
$$;

-- ---------- 5) default de workspace_id = o da requisição ----------
do $$
declare t text;
begin
  for t in
    select c.relname from pg_class c
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'workspace_id' and not a.attisdropped
    where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r'
      and c.relname not in ('eventos_auditoria','acessos_sensiveis')
  loop
    execute format('alter table hub.%I alter column workspace_id set default hub.current_workspace_id()', t);
  end loop;
end $$;

-- ---------- 6) RLS por workspace em TODA tabela de dado ----------
-- Some toda policy antiga (todas eram `hub.is_admin()`), e cada tabela com
-- workspace_id ganha 4: ler = mesmo workspace; escrever = mesmo workspace +
-- papel Dono/Operador (ou automação). O `(select ...)` faz o Postgres
-- avaliar a função 1 vez por consulta, não 1 vez por linha.
do $$
declare
  p record;
  t text;
  v_mesmo text := 'workspace_id = (select hub.current_workspace_id())';
  v_escr  text := '(select hub.pode_escrever())';
begin
  for p in select tablename, policyname from pg_policies where schemaname = 'hub' loop
    execute format('drop policy %I on hub.%I', p.policyname, p.tablename);
  end loop;

  for t in
    select c.relname from pg_class c
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'workspace_id' and not a.attisdropped
    where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r'
      and c.relname not in ('workspace_membros','convites','workspace_modulos','workspace_canais',
                            'workspace_aceites','acessos_sensiveis','eventos_auditoria','config')
  loop
    execute format('alter table hub.%I enable row level security', t);
    execute format('create policy %I on hub.%I for select using (%s)', 'ws_ler', t, v_mesmo);
    execute format('create policy %I on hub.%I for insert with check (%s and %s)', 'ws_inserir', t, v_mesmo, v_escr);
    execute format('create policy %I on hub.%I for update using (%s and %s) with check (%s and %s)', 'ws_alterar', t, v_mesmo, v_escr, v_mesmo, v_escr);
    execute format('create policy %I on hub.%I for delete using (%s and %s)', 'ws_apagar', t, v_mesmo, v_escr);
  end loop;
end $$;

-- tabelas de conta: leitura do próprio workspace; escrita só pelas RPCs de conta (owner postgres)
create policy ws_ler on hub.workspaces for select using (id = (select hub.current_workspace_id()));
create policy ws_ler on hub.workspace_membros for select using (workspace_id = (select hub.current_workspace_id()));
create policy ws_ler on hub.workspace_modulos for select using (workspace_id = (select hub.current_workspace_id()));
create policy ws_ler on hub.modulos for select using (true);
-- auditoria: só Dono/Operador do próprio workspace
create policy ws_ler on hub.eventos_auditoria for select
  using (workspace_id = (select hub.current_workspace_id()) and (select hub.pode_escrever()));

-- ---------- 7) posse: as RPCs de negócio passam pro hub_rpc ----------
-- Ficam com o postgres (precisam enxergar além do workspace):
-- helpers de identidade, trigger functions, segredo do bot e as RPCs de
-- conta/convite da 050. Função nova da tela "Novo cliente" (041+) entra
-- no loop sozinha, desde que se chame rpc_* / bot_*.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'hub'::regnamespace
      and p.prosecdef
      and (p.proname like 'rpc\_%' or p.proname like 'bot\_%' or p.proname in ('crm_ids','fone_no_crm'))
      and p.proname not in (
        'rpc_meus_workspaces','rpc_plataforma_criar_workspace','rpc_plataforma_definir_modulos',
        'rpc_criar_convite','rpc_revogar_convite','rpc_aceitar_convite','rpc_membros','rpc_alterar_membro',
        'rpc_onboarding_salvar_empresa','rpc_onboarding_confirmar_regime','rpc_aceitar_termos','rpc_perfil_fiscal')
  loop
    execute format('alter function %s owner to hub_rpc', f.sig);
  end loop;
end $$;

-- ---------- 8) Storage (bucket contratos): pasta = workspace ----------
-- Caminho novo: <workspace_id>/<slug-cliente>/<arquivo>. Os 4 PDFs de hoje
-- (<slug>/<arquivo>) contam como do workspace 1 até serem movidos (etapa 4).
create or replace function hub.storage_workspace_do_caminho(p_name text)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case
    when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(p_name, '/', 1)::uuid
    else (select id from hub.workspaces where slug = 'luhpanda')
  end
$$;
revoke all on function hub.storage_workspace_do_caminho(text) from public, anon;
grant execute on function hub.storage_workspace_do_caminho(text) to authenticated;

drop policy if exists hub_contratos_admin_select on storage.objects;
drop policy if exists hub_contratos_admin_insert on storage.objects;
drop policy if exists hub_contratos_admin_update on storage.objects;
drop policy if exists hub_contratos_admin_delete on storage.objects;
create policy hub_contratos_ws_select on storage.objects for select
  using (bucket_id = 'contratos' and hub.storage_workspace_do_caminho(name) = hub.current_workspace_id());
create policy hub_contratos_ws_insert on storage.objects for insert
  with check (bucket_id = 'contratos' and hub.storage_workspace_do_caminho(name) = hub.current_workspace_id() and hub.pode_escrever());
create policy hub_contratos_ws_update on storage.objects for update
  using (bucket_id = 'contratos' and hub.storage_workspace_do_caminho(name) = hub.current_workspace_id() and hub.pode_escrever())
  with check (bucket_id = 'contratos' and hub.storage_workspace_do_caminho(name) = hub.current_workspace_id() and hub.pode_escrever());
create policy hub_contratos_ws_delete on storage.objects for delete
  using (bucket_id = 'contratos' and hub.storage_workspace_do_caminho(name) = hub.current_workspace_id() and hub.pode_escrever());

-- ---------- 9) trava final: nada de dado sem dono ----------
do $$
declare v text;
begin
  select string_agg(c.relname, ', ') into v
  from pg_class c
  where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r'
    and c.relname not in ('workspaces','modulos','plataforma_admins')
    and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'workspace_id'
                    and a.attnotnull or (a.attrelid = c.oid and a.attname = 'workspace_id' and c.relname = 'eventos_auditoria'));
  if v is not null then raise exception '052: tabela(s) sem workspace_id: %', v; end if;

  select string_agg(tablename || '.' || policyname, ', ') into v
  from pg_policies where schemaname = 'hub' and (qual ilike '%is_admin%' or with_check ilike '%is_admin%');
  if v is not null then raise exception '052: policy ainda depende de is_admin: %', v; end if;

  select string_agg(c.relname, ', ') into v
  from pg_class c where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r' and not c.relrowsecurity;
  if v is not null then raise exception '052: tabela sem RLS: %', v; end if;
end $$;
