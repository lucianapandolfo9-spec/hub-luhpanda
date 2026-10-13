-- =====================================================================
-- 045 — CADASTRO DE RECEBÍVEL: INTEGRIDADE (valor, pagamento, dash)
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 13/10/2026
-- Depende de: 038 (salvar), 044. NÃO APLICADA — escrita e testada em PGlite
-- contra o schema de produção de 08/10 (tests/novo-cliente/recebivel.test.mjs).
-- Rollback: migrations/rollback/045_rollback.sql
--
-- OS PROBLEMAS (causa raiz)
--   1. VALOR LANÇADO À MÃO ERA SOBRESCRITO PELO CONTRATO. rpc_salvar_recebivel
--      inseria com valor_travado=false. O recebível manual de origem
--      'contrato' (default do form) é "adotado" pelo gerador (034/035/041)
--      quando o cliente ganha contrato e, como não estava travado, o reajuste
--      em massa (parte B) trocava o valor digitado pelo valor mensal do
--      contrato, em silêncio. Lançamento feito pela tela é decisão humana:
--      nasce travado.
--   2. SEM VALIDAÇÃO NO BANCO. valor nulo/negativo, cliente inexistente e
--      descrição vazia estouravam como erro cru de constraint ("violates
--      check constraint ...") ou, pior, passavam (descrição só de espaços).
--      Agora cada um tem código próprio (friendlyError no front).
--   3. RECEBÍVEL DE CONTRATO PODIA MUDAR DE CLIENTE pelo "Editar" (o
--      ON CONFLICT trocava cliente_id e o contrato_id ficava no cliente
--      antigo → parcela de um cliente apontando pro contrato de outro).
--   4. MARCAR PAGO SEM GUARDA. rpc_marcar_pago aceitava valor nulo/zero/
--      negativo, recebível inexistente (devolvia o id como se tivesse
--      dado certo) e valor acima do que faltava (a falta é GREATEST(...,0),
--      então o excedente sumia da conta e o "Entrou" passava do "Previsto").
--   5. DASH POR PERÍODO IGNORAVA RECEBÍVEL SEM VENCIMENTO. rpc_dash_periodo
--      filtra por vence_em; lançamento manual sem "Vence em" aparecia na tela
--      Recebíveis e sumia do Previsto do Dash. E "vencidos" usava
--      current_date (UTC do servidor), não o dia de Recife. Agora usa
--      coalesce(vence_em, competencia) e o dia de Recife.
--
-- Assinaturas iguais → wrappers públicos e grants preservados.
-- =====================================================================

-- 1, 2, 3 -------------------------------------------------------------
create or replace function hub.rpc_salvar_recebivel(p jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare v_id uuid;
        v_comp date;
        v_cliente uuid;
        v_valor bigint;
        v_atual record;
begin
  -- Nunca remover ao recriar: sem ele qualquer authenticated escreve.
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_comp := date_trunc('month', (p->>'competencia')::date)::date;
  if v_comp is null then raise exception 'competência é obrigatória'; end if;

  v_cliente := (p->>'cliente_id')::uuid;
  if v_cliente is null then raise exception 'hub_recebivel_sem_cliente'; end if;
  if not exists (select 1 from hub.clientes where id = v_cliente) then
    raise exception 'hub_recebivel_cliente_inexistente';
  end if;

  if p->>'descricao' is null or btrim(p->>'descricao') = '' then
    raise exception 'hub_recebivel_sem_descricao';
  end if;

  v_valor := (p->>'valor_centavos')::bigint;
  if v_valor is null or v_valor < 0 then raise exception 'hub_recebivel_valor_invalido'; end if;

  v_id := coalesce((p->>'id')::uuid, gen_random_uuid());

  -- 3: recebível ligado a contrato não troca de cliente pelo "Editar".
  select r.cliente_id, r.contrato_id into v_atual from hub.recebiveis r where r.id = v_id;
  if found and v_atual.contrato_id is not null and v_atual.cliente_id is distinct from v_cliente then
    raise exception 'hub_recebivel_contrato_outro_cliente';
  end if;

  insert into hub.recebiveis (id, cliente_id, competencia, descricao, valor_centavos, entrada_centavos, entrou_em, vence_em, origem, observacao, valor_travado)
  values (v_id, v_cliente, v_comp, btrim(p->>'descricao'), v_valor, coalesce((p->>'entrada_centavos')::bigint, 0), (p->>'entrou_em')::date, (p->>'vence_em')::date, coalesce(p->>'origem','contrato'), p->>'observacao',
          -- 1: lançamento manual NASCE travado (o gerador nunca reescreve o valor digitado)
          coalesce((p->>'valor_travado')::boolean, true))
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, competencia=excluded.competencia, descricao=excluded.descricao,
    valor_centavos=excluded.valor_centavos, vence_em=excluded.vence_em, origem=excluded.origem,
    observacao=excluded.observacao, sincronizado_planilha=false,
    valor_travado = case
      when p ? 'valor_travado' then coalesce((p->>'valor_travado')::boolean, false)
      when hub.recebiveis.valor_centavos is distinct from excluded.valor_centavos then true
      else hub.recebiveis.valor_travado
    end;

  return v_id;
end;
$function$;

-- 4 -------------------------------------------------------------------
create or replace function hub.rpc_marcar_pago(p_id uuid, p_valor_centavos bigint, p_data date)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare v_r hub.recebiveis;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  if p_valor_centavos is null or p_valor_centavos <= 0 then raise exception 'hub_pagamento_valor_invalido'; end if;
  if p_data is null then raise exception 'hub_pagamento_sem_data'; end if;

  select * into v_r from hub.recebiveis where id = p_id for update;
  if not found then raise exception 'hub_recebivel_nao_encontrado'; end if;

  if coalesce(v_r.entrada_centavos, 0) + p_valor_centavos > v_r.valor_centavos then
    raise exception 'hub_pagamento_maior_que_falta';
  end if;

  update hub.recebiveis
     set entrada_centavos = coalesce(entrada_centavos, 0) + p_valor_centavos,
         entrou_em = p_data,
         sincronizado_planilha = false
   where id = p_id;

  return p_id;
end;
$function$;

-- 5 -------------------------------------------------------------------
create or replace function hub.rpc_dash_periodo(p_desde date, p_ate date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_hoje date := (now() at time zone 'America/Recife')::date;
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

  -- 045: sem "Vence em", o recebível conta no dia 1 da competência.
  select coalesce(sum(valor_centavos), 0), coalesce(sum(entrada_centavos), 0)
    into v_previsto, v_entrado
  from hub.recebiveis
  where coalesce(vence_em, competencia) between p_desde and p_ate;

  -- vencido de verdade tem data de vencimento; sem data não é "vencido".
  select count(*) into v_vencidos
  from hub.recebiveis
  where vence_em between p_desde and p_ate
    and vence_em < v_hoje
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
      select coalesce(vence_em, competencia) as dia, sum(valor_centavos) previsto, sum(entrada_centavos) entrado
      from hub.recebiveis
      where coalesce(vence_em, competencia) between p_desde and p_ate
      group by 1
    ) r on r.dia = d.dia::date;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'rotulo', initcap(to_char(m.mes, 'Mon/YY')),
      'previsto_centavos', coalesce(r.previsto, 0),
      'entrado_centavos', coalesce(r.entrado, 0)
    ) order by m.mes), '[]'::jsonb) into v_series
    from generate_series(date_trunc('month', p_desde), date_trunc('month', p_ate), interval '1 month') m(mes)
    left join (
      select date_trunc('month', coalesce(vence_em, competencia)) as mes, sum(valor_centavos) previsto, sum(entrada_centavos) entrado
      from hub.recebiveis
      where coalesce(vence_em, competencia) between p_desde and p_ate
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
$function$;
