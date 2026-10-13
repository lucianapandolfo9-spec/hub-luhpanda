-- Rollback da 045: volta as 3 funções à definição de produção de 08/10/2026.
-- (rpc_salvar_recebivel = 038 · rpc_marcar_pago e rpc_dash_periodo = schema de 08/10.)
-- Não toca em dados: recebíveis criados com valor_travado=true continuam travados.

create or replace function hub.rpc_salvar_recebivel(p jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare v_id uuid;
        v_comp date;
begin
  -- confirmado por introspecção que a versão em produção TEM este guard.
  -- Sem ele, qualquer usuário authenticated escreveria recebível de qualquer
  -- cliente. Nunca remover ao recriar esta função.
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  -- 038: competência é o MÊS. Qualquer dia vira o dia 1.
  v_comp := date_trunc('month', (p->>'competencia')::date)::date;
  if v_comp is null then raise exception 'competência é obrigatória'; end if;

  insert into hub.recebiveis (id, cliente_id, competencia, descricao, valor_centavos, entrada_centavos, entrou_em, vence_em, origem, observacao, valor_travado)
  values (coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, v_comp, p->>'descricao', (p->>'valor_centavos')::bigint, coalesce((p->>'entrada_centavos')::bigint, 0), (p->>'entrou_em')::date, (p->>'vence_em')::date, coalesce(p->>'origem','contrato'), p->>'observacao', coalesce((p->>'valor_travado')::boolean, false))
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, competencia=excluded.competencia, descricao=excluded.descricao,
    valor_centavos=excluded.valor_centavos, vence_em=excluded.vence_em, origem=excluded.origem,
    observacao=excluded.observacao, sincronizado_planilha=false,
    -- precedência: payload explícito (é assim que ela DESTRAVA) > mudou o valor
    -- pela tela (trava) > fica como estava (salvar só a observação não destrava).
    valor_travado = case
      when p ? 'valor_travado' then coalesce((p->>'valor_travado')::boolean, false)
      when hub.recebiveis.valor_centavos is distinct from excluded.valor_centavos then true
      else hub.recebiveis.valor_travado
    end
  returning id into v_id;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION hub.rpc_marcar_pago(p_id uuid, p_valor_centavos bigint, p_data date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.recebiveis
  set entrada_centavos = entrada_centavos + p_valor_centavos,
      entrou_em = p_data,
      sincronizado_planilha = false
  where id = p_id;

  return p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION hub.rpc_dash_periodo(p_desde date, p_ate date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;

