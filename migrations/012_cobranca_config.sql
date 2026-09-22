-- ============================================================
-- HUB LUH PANDA — 012: configuração de cobrança por cliente (Fase 3, Bloco B, B6)
--
-- Prepara o terreno de banco pro bot `HUB — Cobrança Automática` (já criado
-- no n8n, INATIVO) ler daqui em vez de ter tudo hardcoded no workflow.
-- Não ativa o bot nesta rodada (isso é D19/D20 — depende de chip novo e
-- disparo assistido, pendências dela).
--
-- ⚠️ REVISADA (22/09/2026, sessão com Supabase MCP) — a primeira versão
-- desta migration tentava recriar `hub.cobranca_envios`, mas essa tabela
-- JÁ EXISTE em produção desde a Fase 2 (Financeiro): loga por
-- `recebivel_id` + `bucket` ('d_menos_3'/'d0'/'d_mais_2'/'d_mais_7'/
-- 'escalado'), escrita por `hub.bot_registrar_envio` e lida por
-- `hub.bot_cobrancas_do_dia` — o motor real que o n8n já chama. Também
-- `dia_vencimento` e `whatsapp_e164` por cliente já existem de verdade em
-- `hub.contratos.dia_vencimento` (contrato ativo) e `hub.contatos.
-- whatsapp_e164` (contato principal) — ter uma cópia nova nesta tabela
-- divergiria do que o bot realmente usa.
--
-- Reconciliação decidida com a Luciana:
--   • NÃO recriar `hub.cobranca_envios` — só ler dela via RPC nova.
--   • `hub.cobranca_config` guarda só o que é genuinamente novo: `metodo`
--     (pix/mp_link) e `ativo` (pausar/retomar a régua pro cliente).
--     Vencimento e WhatsApp aparecem na tela vindos ao vivo de
--     `hub.contratos`/`hub.contatos` — editar lá, não aqui.
--   • `hub.cobranca_mensagens.etapa` usa a MESMA convenção de nome do
--     `bucket` que o bot já usa (`d_menos_3`/`d0`/`d_mais_2`/`d_mais_7`),
--     em vez de inventar uma segunda ('d-3'/'d+2') que divergiria depois.
--
-- Textos da régua nascem como PLACEHOLDER — o workflow `HUB — Cobrança
-- Automática` já tem os 4 textos reais testados com pinData, mas esta
-- sessão não tem n8n MCP pra puxar o texto exato. Substituir numa sessão
-- com n8n MCP antes de D19/D20.
-- ============================================================

