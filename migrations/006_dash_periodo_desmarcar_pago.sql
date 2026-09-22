-- ============================================================
-- HUB LUH PANDA — 006: filtro de período no Dash + "desmarcar pago"
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (21/09/2026) — esta sessão de dev não
-- teve acesso às ferramentas MCP do Supabase (nem Chrome/n8n) pra rodar
-- contra o projeto `arroba-certa` e conferir o schema real antes de
-- aplicar. Antes de aplicar numa sessão com acesso:
--   1) confirmar que `hub.recebiveis` tem exatamente as colunas usadas
--      abaixo (cliente_id, competencia, descricao, valor_centavos,
--      entrada_centavos, entrou_em, vence_em, falta_centavos GENERATED,
--      origem, observacao) — nomes tirados do PROJETO.md ("hub.recebiveis
--      .entrada_centavos/entrou_em são a verdade") e do contrato já usado
--      pelo front-end em produção (hub_rpc_recebiveis/hub_rpc_marcar_pago);
--   2) rodar com `execute_sql` num caso real antes de religar o front;
--   3) rodar `get_advisors` (segurança) depois de aplicar.
-- Este arquivo só ADICIONA funções novas — não altera nenhuma tabela,
-- função ou guarda já existente (hub.is_admin(), CHECK de porta de saída,
-- falta_centavos GENERATED, trigger de auditoria continuam intocados).
-- ============================================================

-- ---------- filtro de período livre pro Dash (7 dias / 30 dias / mês / personalizado) ----------
-- Fonte: hub.recebiveis, filtrado por vence_em (não por data de pagamento —
-- "previsto" e "entrado" são sempre lidos em relação a quando o recebível
-- vence, o que já é o comportamento do hub_rpc_recebiveis por competência).
-- Granularidade do gráfico: por dia se o intervalo tiver até 31 dias,
-- por mês caso contrário — decisão do @dev, sem impacto em dado existente.
create or replace function hub.rpc_dash_periodo(p_desde date, p_ate date)
returns jsonb
language plpgsql stable security definer set search_path = pg_catalog
as $$
declare
  v_previsto bigint;
  v_entrado bigint;
  v_vencidos int;
  v_bucket text;
  v_series jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_desde is null or p_ate is null or p_desde > p_ate then
    raise exception 'período inválido';
  end if;

  select coalesce(sum(valor_centavos), 0), coalesce(sum(entrada_centavos), 0)
    into v_previsto, v_entrado
  from hub.recebiveis
  where vence_em between p_desde and p_ate;

  select count(*) into v_vencidos
  from hub.recebiveis
  where vence_em between p_desde and p_ate
    and vence_em < current_date
    and falta_centavos > 0;

  v_bucket := case when (p_ate - p_desde) <= 31 then 'dia' else 'mes' end;

  if v_bucket = 'dia' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'rotulo', to_char(d.dia, 'DD/MM'),
      'previsto_centavos', coalesce(r.previsto, 0),
      'entrado_centavos', coalesce(r.entrado, 0)
    ) order by d.dia), '[]'::jsonb) into v_series
    from generate_series(p_desde, p_ate, interval '1 day') d(dia)
    left join (
      select vence_em, sum(valor_centavos) previsto, sum(entrada_centavos) entrado
      from hub.recebiveis
      where vence_em between p_desde and p_ate
      group by vence_em
    ) r on r.vence_em = d.dia::date;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'rotulo', initcap(to_char(m.mes, 'Mon/YY')),
      'previsto_centavos', coalesce(r.previsto, 0),
      'entrado_centavos', coalesce(r.entrado, 0)
    ) order by m.mes), '[]'::jsonb) into v_series
    from generate_series(date_trunc('month', p_desde), date_trunc('month', p_ate), interval '1 month') m(mes)
    left join (
      select date_trunc('month', vence_em) as mes, sum(valor_centavos) previsto, sum(entrada_centavos) entrado
      from hub.recebiveis
      where vence_em between p_desde and p_ate
      group by 1
    ) r on r.mes = m.mes;
  end if;

  return jsonb_build_object(
    'desde', p_desde,
    'ate', p_ate,
    'previsto_centavos', v_previsto,
    'entrado_centavos', v_entrado,
    'falta_centavos', v_previsto - v_entrado,
    'vencidos_count', v_vencidos,
    'granularidade', v_bucket,
    'serie', v_series
  );
end;
$$;

-- ---------- desmarcar pago (reversão do "marcar pago", pra qualquer cliente) ----------
-- Não recria auditoria — a tabela hub.recebiveis já tem trigger de
-- auditoria (hub.registrar_auditoria), então o UPDATE abaixo já fica
-- rastreado sozinho (quem, quando, valor antes/depois).
create or replace function hub.rpc_desmarcar_pago(p_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.recebiveis
  set entrada_centavos = 0, entrou_em = null
  where id = p_id;

  if not found then
    raise exception 'recebível não encontrado';
  end if;
end;
$$;

revoke all on function hub.rpc_dash_periodo(date, date) from public, anon;
revoke all on function hub.rpc_desmarcar_pago(uuid) from public, anon;
grant execute on function hub.rpc_dash_periodo(date, date) to authenticated;
grant execute on function hub.rpc_desmarcar_pago(uuid) to authenticated;

-- ---------- wrappers públicos (mesmo padrão do 004_wrappers_publicos.sql) ----------
create or replace function public.hub_rpc_dash_periodo(p_desde date, p_ate date)
returns jsonb
language sql stable security invoker set search_path = pg_catalog
as $$ select hub.rpc_dash_periodo(p_desde, p_ate); $$;

create or replace function public.hub_rpc_desmarcar_pago(p_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_desmarcar_pago(p_id); $$;

revoke all on function public.hub_rpc_dash_periodo(date, date) from public, anon;
revoke all on function public.hub_rpc_desmarcar_pago(uuid) from public, anon;
grant execute on function public.hub_rpc_dash_periodo(date, date) to authenticated;
grant execute on function public.hub_rpc_desmarcar_pago(uuid) to authenticated;
