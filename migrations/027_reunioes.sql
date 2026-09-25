-- ============================================================
-- HUB LUH PANDA — 027: reuniões do Meetily (Fase 3, Bloco D — D3, item 12)
--
-- A ponte `scripts/subir-reuniao` (no Mac dela) lê o SQLite do Meetily
-- somente leitura, ela escolhe qual reunião sobe, e o payload cai aqui.
-- Nada varre, nada agenda, nada sobe sozinho — reunião pessoal, médico e
-- família nunca saem do Mac. É a mesma lição do Bloco C, aplicada antes de
-- doer: a guarda tem que ser desenho, não disciplina.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (separação de papéis: quem coda
-- não aplica). Aplicar com `apply_migration` e rodar `get_advisors`
-- (security) depois, como nos blocos anteriores.
--
-- ⚠️ A 025 e a 026 já foram usadas pelo D2 (Contratos), que rodou em paralelo. Esta é
-- a 027 de propósito — não renumerar de novo sem checar `ls migrations/`.
--
-- ------------------------------------------------------------
-- TRÊS SUPOSIÇÕES QUE A SESSÃO QUE APLICAR PRECISA CONFERIR
-- ------------------------------------------------------------
--
-- (1) `hub.check_bot_secret(text)` existe em produção desde a Fase 2, mas
--     NUNCA foi commitada como migration (é a pendência "migration
--     retroativa das RPCs da Fase 2", registrada no plano). Não consegui
--     ler o corpo dela desta sessão. O bloco de pré-checagem abaixo aborta
--     com mensagem legível se a assinatura não for `(text) -> boolean`.
--
-- (2) O guard é `check_bot_secret(...) OR is_ingestor()`, não AND.
--     Motivo: a ponte chama com a chave ANON (mesma via dos workflows
--     `hub_bot_*` da Fase 2, credencial "Supabase Hub Anon"), e pra quem
--     chega como anon `hub.is_ingestor()` é FALSO — auth.role() = 'anon'.
--     Com AND nada entraria. O OR mantém as duas portas válidas: o segredo
--     (ponte/n8n) e quem já é privilegiado (ela logada, ou service_role).
--
-- (3) O wrapper público desta RPC de ingestão é SECURITY DEFINER, e é o
--     único do projeto que foge do `security invoker` padrão. Motivo: a 001
--     revogou `usage on schema hub` de anon. Wrapper invoker executa o corpo
--     como o chamador, então anon tomaria "permission denied for schema hub"
--     — exatamente o furo que a 014 consertou pro service_role. A alternativa
--     seria `grant usage on schema hub to anon`, que abriria o schema inteiro
--     pra anon de uma vez só (e qualquer função hub que tenha escapado do
--     `revoke ... from public` viraria alcançável). Uma porta só, com o
--     segredo como fechadura, é mais barato de auditar no D6.
--     ✅ CONFERIR ao aplicar: `select has_schema_privilege('anon','hub','usage')`.
--     Se der TRUE, a Fase 2 já abriu esse grant e vale reconciliar — ou
--     fechar o grant e ficar só com esta porta.
-- ============================================================


-- ============================================================
-- 0) pré-checagem: as dependências que não moram em migration
-- ============================================================
do $$
begin
  if to_regprocedure('hub.check_bot_secret(text)') is null then
    raise exception
      'hub.check_bot_secret(text) não existe neste banco. Ela nasceu na Fase 2 e nunca foi commitada como migration. Confirme a assinatura real antes de aplicar a 027 — sem ela a ponte subir-reuniao toma "acesso negado" em toda chamada.';
  end if;
  if to_regprocedure('hub.is_ingestor()') is null then
    raise exception 'hub.is_ingestor() não existe — aplicar a 013 antes da 027.';
  end if;
  if to_regprocedure('hub.default_workspace_id()') is null then
    raise exception 'hub.default_workspace_id() não existe — aplicar a 010 antes da 027.';
  end if;
end $$;


