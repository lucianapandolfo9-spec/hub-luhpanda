-- ============================================================
-- HUB LUH PANDA — 032: Bloco G — Carteira: tipo de cobrança (fixo × porcentagem)
--
-- Desenhado 25/09/2026 via /grill-me (Hub Dev.md, seção Bloco G). Motivado
-- por um cliente novo real: Victor Vizinho — ela fica com 33,3% sobre as
-- vendas dele, não recebe valor fixo nem direto. Hoje `hub.clientes` não tem
-- onde anotar "esse cliente é comissão".
--
-- Decisões travadas no grill-me (não redesenhar):
--   1) Campo mora no CLIENTE inteiro, não por contrato/serviço — um cliente
--      é OU valor fixo OU porcentagem, vale pra tudo que ele paga.
--   2) SEM motor de cálculo novo. O recebível de comissão continua lançado
--      MANUAL, como qualquer recebível hoje. O percentual salvo é só
--      referência/registro — não dispara nada automático.
--   3) Percentual é número fixo (ex: 33.30), não texto livre.
--   4) Sem campo de "valor estimado" pro MRR — a soma dos recebíveis reais
--      do mês já é o número certo pros KPIs, igual pro cliente fixo.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev caso não haja Supabase MCP
-- disponível (separação de papéis: quem coda não aplica). Se houver MCP
-- nesta sessão, aplicar com `apply_migration` e rodar `get_advisors`
-- (security) depois, como nos blocos anteriores.
--
-- ⚠️ DROP + CREATE de hub.rpc_carteira de novo (4ª vez — 021 demandas, 022
-- tem_whatsapp, 023 recorrente, agora tipo_cobranca/percentual_comissao):
-- RETURNS TABLE ganha coluna e Postgres não deixa `create or replace` mudar
-- o shape. Todos os campos das migrations anteriores seguem intactos aqui;
-- este arquivo é a definição completa e atual.
--
-- hub.rpc_cliente (003_rpcs.sql) NÃO precisa mudar — usa
-- `select * into v_cliente from hub.clientes` + `to_jsonb(v_cliente)`, então
-- as 2 colunas novas chegam pra ficha do cliente de graça.
-- ============================================================

-- ---------- colunas novas ----------

alter table hub.clientes
  add column if not exists tipo_cobranca text not null default 'fixo'
    check (tipo_cobranca in ('fixo','percentual'));

alter table hub.clientes
  add column if not exists percentual_comissao numeric(5,2);

comment on column hub.clientes.tipo_cobranca is
  'fixo = mensalidade/valor combinado (padrão, hub.contratos.valor_mensal_centavos). percentual = comissão sobre venda do cliente (ex: Victor Vizinho, 33,3%) — sem motor de cálculo, ela lança o recebível manual como sempre.';
comment on column hub.clientes.percentual_comissao is
  'Só preenchido quando tipo_cobranca=percentual. É referência/registro, não dispara cálculo automático nenhum.';


-- ============================================================
-- hub.rpc_carteira — devolve tipo_cobranca + percentual_comissao
-- ============================================================

drop function if exists public.hub_rpc_carteira();
drop function if exists hub.rpc_carteira();

create function hub.rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, recorrente boolean,
  servico text, valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean,
  tem_whatsapp boolean, tipo_cobranca text, percentual_comissao numeric,
  demandas_abertas int, demandas_atrasadas int, demandas_previa jsonb
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
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
    -- "formal" = contrato assinado ou ativo, não basta existir a linha
    coalesce(ct.status in ('assinado','ativo'), false) as tem_contrato,
    (ct.dia_vencimento is not null) as tem_vencimento,
    -- mesma leitura de contato da 012 (rpc_cobranca_config_lista): principal
    -- na frente, e basta UM contato com número pra valer
    (
      (select k.whatsapp_e164 from hub.contatos k
         where k.cliente_id = c.id and k.whatsapp_e164 is not null
         order by k.is_principal desc limit 1)
      is not null
    ) as tem_whatsapp,
    c.tipo_cobranca, c.percentual_comissao,
    coalesce(dm.abertas, 0) as demandas_abertas,
    coalesce(dm.atrasadas, 0) as demandas_atrasadas,
    coalesce(dm.previa, '[]'::jsonb) as demandas_previa
  from hub.clientes c

  -- contrato MAIS RELEVANTE, não o mais recente (021, item 3 do plano):
  -- status > campos preenchidos > created_at como último desempate
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

  -- demandas do cliente num lateral só (021, item 1 do plano) — nunca N+1
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

  -- SEM `where c.recorrente` — de propósito, ver 023. Esta RPC é cache de
  -- uso geral (loadCarteiraCache alimenta os <select> de cliente); quem
  -- esconde avulso é a tela que exibe carteira, não o cache.
  order by c.nome;
