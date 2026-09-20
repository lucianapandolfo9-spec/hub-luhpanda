-- ============================================================
-- HUB LUH PANDA — 001: schema, segurança, auditoria
-- Convive com public.* (Certo Agro) e posta_ai.* (aprovi.ai)
-- no mesmo projeto Supabase (tscnqvuzlfagotirgjbz).
-- ============================================================

create schema if not exists hub;

-- Nenhum acesso direto por API a este schema. Tudo passa por RPC.
revoke all on schema hub from anon, authenticated, public;
grant usage on schema hub to authenticated;

-- ---------- admin (só a Luciana) ----------
create or replace function hub.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(auth.email(), '') = 'lucianapandolfo9@gmail.com';
$$;

-- ---------- updated_at genérico ----------
create or replace function hub.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- auditoria ----------
create table hub.eventos_auditoria (
  id uuid primary key default gen_random_uuid(),
  tabela text not null,
  registro_id uuid,
  acao text not null check (acao in ('insert','update','delete')),
  dados_antes jsonb,
  dados_depois jsonb,
  ator_email text,
  criado_em timestamptz not null default now()
);

alter table hub.eventos_auditoria enable row level security;

create policy hub_eventos_auditoria_admin_select
  on hub.eventos_auditoria for select
  using (hub.is_admin());

create or replace function hub.registrar_auditoria()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into hub.eventos_auditoria (tabela, registro_id, acao, dados_antes, dados_depois, ator_email)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op in ('update','delete') then to_jsonb(old) else null end,
    case when tg_op in ('insert','update') then to_jsonb(new) else null end,
    coalesce(auth.email(), 'sistema')
  );
  return coalesce(new, old);
end;
$$;
