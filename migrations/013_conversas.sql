-- ============================================================
-- HUB LUH PANDA — 013: conversas de WhatsApp (Fase 3, Bloco C)
--
-- Decisões do /grill-me de 23/09/2026 (ver plano
-- ~/.claude/plans/chame-aqui-o-dev-iridescent-pearl.md):
--   • Número espelhado: LuhPessoal (pessoal dela), não um chip novo.
--   • Só grava telefone que já está no CRM (whitelist aplicada no n8n,
--     antes de chamar rpc_registrar_mensagem) — conversa pessoal nunca
--     vira linha aqui.
--   • Mídia: texto + transcrição de áudio; foto/documento viram marcador
--     (`tipo`), arquivo em si não é guardado.
--   • "Não lida" é DERIVADA da própria thread (última mensagem é de
--     entrada) — sem tabela de estado que dessincronize do celular.
--   • Envio sai por Edge Function (guarda a chave da Evolution, nunca no
--     cliente); a mensagem de saída nasce aqui como 'enviando' e a Edge
--     Function atualiza o status direto (roda com service_role, fora do
--     RPC layer — não precisa de RPC própria pra isso).
--
-- hub.fone_norm() é a peça crítica: hoje existem dois formatos
-- concorrentes sem validação (`hub.contatos.whatsapp_e164` e
-- `hub.prospects.contato_whatsapp`), e o JID real do WhatsApp tira o nono
-- dígito quando o DDD é >= 31 (gotcha #15/#17 de
-- `dev/referencia/automacao-n8n.md` — o próprio número dela, DDD 84, é
-- `5584994127476` no cadastro mas `558494127476` no JID). A função
-- canonicaliza sempre pra forma SEM o nono dígito quando DDD >= 31, pra
-- cadastro e JID caírem na mesma chave.
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (23/09/2026) — sessão sem Supabase MCP
-- (mesma limitação já documentada nas primeiras sessões dos Blocos A/1.5/
-- 1.6/B). Antes de aplicar numa sessão com acesso:
--   1) conferir por introspecção (`list_tables`) que `hub.workspaces`,
--      `hub.prospects` e `hub.clientes` existem com esses nomes (010/011/002);
--   2) aplicar via `apply_migration`, sozinha (é a próxima na sequência,
--      010→011→012→013 já estão todas commitadas antes dela);
--   3) testar `hub.fone_norm` com os 6 casos do plano — as 4 variantes do
--      mesmo número (com/sem 9º dígito, com/sem 55, com sufixo @s.whatsapp.net)
--      TÊM que cair na mesma string;
--   4) testar as 4 RPCs com `execute_sql` (ingestão idempotente via
--      `on conflict (evolution_msg_id) do nothing`, resumo com `nao_lida`
--      derivada, thread agregada, fila de saída);
--   5) rodar `get_advisors` (security) depois — nenhuma tabela deve ficar
--      sem RLS habilitada.
-- ============================================================

-- ---------- tabelas ----------

create table hub.conversas (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) default hub.default_workspace_id(),
  fone_norm text not null unique,
  prospect_id uuid references hub.prospects(id) on delete set null,
  cliente_id uuid references hub.clientes(id) on delete set null,
  nome_exibicao text,
  ultima_msg_em timestamptz,
  ultima_msg_previa text,
  ultima_msg_direcao text check (ultima_msg_direcao in ('entrada','saida')),
  rascunho_sugerido text, -- o nó de IA do n8n grava aqui; nunca dispara envio sozinho
  criada_em timestamptz not null default now()
);

create table hub.mensagens (
  id uuid primary key default gen_random_uuid(),
  conversa_id uuid not null references hub.conversas(id) on delete cascade,
  direcao text not null check (direcao in ('entrada','saida')),
  corpo text,
  tipo text not null default 'texto' check (tipo in ('texto','audio','imagem','documento','outro')),
  transcrito boolean not null default false,
  enviada_em timestamptz not null default now(),
  evolution_msg_id text unique, -- idempotência: o webhook da Evolution repete evento
  status text check (status is null or status in ('enviando','enviado','erro')), -- só pra saída
  erro text
);

create index idx_mensagens_conversa_enviada on hub.mensagens (conversa_id, enviada_em desc);

