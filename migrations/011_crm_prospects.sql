-- ============================================================
-- HUB LUH PANDA — 011: CRM nativo — funil de prospects (Fase 3, Bloco B, B5)
--
-- Kanban de 6 colunas fiel ao Canvas dela: Reunião marcada (0) → Reunião
-- feita (1) → Precificando (2) → Orçamento enviado (3) → Contrato emitido
-- (4) → Cliente aberto (5). O checklist de onboarding de 7 passos NÃO tem
-- tabela própria — é derivado no front a partir da `coluna`, exatamente
-- como o `mockup-v2-frontend.html` (`vProspect`, array `ONBOARD`) já faz.
--
-- Decisão da Luciana (22/09/2026): kanban SEM drag-and-drop — mover de
-- coluna é ação na ficha do prospect (`#/prospect/:id`), não arrastar o
-- cartão. Mais simples de construir e funciona no celular.
--
-- ⚠️ RASCUNHO AINDA NÃO APLICADO (22/09/2026) — sessão sem Supabase MCP.
-- Antes de aplicar numa sessão com acesso: aplicar depois da 010 (usa
-- `hub.default_workspace_id()` e a tabela `hub.workspaces` dela); conferir
-- que `hub.empresas` tem a linha 'Luh Panda' (fonte da 005) antes de testar
-- `rpc_converter_prospect_em_cliente`; testar as 5 RPCs com `execute_sql`;
-- rodar `get_advisors` depois.
-- ============================================================

create table hub.prospects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) default hub.default_workspace_id(),
  nome text not null,
  origem text,
  contato_whatsapp text,
  contato_email text,
  coluna smallint not null default 0 check (coluna between 0 and 5),
  valor_estimado_centavos bigint,
  nota text,
  gravacao boolean not null default false,
  entrou_em date not null default current_date,
  fechado_em date,
  perdido boolean not null default false,
  motivo_perda text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_prospects_updated_at
  before update on hub.prospects
  for each row execute function hub.set_updated_at();
create trigger trg_prospects_auditoria
  after insert or update or delete on hub.prospects
  for each row execute function hub.registrar_auditoria();

alter table hub.prospects enable row level security;
create policy hub_prospects_admin_all on hub.prospects
  for all using (hub.is_admin()) with check (hub.is_admin());

-- helper local: empresa única de hoje ('Luh Panda', seed da 005). Mesma
-- lógica de hub.default_workspace_id() — só existe 1 hoje.
create or replace function hub.default_empresa_id()
returns uuid
language sql
stable
set search_path = pg_catalog
as $$
  select id from hub.empresas where nome = 'Luh Panda' limit 1;
$$;

revoke all on function hub.default_empresa_id() from public, anon;
grant execute on function hub.default_empresa_id() to authenticated;

-- ---------- RPCs (security definer, padrão 003/007) ----------
create or replace function hub.rpc_prospects()
returns setof hub.prospects
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select * from hub.prospects
  order by perdido, coluna, created_at;
end;
$$;

create or replace function hub.rpc_prospect(p_id uuid)
returns hub.prospects
language plpgsql stable security definer set search_path = pg_catalog
as $$
declare v_row hub.prospects;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  select * into v_row from hub.prospects where id = p_id;
  if not found then return null; end if;
  return v_row;
end;
$$;

create or replace function hub.rpc_salvar_prospect(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.prospects (
    id, nome, origem, contato_whatsapp, contato_email, coluna,
    valor_estimado_centavos, nota, gravacao, entrou_em, fechado_em,
    perdido, motivo_perda
  )
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()),
    p->>'nome', p->>'origem', p->>'contato_whatsapp', p->>'contato_email',
    coalesce((p->>'coluna')::smallint, 0),
    (p->>'valor_estimado_centavos')::bigint, p->>'nota',
    coalesce((p->>'gravacao')::boolean, false),
    coalesce((p->>'entrou_em')::date, current_date),
    (p->>'fechado_em')::date,
    coalesce((p->>'perdido')::boolean, false), p->>'motivo_perda'
  )
  on conflict (id) do update set
    nome=excluded.nome, origem=excluded.origem, contato_whatsapp=excluded.contato_whatsapp,
    contato_email=excluded.contato_email, coluna=excluded.coluna,
    valor_estimado_centavos=excluded.valor_estimado_centavos, nota=excluded.nota,
    gravacao=excluded.gravacao, entrou_em=excluded.entrou_em, fechado_em=excluded.fechado_em,
    perdido=excluded.perdido, motivo_perda=excluded.motivo_perda
  returning id into v_id;

  return v_id;
