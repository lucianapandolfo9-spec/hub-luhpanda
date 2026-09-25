-- ============================================================
-- HUB LUH PANDA — 021: D1 (Fase 3, Bloco D — itens 1, 3, 5 e 8 do plano)
--
-- Quatro mudanças, todas do D1:
--   1) hub.rpc_carteira — escolhe o contrato MAIS RELEVANTE (não o mais
--      recente) e passa a trazer as demandas do cliente junto.
--   2) hub.rpc_salvar_contrato — recusa INSERT de contrato totalmente vazio
--      (a causa raiz da duplicata silenciosa do Régis/Dobradinha).
--   3) hub.rpc_apagar_servico — nova, com trava de uso em contrato_itens.
--   4) CHECK da porta de saída passa a exigir `tipo` junto do timestamp.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (separação de papéis: quem coda
-- não aplica). Aplicar com `apply_migration` e rodar `get_advisors`
-- (security) depois, como nos blocos anteriores.
--
-- ⚠️ ORDEM IMPORTA: aplicar ESTA migration ANTES do passo de dado do D1
-- (preencher as 7 portas de saída e promover os contratos pra `ativo`).
-- Hoje só a Império Ruby está `ativo`, e com porta_saida_tipo='nenhuma' —
-- então o CHECK apertado passa. Se os 7 forem promovidos ANTES, o ALTER
-- falha. O bloco de pré-checagem abaixo aborta com mensagem legível em vez
-- de estourar um erro críptico de constraint.
-- ============================================================


-- ============================================================
-- 1) hub.rpc_carteira — contrato relevante + demandas
-- ============================================================
--
-- POR QUE DROP E NÃO `create or replace`: o retorno é RETURNS TABLE e ganha
-- 3 colunas novas. Postgres não deixa `create or replace` mudar o shape —
-- mesma pedra da 020 com rpc_conversas_resumo. Derruba wrapper público
-- primeiro (ele depende da função do schema hub).
--
-- ESCOLHA DO CONTRATO (bug real, achado no Régis/Dobradinha):
-- antes era `order by created_at desc limit 1`, então um contrato em branco
-- criado por engano às 00:43 ganhava do contrato preenchido de 20/09 — o Hub
-- mostrava "sem vencimento" com o dado na linha de baixo. Agora a ordem é:
--   a) status, por relevância comercial
--      (ativo > assinado > enviado > emitido > rascunho > encerrado)
--   b) dentro do mesmo status, quem tem dia_vencimento/valor preenchidos
--      (os dois > um só > nenhum)
--   c) created_at desc só como desempate final
--
-- DEMANDAS: um único `left join lateral` agrega tudo — contagem, atrasadas
-- e a prévia das 2 mais próximas. Nada de uma chamada por card.

drop function if exists public.hub_rpc_carteira();
drop function if exists hub.rpc_carteira();

create function hub.rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean,
  demandas_abertas int, demandas_atrasadas int, demandas_previa jsonb
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select
    c.id, c.slug, c.nome, c.status,
    coalesce(
      (select string_agg(distinct ci.descricao, ' + ') from hub.contrato_itens ci where ci.contrato_id = ct.id),
      ct.observacao
    ) as servico,
    ct.valor_mensal_centavos, ct.dia_vencimento, ct.status,
    -- "formal" = contrato assinado ou ativo, não basta existir a linha
    coalesce(ct.status in ('assinado','ativo'), false) as tem_contrato,
    (ct.dia_vencimento is not null) as tem_vencimento,
    coalesce(dm.abertas, 0) as demandas_abertas,
    coalesce(dm.atrasadas, 0) as demandas_atrasadas,
    coalesce(dm.previa, '[]'::jsonb) as demandas_previa
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
        -- as 2 abertas de entrega mais próxima; sem data vai pro fim
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

  order by c.nome;
end;
$$;

revoke all on function hub.rpc_carteira() from public, anon;
grant execute on function hub.rpc_carteira() to authenticated;

-- ---------- wrapper público (schema hub não é exposto ao PostgREST) ----------
create function public.hub_rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean,
  demandas_abertas int, demandas_atrasadas int, demandas_previa jsonb
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_carteira(); $$;

revoke all on function public.hub_rpc_carteira() from public, anon;
grant execute on function public.hub_rpc_carteira() to authenticated;


