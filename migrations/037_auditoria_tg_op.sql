-- =====================================================================
-- 037 — AUDITORIA VOLTA A GRAVAR O DADO (TG_OP em maiúscula)
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 07/10/2026
--
-- O BUG (existe desde a 001)
-- hub.registrar_auditoria() comparava `tg_op in ('update','delete')`.
-- O Postgres entrega TG_OP em MAIÚSCULA ('INSERT' | 'UPDATE' | 'DELETE'),
-- então os dois CASE nunca batiam: TODOS os eventos de hub.eventos_auditoria
-- (4.176 em 07/10/2026) foram gravados com dados_antes = dados_depois = NULL.
-- A coluna `acao` saía certa só porque usava lower(tg_op).
-- Consequência prática: "apagou — rastro guardado na auditoria" era falso;
-- recebível apagado não tinha como ser reconstituído (e o projeto Free não
-- tem backup).
--
-- O QUE MUDA
-- Só a função. Os triggers já existentes continuam apontando pra ela, nada
-- mais precisa ser recriado. Não tem como recuperar o passado: os eventos
-- antigos continuam com o dado nulo.
--
-- ⚠️ NUMERAÇÃO: o comentário da 036 reservava "037" pro DROP definitivo do
-- legado Certo Agro. Esse DROP passa a usar o próximo número livre.
--
-- ROLLBACK: não faz sentido voltar pro bug; se precisar, reaplicar a 001.
-- =====================================================================

create or replace function hub.registrar_auditoria()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
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
$$;

-- ---------------------------------------------------------------------
-- PROVA (rodar depois de aplicar; não altera nada — o RAISE desfaz tudo):
--
-- do $$
-- declare v record; r uuid;
-- begin
--   select id into r from hub.recebiveis limit 1;
--   update hub.recebiveis set observacao = observacao where id = r;
--   select dados_antes is not null as tem_antes, dados_depois is not null as tem_depois
--     into v from hub.eventos_auditoria where registro_id = r order by criado_em desc limit 1;
--   raise exception 'PROVA 037: tem_antes=% tem_depois=%', v.tem_antes, v.tem_depois;
-- end $$;
--
-- Esperado: ERROR "PROVA 037: tem_antes=true tem_depois=true" (o erro é
-- proposital: desfaz o UPDATE e o evento de teste).
-- ---------------------------------------------------------------------
