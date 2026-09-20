-- ============================================================
-- HUB LUH PANDA — 004: wrappers em public.*
-- Motivo: o schema `hub` não está exposto ao PostgREST (por
-- desenho — nenhuma tabela deve ser alcançável direto pela API).
-- Só `public` é exposto hoje neste projeto. Mesmo padrão já
-- usado pelo aprovi.ai (funções public.posta_ai_* envolvendo
-- as tabelas do schema posta_ai). Prefixo hub_ evita colisão.
-- ============================================================

create or replace function public.hub_rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_carteira(); $$;

create or replace function public.hub_rpc_catalogo()
returns setof hub.servicos
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_catalogo(); $$;

create or replace function public.hub_rpc_cliente(p_slug text)
returns jsonb
language sql stable security invoker set search_path = pg_catalog
as $$ select hub.rpc_cliente(p_slug); $$;

create or replace function public.hub_rpc_salvar_cliente(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_cliente(p); $$;

create or replace function public.hub_rpc_salvar_contrato(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_contrato(p); $$;

create or replace function public.hub_rpc_salvar_servico(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_servico(p); $$;

revoke all on function public.hub_rpc_carteira() from public, anon;
revoke all on function public.hub_rpc_catalogo() from public, anon;
revoke all on function public.hub_rpc_cliente(text) from public, anon;
revoke all on function public.hub_rpc_salvar_cliente(jsonb) from public, anon;
revoke all on function public.hub_rpc_salvar_contrato(jsonb) from public, anon;
revoke all on function public.hub_rpc_salvar_servico(jsonb) from public, anon;

grant execute on function public.hub_rpc_carteira() to authenticated;
grant execute on function public.hub_rpc_catalogo() to authenticated;
grant execute on function public.hub_rpc_cliente(text) to authenticated;
grant execute on function public.hub_rpc_salvar_cliente(jsonb) to authenticated;
grant execute on function public.hub_rpc_salvar_contrato(jsonb) to authenticated;
grant execute on function public.hub_rpc_salvar_servico(jsonb) to authenticated;
