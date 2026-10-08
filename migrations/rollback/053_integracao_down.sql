-- DRAFT: executar ANTES de 052_down. Não remove dados nem permissões de RLS.
-- 052_down restaura os owners postgres depois de verificar dados de outros tenants.
begin;
do $$
declare definition text;
  injected text := E'\n  if auth.uid() is null and auth.role() = ''service_role'' then\n    perform hub.docuseal_definir_workspace((p->>''docuseal_submission_id'')::bigint);\n  end if;';
begin
  select pg_get_functiondef('hub.rpc_docuseal_registrar_evento(jsonb)'::regprocedure) into definition;
  execute replace(definition, injected, '');
  if to_regprocedure('hub.rpc_novo_cliente(jsonb)') is not null then
    select pg_get_functiondef('hub.rpc_novo_cliente(jsonb)'::regprocedure) into definition;
    execute replace(definition,'v_ws uuid := hub.current_workspace_id()','v_ws uuid := hub.default_workspace_id()');
  end if;
  if to_regprocedure('hub.modules_workspace()') is not null then
    execute $sql$create or replace function hub.modules_workspace() returns uuid
      language plpgsql security definer set search_path=pg_catalog as $body$
      declare w uuid;
      begin
        if auth.uid() is null or not hub.is_admin() then raise exception 'Acesso negado.'; end if;
        w:=hub.default_workspace_id(); if w is null then raise exception 'Workspace não configurado.'; end if;
        return w;
      end $body$ $sql$;
  end if;
end $$;
drop function hub.docuseal_definir_workspace(bigint);
alter table hub.empresas drop constraint empresas_um_cnpj_por_workspace;
commit;
