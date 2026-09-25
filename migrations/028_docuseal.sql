-- ============================================================
-- HUB LUH PANDA — 028: DocuSeal (Fase 3, Bloco D — item 7 revisto, 25/09/2026)
--
-- Contexto (ver Hub Dev.md): os 3 contratos "assinados" no ar (F7, Império
-- Ruby, Dobradinha) NÃO têm assinatura real do cliente — só o carimbo gov.br
-- dela. Decisão: DocuSeal auto-hospedado (assinar.luhpanda.com.br, já
-- deployado e rodando na VPS Hostinger). Fluxo novo: Hub gera o envelope →
-- ela assina primeiro → cliente recebe por e-mail e assina → webhook avisa
-- o Hub → hub.contratos.status atualiza sozinho.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (mesma separação de papéis das
-- migrations anteriores: quem coda não aplica). Aplicar com `apply_migration`
-- e rodar `get_advisors` (security) depois.
--
-- ⚠️ Ela ainda NÃO criou a conta em /setup do DocuSeal nem gerou a API key —
-- então nada disto pôde ser testado ponta a ponta. O desenho segue a OpenAPI
-- pública do DocuSeal (console.docuseal.com/openapi.yml) e a documentação de
-- webhooks — não um payload real capturado. Ver comentário em
-- supabase/functions/docuseal-webhook/index.ts sobre o que conferir na
-- primeira assinatura de teste.
-- ============================================================


-- ============================================================
-- 1) colunas novas em hub.contratos
-- ============================================================
alter table hub.contratos
  add column if not exists docuseal_submission_id bigint,
  add column if not exists docuseal_audit_log_url text;

comment on column hub.contratos.docuseal_submission_id is
  'Id da submission no DocuSeal (assinar.luhpanda.com.br) — é por ele que o webhook acha de volta qual contrato mudou de estado. Um contrato só ganha isto quando o envelope é criado pela Edge Function docuseal-integrar.';
comment on column hub.contratos.docuseal_audit_log_url is
  'Link do PDF de trilha de auditoria que o DocuSeal gera quando a submission fecha (quem assinou, quando, IP) — só informativo, não substitui arquivo_path.';

create unique index if not exists idx_contratos_docuseal_submission
  on hub.contratos (docuseal_submission_id)
  where docuseal_submission_id is not null;


