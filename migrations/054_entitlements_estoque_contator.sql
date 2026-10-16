-- Hub SaaS: gate de licenciamento por produto (P0 SEC-ENT-001).
-- INSTALACAO DEPENDENTE, NAO EXECUTAR ISOLADAMENTE:
-- 1. PR #3: criar tabelas e RPCs de Estoque/Contator.
-- 2. PR #15: 050, 051, 052 e 20261008112355 (role hub_rpc SEM BYPASSRLS).
-- 3. So entao aplicar esta migration, numa janela de homologacao com backup.
-- Nao altera a operacao single-tenant atual da Luciana enquanto nao aplicada.
-- Politica RESTRICTIVE usa AND com ws_ler/ws_inserir/ws_alterar/ws_apagar da 052.
-- Se faltar a 052, ABORTA: nao basta criar uma policy que SECURITY DEFINER
-- do postgres (BYPASSRLS) ignoraria silenciosamente.
begin;

do $$
declare t text; owner_name text; bypass boolean;
begin
  if to_regprocedure('hub.modulo_ativo(text)') is null
     or to_regprocedure('hub.modules_snapshot()') is null
     or not exists (select 1 from pg_roles where rolname='hub_rpc') then
    raise exception '054: aplique primeiro #3 e #15 (050/051/052/integracao)';
  end if;

  foreach t in array array[
    'stock_locations','stock_products','stock_positions',
    'stock_orders','stock_movements','advisory_records'
  ] loop
    if to_regclass('hub.' || t) is null then
      raise exception '054: modulo nao instalado: %', t;
    end if;
    if not exists(select 1 from pg_policies
                  where schemaname='hub' and tablename=t and policyname='ws_ler') then
      raise exception '054: RLS multiempresa (052) ausente em %', t;
    end if;
  end loop;

  select pg_get_userbyid(p.proowner) into owner_name
  from pg_proc p where p.oid='hub.modules_snapshot()'::regprocedure;
  select rolbypassrls into bypass from pg_roles where rolname=owner_name;
  if owner_name <> 'hub_rpc' or coalesce(bypass,true) then
    raise exception '054: modules_snapshot precisa ser owned by hub_rpc sem BYPASSRLS';
  end if;
  foreach t in array array['stock_save','stock_move','stock_order','advisory_save'] loop
    select pg_get_userbyid(p.proowner) into owner_name from pg_proc p
    where p.pronamespace='hub'::regnamespace and p.proname=t limit 1;
    if owner_name is distinct from 'hub_rpc' then
      raise exception '054: %.owner <> hub_rpc: %', t, owner_name;
    end if;
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'stock_locations','stock_products','stock_positions',
    'stock_orders','stock_movements'
  ] loop
    execute format('drop policy if exists licenca_estoque on hub.%I',t);
    execute format(
      'create policy licenca_estoque on hub.%I as restrictive for all ' ||
      'using ((select hub.modulo_ativo(''estoque''))) ' ||
      'with check ((select hub.modulo_ativo(''estoque'')))', t
    );
  end loop;
  drop policy if exists licenca_fiscal on hub.advisory_records;
  create policy licenca_fiscal on hub.advisory_records as restrictive for all
    using ((select hub.modulo_ativo('fiscal')))
    with check ((select hub.modulo_ativo('fiscal')));
end $$;

-- TODO: os demais pacotes precisam de gates equivalentes por RPC e por
-- dados compartilhados. Nao habilitar comercializacao apenas com esta migration.
commit;
