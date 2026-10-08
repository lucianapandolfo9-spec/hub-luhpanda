-- =====================================================================
-- 039 — "PRECISA DE ATENÇÃO" DO DASH SEM DUPLICAR + VENCIMENTO DAS PARCELAS FUTURAS
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 07/10/2026
-- Depende de: 038 (rpc_dash.por_mes por mês, CHECK de competência).
--
-- O BUG (print dela de 07/10, 21:04)
-- O bloco listava CADA recebível em aberto (vencido ou sem vencimento),
-- sem descrição, sem competência, sem filtrar cliente arquivado. Resultado:
-- "The Best" 6 vezes com valores iguais, `teste` e Victor Vizinho (ambos
-- arquivados) no meio, e parcelas de Nov/Dez/Jan — FUTURAS — como
-- "sem dia de vencimento".
--
-- Causa da parcela futura sem vencimento: elas nasceram (28/09) quando o
-- contrato do The Best ainda não tinha dia_vencimento. Depois o dia foi
-- preenchido (5), mas a parte B de rpc_garantir_recebiveis_mes só
-- reajustava VALOR, nunca vence_em.
--
-- O QUE MUDA
--   1. rpc_dash:
--      - vencidos e sem_vencimento ignoram cliente `encerrado` (arquivado);
--      - sem_vencimento só até o MÊS CORRENTE (futuro sem data não é alerta);
--      - cada item traz cliente_id, descricao e competencia (a tela agrupa);
--      - chave nova `futuros_por_cliente`: quantas parcelas em aberto o
--        cliente ainda tem pela frente e a próxima data (pra tela dizer
--        "próximas 4 a partir de 05/11" em vez de listar uma por uma).
--      - por_mes continua por mês (038).
--   2. rpc_garantir_recebiveis_mes, parte C nova: recebível de contrato,
--      do mês corrente em diante, não pago, sem vence_em, de contrato com
--      dia_vencimento → ganha o vencimento. Mesmas travas do reajuste de
--      valor (pago e entrada parcial são intocáveis). Conta como "tocado".
--      Assinatura igual → wrapper público e grants preservados.
-- =====================================================================

