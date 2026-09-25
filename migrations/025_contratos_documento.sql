-- ============================================================
-- HUB LUH PANDA — 025: Contratos (D2, itens 6 e 7 do plano)
--
-- 🔑 MUDANÇA DE DESENHO em relação ao plano escrito: o PDF do contrato sai
-- SEM IA. A Edge Function `contrato-gerar` com Gemini está CANCELADA.
-- O MODELO-BASE.md é um molde mecânico e quase toda lacuna já está no banco;
-- as duas que faltavam entram aqui (endereço do cliente, anexo do serviço),
-- `{{valor_extenso}}` é calculado em JS e `{{cidade}}`/`{{data_assinatura}}`
-- são fixos. Zero chamada de IA, zero risco de cláusula inventada, custo zero.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (separação de papéis: quem coda não
-- aplica). Aplicar com `apply_migration` e rodar `get_advisors` depois.
--
-- ⚠️ O BUCKET NÃO ESTÁ AQUI — está na 026, de propósito. Criar policy em
-- `storage.objects` pode esbarrar em permissão dependendo do papel que o
-- `apply_migration` usa, e migration é transacional: se a policy falhasse
-- aqui, TODO este arquivo (colunas + RPCs) rolaria pra trás junto. Separado,
-- o schema entra de qualquer jeito e só o bucket precisaria do painel.
-- ============================================================


-- ============================================================
-- 1) colunas novas
-- ============================================================

alter table hub.clientes  add column if not exists endereco text;
alter table hub.servicos  add column if not exists anexo_escopo text;

alter table hub.contratos add column if not exists arquivo_path text;
alter table hub.contratos add column if not exists arquivo_nome text;
alter table hub.contratos add column if not exists arquivo_tipo text;
alter table hub.contratos add column if not exists arquivo_em   timestamptz;

comment on column hub.clientes.endereco is
  'Endereço completo numa linha, com cidade/UF — vira {{cliente_endereco}} na cláusula 1 do MODELO-BASE.';
comment on column hub.servicos.anexo_escopo is
  'Texto do Anexo I deste serviço (Inclui / Não inclui / Responsabilidades / Resultados) — vira {{anexo_servico}}. Escrito e revisado por ela; o Hub só propõe um rascunho a partir do `inclui` na primeira vez.';
comment on column hub.contratos.arquivo_path is
  'Caminho no bucket privado `contratos` (<cliente_slug>/<contrato_id>.pdf). Leitura SEMPRE por createSignedUrl de curta duração — nunca URL pública.';


-- ============================================================
-- 2) hub.rpc_contratos() — lista de todos os contratos, todos os clientes
-- ============================================================
--
-- Mesma ordem de relevância de status da 021, e `created_at desc` dentro do
-- mesmo status. `updated_at` vai junto porque a tela usa ele pra "esperando
-- devolução" — ver a ressalva no relatório: updated_at é "sem movimento
-- desde", não "enviado em".

create or replace function hub.rpc_contratos()
returns table (
  contrato_id uuid, numero text, status text,
  cliente_id uuid, cliente_nome text, cliente_slug text,
  servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  inicio_em date, fim_minimo_em date,
  porta_saida_tipo text, porta_saida_escrita_em timestamptz,
  tem_arquivo boolean, arquivo_path text, arquivo_nome text, arquivo_em timestamptz,
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

create or replace function public.hub_rpc_contratos()
returns table (
  contrato_id uuid, numero text, status text,
  cliente_id uuid, cliente_nome text, cliente_slug text,
  servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  inicio_em date, fim_minimo_em date,
  porta_saida_tipo text, porta_saida_escrita_em timestamptz,
  tem_arquivo boolean, arquivo_path text, arquivo_nome text, arquivo_em timestamptz,
  observacao text, created_at timestamptz, updated_at timestamptz
)
language sql stable security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_contratos(); $$;

revoke all on function public.hub_rpc_contratos() from public, anon;
grant execute on function public.hub_rpc_contratos() to authenticated;


-- ============================================================
-- 3) hub.rpc_arquivo_contrato — grava SÓ os 4 campos do arquivo
-- ============================================================
--
-- Não estava na lista, mas é necessário: depois do upload pro Storage o front
-- precisa registrar path/nome/tipo/em no contrato. Passar isso por
-- rpc_salvar_contrato obrigaria a remontar o objeto inteiro (upsert
-- destrutivo) só pra anexar um PDF — exatamente o tipo de caminho que já
-- apagou dado neste repo. Esta faz UPDATE de 4 colunas e mais nada.
-- Passar `arquivo_path` null = desanexar (o objeto no bucket é apagado pelo
-- front antes de chamar).