create table hub.cobranca_config (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) default hub.default_workspace_id(),
  cliente_id uuid not null unique references hub.clientes(id) on delete cascade,
  metodo text not null default 'pix' check (metodo in ('pix','mp_link')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table hub.cobranca_mensagens (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) default hub.default_workspace_id(),
  etapa text not null unique check (etapa in ('d_menos_3','d0','d_mais_2','d_mais_7')),
  texto text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['cobranca_config','cobranca_mensagens']
  loop
    execute format('create trigger trg_%1$s_updated_at before update on hub.%1$s for each row execute function hub.set_updated_at();', t);
    execute format('create trigger trg_%1$s_auditoria after insert or update or delete on hub.%1$s for each row execute function hub.registrar_auditoria();', t);
    execute format('alter table hub.%1$s enable row level security;', t);
    execute format('create policy hub_%1$s_admin_all on hub.%1$s for all using (hub.is_admin()) with check (hub.is_admin());', t);
  end loop;
end $$;

-- seed placeholder da régua — SUBSTITUIR pelo texto real do node antes do bot ir ao ar
insert into hub.cobranca_mensagens (etapa, texto) values
('d_menos_3', 'RASCUNHO — copiar do node Configuração do workflow HUB — Cobrança Automática antes de ativar. (D-3: aviso amigável, 3 dias antes do vencimento, com a chave Pix.)'),
('d0',        'RASCUNHO — copiar do node Configuração do workflow HUB — Cobrança Automática antes de ativar. (D0: cobrança no dia do vencimento, com a chave Pix.)'),
('d_mais_2',  'RASCUNHO — copiar do node Configuração do workflow HUB — Cobrança Automática antes de ativar. (D+2: lembrete de atraso, tom mais direto.)'),
('d_mais_7',  'RASCUNHO — copiar do node Configuração do workflow HUB — Cobrança Automática antes de ativar. (D+7: último aviso antes de escalar pra ela.)');

-- ---------- RPCs (security definer, padrão 003/007) ----------

-- lista clientes ativos com config de cobrança; vencimento e WhatsApp vêm
-- AO VIVO do contrato ativo e do contato principal (mesma fonte que
-- hub.bot_cobrancas_do_dia usa) — nunca uma cópia congelada.
create or replace function hub.rpc_cobranca_config_lista()
returns table (
  cliente_id uuid, cliente_nome text, config_id uuid,
  metodo text, ativo boolean, dia_vencimento smallint, whatsapp_e164 text
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    c.id, c.nome, cc.id, cc.metodo, coalesce(cc.ativo, false),
    (select ct.dia_vencimento from hub.contratos ct
       where ct.cliente_id = c.id and ct.status = 'ativo'
       order by ct.created_at desc limit 1),
    (select k.whatsapp_e164 from hub.contatos k
       where k.cliente_id = c.id and k.whatsapp_e164 is not null
       order by k.is_principal desc limit 1)
  from hub.clientes c
  left join hub.cobranca_config cc on cc.cliente_id = c.id
  where c.status = 'ativo'
  order by c.nome;
end;
$$;

create or replace function hub.rpc_salvar_cobranca_config(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.cobranca_config (id, cliente_id, metodo, ativo)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()),
    (p->>'cliente_id')::uuid,
    coalesce(p->>'metodo', 'pix'),
    coalesce((p->>'ativo')::boolean, true)
  )
  on conflict (cliente_id) do update set
    metodo=excluded.metodo, ativo=excluded.ativo
  returning id into v_id;

  return v_id;
end;
$$;

-- ordem fixa D-3 → D0 → D+2 → D+7 (alfabética ficaria errada)
create or replace function hub.rpc_cobranca_mensagens()
returns setof hub.cobranca_mensagens
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select * from hub.cobranca_mensagens
  order by case etapa when 'd_menos_3' then 0 when 'd0' then 1 when 'd_mais_2' then 2 when 'd_mais_7' then 3 end;
end;
$$;

create or replace function hub.rpc_salvar_cobranca_mensagem(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.cobranca_mensagens
  set texto = p->>'texto'
  where etapa = p->>'etapa'
  returning id into v_id;

  if v_id is null then raise exception 'etapa de régua inválida'; end if;
  return v_id;
end;
$$;

-- lê o log REAL do bot (hub.cobranca_envios, por recebível+bucket, já
-- existente desde a Fase 2) e traduz pra cliente — não duplica tabela.
create or replace function hub.rpc_cobranca_envios_recentes(p_limit int default 20)
returns table (
  cliente_id uuid, cliente_nome text, etapa text, enviado_em timestamptz
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select c.id, c.nome, ce.bucket, ce.enviado_em
  from hub.cobranca_envios ce
  join hub.recebiveis r on r.id = ce.recebivel_id
  join hub.clientes c on c.id = r.cliente_id
  order by ce.enviado_em desc
  limit coalesce(p_limit, 20);
end;
$$;

revoke all on function hub.rpc_cobranca_config_lista() from public, anon;
revoke all on function hub.rpc_salvar_cobranca_config(jsonb) from public, anon;
revoke all on function hub.rpc_cobranca_mensagens() from public, anon;
revoke all on function hub.rpc_salvar_cobranca_mensagem(jsonb) from public, anon;
revoke all on function hub.rpc_cobranca_envios_recentes(int) from public, anon;

grant execute on function hub.rpc_cobranca_config_lista() to authenticated;
grant execute on function hub.rpc_salvar_cobranca_config(jsonb) to authenticated;
grant execute on function hub.rpc_cobranca_mensagens() to authenticated;
grant execute on function hub.rpc_salvar_cobranca_mensagem(jsonb) to authenticated;
grant execute on function hub.rpc_cobranca_envios_recentes(int) to authenticated;

-- ---------- wrappers públicos (mesmo padrão do 004) ----------
create or replace function public.hub_rpc_cobranca_config_lista()
returns table (
  cliente_id uuid, cliente_nome text, config_id uuid,
  metodo text, ativo boolean, dia_vencimento smallint, whatsapp_e164 text
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_cobranca_config_lista(); $$;

create or replace function public.hub_rpc_salvar_cobranca_config(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_cobranca_config(p); $$;

create or replace function public.hub_rpc_cobranca_mensagens()
returns setof hub.cobranca_mensagens
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_cobranca_mensagens(); $$;

create or replace function public.hub_rpc_salvar_cobranca_mensagem(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_cobranca_mensagem(p); $$;

create or replace function public.hub_rpc_cobranca_envios_recentes(p_limit int)
returns table (
  cliente_id uuid, cliente_nome text, etapa text, enviado_em timestamptz
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_cobranca_envios_recentes(p_limit); $$;

revoke all on function public.hub_rpc_cobranca_config_lista() from public, anon;
revoke all on function public.hub_rpc_salvar_cobranca_config(jsonb) from public, anon;
revoke all on function public.hub_rpc_cobranca_mensagens() from public, anon;
revoke all on function public.hub_rpc_salvar_cobranca_mensagem(jsonb) from public, anon;
revoke all on function public.hub_rpc_cobranca_envios_recentes(int) from public, anon;

grant execute on function public.hub_rpc_cobranca_config_lista() to authenticated;
grant execute on function public.hub_rpc_salvar_cobranca_config(jsonb) to authenticated;
grant execute on function public.hub_rpc_cobranca_mensagens() to authenticated;
grant execute on function public.hub_rpc_salvar_cobranca_mensagem(jsonb) to authenticated;
grant execute on function public.hub_rpc_cobranca_envios_recentes(int) to authenticated;
