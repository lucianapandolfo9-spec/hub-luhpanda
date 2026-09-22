-- ============================================================
-- HUB LUH PANDA — 008: apagar contrato (Bloco 1.5, item 4)
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (21/09/2026) — mesma pendência da 007:
-- aplicar numa sessão com Supabase MCP (`apply_migration`), testar com
-- `execute_sql` e rodar `get_advisors` depois.
--
-- Delete REAL (não soft): hub.contrato_itens tem `on delete cascade`
-- (002_nucleo_carteira.sql, linha do contrato_id) e as duas tabelas têm
-- trigger de auditoria — o `dados_antes` completo do contrato E de cada
-- item fica gravado em hub.eventos_auditoria antes de sumir.
-- ============================================================

create or replace function hub.rpc_apagar_contrato(p_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.contratos where id = p_id;
  if not found then raise exception 'contrato não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_apagar_contrato(uuid) from public, anon;
grant execute on function hub.rpc_apagar_contrato(uuid) to authenticated;

-- ---------- wrapper público (mesmo padrão do 004) ----------
create or replace function public.hub_rpc_apagar_contrato(p_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_apagar_contrato(p_id); $$;

revoke all on function public.hub_rpc_apagar_contrato(uuid) from public, anon;
grant execute on function public.hub_rpc_apagar_contrato(uuid) to authenticated;
