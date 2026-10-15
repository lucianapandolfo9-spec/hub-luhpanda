-- 045 — Carteira lê valor dos recebíveis + porta de saída opcional (15/10/2026)
--
-- 1) Carteira: o card só mostrava valor_mensal do contrato. Cliente sem
--    contrato (George — avulso "Criação de Skills"; Palácio — R$ 500 lançado
--    direto em Recebíveis) aparecia com "—" e "🔴 sem vencimento", mesmo com
--    o dinheiro lançado. Pedido dela: "ele lê o valor pelo recebíveis, coloco
--    lá e ele já se liga com o cliente e sobe o valor, porque nem todos têm
--    contrato". rpc_carteira passa a devolver o resumo dos recebíveis do mês
--    de referência (mês corrente; se não houver, o último mês com recebível).
--    Só leitura — nenhum dado é alterado.
--
-- 2) Porta de saída: deixa de travar. Vazia = 'nenhuma' ("acaba quando parar
--    de pagar"). Cai a CHECK hub_contrato_ativo_exige_porta_saida, a
--    ativação do contrato não recusa mais, e o cliente novo aceita sem
--    escolher. porta_saida_escrita_em só é marcada quando ela confirma que
--    está escrita (não é mais forçada para now()).

-- ---------- 1. carteira ----------
drop function if exists public.hub_rpc_carteira();
drop function if exists hub.rpc_carteira();

create function hub.rpc_carteira()
 returns table(cliente_id uuid, slug text, nome text, status text, recorrente boolean, servico text,
               valor_mensal_centavos bigint, dia_vencimento smallint, contrato_status text,
               tem_contrato boolean, tem_vencimento boolean, tem_whatsapp boolean,
               tipo_cobranca text, percentual_comissao numeric,
               demandas_abertas integer, demandas_atrasadas integer, demandas_previa jsonb,
               receb_competencia date, receb_valor_centavos bigint, receb_entrou_centavos bigint,
               receb_falta_centavos bigint, receb_proximo_vence date, receb_ultima_entrada date,
               receb_descricao text)
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog'
as $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select
    c.id, c.slug, c.nome, c.status, c.recorrente,
    coalesce(
      (select string_agg(distinct ci.descricao, ' + ') from hub.contrato_itens ci where ci.contrato_id = ct.id),
      ct.observacao
    ) as servico,
    ct.valor_mensal_centavos, ct.dia_vencimento, ct.status,
    coalesce(ct.status in ('assinado','ativo'), false) as tem_contrato,
    (ct.dia_vencimento is not null) as tem_vencimento,
    (
      (select k.whatsapp_e164 from hub.contatos k
         where k.cliente_id = c.id and k.whatsapp_e164 is not null
         order by k.is_principal desc limit 1)
      is not null
    ) as tem_whatsapp,
    c.tipo_cobranca, c.percentual_comissao,
    coalesce(dm.abertas, 0) as demandas_abertas,
    coalesce(dm.atrasadas, 0) as demandas_atrasadas,
    coalesce(dm.previa, '[]'::jsonb) as demandas_previa,
    rb.competencia, rb.valor, rb.entrou, rb.falta, rb.proximo_vence, rb.ultima_entrada, rb.descricao
  from hub.clientes c

  left join lateral (
    select x.*
    from hub.contratos x
    where x.cliente_id = c.id
    order by
      case x.status
        when 'ativo'     then 0
        when 'assinado'  then 1
        when 'enviado'   then 2
        when 'emitido'   then 3
        when 'rascunho'  then 4
        when 'encerrado' then 5
        else 6
      end,
      (case when x.dia_vencimento is null then 1 else 0 end)
        + (case when x.valor_mensal_centavos is null then 1 else 0 end),
      x.created_at desc
    limit 1
  ) ct on true

  left join lateral (
    select
      (count(*) filter (where d.status <> 'entregue'))::int as abertas,
      (count(*) filter (
        where d.status <> 'entregue'
          and d.entrega_em is not null
          and d.entrega_em < current_date
      ))::int as atrasadas,
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'titulo',     p.titulo,
                   'entrega_em', p.entrega_em,
                   'status',     p.status
                 )
                 order by p.entrega_em asc nulls last, p.created_at asc
               )
        from (
          select d2.titulo, d2.entrega_em, d2.status, d2.created_at
          from hub.demandas d2
          where d2.cliente_id = c.id
            and d2.status <> 'entregue'
          order by d2.entrega_em asc nulls last, d2.created_at asc
          limit 2
        ) p
      ) as previa
    from hub.demandas d
    where d.cliente_id = c.id
  ) dm on true

  -- 045 — mês de referência dos recebíveis: o corrente (fuso Recife); sem
  -- recebível nele, o último mês que tiver. Soma tudo daquele mês.
  left join lateral (
    with ref as (
      select coalesce(
               max(date_trunc('month', r0.competencia)::date)
                 filter (where r0.competencia < (date_trunc('month', now() at time zone 'America/Recife') + interval '1 month')::date),
               max(date_trunc('month', r0.competencia)::date)
             ) as comp
      from hub.recebiveis r0
      where r0.cliente_id = c.id
    )
    select
      ref.comp as competencia,
      sum(r.valor_centavos)::bigint   as valor,
      sum(r.entrada_centavos)::bigint as entrou,
      sum(r.falta_centavos)::bigint   as falta,
      min(r.vence_em) filter (where r.falta_centavos > 0) as proximo_vence,
      max(r.entrou_em) as ultima_entrada,
      string_agg(distinct r.descricao, ' + ') as descricao
    from ref
    join hub.recebiveis r
      on r.cliente_id = c.id
     and date_trunc('month', r.competencia)::date = ref.comp
    group by ref.comp
  ) rb on true

  order by c.nome;
