-- Estoque e assessoria Contator. Executar após 036; não altera recebíveis legados.
begin;
create table hub.stock_locations (
 id uuid primary key default gen_random_uuid(), workspace_id uuid not null references hub.workspaces(id),
 name text not null check(length(name) between 1 and 120), capacity_liters numeric(18,3) check(capacity_liters>0),
 active boolean not null default true, unique(workspace_id,id)
);
create table hub.stock_products (
 id uuid primary key default gen_random_uuid(), workspace_id uuid not null references hub.workspaces(id),
 sku text not null check(length(sku) between 1 and 80), name text not null check(length(name) between 1 and 180),
 category text not null default '', unit text not null check(unit in ('un','kg','l')),
 minimum_quantity numeric(18,3) not null check(minimum_quantity>=0), target_quantity numeric(18,3) not null,
 maximum_quantity numeric(18,3), pack_quantity numeric(18,3) not null check(pack_quantity>0),
 volume_liters numeric(18,3) check(volume_liters>0), supplier text not null default '', lead_days integer not null default 0 check(lead_days between 0 and 365),
 preferred_location_id uuid, active boolean not null default true,
 check(target_quantity>=minimum_quantity), check(maximum_quantity is null or maximum_quantity>=target_quantity),
 unique(workspace_id,sku), unique(workspace_id,id),
 foreign key(workspace_id,preferred_location_id) references hub.stock_locations(workspace_id,id)
);
create table hub.stock_positions (
 id uuid primary key default gen_random_uuid(), workspace_id uuid not null references hub.workspaces(id), product_id uuid not null, location_id uuid not null,
 lot text not null default '', expires_on date, quantity numeric(18,3) not null default 0 check(quantity>=0),
 unit_cost_centavos bigint not null default 0 check(unit_cost_centavos between 0 and 1000000000000),
 unique(workspace_id,id), unique(workspace_id,product_id,location_id,lot),
 foreign key(workspace_id,product_id) references hub.stock_products(workspace_id,id),
 foreign key(workspace_id,location_id) references hub.stock_locations(workspace_id,id)
);
create table hub.stock_orders (
 id uuid primary key default gen_random_uuid(), workspace_id uuid not null references hub.workspaces(id), product_id uuid not null, location_id uuid not null,
 quantity numeric(18,3) not null check(quantity>0), received_quantity numeric(18,3) not null default 0 check(received_quantity>=0 and received_quantity<=quantity),
 supplier text not null, expected_on date, status text not null default 'open' check(status in ('open','received','cancelled')),
 created_at timestamptz not null default now(), unique(workspace_id,id),
 foreign key(workspace_id,product_id) references hub.stock_products(workspace_id,id),
 foreign key(workspace_id,location_id) references hub.stock_locations(workspace_id,id)
);
create table hub.stock_movements (
 id uuid primary key, workspace_id uuid not null references hub.workspaces(id), product_id uuid not null,
 position_id uuid, destination_id uuid, order_id uuid, type text not null,
 quantity numeric(18,3) not null, cost_total_centavos bigint not null, revenue_centavos bigint not null default 0,
 reason text not null, actor uuid not null, payload jsonb not null, created_at timestamptz not null default now(),
 unique(workspace_id,id), foreign key(workspace_id,product_id) references hub.stock_products(workspace_id,id),
 foreign key(workspace_id,position_id) references hub.stock_positions(workspace_id,id),
 foreign key(workspace_id,destination_id) references hub.stock_positions(workspace_id,id),
 foreign key(workspace_id,order_id) references hub.stock_orders(workspace_id,id)
);
create index stock_movements_history on hub.stock_movements(workspace_id,created_at desc);
create index stock_positions_location on hub.stock_positions(workspace_id,location_id);
create index stock_orders_open on hub.stock_orders(workspace_id,product_id) where status='open';
create table hub.advisory_records (
 id uuid primary key default gen_random_uuid(), workspace_id uuid not null references hub.workspaces(id),
 kind text not null check(kind in ('profile','period','scenario','action')), data jsonb not null,
 revision integer not null default 1, updated_at timestamptz not null default now(), unique(workspace_id,id)
);
create index advisory_records_workspace on hub.advisory_records(workspace_id,kind);
create unique index advisory_profile_one on hub.advisory_records(workspace_id) where kind='profile';

