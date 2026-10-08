-- DRAFT: correção de integração da 052 com PRs #3, #12 e #11.
-- Aplicar depois das migrations desses módulos e de 050/051/052,
-- na mesma janela de manutenção, antes de liberar qualquer workspace novo.
-- Nenhuma migration histórica é alterada. Rollback: 053_integracao_down.sql.
begin;
-- (removido em 08/10: o grill de banco com a Luciana decidiu VÁRIOS CNPJs por
--  workspace — P5. A trava empresas_um_cnpj_por_workspace saiu daqui.)
-- CNPJ repetido dentro do MESMO workspace continua proibido:
create unique index if not exists uq_empresas_ws_cnpj on hub.empresas (workspace_id, hub.cnpj_normalizar(cnpj)) where cnpj is not null;

-- Funções internas também precisam obedecer RLS. Só trocar rpc_* não basta.
do $$
declare f record; definition text;
begin
  if to_regprocedure('hub.rpc_novo_cliente(jsonb)') is not null then
    select pg_get_functiondef('hub.rpc_novo_cliente(jsonb)'::regprocedure) into definition;
    if position('v_ws uuid := hub.default_workspace_id()' in definition) = 0 then
      raise exception 'Integração: revisar definição de rpc_novo_cliente antes da virada';
    end if;
    execute replace(definition, 'v_ws uuid := hub.default_workspace_id()', 'v_ws uuid := hub.current_workspace_id()');
  end if;
  if to_regprocedure('hub.modules_workspace()') is not null then
    execute $sql$create or replace function hub.modules_workspace() returns uuid
      language plpgsql security definer set search_path=pg_catalog as $body$
      declare w uuid:=hub.current_workspace_id();
      begin
        if auth.uid() is null or w is null or not hub.pode_ler() then raise exception 'Acesso negado.'; end if;
        return w;
      end $body$ $sql$;
  end if;
  for f in select p.oid::regprocedure as sig from pg_proc p
    where p.pronamespace='hub'::regnamespace and p.prosecdef
    and p.proname in ('contato_do_papel','prospect_com_contato_do_cliente','ativar_contrato_assinado',
      'modules_workspace','stock_lock','stock_capacity','modules_snapshot','stock_save','stock_move','stock_order','advisory_save')
  loop
    execute format('alter function %s owner to hub_rpc', f.sig);
  end loop;
end $$;

-- O webhook de assinatura resolve o tenant pelo ID global da submission.
-- Só service_role sem usuário pode resolver além do workspace da requisição.
create function hub.docuseal_definir_workspace(p_submission_id bigint) returns uuid
language plpgsql security definer set search_path=pg_catalog as $$
declare w uuid;
begin
  if auth.uid() is not null or coalesce(auth.role(),'') <> 'service_role' then raise exception 'acesso negado'; end if;
  select workspace_id into w from hub.contratos where docuseal_submission_id=p_submission_id;
  if w is null then raise exception 'submission não encontrada'; end if;
  perform set_config('hub.workspace_id',w::text,true);
  return w;
end $$;
revoke all on function hub.docuseal_definir_workspace(bigint) from public,anon,authenticated,service_role;
grant execute on function hub.docuseal_definir_workspace(bigint) to hub_rpc;
do $$
declare definition text;
  needle text := 'if not hub.is_ingestor() then raise exception ''acesso negado''; end if;';
begin
  select pg_get_functiondef('hub.rpc_docuseal_registrar_evento(jsonb)'::regprocedure) into definition;
  if position(needle in definition)=0 then raise exception 'Integração: revisar rpc_docuseal_registrar_evento'; end if;
  execute replace(definition,needle,needle || E'\n  if auth.uid() is null and auth.role() = ''service_role'' then\n    perform hub.docuseal_definir_workspace((p->>''docuseal_submission_id'')::bigint);\n  end if;');
end $$;
notify pgrst,'reload schema';
commit;
