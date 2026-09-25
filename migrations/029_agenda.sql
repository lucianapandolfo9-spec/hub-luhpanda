-- ============================================================
-- HUB LUH PANDA — 029: Hub × Google Agenda (Fase 3, Bloco F)
--
-- Desenho fechado via /grill-me em 25/09/2026 (ver Hub Dev.md, seção
-- "🆕 Bloco F — Hub × Google Agenda"). Decisões que moldam esta migration:
--
--   1. O GOOGLE AGENDA É A FONTE DA VERDADE. O Hub nunca guarda cópia do
--      evento (título, horário, convidados) — isso desalinharia. A ÚNICA
--      coisa gravada aqui é o VÍNCULO: qual google_event_id pertence a
--      qual cliente/prospect. Toda vez que a tela precisa mostrar data,
--      hora ou quem foi convidado, ela pergunta pro Google de novo (Edge
--      Function `agenda-google`, ação "obter").
--   2. Calendário usado: o PRINCIPAL da conta dela — não existe um
--      calendário separado, então não existe coluna "calendar_id" aqui.
--   3. `criado_por` distingue vínculo feito pelo botão do Hub ('hub') de
--      um vínculo que um futuro job de sincronia por e-mail do convidado
--      viria a criar ('google') — ESSE JOB AINDA NÃO EXISTE (ver rodapé).
--      A coluna já nasce pronta pra não exigir outra migration quando ele
--      for construído.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (sem Supabase MCP — mesma
-- limitação já registrada nos Blocos A/1.5/1.6/B/D). Aplicar com
-- `apply_migration`, depois `get_advisors` (security), como sempre.
-- ============================================================

do $$
begin
  if to_regprocedure('hub.default_workspace_id()') is null then
    raise exception 'hub.default_workspace_id() não existe — aplicar a 010 antes da 029.';
  end if;
  if to_regprocedure('hub.is_ingestor()') is null then
    raise exception 'hub.is_ingestor() não existe — aplicar a 013 antes da 029.';
  end if;
  if to_regprocedure('hub.rpc_conversas_resumo()') is null then
    raise exception 'hub.rpc_conversas_resumo() não existe — aplicar a 013/020 antes da 029.';
  end if;
  if to_regclass('hub.reunioes') is null then
    raise exception 'hub.reunioes não existe — aplicar a 027 antes da 029 (o rascunho de reunião depende dela).';
  end if;
end $$;


-- ============================================================
-- 1) hub.eventos_agenda — só o vínculo, nunca o evento em si
-- ============================================================
create table hub.eventos_agenda (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) default hub.default_workspace_id(),
  google_event_id text not null unique,
  cliente_id uuid references hub.clientes(id) on delete set null,
  prospect_id uuid references hub.prospects(id) on delete set null,
  criado_por text not null default 'hub' check (criado_por in ('hub','google')),
  criado_em timestamptz not null default now()
);

create index idx_eventos_agenda_cliente  on hub.eventos_agenda (cliente_id)  where cliente_id  is not null;
create index idx_eventos_agenda_prospect on hub.eventos_agenda (prospect_id) where prospect_id is not null;

create trigger trg_eventos_agenda_auditoria
  after insert or update or delete on hub.eventos_agenda
  for each row execute function hub.registrar_auditoria();

alter table hub.eventos_agenda enable row level security;
create policy hub_eventos_agenda_admin_all on hub.eventos_agenda
  for all using (hub.is_admin()) with check (hub.is_admin());


