-- ============================================================
-- HUB — ROLLBACK da 050. ⚠️ DRAFT. Rodar só depois do 051_down.
-- Apaga as tabelas de conta (membros, convites, módulos, canais, aceites,
-- trilha) e os campos de perfil fiscal. Workspaces criados depois da 050
-- são apagados; o workspace 1 fica.
-- ============================================================
drop table hub.acessos_sensiveis;
drop table hub.workspace_aceites;
drop table hub.workspace_canais;
drop table hub.workspace_modulos;
drop table hub.modulos;
drop table hub.convites;
drop table hub.workspace_membros;
drop function hub.trg_membros_regras();
drop table hub.plataforma_admins;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'public' and p.proname in (
             'hub_rpc_meus_workspaces','hub_rpc_plataforma_criar_workspace','hub_rpc_plataforma_definir_modulos',
             'hub_rpc_criar_convite','hub_rpc_revogar_convite','hub_rpc_aceitar_convite','hub_rpc_membros',
             'hub_rpc_alterar_membro','hub_rpc_onboarding_salvar_empresa','hub_rpc_onboarding_confirmar_regime',
             'hub_rpc_aceitar_termos','hub_rpc_perfil_fiscal'))
       or (n.nspname = 'hub' and p.proname in (
             'rpc_meus_workspaces','rpc_plataforma_criar_workspace','rpc_plataforma_definir_modulos',
             'rpc_criar_convite','rpc_revogar_convite','rpc_aceitar_convite','rpc_membros','rpc_alterar_membro',
             'rpc_onboarding_salvar_empresa','rpc_onboarding_confirmar_regime','rpc_aceitar_termos','rpc_perfil_fiscal',
             '_gerar_convite','ingestor_definir_workspace','modulo_ativo','is_plataforma_admin','eh_dono',
             'pode_escrever','pode_ler','eh_automacao','papel_atual','current_workspace_id'))
  loop
    execute format('drop function %s', f.sig);
  end loop;
end $$;


alter table hub.empresas
  drop constraint empresas_cnpj_valido,
  drop constraint empresas_regime_check,
  drop constraint empresas_regime_sugerido_check,
  drop constraint empresas_regime_confirmado,
  drop constraint empresas_faixa_check,
  drop constraint empresas_receita_fonte_check,
  drop column razao_social, drop column nome_fantasia, drop column cnae_principal,
  drop column cnaes_secundarios, drop column natureza_juridica,
  drop column situacao_cadastral, drop column endereco, drop column socios,
  drop column simples_optante, drop column simples_desde, drop column simei_optante, drop column simei_desde,
  drop column regime_sugerido, drop column regime_sugerido_fonte, drop column regime_sugerido_ano,
  drop column regime, drop column regime_confirmado_por, drop column regime_confirmado_em,
  drop column faixa_faturamento, drop column receita_fonte, drop column receita_consultada_em;
drop function hub.cnpj_valido(text);
drop function hub.cnpj_normalizar(text);

delete from hub.workspaces where slug <> 'luhpanda';
alter table hub.workspaces drop column status, drop column vagas, drop column criado_por;

-- auditoria volta ao texto da 037 (produção, 07/10/2026)
CREATE OR REPLACE FUNCTION hub.registrar_auditoria()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  insert into hub.eventos_auditoria (tabela, registro_id, acao, dados_antes, dados_depois, ator_email)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    coalesce(auth.email(), 'sistema')
  );
  return coalesce(new, old);
end;
$function$
;