-- ---------- triggers de auditoria (mesmo padrão do resto do schema hub) ----------
create trigger trg_conversas_auditoria
  after insert or update or delete on hub.conversas
  for each row execute function hub.registrar_auditoria();
create trigger trg_mensagens_auditoria
  after insert or update or delete on hub.mensagens
  for each row execute function hub.registrar_auditoria();

-- ---------- RLS ----------
alter table hub.conversas enable row level security;
create policy hub_conversas_admin_all on hub.conversas
  for all using (hub.is_admin()) with check (hub.is_admin());

alter table hub.mensagens enable row level security;
create policy hub_mensagens_admin_all on hub.mensagens
  for all using (hub.is_admin()) with check (hub.is_admin());

-- ---------- hub.fone_norm — canonicaliza telefone BR pra chave única ----------
-- Regras: tira tudo que não é dígito (corta sufixo @s.whatsapp.net/@g.us
-- antes); garante prefixo 55 quando vem sem DDI (10 ou 11 dígitos);
-- remove o nono dígito quando DDD >= 31, porque é assim que o WhatsApp
-- registra o JID real (gotcha #15). DDD <= 30 mantém o 9 como está.
create or replace function hub.fone_norm(p_fone text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v text;
  v_ddd int;
  v_resto text;
begin
  if p_fone is null then
    return null;
  end if;

  -- corta o que vier depois de @ (JID de contato ou de grupo)
  v := split_part(p_fone, '@', 1);

  -- reduz a dígitos
  v := regexp_replace(v, '\D', '', 'g');

  if v = '' then
    return null;
  end if;

  -- sem DDI: DDD (2) + número (8 ou 9) = 10 ou 11 dígitos → prefixa 55
  if length(v) in (10, 11) then
    v := '55' || v;
  end if;

  -- com prefixo 55 + DDD (2) + número (8 ou 9) = 12 ou 13 dígitos:
  -- aplica a regra do nono dígito. Qualquer outro formato (ex.: ID de
  -- grupo, que não começa com 55) passa direto, sem tentar validar.
  if left(v, 2) = '55' and length(v) in (12, 13) then
    v_ddd := substring(v from 3 for 2)::int;
    v_resto := substring(v from 5);

    if v_ddd >= 31 and length(v_resto) = 9 and left(v_resto, 1) = '9' then
      v_resto := substring(v_resto from 2);
      v := '55' || lpad(v_ddd::text, 2, '0') || v_resto;
    end if;
  end if;

  return v;
end;
$$;

revoke all on function hub.fone_norm(text) from public, anon;
grant execute on function hub.fone_norm(text) to authenticated;

-- ---------- RPCs (security definer, padrão 003/011/012) ----------

-- thread completa de uma conversa (conversa + mensagens), molde do
-- hub.rpc_cliente em 003_rpcs.sql
create or replace function hub.rpc_conversa_thread(p_fone text)
returns jsonb
language plpgsql stable security definer set search_path = pg_catalog
as $$
declare
  v_fone text;
  v_conversa hub.conversas;
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p_fone);
  select * into v_conversa from hub.conversas where fone_norm = v_fone;
  if not found then return null; end if;

  select jsonb_build_object(
    'conversa', to_jsonb(v_conversa),
    'mensagens', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.enviada_em)
      from hub.mensagens m
      where m.conversa_id = v_conversa.id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- resumo de TODAS as conversas numa chamada só, pro kanban. nao_lida é
-- DERIVADA (última mensagem é de entrada) — sem tabela de estado.
create or replace function hub.rpc_conversas_resumo()
returns table (
  fone_norm text,
  prospect_id uuid,
  cliente_id uuid,
  nome_exibicao text,
  ultima_msg_previa text,
  ultima_msg_em timestamptz,
  ultima_msg_direcao text,
  nao_lida boolean
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    c.fone_norm, c.prospect_id, c.cliente_id, c.nome_exibicao,
    c.ultima_msg_previa, c.ultima_msg_em, c.ultima_msg_direcao,
    coalesce(c.ultima_msg_direcao = 'entrada', false) as nao_lida
  from hub.conversas c
  order by c.ultima_msg_em desc nulls last;
end;
$$;

-- ingestão vinda do n8n (webhook Evolution já filtrado pela whitelist).
-- upsert da conversa por fone_norm + insert idempotente da mensagem.
create or replace function hub.rpc_registrar_mensagem(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_direcao text;
  v_corpo text;
  v_tipo text;
  v_enviada_em timestamptz;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  v_direcao := coalesce(p->>'direcao', 'entrada');
  v_corpo := p->>'corpo';
  v_tipo := coalesce(p->>'tipo', 'texto');
  v_enviada_em := coalesce((p->>'enviada_em')::timestamptz, now());

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao)
  values (
    v_fone,
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid,
    p->>'nome_exibicao'
  )
  on conflict (fone_norm) do update set
    prospect_id   = coalesce(excluded.prospect_id, hub.conversas.prospect_id),
    cliente_id    = coalesce(excluded.cliente_id, hub.conversas.cliente_id),
    nome_exibicao = coalesce(excluded.nome_exibicao, hub.conversas.nome_exibicao)
  returning id into v_conversa_id;

  -- idempotência: webhook da Evolution repete evento (gotcha do próprio
  -- protocolo n8n). on conflict do nothing não gera linha nova nem
  -- v_msg_id, então o bloco abaixo não pisa na "última mensagem" de novo.
  insert into hub.mensagens (
    conversa_id, direcao, corpo, tipo, transcrito, enviada_em, evolution_msg_id
  )
  values (
    v_conversa_id, v_direcao, v_corpo, v_tipo,
    coalesce((p->>'transcrito')::boolean, false),
    v_enviada_em,
    p->>'evolution_msg_id'
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
$$;

-- enfileira mensagem de saída (status='enviando') pra Edge Function
-- pegar o id, mandar pra Evolution e marcar enviado/erro depois.
create or replace function hub.rpc_enfileirar_saida(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
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

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao)
  values (v_fone, (p->>'prospect_id')::uuid, (p->>'cliente_id')::uuid, p->>'nome_exibicao')
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
$$;

revoke all on function hub.rpc_conversa_thread(text) from public, anon;
revoke all on function hub.rpc_conversas_resumo() from public, anon;
revoke all on function hub.rpc_registrar_mensagem(jsonb) from public, anon;
revoke all on function hub.rpc_enfileirar_saida(jsonb) from public, anon;

grant execute on function hub.rpc_conversa_thread(text) to authenticated;
grant execute on function hub.rpc_conversas_resumo() to authenticated;
grant execute on function hub.rpc_registrar_mensagem(jsonb) to authenticated;
grant execute on function hub.rpc_enfileirar_saida(jsonb) to authenticated;

-- ---------- wrappers públicos (mesmo padrão do 004/011/012) ----------
-- sem wrapper o supabase-js não enxerga: o schema hub não é exposto ao PostgREST.

create or replace function public.hub_rpc_conversa_thread(p_fone text)
returns jsonb
language sql stable security invoker set search_path = pg_catalog
as $$ select hub.rpc_conversa_thread(p_fone); $$;

create or replace function public.hub_rpc_conversas_resumo()
returns table (
  fone_norm text,
  prospect_id uuid,
  cliente_id uuid,
  nome_exibicao text,
  ultima_msg_previa text,
  ultima_msg_em timestamptz,
  ultima_msg_direcao text,
  nao_lida boolean
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_conversas_resumo(); $$;

create or replace function public.hub_rpc_registrar_mensagem(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_registrar_mensagem(p); $$;

create or replace function public.hub_rpc_enfileirar_saida(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_enfileirar_saida(p); $$;

revoke all on function public.hub_rpc_conversa_thread(text) from public, anon;
revoke all on function public.hub_rpc_conversas_resumo() from public, anon;
revoke all on function public.hub_rpc_registrar_mensagem(jsonb) from public, anon;
revoke all on function public.hub_rpc_enfileirar_saida(jsonb) from public, anon;

grant execute on function public.hub_rpc_conversa_thread(text) to authenticated;
grant execute on function public.hub_rpc_conversas_resumo() to authenticated;
grant execute on function public.hub_rpc_registrar_mensagem(jsonb) to authenticated;
grant execute on function public.hub_rpc_enfileirar_saida(jsonb) to authenticated;