end;
$function$;

revoke all on function hub.rpc_carteira() from public;
grant execute on function hub.rpc_carteira() to authenticated;

create function public.hub_rpc_carteira()
 returns table(cliente_id uuid, slug text, nome text, status text, recorrente boolean, servico text,
               valor_mensal_centavos bigint, dia_vencimento smallint, contrato_status text,
               tem_contrato boolean, tem_vencimento boolean, tem_whatsapp boolean,
               tipo_cobranca text, percentual_comissao numeric,
               demandas_abertas integer, demandas_atrasadas integer, demandas_previa jsonb,
               receb_competencia date, receb_valor_centavos bigint, receb_entrou_centavos bigint,
               receb_falta_centavos bigint, receb_proximo_vence date, receb_ultima_entrada date,
               receb_descricao text)
 language sql
 stable
 set search_path to 'pg_catalog'
as $function$ select * from hub.rpc_carteira(); $function$;

revoke all on function public.hub_rpc_carteira() from public, anon;
grant execute on function public.hub_rpc_carteira() to authenticated, service_role;

-- ---------- 2. porta de saída opcional ----------
alter table hub.contratos drop constraint if exists hub_contrato_ativo_exige_porta_saida;

-- Troca cirúrgica nas duas funções (texto exato, com trava: se a função
-- tiver mudado e o trecho não bater, a migration falha em vez de seguir).
do $mig$
declare
  v_def text;
  v_novo text;
begin
  -- ativar_contrato_assinado
  v_def := pg_get_functiondef('hub.ativar_contrato_assinado(uuid,date,boolean)'::regprocedure);
  v_novo := replace(v_def,
$a$  if v_ct.porta_saida_tipo is null then
    raise exception 'hub_contrato_ativo_exige_porta_saida';
  end if;
  if v_ct.porta_saida_escrita_em is null and not coalesce(p_porta_escrita, false) then
    raise exception 'hub_contrato_ativo_exige_porta_saida';
  end if;
$a$,
$b$  -- 045: porta de saída opcional — não trava mais a ativação (vazia = 'nenhuma')
$b$);
  v_novo := replace(v_novo,
$a$         porta_saida_escrita_em = coalesce(porta_saida_escrita_em, now())$a$,
$b$         porta_saida_tipo = coalesce(porta_saida_tipo, 'nenhuma'),
         porta_saida_escrita_em = coalesce(porta_saida_escrita_em,
                                           case when coalesce(p_porta_escrita, false) then now() end)$b$);
  if v_novo = v_def or v_novo like '%hub_contrato_ativo_exige_porta_saida%' then
    raise exception '045: trecho de ativar_contrato_assinado não bateu';
  end if;
  execute v_novo;

  -- rpc_novo_cliente
  v_def := pg_get_functiondef('hub.rpc_novo_cliente(jsonb)'::regprocedure);
  v_novo := replace(v_def,
$a$  if v_porta is null or v_porta not in ('manutencao_mensal','desligamento_build_30') then
    raise exception 'hub_novo_cliente_sem_porta_saida';
  end if;$a$,
$b$  -- 045: porta de saída opcional — vazia = 'nenhuma'
  v_porta := coalesce(v_porta, 'nenhuma');
  if v_porta not in ('manutencao_mensal','desligamento_build_30','nenhuma') then
    raise exception 'hub_novo_cliente_porta_saida_invalida';
  end if;$b$);
  if v_novo = v_def then
    raise exception '045: trecho de rpc_novo_cliente não bateu';
  end if;
  execute v_novo;
end
$mig$;
