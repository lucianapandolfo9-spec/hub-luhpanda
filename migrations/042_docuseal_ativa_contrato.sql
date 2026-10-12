-- =====================================================================
-- 042 — WEBHOOK DO DOCUSEAL USA A FUNÇÃO ÚNICA "CONTRATO ASSINADO"
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 07/10/2026
--
-- 🔴 DEPENDE DA 041 (tela única "Novo cliente", outro PR). A 041 cria
--    hub.ativar_contrato_assinado(p_contrato_id uuid, p_assinado_em date,
--    p_porta_escrita boolean default false) → jsonb
-- e diz no cabeçalho: "O webhook do DocuSeal, quando entrar (PR separado),
-- chama esta mesma função". Este é esse PR. Aplicar SÓ depois da 041; sem
-- ela, esta migration falha na criação (a função não existe) — o que é o
-- comportamento certo, não deixa meia-integração no banco.
--
-- O QUE MUDA
-- hub.rpc_docuseal_registrar_evento (chamada pelo docuseal-webhook com
-- service_role, porta hub.is_ingestor()) passa a:
--   1. achar o contrato pelo docuseal_submission_id;
--   2. se já está `ativo` → não rebaixa (antes, um reenvio do webhook
--      sobrescrevia `ativo` com `assinado`);
--   3. tentar hub.ativar_contrato_assinado(contrato, data da assinatura,
--      false) — a MESMA função do botão manual: ativa e gera as parcelas;
--   4. se a ativação recusar (sem porta de saída escrita, sem valor, sem
--      dia de vencimento…), NÃO perde o evento: grava status `assinado` +
--      audit log e devolve o motivo em `ativacao.erro`. Ela completa o que
--      falta e clica no botão manual depois (idempotente).
-- `p_porta_escrita` vai FALSE de propósito: a assinatura do cliente não é
-- a Luciana confirmando que escreveu a porta de saída.
--
-- Payload novo aceito: p.assinado_em (date, opcional). Sem ele, usa hoje
-- (America/Recife). A Edge Function manda o completed_at do DocuSeal.
-- Assinatura e grants da função não mudam (CREATE OR REPLACE preserva).
-- =====================================================================

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
      update hub.contratos set status = 'assinado' where id = v_contrato.id;
      v_ativacao := jsonb_build_object('ativado', false, 'erro', sqlerrm);
    end;
  end if;

  select cl.slug into v_cliente_slug from hub.clientes cl where cl.id = v_contrato.cliente_id;

  return jsonb_build_object('contrato_id', v_contrato.id, 'cliente_slug', v_cliente_slug,
                            'ativacao', v_ativacao);
end;
$function$;