-- ============================================================
-- 1) hub.reunioes
-- ============================================================
--
-- `meetily_meeting_id` é o `meetings.id` do SQLite local (text, formato
-- 'meeting-<uuid>' — NÃO é uuid puro, por isso a coluna é text). É ele que
-- garante a idempotência: reenviar a mesma reunião atualiza a linha, nunca
-- cria uma segunda.
--
-- `key_points` e `action_items` existem porque o plano pediu, mas ⚠️ leia o
-- cabeçalho de `scripts/subir-reuniao`: no Meetily v0.4.1 real essas colunas
-- do SQLite estão SEMPRE vazias (as 4378 linhas de `transcripts` têm
-- summary/key_points/action_items nulos nas 11 reuniões). O resumo de
-- verdade mora em `summary_processes.result -> markdown`, e decisões/ações
-- são seções DENTRO desse markdown. A ponte faz uma extração best-effort
-- dessas seções; quando não reconhece o cabeçalho, manda null em vez de
-- chutar. `resumo` é sempre o markdown inteiro.
--
-- `analise` é a saída da Edge Function `reuniao-analisar` (quem é o cliente,
-- dor, escopo, prazo, combinados, proposta com preço SÓ do catálogo).
create table hub.reunioes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) default hub.default_workspace_id(),
  meetily_meeting_id text not null unique,
  prospect_id uuid references hub.prospects(id) on delete set null,
  cliente_id uuid references hub.clientes(id) on delete set null,
  titulo text,
  realizada_em timestamptz,
  transcricao text,
  resumo text,
  key_points text,
  action_items text,
  analise jsonb,
  criada_em timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_reunioes_realizada on hub.reunioes (realizada_em desc nulls last);
create index idx_reunioes_prospect on hub.reunioes (prospect_id) where prospect_id is not null;
create index idx_reunioes_cliente on hub.reunioes (cliente_id) where cliente_id is not null;

-- ---------- triggers (mesmo padrão das outras tabelas de negócio) ----------
create trigger trg_reunioes_updated_at
  before update on hub.reunioes
  for each row execute function hub.set_updated_at();

-- ⚠️ `hub.registrar_auditoria()` grava to_jsonb(old) E to_jsonb(new) — ou
-- seja, uma transcrição de 50 KB vira ~100 KB em eventos_auditoria a cada
-- UPDATE. Por isso a rpc_registrar_reuniao abaixo só faz UPDATE quando algum
-- campo mudou de verdade (`is distinct from`): reenvio idêntico não gera
-- linha de auditoria nenhuma. Se um dia isso incomodar, o próximo passo é um
-- trigger próprio que audita a linha SEM a coluna `transcricao` — não
-- desligar a auditoria.
create trigger trg_reunioes_auditoria
  after insert or update or delete on hub.reunioes
  for each row execute function hub.registrar_auditoria();

-- ---------- RLS ----------
alter table hub.reunioes enable row level security;
create policy hub_reunioes_admin_all on hub.reunioes
  for all using (hub.is_admin()) with check (hub.is_admin());


