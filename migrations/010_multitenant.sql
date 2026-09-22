-- ============================================================
-- HUB LUH PANDA — 010: multi-tenant mínimo (Fase 3, Bloco B, item B4)
--
-- Decisão da Luciana (22/09/2026): OPÇÃO MÍNIMA. Só a coluna
-- `workspace_id` (default = workspace dela) nas tabelas existentes e
-- novas — NÃO mexer nas policies de RLS. Hoje só existe ela como admin,
-- `hub.is_admin()` sozinho já isola tudo. `hub.workspace_members` +
-- `hub.current_workspace_id()` + policy por workspace só entram quando
-- existir um 2º tenant real (produto "CRM + bot de atendimento"), com
-- /grill-me próprio daquela fase. Não pagar complexidade antes da hora.
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (22/09/2026) — sessão sem Supabase MCP
-- (mesma limitação dos Blocos A/1.5/1.6, ver cabeçalho da 006/007). Antes
-- de aplicar numa sessão com acesso:
--   1) conferir por introspecção (`list_tables`) que as 7 tabelas do loop
--      abaixo existem com os nomes esperados (bater com 002/007);
--   2) aplicar via `apply_migration`, na ordem 010 → 011 → 012;
--   3) rodar `get_advisors` (security) depois — nenhuma tabela deve ficar
--      sem RLS habilitada (a de `hub.workspaces` já nasce com policy).
-- ============================================================

create table hub.workspaces (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_workspaces_updated_at
  before update on hub.workspaces
  for each row execute function hub.set_updated_at();
create trigger trg_workspaces_auditoria
  after insert or update or delete on hub.workspaces
  for each row execute function hub.registrar_auditoria();

alter table hub.workspaces enable row level security;
create policy hub_workspaces_admin_all on hub.workspaces
  for all using (hub.is_admin()) with check (hub.is_admin());

-- seed: o único workspace de hoje
insert into hub.workspaces (nome, slug) values ('Luh Panda', 'luhpanda');

-- helper: resolve o workspace único de hoje. Vira "múltiplo" só na fase
-- que ligar hub.workspace_members — aí esta função é substituída por
-- hub.current_workspace_id() (lido de auth.uid()), não antes.
create or replace function hub.default_workspace_id()
returns uuid
language sql
stable
set search_path = pg_catalog
as $$
  select id from hub.workspaces where slug = 'luhpanda' limit 1;
$$;

revoke all on function hub.default_workspace_id() from public, anon;
grant execute on function hub.default_workspace_id() to authenticated;

-- coluna workspace_id nas tabelas existentes do schema hub, retroativa
-- (as tabelas novas do Bloco B — prospects, cobranca_* — já nascem com a
-- coluna nas migrations 011/012, sem precisar deste loop).
do $$
declare t text;
begin
  foreach t in array array['empresas','clientes','contatos','servicos','contratos','contrato_itens','demandas']
  loop
    execute format(
      'alter table hub.%1$s add column workspace_id uuid references hub.workspaces(id) default hub.default_workspace_id();',
      t
    );
    execute format(
      'update hub.%1$s set workspace_id = hub.default_workspace_id() where workspace_id is null;',
      t
    );
    execute format(
      'alter table hub.%1$s alter column workspace_id set not null;',
      t
    );
  end loop;
end $$;
