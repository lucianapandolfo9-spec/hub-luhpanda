-- =====================================================================
-- 043 — TETO DO MEI POR ANO (ano de abertura é PROPORCIONAL)
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 08/10/2026
-- Depende de: 039 (recria hub.rpc_dash a partir dela).
--
-- O BUG
-- O card "TETO MEI — 2026" mostrava R$ 81.000 e "acima de R$ 97.200 é
-- retroativo". Errado pra 2026: o MEI dela abriu em 29/04/2026, e no ano de
-- abertura o limite é PROPORCIONAL (LC 123/2006, art. 18-A, §2º):
-- R$ 6.750 × meses de atividade, contando o mês de abertura. Abr–dez = 9
-- meses → R$ 60.750; faixa de 20% → R$ 72.900. Acima dela o desenquadra-
-- mento retroage à DATA DE ABERTURA (29/04/2026), não a 1º de janeiro.
-- R$ 81.000 / R$ 97.200 só a partir de 2027. Regra registrada no vault
-- (Financeiro/Contabilidade Própria, conferida em 01/10/2026) e no CLAUDE.md.
--
-- O QUE MUDA
--   1. hub.empresas.aberta_em (date) — preenchida pro MEI dela (29/04/2026).
--   2. hub.mei_limites(p_ano) — teto, tolerância (120%), meses e a data pra
--      onde o desenquadramento retroage, pro ano pedido. Regra:
--        • ano de abertura: teto_anual/12 × (13 − mês de abertura);
--          retroage à data de abertura;
--        • anos seguintes: teto_anual cheio; retroage a 1º/jan;
--        • aberta_em vazia: teto cheio (comportamento antigo).
--   3. hub.rpc_dash: velocimetro_mei passa a vir de hub.mei_limites e manda
--      tudo que a tela precisa pro texto certo de cada caso.
-- =====================================================================

-- 1 -------------------------------------------------------------------
alter table hub.empresas add column if not exists aberta_em date;
comment on column hub.empresas.aberta_em is
  '043: data de abertura do CNPJ. No ano de abertura o teto do MEI é proporcional (LC 123/2006 art. 18-A §2º).';

update hub.empresas
   set aberta_em = '2026-04-29'
 where tipo = 'mei' and cnpj = '66.521.744/0001-60' and aberta_em is null;

-- 2 -------------------------------------------------------------------
create or replace function hub.mei_limites(p_ano int)
returns table(ano int, teto_anual_centavos bigint, meses int, teto_centavos bigint,
              tolerancia_centavos bigint, ano_abertura boolean, aberta_em date, retroage_a date)
language plpgsql
stable security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_anual bigint;
  v_aberta date;
  v_meses int := 12;
  v_teto bigint;
begin
  select e.teto_anual_centavos, e.aberta_em into v_anual, v_aberta
    from hub.empresas e where e.tipo = 'mei' order by e.created_at limit 1;
  v_anual := coalesce(v_anual, 8100000);

  if v_aberta is not null and extract(year from v_aberta)::int = p_ano then
    v_meses := 13 - extract(month from v_aberta)::int;      -- mês de abertura conta
    v_teto := round(v_anual::numeric / 12 * v_meses)::bigint;
  elsif v_aberta is not null and extract(year from v_aberta)::int > p_ano then
    v_meses := 0; v_teto := 0;                              -- ainda não existia
  else
    v_teto := v_anual;
  end if;

  return query select p_ano, v_anual, v_meses, v_teto,
    round(v_teto::numeric * 1.2)::bigint,
    (v_aberta is not null and extract(year from v_aberta)::int = p_ano),
    v_aberta,
    case when v_aberta is not null and extract(year from v_aberta)::int = p_ano
         then v_aberta else make_date(p_ano, 1, 1) end;
end;
$function$;

revoke all on function hub.mei_limites(int) from public, anon, authenticated;

-- 3 -------------------------------------------------------------------
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
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

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
    -- 043: teto do ANO, proporcional no ano de abertura (hub.mei_limites)
    'velocimetro_mei', (
      select jsonb_build_object(
        'entrado_ano_centavos', coalesce((
          select sum(entrada_centavos) from hub.recebiveis
          where entrou_em >= v_ano_inicio and entrou_em < v_ano_inicio + interval '1 year'
        ), 0),
        'ano', l.ano,
        'teto_centavos', l.teto_centavos,
        'tolerancia_centavos', l.tolerancia_centavos,
        'teto_anual_centavos', l.teto_anual_centavos,
        'meses', l.meses,
        'ano_abertura', l.ano_abertura,
        'aberta_em', l.aberta_em,
        'retroage_a', l.retroage_a
      )
      from hub.mei_limites(extract(year from v_hoje)::int) l
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
