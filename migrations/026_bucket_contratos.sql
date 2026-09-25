-- ============================================================
-- HUB LUH PANDA — 026: bucket privado `contratos` (D2, item 6b)
--
-- PRIMEIRO uso de Storage no Hub. Hoje o único bucket do projeto é
-- `posta-ai-media`, que é PÚBLICO e é de outro produto (aprovi.ai) — este
-- aqui não tem nada a ver com aquele e nasce privado.
--
-- Guarda o PDF do contrato ASSINADO. Caminho:
--   <cliente_slug>/<contrato_id>.pdf
-- Previsível de propósito: o contrato aponta pro arquivo por
-- hub.contratos.arquivo_path, e reenviar o mesmo contrato sobrescreve em vez
-- de acumular lixo.
--
-- 🔴 SEPARADO DA 025 DE PROPÓSITO. `storage.objects` pertence a
-- `supabase_storage_admin`; criar policy nela depende do papel com que o
-- `apply_migration` roda. Migration é transacional — se a policy falhar
-- dentro da 025, as colunas e as RPCs rolam pra trás junto. Aqui, se falhar,
-- só o bucket fica faltando e o resto do D2 já está no banco.
--
-- ⚠️ SE ESTE ARQUIVO FALHAR com `42501 / permission denied for table objects`
-- (ou `must be owner of table objects`), NÃO force: criar pelo painel do
-- Supabase (Storage → New bucket, e depois Policies). Os parâmetros do bucket
-- e as 4 policies estão escritos abaixo exatamente como precisam ficar.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev. Aplicar depois da 025 e rodar
-- `get_advisors` (security) em seguida.
-- ============================================================

-- ---------- o bucket ----------
-- public=false: nada é servido por URL aberta. A leitura do front é sempre
-- por createSignedUrl de curta duração (60s).
-- 20 MB é folgado pra PDF de contrato assinado (os 3 reais no disco têm
-- menos de 1 MB cada).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contratos', 'contratos', false, 20971520, array['application/pdf'])
on conflict (id) do update set
  public             = false,
  file_size_limit    = 20971520,
  allowed_mime_types = array['application/pdf'];


-- ---------- policies: só a admin, nas 4 operações ----------
-- hub.is_admin() é SECURITY DEFINER e só devolve true pro e-mail dela
-- (001_schema_seguranca_auditoria.sql). `authenticated` sozinho NÃO basta —
-- qualquer pessoa logada no projeto é `authenticated`, e este bucket guarda
-- documento assinado com CNPJ e endereço de cliente.

drop policy if exists hub_contratos_admin_select on storage.objects;
drop policy if exists hub_contratos_admin_insert on storage.objects;
drop policy if exists hub_contratos_admin_update on storage.objects;
drop policy if exists hub_contratos_admin_delete on storage.objects;

create policy hub_contratos_admin_select on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos' and hub.is_admin());

create policy hub_contratos_admin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'contratos' and hub.is_admin());

create policy hub_contratos_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'contratos' and hub.is_admin())
  with check (bucket_id = 'contratos' and hub.is_admin());

create policy hub_contratos_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'contratos' and hub.is_admin());


-- Conferência depois de aplicar:
--   select id, public, file_size_limit, allowed_mime_types
--     from storage.buckets where id = 'contratos';
--   select policyname, cmd from pg_policies
--    where schemaname = 'storage' and tablename = 'objects'
--      and policyname like 'hub_contratos_%';   -- esperado: 4 linhas
