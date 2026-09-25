-- ============================================================
-- HUB LUH PANDA — 022: hub.rpc_carteira ganha `tem_whatsapp`
--
-- ACHADO NO TESTE REAL DO D1 (24/09/2026): o selo "⚠ sem WhatsApp" do card
-- de cliente no kanban estava preso ao RESUMO DE CONVERSA, não ao contato.
-- Resultado: GL4 / Gio aparecia "sem WhatsApp" sendo que tem
-- hub.contatos.whatsapp_e164 = '17472755982' cadastrado desde 24/09 — ela só
-- nunca trocou mensagem. "Sem conversa ainda" e "sem WhatsApp cadastrado" são
-- estados diferentes, e só o segundo pede ação dela.
--
-- Estado real no banco na hora do achado:
--   Daniel Magnus 558488505335 (1 conversa) · F7 558499441661 (1) ·
--   GL4/Gio 17472755982 (0 conversas) ← o selo mentia aqui ·
--   Imperio Ruby null (0) · Lead Performance null (0) ·
--   Manu Pestana 5511983587501 (1) · Pandoka null (0) ·
--   Régis/Dobradinha 120363409640736089 @grupo (1)
--
-- FONTE DO CAMPO: o MESMO subselect que hub.rpc_cobranca_config_lista já usa
-- (012, linhas 94-96) pra achar o WhatsApp do cliente — contato com
-- whatsapp_e164 não nulo, principal na frente. Não inventei convenção: se o
-- bot de cobrança acharia um número pro cliente, o card diz que tem WhatsApp.
-- Os dois não podem divergir.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (separação de papéis: quem coda não
-- aplica). Aplicar com `apply_migration` e rodar `get_advisors` (security)
-- depois. Depende da 021 já aplicada (os 3 campos de demanda vêm de lá e
-- continuam aqui).
--
-- ⚠️ DROP + CREATE de novo: RETURNS TABLE ganha coluna, e Postgres não deixa
-- `create or replace` mudar o shape. Wrapper público derrubado junto e os
-- grants refeitos nos dois — mesma receita da 021 e da 020.
-- ============================================================

drop function if exists public.hub_rpc_carteira();
drop function if exists hub.rpc_carteira();

create function hub.rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
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
    c.id, c.slug, c.nome, c.status,
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
  tem_whatsapp boolean,
  demandas_abertas int, demandas_atrasadas int, demandas_previa jsonb
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_carteira(); $$;

revoke all on function public.hub_rpc_carteira() from public, anon;
grant execute on function public.hub_rpc_carteira() to authenticated;

-- Conferência rápida depois de aplicar (deve bater com a tabela do cabeçalho:
-- 5 clientes com true, 3 com false — Imperio Ruby, Lead Performance, Pandoka):
--   select nome, tem_whatsapp from hub.rpc_carteira() order by nome;
