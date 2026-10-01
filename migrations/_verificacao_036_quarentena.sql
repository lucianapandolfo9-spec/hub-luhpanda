-- =====================================================================
-- VERIFICAÇÃO da migration 036 — quarentena do legado Certo Agro
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz
-- Rodado em 01/10/2026 logo após aplicar a 036: 22/22 PASSOU.
--
-- Leia a coluna `veredito`. Qualquer FALHOU é bloqueador — nesse caso use o
-- bloco ROLLBACK comentado no fim da 036.
--
-- A checagem nº 12 é a mais importante: se aparecer função ÓRFÃ em `public`
-- (nem hub*, nem posta_ai*, nem uma das 3 rpc_ do aprovi), então alguma
-- coisa ficou atrás ou foi movida errado.
-- =====================================================================

with chk as (select * from (values
  ('1', 'public: tabelas',        (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r')::text, '0'),
  ('2', 'public: views',          (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v')::text, '0'),
  ('3', 'public: sequences',      (select count(*) from pg_sequences where schemaname='public')::text, '0'),
  ('4', 'public: funcoes (120 -> 88)', (select count(*) from pg_proc where pronamespace='public'::regnamespace)::text, '88'),
  ('5', 'legado: tabelas',        (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='_legado_certo_agro' and c.relkind='r')::text, '13'),
  ('6', 'legado: views',          (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='_legado_certo_agro' and c.relkind='v')::text, '1'),
  ('7', 'legado: sequences',      (select count(*) from pg_sequences where schemaname='_legado_certo_agro')::text, '1'),
  ('8', 'legado: funcoes',        (select count(*) from pg_proc where pronamespace='_legado_certo_agro'::regnamespace)::text, '32'),
  ('9', 'public: funcoes hub*',   (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname like 'hub%')::text, '67'),
  ('10','public: funcoes posta_ai*', (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname like 'posta_ai%')::text, '18'),
  -- As 3 do aprovi SEM prefixo posta_ai_. Se um filtro negativo tivesse sido
  -- usado na 036, estas teriam ido pra quarentena e o aprovi.ai pararia de
  -- publicar — descoberto só quando o próximo post vencesse.
  ('11','public: as 3 rpc_ do aprovi', (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('rpc_proximo_post_agendado','rpc_marcar_resultado_publicacao','rpc_validar_upload'))::text, '3'),
  ('12','public: funcoes ORFAS (nao hub/posta_ai/rpc)', (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname not like 'hub%' and proname not like 'posta_ai%' and proname not in ('rpc_proximo_post_agendado','rpc_marcar_resultado_publicacao','rpc_validar_upload'))::text, '0'),
  ('13','anon tem USAGE no schema legado', (select has_schema_privilege('anon','_legado_certo_agro','usage'))::text, 'false'),
  ('14','authenticated tem USAGE no legado', (select has_schema_privilege('authenticated','_legado_certo_agro','usage'))::text, 'false'),
  ('15','roles publicos com SELECT em tabela do legado', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace, unnest(array['anon','authenticated']) r(rn) where n.nspname='_legado_certo_agro' and c.relkind='r' and has_table_privilege(r.rn, c.oid, 'select'))::text, '0'),
  ('16','APROVI VIVO: posts',     (select count(*) from posta_ai.posts)::text, '40'),
  ('17','APROVI VIVO: cron jobs', (select count(*) from cron.job)::text, '2'),
  ('18','HUB VIVO: clientes',     (select count(*) from hub.clientes)::text, '11'),
  ('19','HUB VIVO: recebiveis',   (select count(*) from hub.recebiveis)::text, '46'),
  -- Quarentena, nao DROP: o dado tem que continuar lá.
  ('20','LEGADO INTACTO: cotacoes',(select count(*) from _legado_certo_agro.cotacao_arroba)::text, '367'),
  ('21','LEGADO INTACTO: triggers nas tabelas', (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='_legado_certo_agro' and not t.tgisinternal)::text, '9'),
  ('22','HUB INTACTO: triggers',  (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='hub' and not t.tgisinternal)::text, '31')
) as t(n, checagem, obtido, esperado))
select n, checagem, esperado, obtido,
       case when obtido=esperado then 'PASSOU' else '>>> FALHOU <<<' end as veredito
from chk order by n::int;


-- =====================================================================
-- PROVA DE ATAQUE — de FORA do banco, com a anon key
-- =====================================================================
-- As checagens acima rodam de dentro do Postgres. Esta roda de fora, com a
-- credencial que um atacante tem: a anon key, que é publicada no config.js
-- de dois repos PÚBLICOS (aprovi-ai e hub-luhpanda).
--
-- Lição registrada: testar com curl direto na API, não clicando na tela.
--
--   REF=tscnqvuzlfagotirgjbz
--   ANON=$(grep -oE 'eyJ[A-Za-z0-9._-]+' config.js | head -1)
--   B="https://$REF.supabase.co"
--
--   # Tabelas do Certo Agro — esperado 404 (fora do PostgREST).
--   # NAO 401: 401 significaria que ainda estao em public e so faltou credencial.
--   for t in fazenda lote pesagem cotacao_arroba assinatura admin_sistema; do
--     curl -s -o /dev/null -w "$t %{http_code}\n" "$B/rest/v1/$t?select=id&limit=1" -H "apikey: $ANON"
--   done
--
--   # RPCs do Certo Agro — esperado 404
--   for f in eh_admin calc_gmd admin_dashboard_clientes; do
--     curl -s -o /dev/null -w "$f %{http_code}\n" -X POST "$B/rest/v1/rpc/$f" \
--       -H "apikey: $ANON" -H 'Content-Type: application/json' -d '{}'
--   done
--
--   # A RPC que vazava o token da Meta — esperado 401, NUNCA 200
--   curl -s -o /dev/null -w "%{http_code}\n" -X POST "$B/rest/v1/rpc/rpc_proximo_post_agendado" \
--     -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' -d '{}'
--
--   # Aprovi vivo — esperado 200
--   curl -s -o /dev/null -w "%{http_code}\n" -X POST "$B/rest/v1/rpc/posta_ai_admin_list_brands" \
--     -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' -d '{}'
--
-- RESULTADO EM 01/10/2026 — tudo como esperado:
--   fazenda/lote/pesagem/cotacao_arroba/assinatura/admin_sistema .... 404
--   eh_admin / calc_gmd / admin_dashboard_clientes .................. 404
--   rpc_proximo_post_agendado ....................................... 401
--   posta_ai_admin_list_brands ...................................... 200
--
-- 📌 Função da Hub com anon key dá 401 e isso é CORRETO, não regressão:
--    hub_rpc_catalogo / hub_rpc_dash / hub_rpc_carteira têm
--    anon=false, authenticated=true — a Hub exige login por desenho.
--    Para provar que o corpo delas executa, chame por SQL: o retorno
--    esperado é `P0001: acesso negado` levantado por hub.is_admin(),
--    o que significa que a função foi alcançada e a guarda funcionou.
-- =====================================================================
