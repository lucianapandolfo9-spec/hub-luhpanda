-- ============================================================
-- HUB LUH PANDA — 031: hub.eventos_agenda ganha calendario_id — Fase 3,
-- Bloco F, 5º ajuste pedido por ela em 25/09/2026 ("ler DOIS calendários,
-- não só o principal" — Gestão PDK / primary + Luh Panda).
--
-- Por que o default 'primary' é seguro (não é gambiarra, é fato):
--   • TODO vínculo em hub.eventos_agenda até hoje nasceu pela ação
--     "criar" da Edge Function `agenda-google` — e "criar" SEMPRE usou (e
--     continua usando, o 5º ajuste não mudou isso) o calendário principal
--     da conta (`/calendars/primary/events`). Não existe, e nunca existiu,
--     um vínculo criado em outro calendário.
--   • Logo, todo vínculo pré-existente É de fato do calendário 'primary'
--     — o default não é uma suposição otimista, é a realidade de como
--     esses vínculos foram criados. Nenhum dado migra errado.
--   • Esta migration só ensina o Hub a LER também o calendário "Luh
--     Panda" (Edge Function `agenda-google`, ações "listar"/"obter"/
--     "cancelar"/"editar"). "criar" continua só no primary — não foi
--     pedido, é fora de escopo aqui.
--
-- ⚠️ Sessão sem Supabase MCP nem Chrome MCP nesta leva (mesma limitação já
-- registrada em todo o Bloco F). Aplicar com `apply_migration`, depois
-- `get_advisors` (security), como sempre — e confirmar visualmente no
-- Chrome numa próxima sessão.
-- ============================================================

do $$
begin
  if to_regclass('hub.eventos_agenda') is null then
    raise exception 'hub.eventos_agenda não existe — aplicar a 029 antes da 031.';
  end if;
end $$;

alter table hub.eventos_agenda
  add column if not exists calendario_id text not null default 'primary';

-- hub.rpc_eventos_agenda_do_contato faz "select * from hub.eventos_agenda"
-- (RETURNS SETOF hub.eventos_agenda) — calendario_id aparece sozinho no
-- retorno pro front, sem precisar recriar a função nem o wrapper público.
