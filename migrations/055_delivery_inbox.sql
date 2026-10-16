-- 055 — Hub: caixa de entrada de eventos de marketplaces de delivery.
--
-- DRAFT, depende da instalação dos módulos (#3), da 050/051/052 + integração
-- (#15) e dos gates de licença (#24 / migration 054). NÃO APLICAR na
-- base existente sem staging, backup e homologação.
-- A ingestão só aceita EVENTOS JÁ AUTENTICADOS e NORMALIZADOS pelo backend;
-- este SQL nunca autentica webhooks de iFood/Rappi/99Food por si.
begin;

do $$
begin
  if to_regprocedure('hub.current_workspace_id()') is null
     or to_regprocedure('hub.modulo_ativo(text)') is null
     or not exists (select 1 from pg_roles where rolname='hub_rpc') then
    raise exception '055: falta a virada multiempresa e os gates de licenca (#15/#24)';
  end if;
  if not exists(select 1 from pg_policies
                where schemaname='hub' and tablename='stock_products'
                  and policyname='licenca_estoque') then
    raise exception '055: migration 054 ainda nao aplicada';
  end if;
end $$;

insert into hub.modulos(slug,nome,ordem)
values ('pedidos_delivery','Central de pedidos de delivery',7)
on conflict (slug) do nothing;
-- IMPORTANTE: nenhuma conta recebe este modulo automaticamente.

create table hub.delivery_connections (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id),
  provider text not null check (provider in ('ifood','99food','rappi')),
  external_store_id text not null check (length(btrim(external_store_id)) between 1 and 180),
  nome text not null default '',
  ativo boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique(provider,external_store_id),
  unique(workspace_id,id)
);

create table hub.delivery_orders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id),
  connection_id uuid not null,
  external_order_id text not null check (length(btrim(external_order_id)) between 1 and 180),
  status text not null default 'revisar'
    check(status in ('agendado','novo','confirmado','preparando','pronto',
                     'em_entrega','concluido','cancelado','revisar')),
  ultimo_evento_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique(connection_id,external_order_id),
  unique(workspace_id,id),
  foreign key(workspace_id,connection_id)
    references hub.delivery_connections(workspace_id,id)
);
create index idx_delivery_orders_painel
  on hub.delivery_orders(workspace_id,status,atualizado_em desc);

create table hub.delivery_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id),
  connection_id uuid not null,
  order_id uuid not null,
  external_event_id text not null check(length(btrim(external_event_id)) between 1 and 180),
  source_status text not null default '',
  normalized_status text not null,
  ocorrido_em timestamptz,
  recebido_em timestamptz not null default now(),
  unique(connection_id,external_event_id),
  foreign key(workspace_id,connection_id)
    references hub.delivery_connections(workspace_id,id),
  foreign key(workspace_id,order_id)
    references hub.delivery_orders(workspace_id,id)
);
create index idx_delivery_events_workspace
  on hub.delivery_events(workspace_id,recebido_em desc);

-- Role interna sem BYPASSRLS, nunca o navegador e nem o service_role.
do $$
declare t text;
begin
  foreach t in array array['delivery_connections','delivery_orders','delivery_events'] loop
    execute format('alter table hub.%I enable row level security',t);
    execute format('revoke all on hub.%I from public, anon, authenticated',t);
    execute format('grant select, insert, update, delete on hub.%I to hub_rpc',t);
    execute format('create policy ws_ler on hub.%I for select to hub_rpc using ' ||
      '(workspace_id = (select hub.current_workspace_id()) and (select hub.modulo_ativo(''pedidos_delivery'')))',t);
    execute format('create policy ws_inserir on hub.%I for insert to hub_rpc with check ' ||
      '(workspace_id = (select hub.current_workspace_id()) and (select hub.pode_escrever()) and (select hub.modulo_ativo(''pedidos_delivery'')))',t);
    execute format('create policy ws_alterar on hub.%I for update to hub_rpc using ' ||
      '(workspace_id = (select hub.current_workspace_id()) and (select hub.pode_escrever()) and (select hub.modulo_ativo(''pedidos_delivery''))) with check ' ||
      '(workspace_id = (select hub.current_workspace_id()) and (select hub.pode_escrever()) and (select hub.modulo_ativo(''pedidos_delivery'')))',t);
    execute format('create policy ws_apagar on hub.%I for delete to hub_rpc using ' ||
      '(workspace_id = (select hub.current_workspace_id()) and (select hub.pode_escrever()) and (select hub.modulo_ativo(''pedidos_delivery'')))',t);
    execute format('create trigger delivery_audit after insert or update or delete on hub.%I ' ||
      'for each row execute function hub.registrar_auditoria()',t);
  end loop;
end $$;

