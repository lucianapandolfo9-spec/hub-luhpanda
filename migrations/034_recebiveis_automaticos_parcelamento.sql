-- ============================================================
-- HUB LUH PANDA — 034: recebíveis automáticos + parcelamento com fim
-- programado + apagar cliente sem histórico
--
-- Pedido dela (28/09/2026), 3 pontas do mesmo problema — "cada mês da tela
-- Recebíveis parece que precisa ser preenchido manualmente":
--
--   1) RECORRÊNCIA AUTOMÁTICA — cliente com mensalidade recorrente deve
--      gerar o recebível do mês seguinte sozinho, sem lançar na mão.
--   2) PARCELAMENTO COM FIM — ex.: Daniel Magnus (robô de atendimento, 6x,
--      R$500). Precisa de um "número de parcelas" por contrato, e a
--      recorrência automática do item 1 tem que PARAR de gerar depois da
--      última parcela — não pode virar mensalidade infinita quando era um
--      parcelamento fechado.
--   3) APAGAR CLIENTE sem histórico direto do card da Carteira (item 2 do
--      pedido "arquivar/apagar cliente") — arquivar já existe (033); apagar
--      de vez só é seguro quando não existe contrato/recebível/demanda real
--      dependurado (senão apaga histórico de cliente de verdade, o que o
--      projeto já decidiu nunca fazer sem ela mandar — CLAUDE.md).
--
-- DESENHO (decisões tomadas nesta sessão, documentadas — não um /grill-me
-- completo com ela; ela confirma quando revisar):
--
--   • Sem cron/n8n novo. A geração roda por RPC idempotente
--     (hub.rpc_garantir_recebiveis_mes), chamada pelo FRONT toda vez que a
--     tela Financeiro/Recebíveis carrega um mês (e pré-aquece os 3 meses
--     seguintes) — mesmo princípio de "o Google Agenda é a fonte da
--     verdade, o Hub só lê" já usado no Bloco F: aqui o CONTRATO é a fonte
--     da verdade, o recebível nasce dele sob demanda, sempre em dia.
--   • `hub.recebiveis` ganha `contrato_id` (nullable) — sem isso não dá pra
--     saber QUANTAS parcelas de um contrato específico já nasceram (um
--     cliente pode ter mais de um contrato ao longo do tempo) nem impedir
--     duplicata de forma confiável.
--   • `hub.contratos` ganha `parcelas_total` (null = mensalidade sem fim,
--     igual hoje) e `recorrencia_ativa` (default true — escape hatch pra
--     ela pausar a geração automática sem mexer no status do contrato).
--   • Parcela N/total: a função conta quantos recebíveis já existem com
--     aquele `contrato_id` e usa isso como número da próxima parcela. Ao
--     atingir `parcelas_total`, para de gerar — não precisa de coluna de
--     contador (menos estado pra dessincronizar).
--   • Descrição do recebível gerado: primeiro item do contrato
--     (`hub.contrato_itens.descricao`), senão "Mensalidade"; se tem
--     parcelas_total, entra " — parcela N/total" (mesmo formato que já
--     aparecia manualmente pro Daniel Magnus, "1/6").
--   • NÃO gera retroativo além do que ela já lançou à mão — só cobre daqui
--     pra frente (mês atual em diante). Backfill de meses passados continua
--     manual, como já era (ela pediu "meses FUTUROS").
--
-- ⚠️ NÃO APLICADA por esta sessão de dev — sem Supabase MCP disponível
-- (confirmado por ToolSearch no início, mesma limitação de quase toda
-- sessão anterior deste projeto). Antes de aplicar numa sessão com MCP:
--   1) conferir por introspecção que `hub.recebiveis` tem as colunas já
--      documentadas na 006/009 (cliente_id, competencia, descricao,
--      valor_centavos, entrada_centavos, entrou_em, vence_em,
--      falta_centavos GENERATED, origem, observacao) antes de rodar o
--      ALTER TABLE abaixo;
--   2) aplicar via `apply_migration`;
--   3) rodar `get_advisors` (security) depois;
--   4) testar com `hub_rpc_garantir_recebiveis_mes` num mês futuro (ex.:
--      dezembro/2026) num cliente de TESTE antes de confiar nos 8 reais.
-- ============================================================

do $$
begin
  if to_regclass('hub.contratos') is null then
    raise exception 'hub.contratos não existe — aplicar a 002 antes da 034.';
  end if;
  if to_regclass('hub.recebiveis') is null then
    raise exception 'hub.recebiveis não existe (tabela da Fase 2, nunca migrada — ver nota no topo do 006) — conferir manualmente antes de seguir.';
  end if;
end $$;


-- ============================================================
-- 1) colunas novas
-- ============================================================

