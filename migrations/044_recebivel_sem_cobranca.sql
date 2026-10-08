-- =====================================================================
-- 044 — RECEBÍVEL DE R$ 0 É "SEM COBRANÇA", NÃO "PAGO"
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 08/10/2026
-- Depende de: 038, 039, 040 (recria as três funções a partir delas).
--
-- O CASO (08/10)
-- Manu Pestana, Out/26: R$ 0,00 com status "Pago". NÃO foi o gerador: o
-- recebível nasceu certo (R$ 500, 28/09) e foi EDITADO PELA TELA pra R$ 0
-- em 30/09 20:35 UTC pela sessão dela (auditoria: ator = e-mail dela;
-- valor_travado = true, que é a marca de edição manual da 035). O contrato
-- continua R$ 500/mês, Nov–Jan R$ 500. O dado fica como está — é decisão
-- dela (mês de cortesia? erro de digitação?).
-- O defeito do SISTEMA é só de leitura: status = 'pago' sempre que
-- falta = 0, e com valor 0 a falta é 0 → "Pago" (e entrava no "Clientes
-- pagos" da tela).
--
-- O QUE MUDA
--   1. rpc_recebiveis e rpc_recebiveis_cliente: valor 0 → 'sem_cobranca'.
--   2. rpc_garantir_recebiveis_mes: contrato com valor_mensal 0 não gera
--      recebível (prevenção — hoje nenhum contrato tem valor 0).
-- Assinaturas iguais → wrappers e grants preservados.
-- =====================================================================

-- 1 ---
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
      when r.valor_centavos = 0 then 'sem_cobranca'   -- 044
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
      when r.valor_centavos = 0 then 'sem_cobranca'   -- 044
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

-- 2 ---
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
      and ct.valor_mensal_centavos > 0          -- 044: contrato de R$ 0 não gera recebível
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