-- ============================================================
-- 2) hub.rpc_eventos_agenda_vincular — a Edge Function `agenda-google`
--    chama isso logo depois de criar o evento no Google (repassando o JWT
--    dela — é ela clicando "Marcar reunião", não um bot).
-- ============================================================
create or replace function hub.rpc_eventos_agenda_vincular(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
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
$$;

-- lista os google_event_id ligados a um cliente OU prospect — é o que a
-- ficha usa pra saber quais IDs perguntar pro Google (ação "obter").
create or replace function hub.rpc_eventos_agenda_do_contato(p jsonb)
returns setof hub.eventos_agenda
language plpgsql stable security definer set search_path = pg_catalog
as $$
declare
  v_cliente uuid := (p->>'cliente_id')::uuid;
  v_prospect uuid := (p->>'prospect_id')::uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if v_cliente is null and v_prospect is null then
    raise exception 'informe cliente_id ou prospect_id';
  end if;
  return query
  select * from hub.eventos_agenda ea
  where (v_cliente is not null and ea.cliente_id = v_cliente)
     or (v_prospect is not null and ea.prospect_id = v_prospect)
  order by ea.criado_em desc;
end;
$$;

revoke all on function hub.rpc_eventos_agenda_vincular(jsonb)    from public, anon;
revoke all on function hub.rpc_eventos_agenda_do_contato(jsonb)  from public, anon;
grant execute on function hub.rpc_eventos_agenda_vincular(jsonb)   to authenticated;
grant execute on function hub.rpc_eventos_agenda_do_contato(jsonb) to authenticated;


-- ============================================================
-- 3) hub.rpc_criar_rascunho_reuniao_agenda — item 8 do Bloco F
--
-- Ao criar um evento vinculado a cliente/prospect, deixa um rascunho
-- esperando em hub.reunioes (a MESMA tabela do D3/Meetily — sem tabela
-- paralela). meetily_meeting_id sintético ('agenda-<google_event_id>') pra
-- nunca colidir com um id real do Meetily.
--
-- ⚠️ NÃO faz o "encaixe automático" com uma reunião real do Meetily que
-- chegue depois (mesmo cliente, horário próximo) — isso ficou como
-- pendência explícita no D3 original e continua em aberto aqui. Hoje: se
-- a transcrição real subir depois, vira uma SEGUNDA linha em hub.reunioes
-- (meetily_meeting_id diferente) até alguém (ela, na tela) vincular ou
-- apagar o rascunho velho. Documentado, não escondido.
create or replace function hub.rpc_criar_rascunho_reuniao_agenda(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
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
$$;

revoke all on function hub.rpc_criar_rascunho_reuniao_agenda(jsonb) from public, anon;
grant execute on function hub.rpc_criar_rascunho_reuniao_agenda(jsonb) to authenticated;


-- ============================================================
-- 4) sugestão de horário detectada pela IA na conversa (item 5 do Bloco F)
--
-- MESMO PADRÃO de hub.conversas.rascunho_sugerido (migration 013): o n8n
-- grava, o Hub só EXIBE um banner na ficha — nunca cria o evento sozinha.
-- Ela confirma clicando "Marcar reunião", que abre o mini-form já
-- pré-preenchido com o horário sugerido.
--
-- ⚠️ O NÓ DE IA QUE ESCREVE AQUI AINDA NÃO EXISTE — precisa entrar no
-- workflow n8n `HUB — Conversas WhatsApp` (bYWqiukkixOla1GN) numa sessão
-- com acesso ao N8N MCP, que esta sessão não tinha. Ver Hub Dev.md.
alter table hub.conversas
  add column sugestao_reuniao jsonb; -- {texto, data_hora_sugerida, detectado_em}

