-- Somente leitura. Executar após instalar a migration no SQL Editor.
-- Esperado: 19 linhas, todas com ok=true; não consulta dados dos clientes.
with expected_tables(name) as (
 select unnest(array['stock_locations','stock_products','stock_positions','stock_orders','stock_movements','advisory_records'])
), table_checks as (
 select 'tabela'::text as tipo, 'hub.'||e.name as objeto,
 coalesce(c.relkind='r' and c.relrowsecurity
  and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='workspace_id' and a.attnotnull and not a.attisdropped)
  and exists(select 1 from pg_policy p where p.polrelid=c.oid and p.polname='modules_scope')
  and exists(select 1 from pg_trigger t where t.tgrelid=c.oid and t.tgname='modules_audit' and t.tgenabled in ('O','A') and not t.tgisinternal)
  and not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  and not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),false) as ok
 from expected_tables e left join pg_class c on c.oid=to_regclass('hub.'||e.name)
), expected_functions(signature,definer,authenticated_execute) as (values
 ('hub.modules_workspace()',true,false),
 ('hub.stock_lock()',true,false),
 ('hub.stock_capacity(uuid,uuid,numeric,numeric)',true,false),
 ('hub.modules_snapshot()',true,true),
 ('hub.stock_save(text,jsonb)',true,true),
 ('hub.stock_move(jsonb)',true,true),
 ('hub.stock_order(jsonb)',true,true),
 ('hub.advisory_save(text,jsonb,uuid,integer)',true,true),
 ('public.hub_rpc_modules_snapshot()',false,true),
 ('public.hub_rpc_stock_save(text,jsonb)',false,true),
 ('public.hub_rpc_stock_move(jsonb)',false,true),
 ('public.hub_rpc_stock_order(jsonb)',false,true),
 ('public.hub_rpc_advisory_save(text,jsonb,uuid,integer)',false,true)
), function_checks as (
 select 'funcao'::text as tipo,e.signature as objeto,
 coalesce(p.prosecdef=e.definer and 'search_path=pg_catalog'=any(p.proconfig)
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and has_function_privilege('authenticated',p.oid,'EXECUTE')=e.authenticated_execute,false) as ok
 from expected_functions e left join pg_proc p on p.oid=to_regprocedure(e.signature)
)
select * from table_checks union all select * from function_checks order by tipo,objeto;