alter table hub.contratos
  add column if not exists parcelas_total smallint
    check (parcelas_total is null or parcelas_total > 0);

alter table hub.contratos
  add column if not exists recorrencia_ativa boolean not null default true;

comment on column hub.contratos.parcelas_total is
  'Null = mensalidade sem fim (padrão). Preenchido = parcelamento fechado (ex.: Daniel Magnus, 6x) — a geração automática de recebíveis para depois da parcela N.';
comment on column hub.contratos.recorrencia_ativa is
  'Escape hatch pra pausar a geração automática de recebíveis sem mexer no status do contrato. Default true — todo contrato ativo com valor mensal gera recebível sozinho, a menos que ela desligue aqui.';

alter table hub.recebiveis
  add column if not exists contrato_id uuid references hub.contratos(id) on delete set null;

comment on column hub.recebiveis.contrato_id is
  'Liga o recebível ao contrato que o gerou (migration 034). Nullable: recebíveis antigos/lançados à mão continuam sem vínculo, sem problema — só quem foi gerado por hub.rpc_garantir_recebiveis_mes carrega isso, e é o que permite contar "parcela N/total" e não duplicar mês.';

create index if not exists idx_recebiveis_contrato_id on hub.recebiveis(contrato_id) where contrato_id is not null;


-- ============================================================
-- 2) hub.rpc_garantir_recebiveis_mes — gera o que falta, idempotente
-- ============================================================
--
-- Chamada pelo front toda vez que a tela Financeiro abre um mês (e uns
-- meses à frente, pra "já estar lá" quando ela navega). Segura de rodar
-- quantas vezes quiser: sempre confere se já existe recebível de contrato
-- pra aquele cliente+mês antes de inserir.

create or replace function hub.rpc_garantir_recebiveis_mes(p_competencia date)
returns int
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_comp date;
  v_ultimo_dia date;
  rec record;
  v_parcela_num int;
  v_descricao text;
  v_vence date;
  v_criados int := 0;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_competencia is null then raise exception 'competência é obrigatória'; end if;

  v_comp := date_trunc('month', p_competencia)::date;
  v_ultimo_dia := (v_comp + interval '1 month - 1 day')::date;

  for rec in
    select ct.id as contrato_id, ct.cliente_id, ct.valor_mensal_centavos,
           ct.dia_vencimento, ct.parcelas_total, ct.inicio_em
    from hub.contratos ct
    join hub.clientes cl on cl.id = ct.cliente_id
    where ct.status = 'ativo'
      and ct.recorrencia_ativa
      and ct.valor_mensal_centavos is not null
      and coalesce(cl.recorrente, true) is not false
  loop
    -- já existe recebível de CONTRATO pra esse cliente nessa competência?
    -- não duplica (olha por cliente_id, não só contrato_id, pra cobrir o
    -- caso de um recebível antigo lançado à mão sem contrato_id ainda).
    if exists (
      select 1 from hub.recebiveis
      where cliente_id = rec.cliente_id and origem = 'contrato'
        and date_trunc('month', competencia)::date = v_comp
    ) then
      continue;
    end if;

    -- não gera pra competência anterior ao início do contrato, se souber
    if rec.inicio_em is not null and v_comp < date_trunc('month', rec.inicio_em)::date then
      continue;
    end if;

    -- número da próxima parcela = quantos recebíveis desse contrato_id já existem + 1
    select count(*) into v_parcela_num from hub.recebiveis where contrato_id = rec.contrato_id;
    v_parcela_num := v_parcela_num + 1;

    if rec.parcelas_total is not null and v_parcela_num > rec.parcelas_total then
      continue; -- parcelamento encerrado — não vira mensalidade infinita
    end if;

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
  end loop;

  return v_criados;
end;
$$;

revoke all on function hub.rpc_garantir_recebiveis_mes(date) from public, anon;
grant execute on function hub.rpc_garantir_recebiveis_mes(date) to authenticated;

create or replace function public.hub_rpc_garantir_recebiveis_mes(p_competencia date)
returns int
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_garantir_recebiveis_mes(p_competencia); $$;

revoke all on function public.hub_rpc_garantir_recebiveis_mes(date) from public, anon;
grant execute on function public.hub_rpc_garantir_recebiveis_mes(date) to authenticated;


-- ============================================================
-- 3) hub.rpc_salvar_contrato — passthrough de parcelas_total/recorrencia_ativa
-- ============================================================
--
-- Mesma armadilha de sempre (023/025/032): o upsert é destrutivo. Shape do
-- retorno não muda (uuid) — create or replace basta, wrapper da 004
-- continua válido.

