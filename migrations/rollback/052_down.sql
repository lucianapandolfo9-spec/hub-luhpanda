-- ============================================================
-- HUB — ROLLBACK da 052 (volta pro modelo "só o e-mail dela")
-- ⚠️ DRAFT. Recusa rodar se existir dado de outro workspace: antes de
-- voltar, decidir o que fazer com os clientes que já entraram (exportar /
-- apagar). Volta tudo ao texto de produção lido em 07/10/2026.
-- ============================================================
do $$
declare
  v_ws1 uuid := (select id from hub.workspaces where slug = 'luhpanda');
  t text; n int; v text := '';
begin
  for t in
    select c.relname from pg_class c
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'workspace_id' and not a.attisdropped
    where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r'
      and c.relname not in ('eventos_auditoria','acessos_sensiveis','workspace_membros','convites',
                            'workspace_modulos','workspace_canais','workspace_aceites')
  loop
    execute format('select count(*) from hub.%I where workspace_id <> %L', t, v_ws1) into n;
    if n > 0 then v := v || t || '(' || n || ') '; end if;
  end loop;
  if v <> '' then
    raise exception '052_down: há dado de outro workspace em: % — resolver antes de voltar', v;
  end if;
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'hub'::regnamespace and p.proname like 'bot\_%'
  loop
    execute format('revoke execute on function %s from service_role', f.sig);
  end loop;
end $$;

-- posse de volta pro postgres
reassign owned by hub_rpc to postgres;
drop owned by hub_rpc;
drop role hub_rpc;

-- storage
drop policy if exists hub_contratos_ws_select on storage.objects;
drop policy if exists hub_contratos_ws_insert on storage.objects;
drop policy if exists hub_contratos_ws_update on storage.objects;
drop policy if exists hub_contratos_ws_delete on storage.objects;
create policy hub_contratos_admin_select on storage.objects for select using ((bucket_id = 'contratos'::text) and hub.is_admin());
create policy hub_contratos_admin_insert on storage.objects for insert with check ((bucket_id = 'contratos'::text) and hub.is_admin());
create policy hub_contratos_admin_update on storage.objects for update using ((bucket_id = 'contratos'::text) and hub.is_admin()) with check ((bucket_id = 'contratos'::text) and hub.is_admin());
create policy hub_contratos_admin_delete on storage.objects for delete using ((bucket_id = 'contratos'::text) and hub.is_admin());
drop function if exists hub.storage_workspace_do_caminho(text);

-- policies: some as de workspace, voltam as de is_admin()
do $$
declare p record;
begin
  for p in select tablename, policyname from pg_policies where schemaname = 'hub' loop
    execute format('drop policy %I on hub.%I', p.policyname, p.tablename);
  end loop;
end $$;
create policy hub_eventos_auditoria_admin_select on hub.eventos_auditoria for SELECT using (hub.is_admin());
create policy hub_empresas_admin_all on hub.empresas for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_clientes_admin_all on hub.clientes for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_contatos_admin_all on hub.contatos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_servicos_admin_all on hub.servicos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_contratos_admin_all on hub.contratos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_contrato_itens_admin_all on hub.contrato_itens for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_recebiveis_admin_all on hub.recebiveis for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_custos_fixos_admin_all on hub.custos_fixos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_cobranca_envios_admin_select on hub.cobranca_envios for SELECT using (hub.is_admin());
create policy hub_demandas_admin_all on hub.demandas for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_workspaces_admin_all on hub.workspaces for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_prospects_admin_all on hub.prospects for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_cobranca_config_admin_all on hub.cobranca_config for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_cobranca_mensagens_admin_all on hub.cobranca_mensagens for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_conversas_admin_all on hub.conversas for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_mensagens_admin_all on hub.mensagens for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_reunioes_admin_all on hub.reunioes for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_eventos_agenda_admin_all on hub.eventos_agenda for ALL using (hub.is_admin()) with check (hub.is_admin());

-- defaults voltam pro workspace fixo
do $$
declare t text;
begin
  for t in
    select c.relname from pg_class c
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'workspace_id' and not a.attisdropped
    where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r'
      and c.relname not in ('eventos_auditoria','acessos_sensiveis','workspace_membros','convites',
                            'workspace_modulos','workspace_canais','workspace_aceites')
  loop
    execute format('alter table hub.%I alter column workspace_id set default hub.default_workspace_id()', t);
  end loop;
end $$;

-- unicidade global de volta
alter table hub.clientes drop constraint clientes_ws_slug_key, add constraint clientes_slug_key unique (slug);
alter table hub.servicos drop constraint servicos_ws_slug_key, add constraint servicos_slug_key unique (slug);
alter table hub.conversas drop constraint conversas_ws_fone_norm_key, add constraint conversas_fone_norm_key unique (fone_norm);
alter table hub.mensagens drop constraint mensagens_ws_evolution_msg_id_key, add constraint mensagens_evolution_msg_id_key unique (evolution_msg_id);
alter table hub.cobranca_mensagens drop constraint cobranca_mensagens_ws_etapa_key, add constraint cobranca_mensagens_etapa_key unique (etapa);
alter table hub.eventos_agenda drop constraint eventos_agenda_ws_google_event_id_key, add constraint eventos_agenda_google_event_id_key unique (google_event_id);
alter table hub.reunioes drop constraint reunioes_ws_meetily_meeting_id_key, add constraint reunioes_meetily_meeting_id_key unique (meetily_meeting_id);
alter table hub.config drop constraint config_pkey, add constraint config_pkey primary key (chave);

-- funções de volta ao texto de produção (07/10/2026)
CREATE OR REPLACE FUNCTION hub.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select coalesce(auth.email(), '') = 'lucianapandolfo9@gmail.com';
$function$
;
CREATE OR REPLACE FUNCTION hub.is_ingestor()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select hub.is_admin()
      or coalesce(auth.role(), '') = 'service_role'
      or current_user = 'service_role';
$function$
;
CREATE OR REPLACE FUNCTION hub.default_empresa_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select id from hub.empresas where nome = 'Luh Panda' limit 1;
$function$
;
drop function hub.check_bot_secret(text);
CREATE OR REPLACE FUNCTION hub.check_bot_secret(p_secret text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions'
AS $function$
  select exists (
    select 1 from hub.config
    where chave = 'bot_secret'
      and valor_hash = encode(digest(coalesce(p_secret,''), 'sha256'), 'hex')
  );
$function$
;
revoke all on function hub.check_bot_secret(text) from public; grant execute on function hub.check_bot_secret(text) to anon, authenticated, service_role;
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
  on conflict (fone_norm) do update set
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
  on conflict (evolution_msg_id) do nothing
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
  on conflict (google_event_id) do update set
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
  on conflict (fone_norm) do update set
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
  on conflict (meetily_meeting_id) do nothing
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
  on conflict (meetily_meeting_id) do update set
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