end;
$$;

-- delete real — pra ela limpar prospects fantasmas/de teste do funil.
-- O trigger de auditoria acima grava o dados_antes antes de sumir.
create or replace function hub.rpc_apagar_prospect(p_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.prospects where id = p_id;
  if not found then raise exception 'prospect não encontrado'; end if;
end;
$$;

-- converte prospect em cliente de verdade: cria a linha em hub.clientes
-- (empresa dela, status 'ativo') e fecha o prospect (coluna=5, fechado_em).
-- Não apaga o prospect — fica no funil como "Cliente aberto", histórico
-- intacto (mesmo princípio de nunca apagar carteira usado no resto do hub).
create or replace function hub.rpc_converter_prospect_em_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_prospect hub.prospects; v_cliente_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select * into v_prospect from hub.prospects where id = (p->>'prospect_id')::uuid;
  if not found then raise exception 'prospect não encontrado'; end if;

  insert into hub.clientes (empresa_id, slug, nome, razao_social, documento, segmento, origem, status, entrou_em, observacao)
  values (
    hub.default_empresa_id(),
    p->>'slug',
    coalesce(p->>'nome', v_prospect.nome),
    p->>'razao_social', p->>'documento', p->>'segmento',
    coalesce(p->>'origem', v_prospect.origem),
    'ativo', current_date,
    p->>'observacao'
  )
  returning id into v_cliente_id;

  update hub.prospects
  set coluna = 5, fechado_em = current_date
  where id = v_prospect.id;

  return v_cliente_id;
end;
$$;

revoke all on function hub.rpc_prospects() from public, anon;
revoke all on function hub.rpc_prospect(uuid) from public, anon;
revoke all on function hub.rpc_salvar_prospect(jsonb) from public, anon;
revoke all on function hub.rpc_apagar_prospect(uuid) from public, anon;
revoke all on function hub.rpc_converter_prospect_em_cliente(jsonb) from public, anon;

grant execute on function hub.rpc_prospects() to authenticated;
grant execute on function hub.rpc_prospect(uuid) to authenticated;
grant execute on function hub.rpc_salvar_prospect(jsonb) to authenticated;
grant execute on function hub.rpc_apagar_prospect(uuid) to authenticated;
grant execute on function hub.rpc_converter_prospect_em_cliente(jsonb) to authenticated;

-- ---------- wrappers públicos (mesmo padrão do 004) ----------
create or replace function public.hub_rpc_prospects()
returns setof hub.prospects
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_prospects(); $$;

create or replace function public.hub_rpc_prospect(p_id uuid)
returns hub.prospects
language sql stable security invoker set search_path = pg_catalog
as $$ select hub.rpc_prospect(p_id); $$;

create or replace function public.hub_rpc_salvar_prospect(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_prospect(p); $$;

create or replace function public.hub_rpc_apagar_prospect(p_id uuid)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_apagar_prospect(p_id); $$;

create or replace function public.hub_rpc_converter_prospect_em_cliente(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_converter_prospect_em_cliente(p); $$;

revoke all on function public.hub_rpc_prospects() from public, anon;
revoke all on function public.hub_rpc_prospect(uuid) from public, anon;
revoke all on function public.hub_rpc_salvar_prospect(jsonb) from public, anon;
revoke all on function public.hub_rpc_apagar_prospect(uuid) from public, anon;
revoke all on function public.hub_rpc_converter_prospect_em_cliente(jsonb) from public, anon;

grant execute on function public.hub_rpc_prospects() to authenticated;
grant execute on function public.hub_rpc_prospect(uuid) to authenticated;
grant execute on function public.hub_rpc_salvar_prospect(jsonb) to authenticated;
grant execute on function public.hub_rpc_apagar_prospect(uuid) to authenticated;
grant execute on function public.hub_rpc_converter_prospect_em_cliente(jsonb) to authenticated;
