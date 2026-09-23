-- ============================================================
-- HUB LUH PANDA — 018: fecha o buraco de duplicação do eco da Evolution
--
-- Aplicada em 23/09/2026, no minuto em que o webhook de ingestão foi ativado.
-- Achado por raciocínio sobre o novo fluxo, antes de a Luciana esbarrar nele.
--
-- O PROBLEMA: quando ela manda pelo Hub, a mensagem é gravada por
-- `rpc_preparar_envio` SEM `evolution_msg_id` — nesse momento ela ainda não
-- foi enviada, o id não existe. Logo depois a Evolution ecoa a mesma mensagem
-- pelo `MESSAGES_UPSERT` com `fromMe=true` e um id. O webhook chama
-- `rpc_registrar_mensagem`, que não encontra conflito de `evolution_msg_id`
-- (porque a linha original tem NULL ali) e insere uma SEGUNDA linha.
--
-- Resultado: cada mensagem enviada pelo Hub apareceria duplicada na thread.
--
-- A CORREÇÃO: a Edge Function agora passa o `key.id` devolvido pela Evolution
-- ao marcar como enviado. Com o id gravado na linha original, o eco bate no
-- unique de `evolution_msg_id` e o `on conflict do nothing` descarta — que é
-- exatamente para isso que aquela restrição existe.
-- ============================================================

create or replace function hub.rpc_marcar_envio(p jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_status text;
  v_evo_id text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_status := coalesce(p->>'status', 'erro');
  if v_status not in ('enviado', 'erro') then
    raise exception 'status inválido: %', v_status;
  end if;

  v_evo_id := nullif(p->>'evolution_msg_id', '');

  update hub.mensagens
  set status = v_status,
      erro   = case when v_status = 'erro'
                    then left(coalesce(p->>'erro', 'falha desconhecida'), 500)
                    else null end,
      -- só grava o id quando veio; nunca apaga um id já existente
      evolution_msg_id = coalesce(v_evo_id, evolution_msg_id)
  where id = (p->>'msg_id')::uuid;
end;
$$;

revoke all on function hub.rpc_marcar_envio(jsonb) from public, anon;
grant execute on function hub.rpc_marcar_envio(jsonb) to authenticated;