create function hub.modules_workspace() returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid;
begin
 if auth.uid() is null or not hub.is_admin() then raise exception 'Acesso negado.'; end if;
 w:=hub.default_workspace_id(); if w is null then raise exception 'Workspace não configurado.'; end if;
 return w;
end $$;
-- Um lock por workspace serializa movimentos, compras e mudanças de capacidade.
create function hub.stock_lock() returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid:=hub.modules_workspace();
begin perform pg_advisory_xact_lock(hashtextextended(w::text,0)); return w; end $$;
create function hub.stock_capacity(w uuid, loc uuid, added numeric, volume numeric) returns void
 language plpgsql security definer set search_path=pg_catalog as $$
declare cap numeric; used numeric;
begin
 select capacity_liters into cap from hub.stock_locations where workspace_id=w and id=loc and active;
 if not found then raise exception 'Local indisponível.'; end if;
 if cap is null then return; end if;
 if volume is null or exists(select 1 from hub.stock_positions b join hub.stock_products p on p.id=b.product_id and p.workspace_id=b.workspace_id where b.workspace_id=w and b.location_id=loc and b.quantity>0 and p.volume_liters is null)
 then raise exception 'Informe o volume de todos os itens deste local.'; end if;
 select coalesce(sum(b.quantity*p.volume_liters),0) into used from hub.stock_positions b join hub.stock_products p on p.id=b.product_id and p.workspace_id=b.workspace_id where b.workspace_id=w and b.location_id=loc;
 if used+added*volume>cap then raise exception 'Capacidade do local excedida.'; end if;
end $$;
create function hub.modules_snapshot() returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid:=hub.modules_workspace();
begin return jsonb_build_object(
 'locations',coalesce((select jsonb_agg(t order by t.name) from hub.stock_locations t where workspace_id=w),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(t order by t.sku) from hub.stock_products t where workspace_id=w),'[]'::jsonb),
 'positions',coalesce((select jsonb_agg(t order by t.expires_on nulls last,t.id) from hub.stock_positions t where workspace_id=w),'[]'::jsonb),
 'orders',coalesce((select jsonb_agg(t order by t.created_at desc) from hub.stock_orders t where workspace_id=w),'[]'::jsonb),
 'movements',coalesce((select jsonb_agg(t order by t.created_at desc) from hub.stock_movements t where workspace_id=w and created_at>=now()-interval '90 days'),'[]'::jsonb),
 'advisory',coalesce((select jsonb_agg(t order by t.updated_at desc) from hub.advisory_records t where workspace_id=w),'[]'::jsonb)); end $$;