-- ============================================================
-- 2) hub.rpc_registrar_reuniao — a ponte escreve aqui
-- ============================================================
--
-- Quem chama é o script no Mac dela, com a chave anon + o segredo do bot
-- lido de ~/.config/hub/credenciais. NÃO usa service_role: a CLAUDE.md dela
-- é explícita, e o segredo do bot é a via que já existe desde a Fase 2.
--
-- O segredo é removido do payload na primeira linha útil, antes de qualquer
-- coisa tocar em tabela — assim ele nunca chega perto de `eventos_auditoria`
-- nem de uma mensagem de erro.
create or replace function hub.rpc_registrar_reuniao(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_ok boolean;
  v_mid text;
  v_id uuid;
begin
  v_ok := coalesce(hub.check_bot_secret(p->>'secret'), false) or hub.is_ingestor();
  p := p - 'secret';                       -- a partir daqui o segredo não existe mais
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
    -- amarração e análise são DELA, feitas no Hub. Um reenvio da ponte
    -- nunca desfaz o que ela ligou a um prospect nem apaga a proposta.
    prospect_id  = coalesce(hub.reunioes.prospect_id, excluded.prospect_id),
    cliente_id   = coalesce(hub.reunioes.cliente_id,  excluded.cliente_id)
  where
    -- reenvio idêntico não vira UPDATE (e portanto não vira auditoria)
    hub.reunioes.titulo       is distinct from coalesce(excluded.titulo,       hub.reunioes.titulo)
    or hub.reunioes.realizada_em is distinct from coalesce(excluded.realizada_em, hub.reunioes.realizada_em)
    or hub.reunioes.transcricao  is distinct from coalesce(excluded.transcricao,  hub.reunioes.transcricao)
    or hub.reunioes.resumo       is distinct from coalesce(excluded.resumo,       hub.reunioes.resumo)
    or hub.reunioes.key_points   is distinct from coalesce(excluded.key_points,   hub.reunioes.key_points)
    or hub.reunioes.action_items is distinct from coalesce(excluded.action_items, hub.reunioes.action_items)
    or hub.reunioes.prospect_id  is distinct from coalesce(hub.reunioes.prospect_id, excluded.prospect_id)
    or hub.reunioes.cliente_id   is distinct from coalesce(hub.reunioes.cliente_id,  excluded.cliente_id)
  returning id into v_id;

  -- o WHERE acima faz o DO UPDATE não devolver linha quando nada mudou;
  -- nesse caso o id vem da linha que já existe (e a resposta é a mesma).
  if v_id is null then
    select r.id into v_id from hub.reunioes r where r.meetily_meeting_id = v_mid;
  end if;

  return v_id;
end;
$$;


-- ============================================================
-- 3) hub.rpc_reunioes — a lista da tela (SEM a transcrição)
-- ============================================================
--
-- A transcrição tem dezenas de KB por reunião (as reais vão de 12 KB a
-- 60 KB). Ela nunca entra na listagem — só no detalhe, uma por vez.
create or replace function hub.rpc_reunioes()
returns table (
  id uuid,
  meetily_meeting_id text,
  titulo text,
  realizada_em timestamptz,
  resumo text,
  prospect_id uuid,
  prospect_nome text,
  cliente_id uuid,
  cliente_nome text,
  cliente_slug text,
  tem_transcricao boolean,
  transcricao_chars integer,
  tem_analise boolean,
  criada_em timestamptz
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    r.id,
    r.meetily_meeting_id,
    r.titulo,
    r.realizada_em,
    r.resumo,
    r.prospect_id,
    pr.nome,
    r.cliente_id,
    cl.nome,
    cl.slug,
    (r.transcricao is not null and r.transcricao <> '') as tem_transcricao,
    coalesce(length(r.transcricao), 0)                  as transcricao_chars,
    (r.analise is not null)                             as tem_analise,
    r.criada_em
  from hub.reunioes r
  left join hub.prospects pr on pr.id = r.prospect_id
  left join hub.clientes  cl on cl.id = r.cliente_id
  order by r.realizada_em desc nulls last, r.criada_em desc;
end;
$$;


-- ============================================================
-- 4) hub.rpc_reuniao — detalhe completo (com transcrição)
-- ============================================================
-- molde do hub.rpc_cliente (003_rpcs.sql) / hub.rpc_conversa_thread (013)
create or replace function hub.rpc_reuniao(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = pg_catalog
as $$
declare
  v hub.reunioes;
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select * into v from hub.reunioes where id = p_id;
  if not found then return null; end if;

  select jsonb_build_object(
    'reuniao', to_jsonb(v),
    'prospect', (select to_jsonb(pr) from hub.prospects pr where pr.id = v.prospect_id),
    'cliente',  (select to_jsonb(cl) from hub.clientes  cl where cl.id = v.cliente_id)
  ) into v_result;

  return v_result;
end;
$$;


-- ============================================================
-- 5) hub.rpc_amarrar_reuniao — ligar a um prospect OU cliente
-- ============================================================
--
-- Payload: { id, prospect_id, cliente_id }. Mandar null desliga de propósito
-- (é assim que ela corrige uma amarração errada), então aqui NÃO tem
-- coalesce: o que vier é o que fica.
-- Sem exclusividade entre os dois, igual hub.conversas: um prospect que
-- virou cliente pode legitimamente ter os dois preenchidos.
create or replace function hub.rpc_amarrar_reuniao(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_id uuid;
  v_prospect uuid;
  v_cliente uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_id := (p->>'id')::uuid;
  if v_id is null then raise exception 'id da reunião é obrigatório'; end if;

  v_prospect := (p->>'prospect_id')::uuid;
  v_cliente  := (p->>'cliente_id')::uuid;

  if v_prospect is not null and not exists (select 1 from hub.prospects where id = v_prospect) then
    raise exception 'prospect não encontrado';
  end if;
  if v_cliente is not null and not exists (select 1 from hub.clientes where id = v_cliente) then
    raise exception 'cliente não encontrado';
  end if;

  update hub.reunioes
  set prospect_id = v_prospect,
      cliente_id  = v_cliente
  where id = v_id
  returning id into v_id;

  if v_id is null then raise exception 'reunião não encontrada'; end if;
  return v_id;
end;
$$;


-- ============================================================
-- 6) hub.rpc_salvar_analise — grava a saída da Edge Function
-- ============================================================
--
-- Quem chama é a Edge Function `reuniao-analisar`, repassando o JWT do
-- navegador dela (mesmo desenho da wa-send: a função NÃO usa service_role,
-- então hub.is_admin() continua sendo a fechadura).
-- Payload: { id, analise }.
create or replace function hub.rpc_salvar_analise(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_id uuid;
  v_analise jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_id := (p->>'id')::uuid;
  if v_id is null then raise exception 'id da reunião é obrigatório'; end if;

  v_analise := p->'analise';
  if v_analise is null or jsonb_typeof(v_analise) <> 'object' then
    raise exception 'analise precisa ser um objeto jsonb';
  end if;

  update hub.reunioes
  set analise = v_analise
  where id = v_id
  returning id into v_id;

  if v_id is null then raise exception 'reunião não encontrada'; end if;
  return v_id;
end;
$$;


-- ============================================================
-- 7) grants do schema hub
-- ============================================================
revoke all on function hub.rpc_registrar_reuniao(jsonb) from public, anon;
revoke all on function hub.rpc_reunioes()              from public, anon;
revoke all on function hub.rpc_reuniao(uuid)           from public, anon;
revoke all on function hub.rpc_amarrar_reuniao(jsonb)  from public, anon;
revoke all on function hub.rpc_salvar_analise(jsonb)   from public, anon;