-- Lista apenas o workspace + módulo contratado. Sem dados pessoais.
create function hub.rpc_delivery_orders(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare output jsonb;
begin
  if not hub.pode_ler() or not hub.modulo_ativo('pedidos_delivery')
     or coalesce(p_limit,0) not between 1 and 200 then
    raise exception 'acesso negado ou limite invalido';
  end if;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into output from (
    select o.id,o.connection_id,c.provider,c.nome as loja,
      o.external_order_id,o.status,o.ultimo_evento_em,o.atualizado_em
    from hub.delivery_orders o
    join hub.delivery_connections c
      on c.id=o.connection_id and c.workspace_id=o.workspace_id
    order by o.atualizado_em desc,o.id
    limit p_limit
  ) x;
  return output;
end $$;
alter function hub.rpc_delivery_orders(integer) owner to hub_rpc;
revoke all on function hub.rpc_delivery_orders(integer) from public,anon;
grant execute on function hub.rpc_delivery_orders(integer) to authenticated;
create function public.hub_rpc_delivery_orders(p_limit integer default 100)
returns jsonb language sql security invoker set search_path=pg_catalog as $$
  select hub.rpc_delivery_orders(p_limit)
$$;
revoke all on function public.hub_rpc_delivery_orders(integer) from public,anon;
grant execute on function public.hub_rpc_delivery_orders(integer) to authenticated;

-- Invocação APENAS pela Edge Function depois de autenticar assinatura/token
-- + resolver provider/store_id. A function mantém ownership postgres porque
-- precisa resolver a conexão globalmente (usuário humano NUNCA pode chamá-la).
create function hub.rpc_delivery_ingest(p_provider text,p_store_id text,p_event jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  c hub.delivery_connections;
  o hub.delivery_orders;
  ev hub.delivery_events;
  v_order text := btrim(coalesce(p_event->>'externalOrderId',''));
  v_event text := btrim(coalesce(p_event->>'externalEventId',''));
  v_status text := btrim(coalesce(p_event->>'status',''));
  v_source text := left(coalesce(p_event->>'sourceStatus',''),100);
  v_time timestamptz;
  v_next text;
  v_current_rank integer;
  v_new_rank integer;
begin
  if auth.uid() is not null or coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'acesso negado';
  end if;
  if p_provider not in ('ifood','99food','rappi') or p_event is null
    or jsonb_typeof(p_event)<>'object'
    or length(v_order) not between 1 and 180
    or length(v_event) not between 1 and 180
    or v_status not in ('agendado','novo','confirmado','preparando','pronto',
                       'em_entrega','concluido','cancelado','revisar') then
    raise exception 'evento invalido';
  end if;
  if nullif(btrim(coalesce(p_event->>'externalStoreId','')),'') is distinct from p_store_id then
    raise exception 'loja do evento nao confere';
  end if;
  if p_event ? 'occurredAt' and jsonb_typeof(p_event->'occurredAt')='string' then
    v_time := (p_event->>'occurredAt')::timestamptz;
  end if;

  select * into c from hub.delivery_connections
   where provider=p_provider and external_store_id=p_store_id and ativo;
  if not found then raise exception 'conexao nao autorizada'; end if;
  if not exists(select 1 from hub.workspaces w
                 where w.id=c.workspace_id and w.status='ativo') then
    raise exception 'workspace suspenso ou em onboarding';
  end if;
  if not exists(select 1 from hub.workspace_modulos m
                 where m.workspace_id=c.workspace_id
                   and m.modulo_slug='pedidos_delivery'
                   and m.ativo and (m.ate is null or m.ate>=current_date)) then
    raise exception 'pacote delivery nao contratado';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    c.id::text||':'||v_order,0));
  select * into ev from hub.delivery_events
    where connection_id=c.id and external_event_id=v_event;
  if found then
    -- O mesmo ID de evento nunca pode apontar para outro pedido da loja.
    -- Falhar em vez de aceitar em silencio evita misturar historicos.
    if not exists (
      select 1 from hub.delivery_orders existing
       where existing.id = ev.order_id
         and existing.connection_id = c.id
         and existing.external_order_id = v_order
    ) then
      raise exception 'colisao entre evento e pedido';
    end if;
    return jsonb_build_object('duplicate',true,'orderId',ev.order_id);
  end if;

  insert into hub.delivery_orders(workspace_id,connection_id,external_order_id,status,ultimo_evento_em)
  values(c.workspace_id,c.id,v_order,v_status,v_time)
  on conflict(connection_id,external_order_id) do nothing;
  select * into o from hub.delivery_orders
    where connection_id=c.id and external_order_id=v_order for update;
  if not found then raise exception 'pedido nao encontrado'; end if;

  -- Evento fora de ordem nunca retrocede pedido. Estado terminal e imutavel:
  -- corrigir eventual cancelamento tardio requer reconciliacao manual, nao
  -- um UPDATE automatico que pode confirmar duas vezes/alterar estoque.
  v_current_rank := array_position(
    array['agendado','novo','confirmado','preparando','pronto','em_entrega','concluido'],
    o.status);
  v_new_rank := array_position(
    array['agendado','novo','confirmado','preparando','pronto','em_entrega','concluido'],
    v_status);
  v_next := o.status;
  if o.status not in ('cancelado','concluido')
     and (v_time is null or o.ultimo_evento_em is null or v_time >= o.ultimo_evento_em)
  then
    if v_status='cancelado' then
      v_next := 'cancelado';
    elsif v_status<>'revisar'
      and (o.status='revisar' or coalesce(v_new_rank,-1)>=coalesce(v_current_rank,-1)) then
      v_next := v_status;
    end if;
  end if;
  update hub.delivery_orders
     set status=v_next,ultimo_evento_em=greatest(o.ultimo_evento_em,v_time),
         atualizado_em=now()
   where id=o.id;

  insert into hub.delivery_events(workspace_id,connection_id,order_id,
                                  external_event_id,source_status,normalized_status,ocorrido_em)
  values(c.workspace_id,c.id,o.id,v_event,v_source,v_status,v_time);
  return jsonb_build_object('duplicate',false,'orderId',o.id,'status',v_next);
end $$;
revoke all on function hub.rpc_delivery_ingest(text,text,jsonb) from public,anon,authenticated;
grant execute on function hub.rpc_delivery_ingest(text,text,jsonb) to service_role;
create function public.hub_rpc_delivery_ingest(p_provider text,p_store_id text,p_event jsonb)
returns jsonb language sql security invoker set search_path=pg_catalog as $$
  select hub.rpc_delivery_ingest(p_provider,p_store_id,p_event)
$$;
revoke all on function public.hub_rpc_delivery_ingest(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.hub_rpc_delivery_ingest(text,text,jsonb) to service_role;

notify pgrst,'reload schema';
commit;