-- ============================================================
-- 2) hub.rpc_salvar_contrato — recusa INSERT de contrato vazio
-- ============================================================
--
-- CAUSA RAIZ do item 3 do plano: `coalesce((p->>'id')::uuid, gen_random_uuid())`
-- significa que payload sem `id` SEMPRE insere. Abrir o modal "Novo contrato",
-- salvar sem preencher nada e fechar criava uma linha fantasma que depois
-- ganhava do contrato bom na leitura da carteira.
--
-- A guarda vale SÓ pro INSERT (sem `id` no payload). UPDATE continua livre —
-- limpar campos de um contrato existente é decisão dela, não acidente.
-- O shape do retorno não muda, então `create or replace` basta e o wrapper
-- público da 004 continua válido sem recriação.

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
  then
    -- nome de erro estável, no estilo de hub_contrato_ativo_exige_porta_saida,
    -- pro front traduzir em friendlyError()
    raise exception 'hub_contrato_vazio_nao_cria';
  end if;

  insert into hub.contratos (id, cliente_id, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_valor_centavos, porta_saida_escrita_em, observacao)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, p->>'numero',
    coalesce(p->>'status','rascunho'), (p->>'inicio_em')::date, (p->>'fim_minimo_em')::date,
    (p->>'dia_vencimento')::smallint, (p->>'valor_mensal_centavos')::bigint, p->>'porta_saida_tipo',
    (p->>'porta_saida_valor_centavos')::bigint, (p->>'porta_saida_escrita_em')::timestamptz, p->>'observacao'
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, numero=excluded.numero, status=excluded.status, inicio_em=excluded.inicio_em,
    fim_minimo_em=excluded.fim_minimo_em, dia_vencimento=excluded.dia_vencimento, valor_mensal_centavos=excluded.valor_mensal_centavos,
    porta_saida_tipo=excluded.porta_saida_tipo, porta_saida_valor_centavos=excluded.porta_saida_valor_centavos,
    porta_saida_escrita_em=excluded.porta_saida_escrita_em, observacao=excluded.observacao
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_contrato(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_contrato(jsonb) to authenticated;


-- ============================================================
-- 3) hub.rpc_apagar_servico — delete real, travado por uso
-- ============================================================
--
-- Espelha hub.rpc_apagar_contrato (008): is_admin(), delete real, auditoria
-- pelo trigger que hub.servicos já tem desde a 002.
--
-- A diferença: hub.contrato_itens.servico_id referencia hub.servicos sem
-- `on delete`, então o FK já barraria — mas com erro críptico de constraint.
-- Aqui a recusa vem ANTES do delete, com o NOME DO CLIENTE em que o serviço
-- está em uso (contrato_itens → contratos → clientes), pra mensagem dizer
-- exatamente onde mexer.

create or replace function hub.rpc_apagar_servico(p_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_clientes text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select string_agg(distinct cl.nome, ', ' order by cl.nome)
    into v_clientes
  from hub.contrato_itens ci
  join hub.contratos co on co.id = ci.contrato_id
  join hub.clientes  cl on cl.id = co.cliente_id
  where ci.servico_id = p_id;

  if v_clientes is not null then
    -- nome de erro estável + o(s) cliente(s), pro friendlyError() do front
    raise exception 'hub_servico_em_uso: %', v_clientes;
  end if;

  delete from hub.servicos where id = p_id;
  if not found then raise exception 'serviço não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_apagar_servico(uuid) from public, anon;
grant execute on function hub.rpc_apagar_servico(uuid) to authenticated;

-- ---------- wrapper público (mesmo padrão do 004/008) ----------
create or replace function public.hub_rpc_apagar_servico(p_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_apagar_servico(p_id); $$;

revoke all on function public.hub_rpc_apagar_servico(uuid) from public, anon;
grant execute on function public.hub_rpc_apagar_servico(uuid) to authenticated;


-- ============================================================
-- 4) CHECK da porta de saída — exigir tipo JUNTO do timestamp
-- ============================================================
--
-- Antes: `check (status <> 'ativo' or porta_saida_escrita_em is not null)`.
-- Brecha: dava pra ativar marcando só o checkbox "porta de saída já escrita"
-- e deixando o seletor de tipo em branco — o banco aceitava, e o contrato
-- ficava ativo sem dizer QUAL é a saída. `'nenhuma'` é uma decisão registrada
-- ("a saída é: não tem"); NULL é ausência de decisão.
--
-- Pré-checagem obrigatória antes do ALTER: se algum contrato já `ativo` tiver
-- tipo nulo, o ALTER falharia no meio da migration. Aqui ele aborta com
-- mensagem legível e nada é aplicado pela metade.

do $$
declare v_n int; v_quem text;
begin
  select count(*), string_agg(distinct cl.nome, ', ' order by cl.nome)
    into v_n, v_quem
  from hub.contratos co
  join hub.clientes cl on cl.id = co.cliente_id
  where co.status = 'ativo'
    and (co.porta_saida_escrita_em is null or co.porta_saida_tipo is null);

  if v_n > 0 then
    raise exception
      'BLOQUEIO 021: % contrato(s) ativo(s) sem porta de saída completa (%). Preencha porta_saida_tipo + porta_saida_escrita_em antes de apertar o CHECK.',
      v_n, v_quem;
  end if;
end $$;

alter table hub.contratos drop constraint if exists hub_contrato_ativo_exige_porta_saida;

alter table hub.contratos add constraint hub_contrato_ativo_exige_porta_saida
  check (
    status <> 'ativo'
    or (porta_saida_escrita_em is not null and porta_saida_tipo is not null)
  );

comment on constraint hub_contrato_ativo_exige_porta_saida on hub.contratos is
  'Guarda de negócio (CLAUDE.md): contrato ativo tem que ter porta de saída ESCRITA e com TIPO definido — manutencao_mensal, desligamento_build_30 ou nenhuma. NULL = decisão não tomada, e aí não ativa.';
