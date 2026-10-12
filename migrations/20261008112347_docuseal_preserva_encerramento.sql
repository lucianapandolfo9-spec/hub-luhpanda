-- Revisão de 08/10: aplicar APÓS 042. Preserva migrations históricas.
begin;
create or replace function hub.rpc_docuseal_registrar_evento(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_contrato hub.contratos;
  v_cliente_slug text;
  v_submission_id bigint;
  v_status text;
  v_audit_url text;
  v_assinado_em date;
  v_ativacao jsonb;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_submission_id := (p->>'docuseal_submission_id')::bigint;
  v_status := nullif(btrim(coalesce(p->>'status', '')), '');
  v_audit_url := nullif(btrim(coalesce(p->>'audit_log_url', '')), '');
  v_assinado_em := coalesce(nullif(p->>'assinado_em', '')::date,
                            (now() at time zone 'America/Recife')::date);
  if v_submission_id is null then raise exception 'docuseal_submission_id é obrigatório'; end if;
  if v_status is distinct from 'assinado' then
    raise exception 'status inválido pro webhook do DocuSeal: %', v_status;
  end if;

  select * into v_contrato from hub.contratos
   where docuseal_submission_id = v_submission_id
   for update;
  if v_contrato.id is null then
    raise exception 'nenhum contrato com docuseal_submission_id = %', v_submission_id;
  end if;

  -- audit log sempre (vale mesmo pra contrato que já estava ativo)
  update hub.contratos
     set docuseal_audit_log_url = coalesce(v_audit_url, docuseal_audit_log_url)
   where id = v_contrato.id;

  if v_contrato.status = 'ativo' then
    v_ativacao := jsonb_build_object('ja_estava_ativo', true);
  else
    begin
      -- 🔗 PONTO DE INTEGRAÇÃO com a 041: a função única de "assinou".
      v_ativacao := hub.ativar_contrato_assinado(v_contrato.id, v_assinado_em, false);
    exception when others then
      -- recusou (guarda do banco): o evento NÃO se perde.
      -- Um evento atrasado não reabre contratos encerrados/arquivados.
      update hub.contratos set status = 'assinado', assinado_em = v_assinado_em
       where id = v_contrato.id and status not in ('encerrado','arquivado');
      v_ativacao := jsonb_build_object('ativado', false, 'erro', sqlerrm);
    end;
  end if;

  select cl.slug into v_cliente_slug from hub.clientes cl where cl.id = v_contrato.cliente_id;

  return jsonb_build_object('contrato_id', v_contrato.id, 'cliente_slug', v_cliente_slug,
                            'ativacao', v_ativacao);
end;
$function$;
notify pgrst, 'reload schema';
commit;
