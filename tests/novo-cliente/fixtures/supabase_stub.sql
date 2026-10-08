-- Imitação mínima do que o Supabase traz pronto, só pro teste local (PGlite).
-- auth.uid()/email()/role() leem request.jwt.claims, igual ao PostgREST.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema extensions;
create schema storage;
create extension if not exists pgcrypto with schema extensions;
create table auth.users (id uuid primary key default gen_random_uuid(), email text unique, raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'sub','')::uuid $$;
create function auth.email() returns text language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'email','') $$;
create function auth.role() returns text language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role','') $$;
grant usage on schema auth, extensions, storage to anon, authenticated, service_role;
create table storage.buckets (id text primary key, public boolean default false);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text not null, owner uuid);
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'),1)-1] $$;
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to authenticated;
insert into storage.buckets values ('contratos', false);
-- digest() vive em extensions no Supabase
