-- ============================================================
-- HUB LUH PANDA — 009: apagar recebível (Bloco 1.6, item 1)
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (22/09/2026) — esta sessão de dev não
-- teve acesso às ferramentas MCP do Supabase (nem Chrome), mesma
-- limitação das sessões anteriores (ver cabeçalho da 006/007/008).
-- Antes de aplicar numa sessão com acesso:
--   1) conferir por introspecção (`list_tables` verbose ou `execute_sql`
--      com \d hub.recebiveis) que a tabela ainda tem pk uuid `id` e o
--      trigger de auditoria `trg_recebiveis_auditoria` citado no pedido
--      da Luciana — coerente com o que hub_rpc_recebiveis/
--      hub_rpc_marcar_pago/hub_rpc_desmarcar_pago já usam em produção
--      (ver 006_dash_periodo_desmarcar_pago.sql, que documenta as
--      colunas: cliente_id, competencia, descricao, valor_centavos,
--      entrada_centavos, entrou_em, vence_em, falta_centavos GENERATED,
--      origem, observacao);
--   2) aplicar via `apply_migration`;
--   3) testar a RPC com `execute_sql` (o guard is_admin() nega fora de
--      sessão autenticada — "acesso negado" é o esperado);
--   4) rodar `get_advisors` (security) depois.
--
-- Delete REAL (não soft) — mesmo padrão do 008_apagar_contrato.sql e do
-- 007_demandas.sql (rpc_apagar_demanda). O trigger de auditoria que já
-- existe na tabela grava o `dados_antes` inteiro em hub.eventos_auditoria
-- antes de sumir, então o rastro fica — não precisa criar nada novo de
-- auditoria aqui.
-- ============================================================

create or replace function hub.rpc_apagar_recebivel(p_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.recebiveis where id = p_id;
  if not found then raise exception 'recebível não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_apagar_recebivel(uuid) from public, anon;
grant execute on function hub.rpc_apagar_recebivel(uuid) to authenticated;

-- ---------- wrapper público (mesmo padrão do 004/007/008) ----------
create or replace function public.hub_rpc_apagar_recebivel(p_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_apagar_recebivel(p_id); $$;

revoke all on function public.hub_rpc_apagar_recebivel(uuid) from public, anon;
grant execute on function public.hub_rpc_apagar_recebivel(uuid) to authenticated;
