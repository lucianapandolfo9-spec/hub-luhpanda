-- =====================================================================
-- 040 — RECEBÍVEIS DO CLIENTE NA FICHA
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 07/10/2026
--
-- POR QUÊ
-- 07/10: ela abriu a ficha do cliente novo (Palácio Dos Esportes) pra ver
-- o recebível e a aba "Financeiro" só mostrava Contatos. Não existia lugar
-- nenhum que mostrasse "tudo que este cliente me deve / já pagou" — só a
-- tela Recebíveis, mês a mês.
--
-- O QUE FAZ
-- Uma RPC só de LEITURA: todos os recebíveis do cliente, todos os meses,
-- com o mesmo `status` calculado de hub.rpc_recebiveis. Nada muda em dado.
-- =====================================================================

create or replace function hub.rpc_recebiveis_cliente(p_cliente_id uuid)
returns table(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, contrato_id uuid, status text)
language plpgsql
stable security definer
set search_path to 'pg_catalog'
as $function$
declare v_hoje date := (now() at time zone 'America/Recife')::date;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select r.id, r.cliente_id, c.nome, c.slug, r.competencia, r.descricao,
    r.valor_centavos, r.entrada_centavos, r.falta_centavos, r.entrou_em, r.vence_em,
    r.origem, r.observacao, r.contrato_id,
    case
      when r.falta_centavos = 0 then 'pago'
      when r.entrada_centavos > 0 then 'parcial'
      when r.vence_em is not null and r.vence_em < v_hoje then 'vencido'
      else 'aberto'
    end as status
  from hub.recebiveis r
  join hub.clientes c on c.id = r.cliente_id
  where r.cliente_id = p_cliente_id
  order by r.competencia desc, r.vence_em nulls last, r.created_at;
end;
$function$;

revoke all on function hub.rpc_recebiveis_cliente(uuid) from public, anon;
grant execute on function hub.rpc_recebiveis_cliente(uuid) to authenticated;

create or replace function public.hub_rpc_recebiveis_cliente(p_cliente_id uuid)
returns table(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, contrato_id uuid, status text)
language sql security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_recebiveis_cliente(p_cliente_id); $$;

revoke all on function public.hub_rpc_recebiveis_cliente(uuid) from public, anon;
grant execute on function public.hub_rpc_recebiveis_cliente(uuid) to authenticated;