-- ============================================================
-- 2) hub.rpc_docuseal_marcar_enviado — grava o id da submission recém-criada
-- ============================================================
-- Chamada pela Edge Function docuseal-integrar, repassando o JWT dela (ação
-- disparada por ela, na tela) — mesmo desenho de wa-send/reuniao-analisar.
-- Só AVANÇA o status (rascunho/emitido → enviado), nunca rebaixa — mesma
-- lição do bug real do checkbox "marcar assinado" (D2, 24/09).
create or replace function hub.rpc_docuseal_marcar_enviado(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_id uuid;
  v_contrato_id uuid;
  v_submission_id bigint;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_contrato_id := (p->>'contrato_id')::uuid;
  v_submission_id := (p->>'docuseal_submission_id')::bigint;
  if v_contrato_id is null or v_submission_id is null then
    raise exception 'contrato_id e docuseal_submission_id são obrigatórios';
  end if;

  update hub.contratos
  set docuseal_submission_id = v_submission_id,
      status = case when status in ('rascunho','emitido') then 'enviado' else status end
  where id = v_contrato_id
  returning id into v_id;

  if v_id is null then raise exception 'contrato não encontrado'; end if;
  return v_id;
end;
$$;

revoke all on function hub.rpc_docuseal_marcar_enviado(jsonb) from public, anon;
grant execute on function hub.rpc_docuseal_marcar_enviado(jsonb) to authenticated;

create or replace function public.hub_rpc_docuseal_marcar_enviado(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_docuseal_marcar_enviado(p); $$;

revoke all on function public.hub_rpc_docuseal_marcar_enviado(jsonb) from public, anon;
grant execute on function public.hub_rpc_docuseal_marcar_enviado(jsonb) to authenticated;


-- ============================================================
-- 3) hub.rpc_docuseal_registrar_evento — o webhook grava aqui
-- ============================================================
-- Quem chama é a Edge Function docuseal-webhook, SEM sessão dela (é o
-- próprio servidor do DocuSeal batendo, autenticado por HMAC — ver a Edge
-- Function). Ela usa a SUPABASE_SERVICE_ROLE_KEY (injetada automaticamente
-- pelo runtime de Edge Functions), e hub.is_ingestor() já cobre esse caso
-- (auth.role() = 'service_role' — 013_conversas.sql). Mesma porta que a
-- ponte do Meetily usa, adaptada pro caso "não é anon, é service_role
-- direto" (o DocuSeal roda como serviço interno da VPS, não como um script
-- que ela dispara na mão).
--
-- Devolve jsonb (não só o id) porque o webhook precisa do cliente_slug pra
-- montar o caminho <cliente_slug>/<contrato_id>.pdf do bucket `contratos`
-- (026) quando for guardar o PDF final — sem isso teria que fazer uma
-- segunda ida ao banco só pra descobrir o slug.
create or replace function hub.rpc_docuseal_registrar_evento(p jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_contrato hub.contratos;
  v_cliente_slug text;
  v_submission_id bigint;
  v_status text;
  v_audit_url text;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_submission_id := (p->>'docuseal_submission_id')::bigint;
  v_status := nullif(btrim(coalesce(p->>'status', '')), '');
  v_audit_url := nullif(btrim(coalesce(p->>'audit_log_url', '')), '');
  if v_submission_id is null then raise exception 'docuseal_submission_id é obrigatório'; end if;
  -- só aceita o estado que este evento pode legitimamente produzir — nunca
  -- um status arbitrário vindo de fora (mesmo espírito do hub_status_contrato
  -- ser genérico só pra chamada DELA; aqui, vindo de fora, é fechado).
  if v_status is distinct from 'assinado' then
    raise exception 'status inválido pro webhook do DocuSeal: %', v_status;
  end if;

  update hub.contratos
  set status = v_status,
      docuseal_audit_log_url = coalesce(v_audit_url, docuseal_audit_log_url)
  where docuseal_submission_id = v_submission_id
  returning * into v_contrato;

  if v_contrato.id is null then
    raise exception 'nenhum contrato com docuseal_submission_id = %', v_submission_id;
  end if;

  select cl.slug into v_cliente_slug from hub.clientes cl where cl.id = v_contrato.cliente_id;

  return jsonb_build_object('contrato_id', v_contrato.id, 'cliente_slug', v_cliente_slug);
end;
$$;

revoke all on function hub.rpc_docuseal_registrar_evento(jsonb) from public, anon;
grant execute on function hub.rpc_docuseal_registrar_evento(jsonb) to authenticated, service_role;

-- ⚠️ SECURITY DEFINER no wrapper público, de propósito — é o SEGUNDO desta
-- exceção no projeto (a primeira é hub_rpc_registrar_reuniao, 027). Mesmo
-- motivo: quem chama não é `authenticated`, é `service_role`/anon batendo
-- de fora, e um wrapper `invoker` dependeria do caller já ter `usage` no
-- schema hub — não dá pra assumir isso sem checar antes de aplicar.
create or replace function public.hub_rpc_docuseal_registrar_evento(p jsonb)
returns jsonb
language sql security definer set search_path = pg_catalog
as $$ select hub.rpc_docuseal_registrar_evento(p); $$;

revoke all on function public.hub_rpc_docuseal_registrar_evento(jsonb) from public, anon;
grant execute on function public.hub_rpc_docuseal_registrar_evento(jsonb) to authenticated, service_role;


-- ============================================================
-- 4) hub.rpc_arquivo_contrato_ingestor — guarda o PDF final no bucket
-- ============================================================
-- Mesmíssima ação de hub.rpc_arquivo_contrato (025), só que gated por
-- hub.is_ingestor() em vez de hub.is_admin() — NÃO edito a 025 (já aplicada
-- e em uso real desde o D2) pra não mexer em migration que já rodou em
-- produção. Upload em si (bytes pro Storage) é feito pela Edge Function
-- com a service_role key direto na API do Storage — RLS não se aplica a
-- service_role, então não precisa de policy nova em storage.objects.
create or replace function hub.rpc_arquivo_contrato_ingestor(p jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  update hub.contratos set
    arquivo_path = p->>'arquivo_path',
    arquivo_nome = p->>'arquivo_nome',
    arquivo_tipo = p->>'arquivo_tipo',
    arquivo_em   = case when p->>'arquivo_path' is null then null else now() end
  where id = (p->>'contrato_id')::uuid;

  if not found then raise exception 'contrato não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_arquivo_contrato_ingestor(jsonb) from public, anon;
grant execute on function hub.rpc_arquivo_contrato_ingestor(jsonb) to service_role;

create or replace function public.hub_rpc_arquivo_contrato_ingestor(p jsonb)
returns void
language sql security definer set search_path = pg_catalog
as $$ select hub.rpc_arquivo_contrato_ingestor(p); $$;

revoke all on function public.hub_rpc_arquivo_contrato_ingestor(jsonb) from public, anon;
grant execute on function public.hub_rpc_arquivo_contrato_ingestor(jsonb) to service_role;


-- ============================================================
-- 5) hub.rpc_contratos() ganha docuseal_submission_id — pra tela decidir
--    se mostra "Assinar por e-mail" ou "Aguardando assinatura"
-- ============================================================
-- `drop` antes de `create` porque adicionar coluna no `returns table` muda a
-- assinatura (mesmo padrão já usado na 021 pra hub_rpc_carteira).
drop function if exists public.hub_rpc_contratos();
drop function if exists hub.rpc_contratos();

