-- ============================================================
-- HUB LUH PANDA — 003: RPCs (security definer, dentro do schema hub)
-- Nenhuma tabela é exposta direto ao PostgREST — tudo passa por aqui.
-- ============================================================

create or replace function hub.rpc_carteira()
returns table (
  cliente_id uuid, slug text, nome text, status text, servico text,
  valor_mensal_centavos bigint, dia_vencimento smallint,
  contrato_status text, tem_contrato boolean, tem_vencimento boolean
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select
    c.id, c.slug, c.nome, c.status,
    coalesce(
      (select string_agg(distinct ci.descricao, ' + ') from hub.contrato_itens ci where ci.contrato_id = ct.id),
      ct.observacao
    ) as servico,
    ct.valor_mensal_centavos, ct.dia_vencimento, ct.status,
    -- "formal" = contrato assinado ou ativo, não basta existir a linha
    coalesce(ct.status in ('assinado','ativo'), false) as tem_contrato,
    (ct.dia_vencimento is not null) as tem_vencimento
  from hub.clientes c
  left join lateral (
    select * from hub.contratos x where x.cliente_id = c.id order by x.created_at desc limit 1
  ) ct on true
  order by c.nome;
end;
$$;

create or replace function hub.rpc_catalogo()
returns setof hub.servicos
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query select * from hub.servicos order by nome;
end;
$$;

create or replace function hub.rpc_cliente(p_slug text)
returns jsonb
language plpgsql stable security definer set search_path = pg_catalog
as $$
declare
  v_cliente hub.clientes;
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select * into v_cliente from hub.clientes where slug = p_slug;
  if not found then return null; end if;

  select jsonb_build_object(
    'cliente', to_jsonb(v_cliente),
    'contatos', coalesce((select jsonb_agg(to_jsonb(ct)) from hub.contatos ct where ct.cliente_id = v_cliente.id), '[]'::jsonb),
    'contratos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'contrato', to_jsonb(co),
        'itens', coalesce((select jsonb_agg(to_jsonb(it)) from hub.contrato_itens it where it.contrato_id = co.id), '[]'::jsonb)
      ))
      from hub.contratos co where co.cliente_id = v_cliente.id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function hub.rpc_salvar_cliente(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.clientes (id, empresa_id, slug, nome, razao_social, documento, segmento, origem, status, entrou_em, saiu_em, motivo_saida, observacao)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'empresa_id')::uuid, p->>'slug', p->>'nome',
    p->>'razao_social', p->>'documento', p->>'segmento', p->>'origem',
    coalesce(p->>'status','ativo'), (p->>'entrou_em')::date, (p->>'saiu_em')::date, p->>'motivo_saida', p->>'observacao'
  )
  on conflict (id) do update set
    empresa_id=excluded.empresa_id, slug=excluded.slug, nome=excluded.nome, razao_social=excluded.razao_social,
    documento=excluded.documento, segmento=excluded.segmento, origem=excluded.origem, status=excluded.status,
    entrou_em=excluded.entrou_em, saiu_em=excluded.saiu_em, motivo_saida=excluded.motivo_saida, observacao=excluded.observacao
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function hub.rpc_salvar_contrato(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.contratos (id, cliente_id, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_valor_centavos, porta_saida_escrita_em, observacao)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, p->>'numero',
    coalesce(p->>'status','rascunho'), (p->>'inicio_em')::date, (p->>'fim_minimo_em')::date,
    (p->>'dia_vencimento')::smallint, (p->>'valor_mensal_centavos')::bigint, p->>'porta_saida_tipo',
    (p->>'porta_saida_valor_centavos')::bigint, (p->>'porta_saida_escrita_em')::timestamptz, p->>'observacao'
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, numero=excluded.numero, status=excluded.status, inicio_em=excluded.inicio_em,
    fim_minimo_em=excluded.fim_minimo_em, dia_vencimento=excluded.dia_vencimento, valor_mensal_centavos=excluded.valor_mensal_centavos,
    porta_saida_tipo=excluded.porta_saida_tipo, porta_saida_valor_centavos=excluded.porta_saida_valor_centavos,
    porta_saida_escrita_em=excluded.porta_saida_escrita_em, observacao=excluded.observacao
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function hub.rpc_salvar_servico(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.servicos (id, slug, nome, modalidade, preco_referencia_centavos, unidade, inclui, observacao, ativo)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), p->>'slug', p->>'nome', p->>'modalidade',
    (p->>'preco_referencia_centavos')::bigint, p->>'unidade', p->>'inclui', p->>'observacao',
    coalesce((p->>'ativo')::boolean, true)
  )
  on conflict (id) do update set
    slug=excluded.slug, nome=excluded.nome, modalidade=excluded.modalidade,
    preco_referencia_centavos=excluded.preco_referencia_centavos, unidade=excluded.unidade,
    inclui=excluded.inclui, observacao=excluded.observacao, ativo=excluded.ativo
  returning id into v_id;

  return v_id;
end;
$$;

-- grants: só authenticated executa; anon nunca
revoke all on function hub.rpc_carteira() from public, anon;
revoke all on function hub.rpc_catalogo() from public, anon;
revoke all on function hub.rpc_cliente(text) from public, anon;
revoke all on function hub.rpc_salvar_cliente(jsonb) from public, anon;
revoke all on function hub.rpc_salvar_contrato(jsonb) from public, anon;
revoke all on function hub.rpc_salvar_servico(jsonb) from public, anon;

grant execute on function hub.rpc_carteira() to authenticated;
grant execute on function hub.rpc_catalogo() to authenticated;
grant execute on function hub.rpc_cliente(text) to authenticated;
grant execute on function hub.rpc_salvar_cliente(jsonb) to authenticated;
grant execute on function hub.rpc_salvar_contrato(jsonb) to authenticated;
grant execute on function hub.rpc_salvar_servico(jsonb) to authenticated;
