-- ============================================================
-- HUB LUH PANDA — 007: demandas por cliente (Bloco 1.5, item 3)
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (21/09/2026) — esta sessão de dev não
-- teve acesso às ferramentas MCP do Supabase (mesma limitação da primeira
-- sessão do Bloco A, ver cabeçalho da 006). Antes de aplicar numa sessão
-- com acesso:
--   1) conferir por introspecção (`list_tables` verbose) que hub.clientes
--      existe com pk uuid `id` (referenciada abaixo) — deve bater com a
--      002_nucleo_carteira.sql;
--   2) aplicar via `apply_migration`;
--   3) testar as 3 RPCs com `execute_sql` (o guard is_admin() vai negar
--      fora de sessão autenticada — "acesso negado" é o esperado);
--   4) rodar `get_advisors` (security) depois.
-- O front (ficha do cliente, seção "Demandas") já degrada com aviso
-- amigável enquanto esta migration não estiver aplicada.
-- ============================================================

create table hub.demandas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references hub.clientes(id) on delete cascade,
  titulo text not null,
  descricao text,
  entrega_em date,
  status text not null default 'aberta' check (status in ('aberta','fazendo','entregue')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- mesmos triggers padrão de todas as tabelas do hub (002)
create trigger trg_demandas_updated_at
  before update on hub.demandas
  for each row execute function hub.set_updated_at();
create trigger trg_demandas_auditoria
  after insert or update or delete on hub.demandas
  for each row execute function hub.registrar_auditoria();

alter table hub.demandas enable row level security;
create policy hub_demandas_admin_all on hub.demandas
  for all using (hub.is_admin()) with check (hub.is_admin());

-- ---------- RPCs (security definer, padrão 003) ----------
create or replace function hub.rpc_demandas_cliente(p_cliente_id uuid)
returns setof hub.demandas
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select * from hub.demandas
  where cliente_id = p_cliente_id
  -- abertas/fazendo primeiro, ordenadas pela entrega mais próxima
  order by (status = 'entregue'), entrega_em nulls last, created_at;
end;
$$;

create or replace function hub.rpc_salvar_demanda(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.demandas (id, cliente_id, titulo, descricao, entrega_em, status)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()),
    (p->>'cliente_id')::uuid,
    p->>'titulo',
    p->>'descricao',
    (p->>'entrega_em')::date,
    coalesce(p->>'status', 'aberta')
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, titulo=excluded.titulo, descricao=excluded.descricao,
    entrega_em=excluded.entrega_em, status=excluded.status
  returning id into v_id;

  return v_id;
end;
$$;

-- delete real — o trigger de auditoria acima grava o `dados_antes`
-- inteiro em hub.eventos_auditoria antes de sumir, então o rastro fica.
create or replace function hub.rpc_apagar_demanda(p_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.demandas where id = p_id;
  if not found then raise exception 'demanda não encontrada'; end if;
end;
$$;

revoke all on function hub.rpc_demandas_cliente(uuid) from public, anon;
revoke all on function hub.rpc_salvar_demanda(jsonb) from public, anon;
revoke all on function hub.rpc_apagar_demanda(uuid) from public, anon;
grant execute on function hub.rpc_demandas_cliente(uuid) to authenticated;
grant execute on function hub.rpc_salvar_demanda(jsonb) to authenticated;
grant execute on function hub.rpc_apagar_demanda(uuid) to authenticated;

-- ---------- wrappers públicos (mesmo padrão do 004) ----------
create or replace function public.hub_rpc_demandas_cliente(p_cliente_id uuid)
returns setof hub.demandas
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_demandas_cliente(p_cliente_id); $$;

create or replace function public.hub_rpc_salvar_demanda(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_demanda(p); $$;

create or replace function public.hub_rpc_apagar_demanda(p_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_apagar_demanda(p_id); $$;

revoke all on function public.hub_rpc_demandas_cliente(uuid) from public, anon;
revoke all on function public.hub_rpc_salvar_demanda(jsonb) from public, anon;
revoke all on function public.hub_rpc_apagar_demanda(uuid) from public, anon;
grant execute on function public.hub_rpc_demandas_cliente(uuid) to authenticated;
grant execute on function public.hub_rpc_salvar_demanda(jsonb) to authenticated;
grant execute on function public.hub_rpc_apagar_demanda(uuid) to authenticated;