create function hub.rpc_contratos()
returns table (
  contrato_id uuid, numero text, status text,
  cliente_id uuid, cliente_nome text, cliente_slug text,
  servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  inicio_em date, fim_minimo_em date,
  porta_saida_tipo text, porta_saida_escrita_em timestamptz,
  tem_arquivo boolean, arquivo_path text, arquivo_nome text, arquivo_em timestamptz,
  docuseal_submission_id bigint,
  observacao text, created_at timestamptz, updated_at timestamptz
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select
    co.id, co.numero, co.status,
    cl.id, cl.nome, cl.slug,
    coalesce(
      (select string_agg(distinct ci.descricao, ' + ') from hub.contrato_itens ci where ci.contrato_id = co.id),
      null
    ) as servico,
    co.valor_mensal_centavos, co.dia_vencimento,
    co.inicio_em, co.fim_minimo_em,
    co.porta_saida_tipo, co.porta_saida_escrita_em,
    (co.arquivo_path is not null) as tem_arquivo,
    co.arquivo_path, co.arquivo_nome, co.arquivo_em,
    co.docuseal_submission_id,
    co.observacao, co.created_at, co.updated_at
  from hub.contratos co
  join hub.clientes cl on cl.id = co.cliente_id
  order by
    case co.status
      when 'ativo'     then 0
      when 'assinado'  then 1
      when 'enviado'   then 2
      when 'emitido'   then 3
      when 'rascunho'  then 4
      when 'encerrado' then 5
      else 6
    end,
    co.created_at desc;
end;
$$;

revoke all on function hub.rpc_contratos() from public, anon;
grant execute on function hub.rpc_contratos() to authenticated;

create function public.hub_rpc_contratos()
returns table (
  contrato_id uuid, numero text, status text,
  cliente_id uuid, cliente_nome text, cliente_slug text,
  servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  inicio_em date, fim_minimo_em date,
  porta_saida_tipo text, porta_saida_escrita_em timestamptz,
  tem_arquivo boolean, arquivo_path text, arquivo_nome text, arquivo_em timestamptz,
  docuseal_submission_id bigint,
  observacao text, created_at timestamptz, updated_at timestamptz
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_contratos(); $$;

revoke all on function public.hub_rpc_contratos() from public, anon;
grant execute on function public.hub_rpc_contratos() to authenticated;


-- Conferência depois de aplicar:
--   select has_schema_privilege('service_role','hub','usage');
--   select proname, prosecdef from pg_proc
--    where pronamespace = 'hub'::regnamespace and proname like 'rpc_docuseal%' or proname like '%ingestor';
--   select docuseal_submission_id, docuseal_audit_log_url from hub.contratos limit 1; -- deve rodar sem erro
