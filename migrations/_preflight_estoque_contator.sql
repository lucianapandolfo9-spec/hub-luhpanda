-- Somente leitura. Executar no SQL Editor antes da migration de Estoque/Contator.
-- Esperado: todas as linhas com ok=true. Se houver false, revisar antes de instalar.
select 'prerequisito' as etapa, label as verificacao, ok
from (values
 ('schema hub', exists(select 1 from pg_namespace where nspname='hub')),
 ('papel anon', exists(select 1 from pg_roles where rolname='anon')),
 ('papel authenticated', exists(select 1 from pg_roles where rolname='authenticated')),
 ('tabela workspaces', to_regclass('hub.workspaces') is not null),
 ('tabela de auditoria', to_regclass('hub.eventos_auditoria') is not null),
 ('auth.uid()', to_regprocedure('auth.uid()') is not null),
 ('hub.is_admin()', to_regprocedure('hub.is_admin()') is not null),
 ('hub.default_workspace_id()', to_regprocedure('hub.default_workspace_id()') is not null),
 ('hub.registrar_auditoria()', to_regprocedure('hub.registrar_auditoria()') is not null)
) checks(label,ok)
union all
select 'objeto_novo_ausente', name, to_regclass('hub.'||name) is null
from unnest(array['stock_locations','stock_products','stock_positions','stock_orders','stock_movements','advisory_records']) name
union all
select 'objeto_novo_ausente', signature, to_regprocedure(signature) is null
from unnest(array[
 'hub.modules_workspace()', 'hub.stock_lock()', 'hub.stock_capacity(uuid,uuid,numeric,numeric)',
 'hub.modules_snapshot()', 'hub.stock_save(text,jsonb)', 'hub.stock_move(jsonb)',
 'hub.stock_order(jsonb)', 'hub.advisory_save(text,jsonb,uuid,integer)',
 'public.hub_rpc_modules_snapshot()', 'public.hub_rpc_stock_save(text,jsonb)',
 'public.hub_rpc_stock_move(jsonb)', 'public.hub_rpc_stock_order(jsonb)',
 'public.hub_rpc_advisory_save(text,jsonb,uuid,integer)'
]) signature
order by etapa,verificacao;