create or replace function hub.rpc_arquivo_contrato(p jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.contratos set
    arquivo_path = p->>'arquivo_path',
    arquivo_nome = p->>'arquivo_nome',
    arquivo_tipo = p->>'arquivo_tipo',
    arquivo_em   = case when p->>'arquivo_path' is null then null else now() end
  where id = (p->>'contrato_id')::uuid;

  if not found then raise exception 'contrato não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_arquivo_contrato(jsonb) from public, anon;
grant execute on function hub.rpc_arquivo_contrato(jsonb) to authenticated;

create or replace function public.hub_rpc_arquivo_contrato(p jsonb)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_arquivo_contrato(p); $$;

revoke all on function public.hub_rpc_arquivo_contrato(jsonb) from public, anon;
grant execute on function public.hub_rpc_arquivo_contrato(jsonb) to authenticated;


-- ============================================================
-- 4) hub.rpc_status_contrato — mover o estado da assinatura
-- ============================================================
--
-- Mesmo motivo da anterior: "Enviar pro cliente" e "Marcar assinado" mexem em
-- UMA coluna. Não vale remontar o contrato inteiro pra isso.
-- O CHECK hub_contrato_ativo_exige_porta_saida (021) continua valendo — mover
-- pra 'ativo' por aqui sem porta de saída é recusado pelo banco, como deve.

create or replace function hub.rpc_status_contrato(p jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_status text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_status := p->>'status';
  if v_status is null or v_status not in ('rascunho','emitido','enviado','assinado','ativo','encerrado') then
    raise exception 'hub_status_contrato_invalido: %', coalesce(v_status, '(vazio)');
  end if;

  update hub.contratos set status = v_status
  where id = (p->>'contrato_id')::uuid;

  if not found then raise exception 'contrato não encontrado'; end if;
end;
$$;

revoke all on function hub.rpc_status_contrato(jsonb) from public, anon;
grant execute on function hub.rpc_status_contrato(jsonb) to authenticated;

create or replace function public.hub_rpc_status_contrato(p jsonb)
returns void
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_status_contrato(p); $$;

revoke all on function public.hub_rpc_status_contrato(jsonb) from public, anon;
grant execute on function public.hub_rpc_status_contrato(jsonb) to authenticated;


-- ============================================================
-- 5) passthrough das colunas novas nos upserts destrutivos
-- ============================================================
--
-- Terceira vez que essa armadilha aparece (021 contrato, 023 recorrente,
-- agora endereco/anexo_escopo). Mesma dupla proteção da 023: o front manda o
-- campo, E o UPDATE preserva o valor atual quando a chave não vem no payload.

-- ---------- hub.rpc_salvar_cliente (+ endereco) ----------
-- ⚠️ versão completa: mantém `recorrente` da 023 exatamente como está.
create or replace function hub.rpc_salvar_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.clientes (id, empresa_id, slug, nome, razao_social, documento, segmento, origem, status, entrou_em, saiu_em, motivo_saida, observacao, recorrente, endereco)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'empresa_id')::uuid, p->>'slug', p->>'nome',
    p->>'razao_social', p->>'documento', p->>'segmento', p->>'origem',
    coalesce(p->>'status','ativo'), (p->>'entrou_em')::date, (p->>'saiu_em')::date, p->>'motivo_saida', p->>'observacao',
    coalesce((p->>'recorrente')::boolean, true),
    p->>'endereco'
  )
  on conflict (id) do update set
    empresa_id=excluded.empresa_id, slug=excluded.slug, nome=excluded.nome, razao_social=excluded.razao_social,
    documento=excluded.documento, segmento=excluded.segmento, origem=excluded.origem, status=excluded.status,
    entrou_em=excluded.entrou_em, saiu_em=excluded.saiu_em, motivo_saida=excluded.motivo_saida, observacao=excluded.observacao,
    recorrente=coalesce((p->>'recorrente')::boolean, hub.clientes.recorrente),
    endereco=case when p ? 'endereco' then p->>'endereco' else hub.clientes.endereco end
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_cliente(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_cliente(jsonb) to authenticated;

-- ---------- hub.rpc_salvar_servico (+ anexo_escopo) ----------
create or replace function hub.rpc_salvar_servico(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.servicos (id, slug, nome, modalidade, preco_referencia_centavos, unidade, inclui, observacao, ativo, anexo_escopo)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), p->>'slug', p->>'nome', p->>'modalidade',
    (p->>'preco_referencia_centavos')::bigint, p->>'unidade', p->>'inclui', p->>'observacao',
    coalesce((p->>'ativo')::boolean, true),
    p->>'anexo_escopo'
  )
  on conflict (id) do update set
    slug=excluded.slug, nome=excluded.nome, modalidade=excluded.modalidade,
    preco_referencia_centavos=excluded.preco_referencia_centavos, unidade=excluded.unidade,
    inclui=excluded.inclui, observacao=excluded.observacao, ativo=excluded.ativo,
    anexo_escopo=case when p ? 'anexo_escopo' then p->>'anexo_escopo' else hub.servicos.anexo_escopo end
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_servico(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_servico(jsonb) to authenticated;

-- hub.rpc_cliente devolve to_jsonb(cliente) e to_jsonb(contrato), e
-- hub.rpc_catalogo devolve `setof hub.servicos` — as colunas novas aparecem
-- nos três de graça, sem precisar recriar nada. Conferido na 003.

-- Conferência depois de aplicar:
--   select count(*) from hub.rpc_contratos();        -- 8 hoje
--   select nome, endereco from hub.clientes order by nome;
--   select nome, anexo_escopo is not null from hub.servicos order by nome;
