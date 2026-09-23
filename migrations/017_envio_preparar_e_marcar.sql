-- ============================================================
-- HUB LUH PANDA — 017: as duas pontas do envio pela Edge Function
--
-- Aplicada em 23/09/2026.
--
-- A Edge Function `wa-send` precisa de duas coisas que a 013 não dava:
--
-- 1) o telefone JÁ NORMALIZADO, pra montar o JID do WhatsApp. Se ela montasse
--    o JID a partir do que está no cadastro, cairia direto na armadilha do
--    nono dígito (DDD >= 31 não leva o 9) e a Evolution responderia
--    {"exists": false} sem mandar nada — o mesmo erro do gotcha #15.
--    `rpc_enfileirar_saida` já normaliza internamente, mas só devolvia o id
--    da mensagem.
--
-- 2) um jeito de marcar o resultado. A mensagem nasce com status 'enviando';
--    se ninguém fechar esse estado, uma falha de rede deixa a linha pendurada
--    pra sempre e a tela mostra "enviando" eternamente, como se ainda
--    estivesse a caminho.
--
-- Guard `is_admin`, não `is_ingestor`: quem envia é ela, com a sessão dela. A
-- Edge Function repassa o JWT do navegador e nunca usa service_role pra isso.
-- ============================================================

create or replace function hub.rpc_preparar_envio(p jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_msg_id uuid;
  v_fone text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  v_msg_id := hub.rpc_enfileirar_saida(p);

  return jsonb_build_object('msg_id', v_msg_id, 'fone_norm', v_fone);
end;
$$;

create or replace function hub.rpc_marcar_envio(p jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_status text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_status := coalesce(p->>'status', 'erro');
  if v_status not in ('enviado', 'erro') then
    raise exception 'status inválido: %', v_status;
  end if;

  update hub.mensagens
  set status = v_status,
      erro   = case when v_status = 'erro'
                    then left(coalesce(p->>'erro', 'falha desconhecida'), 500)
                    else null end
  where id = (p->>'msg_id')::uuid;
end;
$$;

revoke all on function hub.rpc_preparar_envio(jsonb) from public, anon;
revoke all on function hub.rpc_marcar_envio(jsonb) from public, anon;
grant execute on function hub.rpc_preparar_envio(jsonb) to authenticated;
grant execute on function hub.rpc_marcar_envio(jsonb) to authenticated;

create or replace function public.hub_rpc_preparar_envio(p jsonb)
returns jsonb
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_preparar_envio(p); $$;

create or replace function public.hub_rpc_marcar_envio(p jsonb)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_marcar_envio(p); $$;

revoke all on function public.hub_rpc_preparar_envio(jsonb) from public, anon;
revoke all on function public.hub_rpc_marcar_envio(jsonb) from public, anon;
grant execute on function public.hub_rpc_preparar_envio(jsonb) to authenticated;
grant execute on function public.hub_rpc_marcar_envio(jsonb) to authenticated;