-- 1 -------------------------------------------------------------------
create or replace function hub.rpc_dash()
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_hoje date := (now() at time zone 'America/Recife')::date;
  v_mes date := date_trunc('month', (now() at time zone 'America/Recife'))::date;
  v_ano_inicio date := date_trunc('year', v_hoje)::date;
  v_teto bigint;
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select teto_anual_centavos into v_teto from hub.empresas where tipo = 'mei' limit 1;

  select jsonb_build_object(
    'hoje', v_hoje,
    'por_mes', coalesce((
      select jsonb_agg(m order by m->>'competencia')
      from (
        select jsonb_build_object(
          'competencia', date_trunc('month', competencia)::date,
          'previsto_centavos', sum(valor_centavos),
          'entrado_centavos', sum(entrada_centavos)
        ) as m
        from hub.recebiveis
        group by date_trunc('month', competencia)::date
      ) x
    ), '[]'::jsonb),
    'clientes_ativos', (select count(*) from hub.clientes where status = 'ativo'),
    'velocimetro_mei', jsonb_build_object(
      'entrado_ano_centavos', coalesce((
        select sum(entrada_centavos) from hub.recebiveis
        where entrou_em >= v_ano_inicio and entrou_em < v_ano_inicio + interval '1 year'
      ), 0),
      'teto_centavos', v_teto
    ),
    'custos_fixos', jsonb_build_object(
      'negocio_centavos', coalesce((select sum(valor_centavos) from hub.custos_fixos where categoria='negocio' and ativo), 0),
      'pessoal_centavos', coalesce((select sum(valor_centavos) from hub.custos_fixos where categoria='pessoal' and ativo), 0)
    ),
    'vencidos_hoje_ou_antes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recebivel_id', r.id, 'cliente_id', c.id, 'cliente_nome', c.nome, 'cliente_slug', c.slug,
        'descricao', r.descricao, 'competencia', r.competencia,
        'falta_centavos', r.falta_centavos, 'vence_em', r.vence_em
      ) order by c.nome, r.vence_em)
      from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
      where r.falta_centavos > 0 and r.vence_em is not null and r.vence_em <= v_hoje
        and c.status <> 'encerrado'
    ), '[]'::jsonb),
    'sem_vencimento', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recebivel_id', r.id, 'cliente_id', c.id, 'cliente_nome', c.nome, 'cliente_slug', c.slug,
        'descricao', r.descricao, 'competencia', r.competencia,
        'falta_centavos', r.falta_centavos
      ) order by c.nome, r.competencia)
      from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
      where r.falta_centavos > 0 and r.vence_em is null
        and r.competencia <= v_mes
        and c.status <> 'encerrado'
    ), '[]'::jsonb),
    'futuros_por_cliente', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cliente_id', f.cliente_id, 'quantidade', f.n,
        'proximo_vence_em', f.prox, 'falta_centavos', f.falta
      ))
      from (
        select r.cliente_id, count(*) n, min(r.vence_em) prox, sum(r.falta_centavos) falta
        from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
        where r.falta_centavos > 0 and c.status <> 'encerrado'
          and ((r.vence_em is not null and r.vence_em > v_hoje)
               or (r.vence_em is null and r.competencia > v_mes))
        group by r.cliente_id
      ) f
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- 2 -------------------------------------------------------------------
create or replace function hub.rpc_garantir_recebiveis_mes(p_competencia date)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_comp date;
  v_hoje date;
  v_piso date;
  v_ultimo_dia date;
  rec record;
  v_ja_existe boolean;
  v_legado_n int;
  v_legado_id uuid;
  v_base date;
  v_parcela_num int;
  v_descricao text;
  v_vence date;
  v_n int;
  v_criados int := 0;
  v_ajustados int := 0;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_competencia is null then raise exception 'competência é obrigatória'; end if;

  v_comp := date_trunc('month', p_competencia)::date;
  v_ultimo_dia := (v_comp + interval '1 month - 1 day')::date;

  -- o reajuste nunca desce abaixo do mês corrente. Fuso dela, não o do servidor.
  v_hoje := (now() at time zone 'America/Recife')::date;
  v_piso := greatest(v_comp, date_trunc('month', v_hoje)::date);

  for rec in
    select ct.id as contrato_id, ct.cliente_id, ct.valor_mensal_centavos,
           ct.dia_vencimento, ct.parcelas_total, ct.inicio_em,
           count(*) over (partition by ct.cliente_id) as contratos_do_cliente
    from hub.contratos ct
    join hub.clientes cl on cl.id = ct.cliente_id
    where ct.status = 'ativo'
      and ct.recorrencia_ativa
      and ct.valor_mensal_centavos is not null
      and coalesce(cl.recorrente, true) is not false
    order by ct.id  -- ordem estável: idempotência não pode depender do plano
  loop

    -- ---------- A) criação do mês pedido ----------

    select exists (
      select 1 from hub.recebiveis r
      where r.contrato_id = rec.contrato_id
        and date_trunc('month', r.competencia)::date = v_comp
    ) into v_ja_existe;

    if not v_ja_existe then
      -- LEGADO = recebível de contrato lançado à mão antes da 034, sem
      -- contrato_id (em produção: os de Set/26).
      -- ⚠️ (array_agg(id order by id))[1] e NÃO min(id): o Postgres não tem
      -- agregado min/max pra uuid. Foi o bug da 035, pego no primeiro teste.
      select count(*), (array_agg(r.id order by r.id))[1] into v_legado_n, v_legado_id
      from hub.recebiveis r
      where r.cliente_id = rec.cliente_id
        and r.origem = 'contrato'
        and r.contrato_id is null
        and date_trunc('month', r.competencia)::date = v_comp;

      if v_legado_n = 1 and rec.contratos_do_cliente = 1 then
        -- um órfão, um contrato: adoção certa, não é chute. Não conta como
        -- "linha tocada": o retorno é criados + reajustados.
        update hub.recebiveis set contrato_id = rec.contrato_id where id = v_legado_id;

      elsif v_legado_n > 0 then
        -- ambíguo (ex.: The Best, 2 órfãos em Set/26): RECUA.
        null;

      else
        -- numeração por DISTÂNCIA DE MESES a partir de base estável.
        v_base := date_trunc('month', coalesce(
                    rec.inicio_em,
                    (select min(r.competencia) from hub.recebiveis r
                      where r.contrato_id = rec.contrato_id),
                    v_comp))::date;

        v_parcela_num := ((extract(year from v_comp)::int * 12 + extract(month from v_comp)::int)
                        - (extract(year from v_base)::int * 12 + extract(month from v_base)::int)) + 1;

        if v_parcela_num >= 1
           and (rec.parcelas_total is null or v_parcela_num <= rec.parcelas_total)
        then
          select ci.descricao into v_descricao
          from hub.contrato_itens ci
          where ci.contrato_id = rec.contrato_id
          order by ci.created_at asc
          limit 1;
          if v_descricao is null or btrim(v_descricao) = '' then
            v_descricao := 'Mensalidade';
          end if;
          if rec.parcelas_total is not null then
            v_descricao := v_descricao || ' — parcela ' || v_parcela_num || '/' || rec.parcelas_total;
          end if;

          v_vence := case when rec.dia_vencimento is not null
            then make_date(
              extract(year from v_comp)::int, extract(month from v_comp)::int,
              least(rec.dia_vencimento::int, extract(day from v_ultimo_dia)::int)
            )
            else null end;

          insert into hub.recebiveis
            (cliente_id, contrato_id, competencia, descricao, valor_centavos, vence_em, origem)
          values
            (rec.cliente_id, rec.contrato_id, v_comp, v_descricao, rec.valor_mensal_centavos, v_vence, 'contrato');

          v_criados := v_criados + 1;
        end if;
      end if;
    end if;

    -- ---------- B) reajuste em massa — o conserto do bug ----------
    update hub.recebiveis r
       set valor_centavos = rec.valor_mensal_centavos,
           sincronizado_planilha = false
     where r.contrato_id = rec.contrato_id
       and r.origem = 'contrato'
       and date_trunc('month', r.competencia)::date >= v_piso
       and coalesce(r.entrada_centavos, 0) = 0
       and r.entrou_em is null
       and not r.valor_travado
       and r.valor_centavos is distinct from rec.valor_mensal_centavos;

    get diagnostics v_n = row_count;
    v_ajustados := v_ajustados + v_n;

    -- ---------- C) 039: vencimento que faltou ----------
    -- Parcela que nasceu antes do contrato ter dia_vencimento ficava sem
    -- data pra sempre (The Best Nov/Dez/Jan, 07/10). Só PREENCHE nulo:
    -- vencimento que ela editou à mão nunca é sobrescrito.
    if rec.dia_vencimento is not null then
      update hub.recebiveis r
         set vence_em = make_date(
               extract(year from r.competencia)::int, extract(month from r.competencia)::int,
               least(rec.dia_vencimento::int,
                     extract(day from (date_trunc('month', r.competencia) + interval '1 month - 1 day'))::int)),
             sincronizado_planilha = false
       where r.contrato_id = rec.contrato_id
         and r.origem = 'contrato'
         and r.vence_em is null
         and date_trunc('month', r.competencia)::date >= v_piso
         and coalesce(r.entrada_centavos, 0) = 0
         and r.entrou_em is null;

      get diagnostics v_n = row_count;
      v_ajustados := v_ajustados + v_n;
    end if;

  end loop;

  return v_criados + v_ajustados;
end;
$function$;
