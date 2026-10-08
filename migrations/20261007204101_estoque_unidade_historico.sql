-- Preserva a unidade do histórico, inclusive após zerar o saldo.
-- Aplicar depois de 20261006052445; mantém as permissões da função existente.
begin;
create or replace function hub.stock_save(p_kind text,p_data jsonb) returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid:=hub.stock_lock(); rid uuid:=coalesce((p_data->>'id')::uuid,gen_random_uuid()); n numeric; loc uuid;
begin
 if p_kind='location' then
 insert into hub.stock_locations(id,workspace_id,name,capacity_liters,active) values(rid,w,trim(p_data->>'name'),(p_data->>'capacity_liters')::numeric,coalesce((p_data->>'active')::boolean,true))
 on conflict(id) do update set name=excluded.name,capacity_liters=excluded.capacity_liters,active=excluded.active where hub.stock_locations.workspace_id=w;
 if not found then raise exception 'Local fora do workspace.'; end if;
 if not (select active from hub.stock_locations where id=rid) and exists(select 1 from hub.stock_positions where workspace_id=w and location_id=rid and quantity>0) then raise exception 'Local possui saldo.'; end if;
 if exists(select 1 from hub.stock_orders where workspace_id=w and location_id=rid and status='open') then raise exception 'Conclua ou cancele os pedidos antes de editar o local.'; end if;
 if (select active from hub.stock_locations where id=rid) then perform hub.stock_capacity(w,rid,0,1); end if;
 elsif p_kind='product' then
 if exists(select 1 from hub.stock_orders where workspace_id=w and product_id=rid and status='open') then raise exception 'Conclua ou cancele pedidos antes de editar o item.'; end if;
 if exists(select 1 from hub.stock_products where workspace_id=w and id=rid and unit<>p_data->>'unit')
 and (exists(select 1 from hub.stock_positions where workspace_id=w and product_id=rid and quantity>0)
 or exists(select 1 from hub.stock_movements where workspace_id=w and product_id=rid))
 then raise exception 'Unidade não pode mudar com saldo ou histórico. Cadastre outro item.'; end if;
 insert into hub.stock_products(id,workspace_id,sku,name,category,unit,minimum_quantity,target_quantity,maximum_quantity,pack_quantity,volume_liters,supplier,lead_days,preferred_location_id,active)
 values(rid,w,trim(p_data->>'sku'),trim(p_data->>'name'),coalesce(p_data->>'category',''),p_data->>'unit',(p_data->>'minimum_quantity')::numeric,(p_data->>'target_quantity')::numeric,(p_data->>'maximum_quantity')::numeric,(p_data->>'pack_quantity')::numeric,(p_data->>'volume_liters')::numeric,coalesce(p_data->>'supplier',''),coalesce((p_data->>'lead_days')::integer,0),(p_data->>'preferred_location_id')::uuid,coalesce((p_data->>'active')::boolean,true))
 on conflict(id) do update set sku=excluded.sku,name=excluded.name,category=excluded.category,unit=excluded.unit,minimum_quantity=excluded.minimum_quantity,target_quantity=excluded.target_quantity,maximum_quantity=excluded.maximum_quantity,pack_quantity=excluded.pack_quantity,volume_liters=excluded.volume_liters,supplier=excluded.supplier,lead_days=excluded.lead_days,preferred_location_id=excluded.preferred_location_id,active=excluded.active where hub.stock_products.workspace_id=w;
 if not found then raise exception 'Item fora do workspace.'; end if;
 select sum(quantity) into n from hub.stock_positions where workspace_id=w and product_id=rid;
 if n>0 and not coalesce((p_data->>'active')::boolean,true) then raise exception 'Item possui saldo. Zere ou transfira antes de desativar.'; end if;
 if n>(p_data->>'maximum_quantity')::numeric then raise exception 'Máximo inferior ao saldo atual.'; end if;
 for loc in select distinct location_id from hub.stock_positions where workspace_id=w and product_id=rid and quantity>0 loop perform hub.stock_capacity(w,loc,0,(p_data->>'volume_liters')::numeric); end loop;
 else raise exception 'Cadastro inválido.'; end if;
 return rid;
end $$;
notify pgrst,'reload schema';
commit;