create function hub.stock_save(p_kind text,p_data jsonb) returns uuid language plpgsql security definer set search_path=pg_catalog as $$
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
 if exists(select 1 from hub.stock_positions where workspace_id=w and product_id=rid and quantity>0) and exists(select 1 from hub.stock_products where id=rid and unit<>p_data->>'unit') then raise exception 'Unidade não pode mudar com saldo.'; end if;
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
create function hub.stock_move(p_data jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
 w uuid:=hub.stock_lock(); op uuid:=(p_data->>'id')::uuid; typ text:=p_data->>'type'; prod hub.stock_products; b hub.stock_positions; dest hub.stock_positions; ord hub.stock_orders; prev hub.stock_movements;
 pid uuid:=(p_data->>'product_id')::uuid; loc uuid:=(p_data->>'location_id')::uuid; q numeric(18,3):=(p_data->>'quantity')::numeric;
 cost bigint:=coalesce((p_data->>'unit_cost_centavos')::bigint,0); revenue bigint:=coalesce((p_data->>'revenue_centavos')::bigint,0); delta numeric; total numeric; v_lot text:=coalesce(p_data->>'lot',''); expiry date:=(p_data->>'expires_on')::date;
begin
 if op is null or q is null or q<0 or q::text='NaN' or length(trim(coalesce(p_data->>'reason','')))=0 or length(p_data->>'reason')>2000 then raise exception 'Informe operação, quantidade e motivo.'; end if;
 select * into prev from hub.stock_movements where workspace_id=w and id=op;
 if found then if prev.payload<>p_data then raise exception 'Operação já utilizada com outros dados.'; end if; return to_jsonb(prev); end if;
 if typ not in ('entry','sale','consumption','loss','customer_return','supplier_return','transfer','count') or typ is null then raise exception 'Tipo de movimento inválido.'; end if;
 if typ<>'count' and q=0 then raise exception 'Quantidade deve ser positiva.'; end if;
 if cost<0 or cost>1000000000000 or revenue<0 or revenue>1000000000000 then raise exception 'Valor inválido.'; end if;
 select * into prod from hub.stock_products where workspace_id=w and id=pid and active;
 if not found then raise exception 'Item indisponível.'; end if;
 if p_data->>'order_id' is not null then
 select * into ord from hub.stock_orders where workspace_id=w and id=(p_data->>'order_id')::uuid and status='open' for update;
 if not found or typ<>'entry' or ord.product_id<>pid or q>ord.quantity-ord.received_quantity then raise exception 'Recebimento incompatível com pedido.'; end if;
 loc:=ord.location_id;
 end if;
 if typ in ('entry','customer_return') then
 perform hub.stock_capacity(w,loc,q,prod.volume_liters);
 select coalesce(sum(quantity),0) into total from hub.stock_positions where workspace_id=w and product_id=pid;
 if total+q>prod.maximum_quantity then raise exception 'Máximo do item excedido.'; end if;
 insert into hub.stock_positions(workspace_id,product_id,location_id,lot,expires_on) values(w,pid,loc,v_lot,expiry) on conflict(workspace_id,product_id,location_id,lot) do nothing;
 select * into b from hub.stock_positions where workspace_id=w and product_id=pid and location_id=loc and stock_positions.lot=v_lot for update;
 if b.expires_on is distinct from expiry then raise exception 'Lote já cadastrado com outra validade.'; end if;
 update hub.stock_positions set unit_cost_centavos=round((b.quantity*b.unit_cost_centavos+q*cost)/(b.quantity+q)),quantity=b.quantity+q where id=b.id;
 delta:=q;
 else
 select * into b from hub.stock_positions where workspace_id=w and id=(p_data->>'position_id')::uuid and product_id=pid for update;
 if not found then raise exception 'Saldo não encontrado.'; end if;
 cost:=b.unit_cost_centavos;
 if typ='count' then
 if p_data->>'expected_quantity' is null or b.quantity<>(p_data->>'expected_quantity')::numeric then raise exception 'Saldo mudou desde a contagem. Recarregue e confira.'; end if;
 delta:=q-b.quantity;
 if delta>0 then
 perform hub.stock_capacity(w,b.location_id,delta,prod.volume_liters);
 select coalesce(sum(quantity),0) into total from hub.stock_positions where workspace_id=w and product_id=pid;
 if total+delta>prod.maximum_quantity then raise exception 'Máximo do item excedido.'; end if;
 end if;
 else
 if b.quantity<q then raise exception 'Saldo insuficiente.'; end if;
 if typ in ('sale','consumption') and b.expires_on<(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Lote vencido. Registre perda ou devolução.'; end if;
 delta:=-q;
 end if;
 if typ='transfer' then
 if loc=b.location_id then raise exception 'Escolha outro local.'; end if;
 perform hub.stock_capacity(w,loc,q,prod.volume_liters);
 insert into hub.stock_positions(workspace_id,product_id,location_id,lot,expires_on,unit_cost_centavos) values(w,pid,loc,b.lot,b.expires_on,cost) on conflict(workspace_id,product_id,location_id,lot) do nothing;
 select * into dest from hub.stock_positions where workspace_id=w and product_id=pid and location_id=loc and stock_positions.lot=b.lot for update;
 if dest.expires_on is distinct from b.expires_on then raise exception 'Validade divergente no destino.'; end if;
 update hub.stock_positions set unit_cost_centavos=round((dest.quantity*dest.unit_cost_centavos+q*cost)/(dest.quantity+q)),quantity=dest.quantity+q where id=dest.id;
 end if;
 update hub.stock_positions set quantity=b.quantity+delta where id=b.id;
 end if;
 if ord.id is not null then update hub.stock_orders set received_quantity=received_quantity+q,status=case when received_quantity+q=quantity then 'received' else 'open' end where id=ord.id; end if;
 insert into hub.stock_movements(id,workspace_id,product_id,position_id,destination_id,order_id,type,quantity,cost_total_centavos,revenue_centavos,reason,actor,payload)
 values(op,w,pid,b.id,dest.id,ord.id,typ,case when typ='count' then delta else q end,round(abs(delta)*cost),case when typ='sale' then revenue else 0 end,p_data->>'reason',auth.uid(),p_data) returning * into prev;
 return to_jsonb(prev);
end $$;
create function hub.stock_order(p_data jsonb) returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid:=hub.stock_lock(); rid uuid:=coalesce((p_data->>'id')::uuid,gen_random_uuid()); prod hub.stock_products; loc uuid:=(p_data->>'location_id')::uuid; q numeric(18,3):=(p_data->>'quantity')::numeric; pending numeric; stock numeric; cap numeric; used numeric;
begin
 if p_data->>'status'='cancelled' then update hub.stock_orders set status='cancelled' where id=rid and workspace_id=w and status='open'; if not found then raise exception 'Pedido não disponível.'; end if; return rid; end if;
 if q is null or q<=0 or q::text='NaN' or length(trim(coalesce(p_data->>'supplier','')))=0 then raise exception 'Informe quantidade e fornecedor.'; end if;
 if exists(select 1 from hub.stock_orders where id=rid) then raise exception 'Pedido já registrado. Recarregue.'; end if;
 select * into prod from hub.stock_products where workspace_id=w and id=(p_data->>'product_id')::uuid and active;
 if not found then raise exception 'Item não disponível.'; end if;
 select coalesce(sum(quantity),0) into stock from hub.stock_positions where workspace_id=w and product_id=prod.id;
 select coalesce(sum(quantity-received_quantity),0) into pending from hub.stock_orders where workspace_id=w and product_id=prod.id and status='open';
 if stock+pending+q>prod.maximum_quantity then raise exception 'Saldo e compras excedem o máximo do item.'; end if;
 perform hub.stock_capacity(w,loc,q,prod.volume_liters);
 select capacity_liters into cap from hub.stock_locations where workspace_id=w and id=loc;
 if cap is not null then
 if exists(select 1 from hub.stock_orders o join hub.stock_products p on p.id=o.product_id where o.workspace_id=w and o.location_id=loc and o.status='open' and p.volume_liters is null) then raise exception 'Pedido pendente sem volume cadastrado.'; end if;
 select coalesce(sum(b.quantity*p.volume_liters),0) into used from hub.stock_positions b join hub.stock_products p on p.id=b.product_id where b.workspace_id=w and b.location_id=loc;
 select coalesce(sum((o.quantity-o.received_quantity)*p.volume_liters),0) into pending from hub.stock_orders o join hub.stock_products p on p.id=o.product_id where o.workspace_id=w and o.location_id=loc and o.status='open';
 if used+pending+q*prod.volume_liters>cap then raise exception 'Capacidade já reservada por compras.'; end if;
 end if;
 insert into hub.stock_orders(id,workspace_id,product_id,location_id,quantity,supplier,expected_on) values(rid,w,prod.id,loc,q,p_data->>'supplier',(p_data->>'expected_on')::date); return rid;
end $$;
create function hub.advisory_save(p_kind text,p_data jsonb,p_id uuid default null,p_revision integer default null) returns uuid
 language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid:=hub.stock_lock(); rid uuid:=coalesce(p_id,gen_random_uuid()); k text; n numeric; existing hub.advisory_records;
begin
 if p_kind not in ('profile','period','scenario','action') or p_kind is null or jsonb_typeof(p_data)<>'object' or p_data is null or octet_length(p_data::text)>30000 then raise exception 'Registro inválido.'; end if;
 if p_kind='profile' then
 if coalesce(p_data->>'cnpj','')!~'^[A-Z0-9]{12}[0-9]{2}$' or length(trim(coalesce(p_data->>'name','')))=0 then raise exception 'Informe empresa e CNPJ com 14 posições (sem pontuação).'; end if;
 select * into existing from hub.advisory_records where workspace_id=w and kind='profile';
 if found then rid:=existing.id; end if;
 end if;
 if p_kind in ('period','scenario') then
 if p_kind='period' and coalesce(p_data->>'competence','')!~'^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Competência inválida.'; end if;
 if p_kind='scenario' and (coalesce(p_data->>'regime','') not in ('MEI','Simples Nacional','Lucro Presumido','Lucro Real') or coalesce(p_data->>'eligibility','') not in ('pending','confirmed','blocked') or length(trim(coalesce(p_data->>'name','')))=0) then raise exception 'Informe regime, elegibilidade e nome.'; end if;
 if length(trim(coalesce(p_data->>'assumptions','')))=0 or coalesce(p_data->>'source_url','')!~'^https://[^[:space:]]+$' then raise exception 'Informe premissas e fonte HTTPS.'; end if;
 if coalesce(p_data->>'valid_on','')='' then raise exception 'Informe a data-base das premissas.'; end if;
 perform (p_data->>'valid_on')::date;
 if jsonb_typeof(p_data->'inputs')<>'object' or p_data->'inputs' is null then raise exception 'Premissas numéricas obrigatórias.'; end if;
 foreach k in array array['revenue_centavos','variable_centavos','fixed_centavos','payroll_centavos','extra_tax_centavos','credits_centavos','rate_percent'] loop
 if jsonb_typeof(p_data->'inputs'->k)<>'number' or p_data->'inputs'->k is null then raise exception 'Informe %.',k; end if;
 n:=(p_data->'inputs'->>k)::numeric;
 if n<0 or n>1000000000000 or n::text in ('NaN','Infinity','-Infinity') or (k='rate_percent' and n>100) or (k<>'rate_percent' and n<>trunc(n)) then raise exception 'Premissa inválida: %.',k; end if;
 end loop;
 if p_kind='scenario' and p_data->>'eligibility'='confirmed' and (length(trim(coalesce(p_data->>'reviewed_by','')))=0 or length(trim(coalesce(p_data->>'review_note','')))=0) then raise exception 'Confirmação exige revisor e evidência de elegibilidade.'; end if;
 end if;
 if p_kind='action' then
 if length(trim(coalesce(p_data->>'title','')))=0 or length(trim(coalesce(p_data->>'owner','')))=0 or coalesce(p_data->>'status','') not in ('open','in_review','done') then raise exception 'Informe ação, responsável e status.'; end if;
 if p_data->>'due_on' is null then raise exception 'Informe prazo.'; end if;
 perform (p_data->>'due_on')::date;
 if p_data->>'amount_centavos' is not null then
 n:=(p_data->>'amount_centavos')::numeric;
 if jsonb_typeof(p_data->'amount_centavos')<>'number' or n<0 or n>1000000000000 or n<>trunc(n) or n::text in ('NaN','Infinity','-Infinity') then raise exception 'Valor previsto inválido.'; end if;
 end if;
 if p_data->>'status'='done' and length(trim(coalesce(p_data->>'evidence','')))=0 then raise exception 'Conclusão exige evidência.'; end if;
 end if;
 select * into existing from hub.advisory_records where id=rid;
 if found then
 if existing.workspace_id<>w or existing.kind<>p_kind then raise exception 'Registro indisponível.'; end if;
 if p_revision is null or p_revision<>existing.revision then raise exception 'Registro mudou. Recarregue antes de salvar.'; end if;
 if p_kind='period' and exists(select 1 from hub.advisory_records where workspace_id=w and kind='period' and id<>rid and data->>'competence'=p_data->>'competence') then raise exception 'Competência já cadastrada.'; end if;
 update hub.advisory_records set data=p_data,revision=revision+1,updated_at=now() where id=rid;
 else
 if p_id is not null then raise exception 'Registro não encontrado.'; end if;
 if p_kind='period' and exists(select 1 from hub.advisory_records where workspace_id=w and kind='period' and data->>'competence'=p_data->>'competence') then raise exception 'Competência já cadastrada.'; end if;
 insert into hub.advisory_records(id,workspace_id,kind,data) values(rid,w,p_kind,p_data);
 end if;
 return rid;
end $$;
-- Rejeita NaN/Infinity, que o tipo numeric aceitaria em comparações usuais.
do $$ declare t text; c record; f record; begin
 foreach t in array array['stock_locations','stock_products','stock_positions','stock_orders','stock_movements','advisory_records'] loop
 execute format('alter table hub.%I enable row level security',t);
 execute format('revoke all on hub.%I from public, anon, authenticated',t);
 execute format('create policy modules_scope on hub.%I for all to authenticated using (auth.uid() is not null and hub.is_admin() and workspace_id=hub.default_workspace_id()) with check (auth.uid() is not null and hub.is_admin() and workspace_id=hub.default_workspace_id())',t);
 execute format('create trigger modules_audit after insert or update or delete on hub.%I for each row execute function hub.registrar_auditoria()',t);
 for c in select column_name from information_schema.columns where table_schema='hub' and table_name=t and data_type='numeric' loop
 execute format('alter table hub.%I add check (%I is null or %I::text not in (''NaN'',''Infinity'',''-Infinity''))',t,c.column_name,c.column_name);
 end loop;
 end loop;
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='hub' and p.proname in ('modules_workspace','stock_lock','stock_capacity','modules_snapshot','stock_save','stock_move','stock_order','advisory_save') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end $$;
-- Wrappers públicos invoker; apenas as fachadas privadas são executáveis.
create function public.hub_rpc_modules_snapshot() returns jsonb language sql security invoker set search_path=pg_catalog as $$ select hub.modules_snapshot() $$;
create function public.hub_rpc_stock_save(p_kind text,p_data jsonb) returns uuid language sql security invoker set search_path=pg_catalog as $$ select hub.stock_save(p_kind,p_data) $$;
create function public.hub_rpc_stock_move(p_data jsonb) returns jsonb language sql security invoker set search_path=pg_catalog as $$ select hub.stock_move(p_data) $$;
create function public.hub_rpc_stock_order(p_data jsonb) returns uuid language sql security invoker set search_path=pg_catalog as $$ select hub.stock_order(p_data) $$;
create function public.hub_rpc_advisory_save(p_kind text,p_data jsonb,p_id uuid default null,p_revision integer default null) returns uuid language sql security invoker set search_path=pg_catalog as $$ select hub.advisory_save(p_kind,p_data,p_id,p_revision) $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('hub_rpc_modules_snapshot','hub_rpc_stock_save','hub_rpc_stock_move','hub_rpc_stock_order','hub_rpc_advisory_save')) or (n.nspname='hub' and p.proname in ('modules_snapshot','stock_save','stock_move','stock_order','advisory_save')) loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