-- ingestão: ela logada (authenticated) e o service_role. `anon` NÃO ganha
-- execute aqui dentro — anon nem tem usage no schema hub (001). O caminho
-- do anon é só o wrapper público definer da seção 8.
grant execute on function hub.rpc_registrar_reuniao(jsonb) to authenticated, service_role;

grant execute on function hub.rpc_reunioes()             to authenticated;
grant execute on function hub.rpc_reuniao(uuid)          to authenticated;
grant execute on function hub.rpc_amarrar_reuniao(jsonb) to authenticated;
grant execute on function hub.rpc_salvar_analise(jsonb)  to authenticated;


-- ============================================================
-- 8) wrappers públicos (o schema hub não é exposto ao PostgREST)
-- ============================================================

-- ⚠️ ÚNICO wrapper SECURITY DEFINER do projeto — ver suposição (3) no
-- cabeçalho. É a porta da ponte, e a fechadura é o segredo do bot,
-- verificado na PRIMEIRA linha da função interna.
create or replace function public.hub_rpc_registrar_reuniao(p jsonb)
returns uuid
language sql security definer set search_path = pg_catalog
as $$ select hub.rpc_registrar_reuniao(p); $$;

create or replace function public.hub_rpc_reunioes()
returns table (
  id uuid,
  meetily_meeting_id text,
  titulo text,
  realizada_em timestamptz,
  resumo text,
  prospect_id uuid,
  prospect_nome text,
  cliente_id uuid,
  cliente_nome text,
  cliente_slug text,
  tem_transcricao boolean,
  transcricao_chars integer,
  tem_analise boolean,
  criada_em timestamptz
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_reunioes(); $$;

create or replace function public.hub_rpc_reuniao(p_id uuid)
returns jsonb
language sql stable security invoker set search_path = pg_catalog
as $$ select hub.rpc_reuniao(p_id); $$;

create or replace function public.hub_rpc_amarrar_reuniao(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_amarrar_reuniao(p); $$;

create or replace function public.hub_rpc_salvar_analise(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_analise(p); $$;

revoke all on function public.hub_rpc_registrar_reuniao(jsonb) from public, anon;
revoke all on function public.hub_rpc_reunioes()               from public, anon;
revoke all on function public.hub_rpc_reuniao(uuid)            from public, anon;
revoke all on function public.hub_rpc_amarrar_reuniao(jsonb)   from public, anon;
revoke all on function public.hub_rpc_salvar_analise(jsonb)    from public, anon;

-- a ponte chega como `anon` + segredo do bot (mesma via dos workflows
-- hub_bot_* da Fase 2). Este é o único grant a anon do schema inteiro.
grant execute on function public.hub_rpc_registrar_reuniao(jsonb) to anon, authenticated, service_role;

grant execute on function public.hub_rpc_reunioes()             to authenticated;
grant execute on function public.hub_rpc_reuniao(uuid)          to authenticated;
grant execute on function public.hub_rpc_amarrar_reuniao(jsonb) to authenticated;
grant execute on function public.hub_rpc_salvar_analise(jsonb)  to authenticated;
