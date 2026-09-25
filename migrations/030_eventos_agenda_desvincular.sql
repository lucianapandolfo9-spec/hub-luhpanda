-- ============================================================
-- HUB LUH PANDA — 030: apagar reunião da Agenda (clicando nela, igual ao
-- Google Calendar) — Fase 3, Bloco F, ajuste pedido por ela em 25/09/2026
-- depois de aprovar o Bloco F ao vivo ("tá mto foda").
--
-- Decisão de desenho (sem grill-me novo, reaproveita a Edge Function
-- `agenda-google` — só ganha a ação "cancelar"; ver Hub Dev.md, Bloco F,
-- item 1 da rodada de 2 ajustes pedidos por ela):
--
--   • A Edge Function chama DELETE no Google PRIMEIRO (com
--     sendUpdates=all — avisa quem foi convidado da cancelação, mesmo
--     padrão do "criar"). Só DEPOIS do Google confirmar é que esta RPC
--     roda — nunca o contrário, senão um erro no Google deixaria o
--     vínculo apagado apontando pra um evento que ainda existe na agenda.
--   • hub.eventos_agenda: DELETE real da linha do vínculo (não é dado de
--     negócio como contrato/recebível — é só um ponteiro; não tem valor
--     em manter um vínculo morto pra um evento cancelado).
--   • hub.reunioes: o rascunho criado pelo Bloco F original
--     (`meetily_meeting_id = 'agenda-' || google_event_id`, via
--     rpc_criar_rascunho_reuniao_agenda) só é apagado JUNTO se ainda não
--     tem conteúdo real nenhum anexado (transcrição/resumo/key_points/
--     action_items/análise todos nulos) — um rascunho vazio apontando pra
--     um evento cancelado não serve pra nada. Se ela já subiu a
--     transcrição (ou rodou a análise), a reunião fica — só desvincula do
--     evento cancelado, nunca apaga conteúdo real por causa de um clique
--     na Agenda.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (sem Supabase MCP — mesma
-- limitação já registrada nos blocos anteriores). Aplicar com
-- `apply_migration`, depois `get_advisors` (security), como sempre.
-- ============================================================

do $$
begin
  if to_regclass('hub.eventos_agenda') is null then
    raise exception 'hub.eventos_agenda não existe — aplicar a 029 antes da 030.';
  end if;
  if to_regclass('hub.reunioes') is null then
    raise exception 'hub.reunioes não existe — aplicar a 027 antes da 030.';
  end if;
  if to_regprocedure('hub.is_admin()') is null then
    raise exception 'hub.is_admin() não existe neste banco.';
  end if;
end $$;


-- ============================================================
-- hub.rpc_eventos_agenda_desvincular — chamada pela Edge Function
-- `agenda-google` (ação "cancelar"), DEPOIS que o Google já confirmou o
-- DELETE do evento. Repassa o JWT dela (é ela clicando "Apagar reunião").
-- ============================================================
create or replace function hub.rpc_eventos_agenda_desvincular(p jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_google_id text;
  v_mid text;
  v_rascunho_apagado boolean := false;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_google_id := nullif(btrim(coalesce(p->>'google_event_id', '')), '');
  if v_google_id is null then raise exception 'google_event_id é obrigatório'; end if;

  delete from hub.eventos_agenda where google_event_id = v_google_id;

  -- rascunho do Bloco F (rpc_criar_rascunho_reuniao_agenda) — só some
  -- junto se AINDA NÃO tem conteúdo real nenhum. Conteúdo real nunca é
  -- apagado por um clique de "apagar reunião" na Agenda, só desvinculado
  -- (o front nunca chama isso pra um rascunho com conteúdo — mas a guarda
  -- vive aqui, no banco, não só na confiança do front).
  v_mid := 'agenda-' || v_google_id;
  delete from hub.reunioes
  where meetily_meeting_id = v_mid
    and transcricao  is null
    and resumo       is null
    and key_points    is null
    and action_items is null
    and analise      is null;
  if found then
    v_rascunho_apagado := true;
  end if;

  return jsonb_build_object('ok', true, 'rascunho_apagado', v_rascunho_apagado);
end;
$$;

revoke all on function hub.rpc_eventos_agenda_desvincular(jsonb) from public, anon;
grant execute on function hub.rpc_eventos_agenda_desvincular(jsonb) to authenticated;


-- ============================================================
-- wrapper público (schema hub não é exposto ao PostgREST)
-- ============================================================
create or replace function public.hub_rpc_eventos_agenda_desvincular(p jsonb)
returns jsonb
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_eventos_agenda_desvincular(p); $$;

revoke all on function public.hub_rpc_eventos_agenda_desvincular(jsonb) from public, anon;
grant execute on function public.hub_rpc_eventos_agenda_desvincular(jsonb) to authenticated;
