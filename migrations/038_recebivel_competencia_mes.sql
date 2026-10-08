-- =====================================================================
-- 038 — COMPETÊNCIA DE RECEBÍVEL É SEMPRE O MÊS (dia 1)
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 07/10/2026
-- Depende de: 037 (pra normalização abaixo ficar na auditoria).
--
-- O BUG
-- O form "Novo recebível" tinha Competência como type="date" e
-- hub.rpc_salvar_recebivel gravava a data crua. Ela lançou o Palácio Dos
-- Esportes com 07/10 → competencia = 2026-10-07. hub.rpc_recebiveis busca
-- por IGUALDADE (r.competencia = p_competencia) e a tela manda sempre o
-- dia 1 → o recebível nunca apareceu em Recebíveis. Em 07/10 eram 5 de 48
-- linhas fora do dia 1 (Palácio ×2, The Best 26/09 e 28/09, Victor 25/09).
-- E hub.rpc_dash.por_mes agrupava pela data crua → "meses" falsos no gráfico.
--
-- O QUE MUDA
--   1. rpc_salvar_recebivel trunca a competência pro dia 1 (fonte única).
--   2. rpc_recebiveis compara por mês (defensivo, mesmo resultado agora).
--   3. rpc_dash.por_mes agrupa por mês. (A 039 recria rpc_dash inteira e
--      mantém isso.)
--   4. Normaliza as linhas existentes fora do dia 1 — exceto se colidir
--      com outro recebível do MESMO contrato no mesmo mês (índice
--      uq_recebiveis_contrato_mes); aí a constraint do passo 5 aborta tudo
--      e a linha precisa de decisão humana. Em 07/10 nenhuma tinha contrato.
--   5. CHECK no banco: nenhuma escrita futura (tela, n8n, SQL) grava
--      competência fora do dia 1 de novo.
--
-- Nada de wrapper público muda (assinaturas iguais → grants preservados).
-- =====================================================================

-- 1 -------------------------------------------------------------------
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

-- 2 -------------------------------------------------------------------
create or replace function hub.rpc_recebiveis(p_competencia date)
returns table(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, status text)
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
    r.origem, r.observacao,
    case
      when r.falta_centavos = 0 then 'pago'
      when r.entrada_centavos > 0 then 'parcial'
      when r.vence_em is not null and r.vence_em < v_hoje then 'vencido'
      else 'aberto'
    end as status
  from hub.recebiveis r
  join hub.clientes c on c.id = r.cliente_id
  -- 038: por MÊS, não igualdade de data
  where date_trunc('month', r.competencia) = date_trunc('month', p_competencia)
  order by c.nome;
end;
$function$;

-- 3 -------------------------------------------------------------------
create or replace function hub.rpc_dash()
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_hoje date := (now() at time zone 'America/Recife')::date;
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
          'competencia', date_trunc('month', competencia)::date,   -- 038
          'previsto_centavos', sum(valor_centavos),
          'entrado_centavos', sum(entrada_centavos)
        ) as m
        from hub.recebiveis
        group by date_trunc('month', competencia)::date             -- 038
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
        'recebivel_id', r.id, 'cliente_nome', c.nome, 'cliente_slug', c.slug,
        'falta_centavos', r.falta_centavos, 'vence_em', r.vence_em
      ) order by r.vence_em)
      from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
      where r.falta_centavos > 0 and r.vence_em is not null and r.vence_em <= v_hoje
    ), '[]'::jsonb),
    'sem_vencimento', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recebivel_id', r.id, 'cliente_nome', c.nome, 'cliente_slug', c.slug,
        'falta_centavos', r.falta_centavos
      ))
      from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
      where r.falta_centavos > 0 and r.vence_em is null
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- 4 -------------------------------------------------------------------
update hub.recebiveis r
   set competencia = date_trunc('month', r.competencia)::date
 where r.competencia <> date_trunc('month', r.competencia)::date
   and (
     r.contrato_id is null
     or not exists (
       select 1 from hub.recebiveis o
        where o.contrato_id = r.contrato_id
          and o.id <> r.id
          and date_trunc('month', o.competencia) = date_trunc('month', r.competencia)
     )
   );

-- 5 -------------------------------------------------------------------
alter table hub.recebiveis
  add constraint recebiveis_competencia_dia_1
  check (competencia = date_trunc('month', competencia)::date);

-- ROLLBACK (só do que é reversível):
--   alter table hub.recebiveis drop constraint recebiveis_competencia_dia_1;
--   e reaplicar as definições de rpc_salvar_recebivel / rpc_recebiveis /
--   rpc_dash da migration anterior. A normalização do passo 4 fica (o dia
--   original está na auditoria, dados_antes, graças à 037).
