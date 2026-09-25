-- ============================================================
-- HUB LUH PANDA — 023: cliente recorrente × avulso (D1.1, item 2)
--
-- Decisão dela: "a carteira é recorrência". A Pandoka é freela — trabalho
-- pontual que aparece de vez em quando — e não deve poluir a carteira nem a
-- coluna "Cliente aberto" do CRM. Cliente avulso continua existindo, com
-- ficha, contatos, conversa e RECEBÍVEIS normais; só sai da lista de
-- recorrência.
--
-- `default true` de propósito: nenhum dos 8 clientes existentes muda de
-- comportamento por causa desta migration — só a Pandoka, e explicitamente,
-- no UPDATE do fim do arquivo.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (separação de papéis: quem coda não
-- aplica). Aplicar com `apply_migration`, rodar `get_advisors` (security)
-- depois. Depende da 021 e da 022 já aplicadas.
--
-- ⚠️ DROP + CREATE da rpc_carteira pela TERCEIRA vez (021 demandas, 022
-- tem_whatsapp, 023 recorrente) — RETURNS TABLE ganha coluna e Postgres não
-- deixa `create or replace` mudar o shape. Todos os campos da 021 e da 022
-- seguem intactos aqui; este arquivo é a definição completa e atual.
--
-- 🔴 A RPC NÃO FILTRA. Ela devolve TODOS os clientes, com a coluna
-- `recorrente` junto — quem filtra é o front, nas duas telas que exibem
-- carteira (renderCarteira e clientesCRM).
--
-- Por quê: a primeira versão deste arquivo tinha `where c.recorrente`, e isso
-- transformava um cache de uso geral numa view de uma tela só.
-- `hub_rpc_carteira` alimenta `loadCarteiraCache()`, que alimenta QUALQUER
-- formulário que precise escolher um cliente. A primeira vítima foi o
-- `formRecebivel()`: editar o recebível de R$ 1.599 da Pandoka com ela fora
-- da lista fazia o <select> cair no primeiro cliente e REATRIBUIR o recebível
-- em silêncio. Todo consumidor futuro herdaria o filtro sem saber.
-- Filtro de exibição mora na tela que exibe. Não no cache.
--
-- ✅ CONFERIDO (grep no repo + pg_get_functiondef nas 5 RPCs, pelo coordenador):
--   • Nenhuma RPC do banco chama hub.rpc_carteira.
--   • hub.rpc_recebiveis, hub.rpc_dash e hub.rpc_dash_periodo leem
--     `hub.recebiveis` direto. O recebível de R$ 1.599 da Pandoka (novembro,
--     casamento) continua no total do mês e nos Extras.
--   • hub.rpc_cobranca_config_lista (012) lê `hub.clientes` direto com
--     `where c.status = 'ativo'` — NÃO passa por rpc_carteira, então a
--     Pandoka continua na tela de Cobranças. ISSO ESTÁ CERTO E É DE
--     PROPÓSITO: a carteira é recorrência, a tela de Cobranças é "quem me
--     deve". Não "consertar".
-- ============================================================

-- ---------- coluna nova ----------

alter table hub.clientes add column if not exists recorrente boolean not null default true;

comment on column hub.clientes.recorrente is
  'true = cliente de recorrência, entra na carteira e na coluna "Cliente aberto" do CRM. false = freela/avulso (ex: Pandoka) — sai da carteira mas continua com ficha, conversa e recebíveis normais.';


-- ============================================================
-- hub.rpc_carteira — devolve `recorrente` e FILTRA por ele
-- ============================================================

drop function if exists public.hub_rpc_carteira();
drop function if exists hub.rpc_carteira();

create function hub.rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, recorrente boolean,
  servico text, valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean,
  tem_whatsapp boolean,
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

  -- SEM `where c.recorrente` — de propósito, ver o cabeçalho. Esta RPC é
  -- cache de uso geral (loadCarteiraCache alimenta os <select> de cliente);
  -- quem esconde avulso é a tela que exibe carteira, não o cache.
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
  tem_whatsapp boolean,
  demandas_abertas int, demandas_atrasadas int, demandas_previa jsonb
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_carteira(); $$;

revoke all on function public.hub_rpc_carteira() from public, anon;
grant execute on function public.hub_rpc_carteira() to authenticated;


-- ============================================================
-- hub.rpc_salvar_cliente — passthrough de `recorrente`
-- ============================================================
--
-- Armadilha de sempre: o upsert é destrutivo, então sem tratar a coluna nova
-- qualquer save da ficha voltaria a Pandoka pra recorrente.
--
-- Duas camadas, de propósito:
--   • o front passa `recorrente` em toda função que salva cliente
--     (salvarClienteFicha, salvarClientePatch);
--   • E AQUI o UPDATE preserva o valor atual quando a chave não vem no
--     payload — mesmo padrão de `coalesce(excluded.x, hub.tabela.x)` que a
--     020 já usa em rpc_registrar_mensagem. Assim um salvar antigo, de uma
--     aba que não recarregou o JS, não desfaz a marcação dela.
-- O shape do retorno não muda (uuid), então o wrapper da 004 continua válido.

create or replace function hub.rpc_salvar_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.clientes (id, empresa_id, slug, nome, razao_social, documento, segmento, origem, status, entrou_em, saiu_em, motivo_saida, observacao, recorrente)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'empresa_id')::uuid, p->>'slug', p->>'nome',
    p->>'razao_social', p->>'documento', p->>'segmento', p->>'origem',
    coalesce(p->>'status','ativo'), (p->>'entrou_em')::date, (p->>'saiu_em')::date, p->>'motivo_saida', p->>'observacao',
    coalesce((p->>'recorrente')::boolean, true)
  )
  on conflict (id) do update set
    empresa_id=excluded.empresa_id, slug=excluded.slug, nome=excluded.nome, razao_social=excluded.razao_social,
    documento=excluded.documento, segmento=excluded.segmento, origem=excluded.origem, status=excluded.status,
    entrou_em=excluded.entrou_em, saiu_em=excluded.saiu_em, motivo_saida=excluded.motivo_saida, observacao=excluded.observacao,
    recorrente=coalesce((p->>'recorrente')::boolean, hub.clientes.recorrente)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_cliente(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_cliente(jsonb) to authenticated;


-- ============================================================
-- dado: Pandoka é freela
-- ============================================================
-- Por slug, não por id chumbado. O trigger de auditoria de hub.clientes
-- (002) grava o dados_antes, então dá pra reverter sabendo o que era.

update hub.clientes set recorrente = false where slug = 'pandoka';

-- Conferência depois de aplicar — a RPC devolve os 8, com a Pandoka em false:
--   select nome, recorrente from hub.rpc_carteira() order by nome;  -- 8 linhas
--   select count(*) from hub.rpc_carteira() where recorrente;       -- 7
-- Na tela: carteira 7 · KPI "Clientes ativos" do CRM 7 · <select> de
-- recebível 8 (o filtro é do front, o cache continua completo).
