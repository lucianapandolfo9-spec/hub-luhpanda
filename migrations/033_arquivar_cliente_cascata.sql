-- ============================================================
-- HUB LUH PANDA — 033: Bloco H, item 3 — arquivar cliente em cascata
-- (contratos + demandas), reversível
--
-- Desenhado 25/09/2026 via /grill-me (Hub Dev.md, seção "🆕 Bloco H — 3
-- ajustes em Contratos/Carteira"). Motivo: hoje arquivar/reativar cliente
-- só mexe em hub.clientes (status/saiu_em/motivo_saida) — contrato e
-- demanda continuam rodando como se nada tivesse acontecido. Ela quer que
-- arquivar pause de verdade, e reativar devolva.
--
-- Decisões travadas (não redesenhar):
--   1) Status novo `arquivado` em hub.contratos e hub.demandas — NÃO reusa
--      `encerrado`/`entregue`, que já significam "acabou de verdade" e
--      ficariam ambíguos na hora de reativar.
--   2) Regra de restauração simples, sem guardar o status anterior
--      detalhado: reativar sempre devolve contrato pra `ativo` e demanda
--      pra `aberta` — perde a distinção aberta/fazendo de propósito (ela
--      topou essa simplificação).
--   3) Só contrato `ativo` entra na cascata de arquivar (rascunho/emitido/
--      enviado/assinado não é tocado — não faz sentido um rascunho pular
--      pra `ativo` ao reativar, saltando o resto do pipeline).
--   4) Demanda `aberta` ou `fazendo` entra na cascata; `entregue` não é
--      tocada (já é estado final real).
--   5) Tudo atômico dentro de uma função plpgsql — não em updates soltos
--      no front.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (sem Supabase MCP disponível —
-- mesma limitação documentada nos Blocos A/1.5/1.6/B/D/F/G). Aplicar com
-- `apply_migration`, depois `get_advisors` (security), como sempre.
-- ============================================================

do $$
begin
  if to_regclass('hub.contratos') is null then
    raise exception 'hub.contratos não existe — aplicar a 002 antes da 033.';
  end if;
  if to_regclass('hub.demandas') is null then
    raise exception 'hub.demandas não existe — aplicar a 007 antes da 033.';
  end if;
end $$;


-- ============================================================
-- 1) CHECK constraints ganham 'arquivado'
-- ============================================================

alter table hub.contratos drop constraint contratos_status_check;
alter table hub.contratos add constraint contratos_status_check
  check (status in ('rascunho','emitido','enviado','assinado','ativo','encerrado','arquivado'));

alter table hub.demandas drop constraint demandas_status_check;
alter table hub.demandas add constraint demandas_status_check
  check (status in ('aberta','fazendo','entregue','arquivado'));

-- hub_contrato_ativo_exige_porta_saida (002) não muda: continua valendo só
-- pra status='ativo'. Um contrato só chega em 'arquivado' vindo de 'ativo'
-- (cascata abaixo), então já tinha porta de saída escrita — reativar volta
-- pra 'ativo' sem violar nada.


-- ============================================================
-- 2) hub.rpc_arquivar_cliente — cliente + contrato ativo + demandas abertas
-- ============================================================

create or replace function hub.rpc_arquivar_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_cliente_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_cliente_id := (p->>'cliente_id')::uuid;
  if v_cliente_id is null then raise exception 'cliente_id é obrigatório'; end if;

  update hub.clientes
  set status = 'encerrado',
      saiu_em = coalesce((p->>'saiu_em')::date, current_date),
      motivo_saida = nullif(btrim(coalesce(p->>'motivo_saida', '')), '')
  where id = v_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;

  -- só o contrato que estava rodando de verdade pausa
  update hub.contratos
  set status = 'arquivado'
  where cliente_id = v_cliente_id and status = 'ativo';

  -- demanda em andamento pausa; entregue (estado final real) fica intocada
  update hub.demandas
  set status = 'arquivado'
  where cliente_id = v_cliente_id and status in ('aberta','fazendo');

  return v_cliente_id;
end;
$$;

-- ============================================================
-- 3) hub.rpc_reativar_cliente — espelho, regra simples de restauração
-- ============================================================

create or replace function hub.rpc_reativar_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_cliente_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_cliente_id := (p->>'cliente_id')::uuid;
  if v_cliente_id is null then raise exception 'cliente_id é obrigatório'; end if;

  update hub.clientes
  set status = 'ativo', saiu_em = null, motivo_saida = null
  where id = v_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;

  update hub.contratos
  set status = 'ativo'
  where cliente_id = v_cliente_id and status = 'arquivado';

  -- perde a distinção aberta/fazendo de propósito (decisão do grill-me)
  update hub.demandas
  set status = 'aberta'
  where cliente_id = v_cliente_id and status = 'arquivado';

  return v_cliente_id;
end;
$$;

revoke all on function hub.rpc_arquivar_cliente(jsonb) from public, anon;
revoke all on function hub.rpc_reativar_cliente(jsonb) from public, anon;
grant execute on function hub.rpc_arquivar_cliente(jsonb) to authenticated;
grant execute on function hub.rpc_reativar_cliente(jsonb) to authenticated;


-- ============================================================
-- 4) wrappers públicos (schema hub não é exposto ao PostgREST) — mesmo
--    padrão de 029/032: security invoker, revoke public/anon, grant
--    authenticated.
-- ============================================================

create or replace function public.hub_rpc_arquivar_cliente(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_arquivar_cliente(p); $$;

create or replace function public.hub_rpc_reativar_cliente(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_reativar_cliente(p); $$;

revoke all on function public.hub_rpc_arquivar_cliente(jsonb) from public, anon;
revoke all on function public.hub_rpc_reativar_cliente(jsonb) from public, anon;
grant execute on function public.hub_rpc_arquivar_cliente(jsonb) to authenticated;
grant execute on function public.hub_rpc_reativar_cliente(jsonb) to authenticated;

-- Conferência rápida depois de aplicar (com um cliente de TESTE, nunca um
-- dos 8 reais da carteira):
--   select hub_rpc_arquivar_cliente('{"cliente_id":"<uuid-teste>","motivo_saida":"teste migration 033"}'::jsonb);
--   select status from hub.contratos where cliente_id = '<uuid-teste>';   -- ativo -> arquivado
--   select status from hub.demandas where cliente_id = '<uuid-teste>';   -- aberta/fazendo -> arquivado
--   select hub_rpc_reativar_cliente('{"cliente_id":"<uuid-teste>"}'::jsonb);
--   -- confirma que voltou: cliente ativo, contrato ativo, demanda aberta