create or replace function hub.rpc_salvar_contrato(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  if (p->>'id') is null
     and nullif(btrim(coalesce(p->>'numero','')), '') is null
     and nullif(btrim(coalesce(p->>'valor_mensal_centavos','')), '') is null
     and nullif(btrim(coalesce(p->>'dia_vencimento','')), '') is null
     and nullif(btrim(coalesce(p->>'observacao','')), '') is null
  then
    raise exception 'hub_contrato_vazio_nao_cria';
  end if;

  insert into hub.contratos (id, cliente_id, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_valor_centavos, porta_saida_escrita_em, observacao, parcelas_total, recorrencia_ativa)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, p->>'numero',
    coalesce(p->>'status','rascunho'), (p->>'inicio_em')::date, (p->>'fim_minimo_em')::date,
    (p->>'dia_vencimento')::smallint, (p->>'valor_mensal_centavos')::bigint, p->>'porta_saida_tipo',
    (p->>'porta_saida_valor_centavos')::bigint, (p->>'porta_saida_escrita_em')::timestamptz, p->>'observacao',
    nullif(p->>'parcelas_total','')::smallint, coalesce((p->>'recorrencia_ativa')::boolean, true)
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, numero=excluded.numero, status=excluded.status, inicio_em=excluded.inicio_em,
    fim_minimo_em=excluded.fim_minimo_em, dia_vencimento=excluded.dia_vencimento, valor_mensal_centavos=excluded.valor_mensal_centavos,
    porta_saida_tipo=excluded.porta_saida_tipo, porta_saida_valor_centavos=excluded.porta_saida_valor_centavos,
    porta_saida_escrita_em=excluded.porta_saida_escrita_em, observacao=excluded.observacao,
    parcelas_total=case when p ? 'parcelas_total' then nullif(p->>'parcelas_total','')::smallint else hub.contratos.parcelas_total end,
    recorrencia_ativa=case when p ? 'recorrencia_ativa' then coalesce((p->>'recorrencia_ativa')::boolean, true) else hub.contratos.recorrencia_ativa end
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_contrato(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_contrato(jsonb) to authenticated;


-- ============================================================
-- 4) hub.rpc_apagar_cliente — delete real, só quando NÃO há histórico
-- ============================================================
--
-- Mesmo espírito de hub_servico_em_uso (021): recusa com mensagem que o
-- front traduz, em vez de apagar dado de cliente real por engano. Pensado
-- pro caso "criei um cliente de teste/errado, quero limpar" — não pro caso
-- "cliente real que saiu" (isso é o Arquivar, 033, que já existe e é
-- reversível).

create or replace function hub.rpc_apagar_cliente(p_cliente_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_contratos int; v_recebiveis int; v_demandas int;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_cliente_id is null then raise exception 'cliente_id é obrigatório'; end if;

  select count(*) into v_contratos from hub.contratos where cliente_id = p_cliente_id;
  select count(*) into v_recebiveis from hub.recebiveis where cliente_id = p_cliente_id;
  select count(*) into v_demandas from hub.demandas where cliente_id = p_cliente_id;

  if v_contratos > 0 or v_recebiveis > 0 or v_demandas > 0 then
    raise exception 'hub_cliente_com_historico: % contrato(s), % recebível(is), % demanda(s) — arquive em vez de apagar.',
      v_contratos, v_recebiveis, v_demandas;
  end if;

  delete from hub.contatos where cliente_id = p_cliente_id;
  delete from hub.clientes where id = p_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_apagar_cliente(uuid) from public, anon;
grant execute on function hub.rpc_apagar_cliente(uuid) to authenticated;

create or replace function public.hub_rpc_apagar_cliente(p_cliente_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_apagar_cliente(p_cliente_id); $$;

revoke all on function public.hub_rpc_apagar_cliente(uuid) from public, anon;
grant execute on function public.hub_rpc_apagar_cliente(uuid) to authenticated;


-- ============================================================
-- Conferência rápida depois de aplicar (cliente de TESTE, nunca um dos reais):
--   -- cria contrato ativo, valor 500, dia 10, 3 parcelas, num cliente de teste
--   select hub_rpc_garantir_recebiveis_mes('2026-10-01');
--   select hub_rpc_garantir_recebiveis_mes('2026-11-01');
--   select hub_rpc_garantir_recebiveis_mes('2026-12-01');
--   select hub_rpc_garantir_recebiveis_mes('2027-01-01'); -- deve vir 0 (parcela 4/3 não existe)
--   select competencia, descricao, contrato_id from hub.recebiveis
--     where contrato_id = '<uuid-teste>' order by competencia;
--   -- deve mostrar 3 linhas, "... — parcela 1/3" / "2/3" / "3/3"
--   select hub_rpc_apagar_cliente('<uuid-cliente-com-recebivel>'); -- deve levantar hub_cliente_com_historico
-- ============================================================