end;
$$;

revoke all on function hub.rpc_carteira() from public, anon;
grant execute on function hub.rpc_carteira() to authenticated;

-- ---------- wrapper público (schema hub não é exposto ao PostgREST) ----------
create function public.hub_rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, recorrente boolean,
  servico text, valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean,
  tem_whatsapp boolean, tipo_cobranca text, percentual_comissao numeric,
  demandas_abertas int, demandas_atrasadas int, demandas_previa jsonb
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_carteira(); $$;

revoke all on function public.hub_rpc_carteira() from public, anon;
grant execute on function public.hub_rpc_carteira() to authenticated;


-- ============================================================
-- hub.rpc_salvar_cliente — passthrough de tipo_cobranca/percentual_comissao
-- ============================================================
--
-- Mesma armadilha de sempre (023): o upsert é destrutivo. Sem tratar as
-- colunas novas, qualquer save antigo da ficha voltaria o cliente pra
-- 'fixo' e apagaria o percentual. Front passa os dois campos em toda função
-- que salva cliente (salvarCliente, salvarClienteFicha, salvarClientePatch);
-- e aqui o UPDATE preserva o valor atual quando a chave não vem no payload
-- — mesmo padrão de coalesce(excluded.x, hub.tabela.x).
-- O shape do retorno não muda (uuid), então o wrapper da 004 continua válido.

create or replace function hub.rpc_salvar_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.clientes (id, empresa_id, slug, nome, razao_social, documento, segmento, origem, status, entrou_em, saiu_em, motivo_saida, observacao, recorrente, endereco, tipo_cobranca, percentual_comissao)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'empresa_id')::uuid, p->>'slug', p->>'nome',
    p->>'razao_social', p->>'documento', p->>'segmento', p->>'origem',
    coalesce(p->>'status','ativo'), (p->>'entrou_em')::date, (p->>'saiu_em')::date, p->>'motivo_saida', p->>'observacao',
    coalesce((p->>'recorrente')::boolean, true), p->>'endereco',
    coalesce(p->>'tipo_cobranca', 'fixo'), (p->>'percentual_comissao')::numeric
  )
  on conflict (id) do update set
    empresa_id=excluded.empresa_id, slug=excluded.slug, nome=excluded.nome, razao_social=excluded.razao_social,
    documento=excluded.documento, segmento=excluded.segmento, origem=excluded.origem, status=excluded.status,
    entrou_em=excluded.entrou_em, saiu_em=excluded.saiu_em, motivo_saida=excluded.motivo_saida, observacao=excluded.observacao,
    recorrente=coalesce((p->>'recorrente')::boolean, hub.clientes.recorrente),
    endereco=case when p ? 'endereco' then p->>'endereco' else hub.clientes.endereco end,
    tipo_cobranca=case when p ? 'tipo_cobranca' then coalesce(p->>'tipo_cobranca', 'fixo') else hub.clientes.tipo_cobranca end,
    percentual_comissao=case when p ? 'percentual_comissao' then (p->>'percentual_comissao')::numeric else hub.clientes.percentual_comissao end
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_cliente(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_cliente(jsonb) to authenticated;

-- Conferência rápida depois de aplicar:
--   select nome, tipo_cobranca, percentual_comissao from hub.rpc_carteira() order by nome;
--   -- 8 clientes antigos com 'fixo'/null, nenhum novo ainda até cadastrar o Victor Vizinho