-- o nó de IA do n8n grava aqui (mesma porta do rpc_salvar_rascunho — is_ingestor)
create or replace function hub.rpc_salvar_sugestao_reuniao(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_fone text;
  v_conversa_id uuid;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  update hub.conversas
  set sugestao_reuniao = p->'sugestao'
  where fone_norm = v_fone
  returning id into v_conversa_id;

  return v_conversa_id;
end;
$$;

-- ela dispensa o banner (já marcou a reunião, ou não é o caso) — sempre dela
create or replace function hub.rpc_limpar_sugestao_reuniao(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_fone text;
  v_conversa_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  update hub.conversas
  set sugestao_reuniao = null
  where fone_norm = v_fone
  returning id into v_conversa_id;

  return v_conversa_id;
end;
$$;

revoke all on function hub.rpc_salvar_sugestao_reuniao(jsonb) from public, anon;
revoke all on function hub.rpc_limpar_sugestao_reuniao(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_sugestao_reuniao(jsonb) to authenticated, service_role;
grant execute on function hub.rpc_limpar_sugestao_reuniao(jsonb) to authenticated;

-- rpc_conversa_thread devolve to_jsonb(conversa) inteiro — sugestao_reuniao
-- aparece sozinha ali, sem precisar tocar naquela função (013/016).

-- rpc_conversas_resumo é RETURNS TABLE — precisa DROP antes do CREATE pra
-- mudar o shape (mesma razão da 020 ao adicionar eh_grupo). Ganha
-- `tem_sugestao_reuniao` pro kanban mostrar um selo sem abrir a ficha.
drop function if exists public.hub_rpc_conversas_resumo();
drop function if exists hub.rpc_conversas_resumo();

create function hub.rpc_conversas_resumo()
returns table (
  fone_norm text,
  prospect_id uuid,
  cliente_id uuid,
  nome_exibicao text,
  ultima_msg_previa text,
  ultima_msg_em timestamptz,
  ultima_msg_direcao text,
  nao_lida boolean,
  eh_grupo boolean,
  tem_sugestao_reuniao boolean
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    c.fone_norm, c.prospect_id, c.cliente_id, c.nome_exibicao,
    c.ultima_msg_previa, c.ultima_msg_em, c.ultima_msg_direcao,
    coalesce(c.ultima_msg_direcao = 'entrada', false) as nao_lida,
    c.eh_grupo,
    (c.sugestao_reuniao is not null) as tem_sugestao_reuniao
  from hub.conversas c
  order by c.ultima_msg_em desc nulls last;
end;
$$;

revoke all on function hub.rpc_conversas_resumo() from public, anon;
grant execute on function hub.rpc_conversas_resumo() to authenticated;

create function public.hub_rpc_conversas_resumo()
returns table (
  fone_norm text,
  prospect_id uuid,
  cliente_id uuid,
  nome_exibicao text,
  ultima_msg_previa text,
  ultima_msg_em timestamptz,
  ultima_msg_direcao text,
  nao_lida boolean,
  eh_grupo boolean,
  tem_sugestao_reuniao boolean
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_conversas_resumo(); $$;

revoke all on function public.hub_rpc_conversas_resumo() from public, anon;
grant execute on function public.hub_rpc_conversas_resumo() to authenticated;


-- ============================================================
-- 5) wrappers públicos (schema hub não é exposto ao PostgREST)
-- ============================================================
create or replace function public.hub_rpc_eventos_agenda_vincular(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_eventos_agenda_vincular(p); $$;

create or replace function public.hub_rpc_eventos_agenda_do_contato(p jsonb)
returns setof hub.eventos_agenda
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_eventos_agenda_do_contato(p); $$;

create or replace function public.hub_rpc_criar_rascunho_reuniao_agenda(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_criar_rascunho_reuniao_agenda(p); $$;

create or replace function public.hub_rpc_salvar_sugestao_reuniao(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_sugestao_reuniao(p); $$;

create or replace function public.hub_rpc_limpar_sugestao_reuniao(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_limpar_sugestao_reuniao(p); $$;

revoke all on function public.hub_rpc_eventos_agenda_vincular(jsonb)         from public, anon;
revoke all on function public.hub_rpc_eventos_agenda_do_contato(jsonb)       from public, anon;
revoke all on function public.hub_rpc_criar_rascunho_reuniao_agenda(jsonb)   from public, anon;
revoke all on function public.hub_rpc_salvar_sugestao_reuniao(jsonb)        from public, anon;
revoke all on function public.hub_rpc_limpar_sugestao_reuniao(jsonb)        from public, anon;

grant execute on function public.hub_rpc_eventos_agenda_vincular(jsonb)       to authenticated;
grant execute on function public.hub_rpc_eventos_agenda_do_contato(jsonb)     to authenticated;
grant execute on function public.hub_rpc_criar_rascunho_reuniao_agenda(jsonb) to authenticated;
grant execute on function public.hub_rpc_salvar_sugestao_reuniao(jsonb)       to anon, authenticated, service_role;
grant execute on function public.hub_rpc_limpar_sugestao_reuniao(jsonb)       to authenticated;

-- ⚠️ hub_rpc_salvar_sugestao_reuniao ganha `anon` no wrapper público pelo
-- MESMO motivo do wrapper de rpc_registrar_reuniao (027): o nó de IA do n8n
-- chama com a credencial "Supabase Hub Anon" (Fase 2), que chega como
-- `anon`. A fechadura de verdade é `hub.is_ingestor()` DENTRO da função —
-- aqui ela aceita `service_role`/admin, mas NÃO segredo de bot em texto,
-- porque o n8n para esse fluxo específico ainda não foi desenhado (ver
-- rodapé "falta"). Quando o nó existir, decidir ali se ele chama via
-- service_role (workflow já roda como tal hoje) ou se precisa de guarda
-- extra — não travar a porta agora sem saber qual credencial o nó vai usar.


-- ============================================================
-- RODAPÉ — o que esta migration NÃO faz, de propósito
-- ============================================================
-- 1. NÃO sincroniza evento criado direto no Google (fora do Hub) por
--    e-mail do convidado. A tabela já tem `criado_por='google'` pronta
--    pra isso, mas o job que faria essa varredura/match ainda não existe
--    — decisão registrada no Hub Dev.md, não construído nesta sessão.
-- 2. NÃO estende o workflow n8n `HUB — Conversas WhatsApp` pra detectar
--    data/hora na conversa — precisa de N8N MCP pra ler o nó de Gemini
--    existente antes de mexer (regra do CLAUDE.md: nunca inventar sem
--    entender a estrutura atual). Esta sessão não tinha acesso.
-- 3. NÃO faz o "encaixe automático" entre o rascunho criado aqui e uma
--    reunião real que suba do Meetily depois — ver comentário da seção 3.
