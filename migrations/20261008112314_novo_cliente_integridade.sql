-- Revisão de 08/10: aplicar APÓS 041. Mantém migrations anteriores intactas.
-- Serializa slug e troca de contato principal; recusa cliente divergente.
begin;
create or replace function hub.rpc_novo_cliente(p jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_ws uuid := hub.default_workspace_id();   -- ← vira current_workspace_id() no multi-empresa
  v_id uuid;
  v_prospect_id uuid := nullif(p->>'prospect_id','')::uuid;
  v_prospect hub.prospects;
  v_nome text := nullif(btrim(coalesce(p->>'nome','')), '');
  v_slug_base text := nullif(btrim(lower(coalesce(p->>'slug',''))), '');
  v_slug text;
  v_n int := 1;
  v_recorrente boolean := coalesce((p->>'recorrente')::boolean, true);
  v_tipo text := coalesce(nullif(p->>'tipo_cobranca',''), 'fixo');
  v_pct numeric := nullif(p->>'percentual_comissao','')::numeric;
  v_valor bigint := nullif(p->>'valor_mensal_centavos','')::bigint;
  v_parcelas smallint := nullif(p->>'parcelas_total','')::smallint;
  v_dia smallint := nullif(p->>'dia_vencimento','')::smallint;
  v_inicio date := nullif(p->>'inicio_em','')::date;
  v_porta text := nullif(p->>'porta_saida_tipo','');
  v_porta_valor bigint := nullif(p->>'porta_saida_valor_centavos','')::bigint;
  v_contrato_id uuid;
  v_hoje date := (now() at time zone 'America/Recife')::date;
  v_serv jsonb;
  v_servico hub.servicos;
  v_qtd_serv int;
  v_ct jsonb;
  v_qtd_ct int;
  v_tem_principal boolean;
  v_primeiro boolean := true;
  v_principal boolean;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_id := nullif(p->>'id','')::uuid;
  if v_id is null then raise exception 'hub_novo_cliente_sem_id'; end if;

  -- Idempotência: serializa chamadas com o MESMO id e, se a 1ª já criou,
  -- devolve o resultado dela. Duplo clique / retry nunca duplica nada.
  perform pg_advisory_xact_lock(hashtextextended('hub.novo_cliente:' || v_id::text, 0));
  if exists (select 1 from hub.clientes where id = v_id) then
    return (
      select jsonb_build_object(
        'cliente_id', c.id, 'slug', c.slug, 'ja_existia', true,
        'contrato_id', (select ct.id from hub.contratos ct where ct.cliente_id = c.id order by ct.created_at limit 1),
        'prospect_id', (select pr.id from hub.prospects pr where pr.cliente_id = c.id order by pr.created_at limit 1))
      from hub.clientes c where c.id = v_id);
  end if;

  -- ---------- validação (tudo antes de gravar qualquer linha) ----------
  if v_nome is null then raise exception 'hub_novo_cliente_sem_nome'; end if;
  if v_slug_base is null or v_slug_base !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'hub_novo_cliente_slug_invalido';
  end if;
  if v_tipo not in ('fixo','percentual','misto') then
    raise exception 'hub_novo_cliente_tipo_cobranca_invalido';
  end if;
  if v_tipo in ('percentual','misto') and (v_pct is null or v_pct <= 0 or v_pct > 100) then
    raise exception 'hub_novo_cliente_sem_percentual';
  end if;
  if v_tipo = 'fixo' then v_pct := null; end if;
  -- R$ 0 = "sem cobrança" (044): no percentual puro vira "sem valor mensal"
  if v_tipo = 'percentual' and v_valor = 0 then v_valor := null; end if;
  if v_tipo in ('fixo','misto') and (v_valor is null or v_valor <= 0) then
    raise exception 'hub_novo_cliente_sem_valor';
  end if;
  if v_valor is not null and v_valor <= 0 then raise exception 'hub_novo_cliente_sem_valor'; end if;
  if v_parcelas is not null and v_parcelas < 1 then raise exception 'hub_novo_cliente_parcelas_invalidas'; end if;
  if not v_recorrente and v_valor is not null and v_parcelas is null then
    -- pontual com valor tem fim: sem nº de parcelas viraria mensalidade infinita
    raise exception 'hub_novo_cliente_pontual_sem_parcelas';
  end if;
  if v_valor is not null and (v_dia is null or v_dia not between 1 and 28) then
    raise exception 'hub_novo_cliente_sem_vencimento';
  end if;
  if v_valor is not null and v_inicio is null then
    raise exception 'hub_novo_cliente_sem_inicio';
  end if;
  if v_porta is null or v_porta not in ('manutencao_mensal','desligamento_build_30') then
    raise exception 'hub_novo_cliente_sem_porta_saida';
  end if;

  v_qtd_serv := jsonb_array_length(coalesce(p->'servicos', '[]'::jsonb));
  if v_qtd_serv = 0 then raise exception 'hub_novo_cliente_sem_servico'; end if;

  v_qtd_ct := jsonb_array_length(coalesce(p->'contatos', '[]'::jsonb));
  if v_qtd_ct = 0 then raise exception 'hub_novo_cliente_sem_contato'; end if;
  if exists (select 1 from jsonb_array_elements(p->'contatos') c
             where nullif(btrim(coalesce(c->>'nome','')), '') is null) then
    raise exception 'hub_novo_cliente_contato_sem_nome';
  end if;
  if (select count(*) from jsonb_array_elements(p->'contatos') c
      where coalesce((c->>'is_principal')::boolean, false)) > 1 then
    raise exception 'hub_novo_cliente_dois_principais';
  end if;
  v_tem_principal := exists (select 1 from jsonb_array_elements(p->'contatos') c
                             where coalesce((c->>'is_principal')::boolean, false));

  if v_prospect_id is not null then
    select * into v_prospect from hub.prospects where id = v_prospect_id for update;
    if not found then raise exception 'hub_novo_cliente_prospect_nao_encontrado'; end if;
    if v_prospect.cliente_id is not null then
      raise exception 'hub_novo_cliente_prospect_ja_e_cliente';
    end if;
  end if;

  -- IDs diferentes com o mesmo slug também precisam serializar.
  perform pg_advisory_xact_lock(hashtextextended('hub.novo_cliente.slug:' || v_ws::text || ':' || v_slug_base, 0));
  -- slug livre: nome-2, nome-3... (slug é UNIQUE global hoje)
  v_slug := v_slug_base;
  while exists (select 1 from hub.clientes where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_slug_base || '-' || v_n;
  end loop;

  -- ---------- gravação ----------
  insert into hub.clientes (id, workspace_id, empresa_id, slug, nome, segmento, origem, status,
                            entrou_em, recorrente, tipo_cobranca, percentual_comissao, observacao)
  values (v_id, v_ws, hub.default_empresa_id(), v_slug, v_nome,
          nullif(btrim(coalesce(p->>'segmento','')), ''),
          coalesce(nullif(btrim(coalesce(p->>'origem','')), ''), v_prospect.origem),
          'ativo', coalesce(v_inicio, v_hoje), v_recorrente, v_tipo, v_pct,
          nullif(btrim(coalesce(p->>'observacao','')), ''));

  insert into hub.contratos (workspace_id, cliente_id, status, inicio_em, dia_vencimento,
                             valor_mensal_centavos, parcelas_total, recorrencia_ativa,
                             porta_saida_tipo, porta_saida_valor_centavos)
  values (v_ws, v_id, 'rascunho', v_inicio, v_dia, v_valor, v_parcelas, true,
          v_porta, v_porta_valor)
  returning id into v_contrato_id;

  for v_serv in select * from jsonb_array_elements(p->'servicos') loop
    select * into v_servico from hub.servicos
    where id = nullif(v_serv->>'servico_id','')::uuid and ativo;
    if not found then raise exception 'hub_novo_cliente_servico_invalido'; end if;
    insert into hub.contrato_itens (workspace_id, contrato_id, servico_id, descricao, valor_centavos, recorrencia)
    values (v_ws, v_contrato_id, v_servico.id, v_servico.nome,
            coalesce(nullif(v_serv->>'valor_centavos','')::bigint,
                     case when v_qtd_serv = 1 then v_valor end),
            case when v_recorrente then 'mensal' else 'pontual' end);
  end loop;

  for v_ct in select * from jsonb_array_elements(p->'contatos') loop
    v_principal := coalesce((v_ct->>'is_principal')::boolean, false)
                   or (not v_tem_principal and v_primeiro);
    insert into hub.contatos (workspace_id, cliente_id, nome, papel, papeis, email, whatsapp_e164, eh_grupo, is_principal)
    values (v_ws, v_id, btrim(v_ct->>'nome'),
            nullif(btrim(coalesce(v_ct->>'papel','')), ''),
            coalesce((select array_agg(distinct x order by x)
                      from jsonb_array_elements_text(coalesce(v_ct->'papeis','[]'::jsonb)) x), '{}'),
            nullif(btrim(coalesce(v_ct->>'email','')), ''),
            nullif(btrim(coalesce(v_ct->>'whatsapp_e164','')), ''),
            coalesce((v_ct->>'eh_grupo')::boolean, false),
            v_principal);
    v_primeiro := false;
  end loop;

  -- card do CRM em "Cliente aberto" (coluna 5), ligado ao cliente
  if v_prospect_id is not null then
    update hub.prospects
       set coluna = 5, fechado_em = v_hoje, perdido = false, motivo_perda = null,
           cliente_id = v_id
     where id = v_prospect_id;
  else
    insert into hub.prospects (workspace_id, nome, origem, coluna, valor_estimado_centavos,
                               entrou_em, fechado_em, cliente_id)
    values (v_ws, v_nome, coalesce(nullif(btrim(coalesce(p->>'origem','')), ''), 'Carteira'),
            5, v_valor, v_hoje, v_hoje, v_id)
    returning id into v_prospect_id;
  end if;

  return jsonb_build_object('cliente_id', v_id, 'slug', v_slug, 'contrato_id', v_contrato_id,
                            'prospect_id', v_prospect_id, 'ja_existia', false);
end;
$$;


create or replace function hub.rpc_salvar_contato(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
        v_cliente uuid := (p->>'cliente_id')::uuid;
        v_principal boolean := coalesce((p->>'is_principal')::boolean, false);
        v_papeis text[];
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  -- A identidade do cliente vem do banco antes de desmarcar outro principal.
  if exists (select 1 from hub.contatos where id = nullif(p->>'id','')::uuid and cliente_id <> v_cliente) then
    raise exception 'hub_contato_cliente_divergente';
  end if;
  perform 1 from hub.clientes where id = v_cliente for update;
  if not found then raise exception 'cliente não encontrado'; end if;

  if p ? 'papeis' then
    select coalesce(array_agg(distinct x order by x), '{}') into v_papeis
    from jsonb_array_elements_text(coalesce(p->'papeis', '[]'::jsonb)) x;
  end if;

  v_id := coalesce((p->>'id')::uuid, gen_random_uuid());

  if v_principal then
    update hub.contatos set is_principal = false
    where cliente_id = v_cliente and is_principal and id <> v_id;
  end if;

  insert into hub.contatos (id, cliente_id, nome, papel, email, whatsapp_e164, is_principal, eh_grupo, papeis)
  values (
    v_id, v_cliente, p->>'nome',
    p->>'papel', p->>'email', p->>'whatsapp_e164', v_principal,
    coalesce((p->>'eh_grupo')::boolean, false), coalesce(v_papeis, '{}')
  )
  on conflict (id) do update set
    nome=excluded.nome, papel=excluded.papel, email=excluded.email,
    whatsapp_e164=excluded.whatsapp_e164, is_principal=excluded.is_principal,
    eh_grupo=excluded.eh_grupo,
    papeis=case when p ? 'papeis' then excluded.papeis else hub.contatos.papeis end
  returning id into v_id;

  return v_id;
end;
$$;

notify pgrst, 'reload schema';
commit;
