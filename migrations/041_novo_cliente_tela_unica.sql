-- =====================================================================
-- 041 — TELA ÚNICA "NOVO CLIENTE" + BOTÃO "CONTRATO ASSINADO"
--       + CONTATO COM PAPEL (fonte única) + "FECHOU → VIRAR CLIENTE"
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz (HUB Luh Panda) · Data: 07/10/2026
-- Depende de: 038 (competência sempre dia 1 — o CHECK dela vale aqui).
-- Desenho: vault, "Hub — decisões do grill (07-10-2026)", seção A.
--
-- O QUE MUDA
--   1. Colunas novas (todas aditivas, nada é renomeado nem apagado):
--      • hub.prospects.cliente_id  → o card do CRM fica LIGADO ao cliente.
--      • hub.contatos.papeis text[] → financeiro / decisor / operacional.
--        A coluna antiga `papel` (texto livre: "Dono", "responsável") fica
--        como rótulo/cargo. `papeis` é o que o sistema usa pra rotear.
--      • hub.contratos.assinado_em → a data que ela informa no botão.
--      • hub.clientes.tipo_cobranca aceita 'misto' (fixo + % sobre vendas).
--        Bloco G travou "fixo OU porcentagem"; o grill de 07/10 pediu
--        "comissão/percentual ALÉM do fixo" (caso real: The Best, 6×1.200 +
--        5%). Continua sem motor de cálculo: o % segue sendo registro.
--   2. hub.rpc_novo_cliente(p) — UMA transação: cliente + contrato
--      RASCUNHO + contrato_itens (serviços do catálogo) + contatos + card
--      do CRM em "Cliente aberto" (coluna 5) ligado ao cliente.
--      NENHUM recebível nasce aqui. Idempotente: o front gera o id do
--      cliente quando abre a tela; a 2ª chamada com o mesmo id (duplo
--      clique, retry de rede) devolve o que a 1ª criou, sem duplicar.
--   3. hub.ativar_contrato_assinado(...) — FUNÇÃO ÚNICA de "assinou":
--      ativa o contrato e gera TODAS as parcelas (vencimento + "parcela
--      n/N"). Interna: ninguém de fora executa direto. Hoje quem chama é
--      hub.rpc_contrato_assinado (botão manual, só admin). O webhook do
--      DocuSeal, quando entrar (PR separado), chama esta mesma função.
--   4. Contato: uma fonte só (hub.contatos). Quem lê passa a respeitar o
--      papel, sem mudar nada pra quem não tem papel marcado (todos os
--      contatos de hoje): cobrança → financeiro, senão principal; CRM →
--      card ligado a cliente mostra o contato principal DO CLIENTE (a cópia
--      que mora em hub.prospects deixa de ser lida e de ser sobrescrita).
--      Contato principal passa a ser ÚNICO por cliente.
--
-- MULTI-EMPRESA (não implementado, de propósito): todo insert daqui passa
-- workspace_id EXPLÍCITO, lido de hub.default_workspace_id() num ponto só
-- (v_ws). Quando existir hub.current_workspace_id(), troca-se essa linha.
-- ⚠️ Pendência conhecida pra essa fase: clientes.slug é UNIQUE global
-- (vira (workspace_id, slug)) e hub.is_admin() é e-mail chumbado.
--
-- NÃO APLICADA EM PRODUÇÃO. Testada em PGlite com o schema real (dump
-- só-leitura de 07/10) + 038. Aplicar a 038 antes desta.
-- =====================================================================


-- 1 · COLUNAS ----------------------------------------------------------

alter table hub.prospects
  add column if not exists cliente_id uuid references hub.clientes(id) on delete set null;
create index if not exists idx_prospects_cliente_id on hub.prospects (cliente_id)
  where cliente_id is not null;
comment on column hub.prospects.cliente_id is
  '041: card do CRM ligado ao cliente que nasceu dele. Ligado = o contato exibido vem de hub.contatos (fonte única), não das colunas contato_* desta tabela.';

alter table hub.contatos
  add column if not exists papeis text[] not null default '{}';
alter table hub.contatos drop constraint if exists contatos_papeis_validos;
alter table hub.contatos add constraint contatos_papeis_validos
  check (papeis <@ array['financeiro','decisor','operacional']::text[]);
comment on column hub.contatos.papeis is
  '041: papéis que o sistema usa pra rotear (cobrança → financeiro, assinatura → decisor). `papel` (texto livre) continua como rótulo/cargo.';

-- um principal por cliente. Em 07/10 nenhum cliente tinha 2 (conferido).
create unique index if not exists uq_contatos_um_principal
  on hub.contatos (cliente_id) where is_principal;

alter table hub.contratos add column if not exists assinado_em date;
comment on column hub.contratos.assinado_em is
  '041: data da assinatura informada no botão "Contrato assinado" (ou, no futuro, pelo webhook do DocuSeal).';

alter table hub.clientes drop constraint if exists clientes_tipo_cobranca_check;
alter table hub.clientes add constraint clientes_tipo_cobranca_check
  check (tipo_cobranca in ('fixo','percentual','misto'));


-- 2 · HELPERS DE CONTATO (fonte única) ---------------------------------

-- Contato de um cliente pra um papel: quem tem o papel → principal →
-- qualquer um. Só considera quem tem o canal pedido preenchido.
create or replace function hub.contato_do_papel(p_cliente_id uuid, p_papel text, p_canal text default 'whatsapp')
returns hub.contatos
language sql stable security definer set search_path = pg_catalog
as $$
  select k.* from hub.contatos k
  where k.cliente_id = p_cliente_id
    and case p_canal when 'email' then k.email is not null and btrim(k.email) <> ''
                     else k.whatsapp_e164 is not null end
  order by (p_papel = any(k.papeis)) desc, k.is_principal desc, k.created_at
  limit 1;
$$;
revoke all on function hub.contato_do_papel(uuid, text, text) from public, anon, authenticated;

-- Card do CRM ligado a cliente mostra o contato principal do cliente.
create or replace function hub.prospect_com_contato_do_cliente(p hub.prospects)
returns hub.prospects
language sql stable security definer set search_path = pg_catalog
as $$
  select case
    when p.cliente_id is null then p
    else coalesce((
      select jsonb_populate_record(p, jsonb_build_object(
               'contato_whatsapp', k.whatsapp_e164,
               'contato_email', k.email,
               'contato_eh_grupo', k.eh_grupo))
      from hub.contatos k
      where k.cliente_id = p.cliente_id
      order by k.is_principal desc, k.created_at
      limit 1), p)
  end;
$$;
revoke all on function hub.prospect_com_contato_do_cliente(hub.prospects) from public, anon, authenticated;


-- 3 · LEITORES QUE PASSAM A RESPEITAR O PAPEL --------------------------

create or replace function hub.rpc_prospects()
returns setof hub.prospects
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  -- lateral, e não (f(p)).*: o .* expandido chamaria a função 1× por coluna
  select q.* from hub.prospects p
  cross join lateral hub.prospect_com_contato_do_cliente(p) q
  order by p.perdido, p.coluna, p.created_at;
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
  return hub.prospect_com_contato_do_cliente(v_row);
end;
$$;

-- Igual à 020, com uma diferença: prospect LIGADO a cliente não tem as
-- colunas contato_* sobrescritas (a tela devolve o que leu, que agora vem
-- do cliente — gravar de volta recriaria a cópia que a fonte única aposenta).
-- cliente_id nunca é tocado por aqui: só rpc_novo_cliente liga.
create or replace function hub.rpc_salvar_prospect(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.prospects (
    id, nome, origem, contato_whatsapp, contato_eh_grupo, contato_email, coluna,
    valor_estimado_centavos, nota, gravacao, entrou_em, fechado_em,
    perdido, motivo_perda
  )
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()),
    p->>'nome', p->>'origem', p->>'contato_whatsapp',
    coalesce((p->>'contato_eh_grupo')::boolean, false), p->>'contato_email',
    coalesce((p->>'coluna')::smallint, 0),
    (p->>'valor_estimado_centavos')::bigint, p->>'nota',
    coalesce((p->>'gravacao')::boolean, false),
    coalesce((p->>'entrou_em')::date, current_date),
    (p->>'fechado_em')::date,
    coalesce((p->>'perdido')::boolean, false), p->>'motivo_perda'
  )
  on conflict (id) do update set
    nome=excluded.nome, origem=excluded.origem,
    contato_whatsapp=case when hub.prospects.cliente_id is null then excluded.contato_whatsapp else hub.prospects.contato_whatsapp end,
    contato_eh_grupo=case when hub.prospects.cliente_id is null then excluded.contato_eh_grupo else hub.prospects.contato_eh_grupo end,
    contato_email=case when hub.prospects.cliente_id is null then excluded.contato_email else hub.prospects.contato_email end,
    coluna=excluded.coluna,
    valor_estimado_centavos=excluded.valor_estimado_centavos, nota=excluded.nota,
    gravacao=excluded.gravacao, entrou_em=excluded.entrou_em, fechado_em=excluded.fechado_em,
    perdido=excluded.perdido, motivo_perda=excluded.motivo_perda
  returning id into v_id;

  return v_id;
end;
$$;

-- Igual à 020 + `papeis` (só muda se vier no payload, pra tela antiga não
-- apagar) + principal único (marcar um desmarca os outros do mesmo cliente).
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

-- Tela Cobranças: o WhatsApp mostrado é o do FINANCEIRO; sem papel marcado
-- cai no principal — exatamente o comportamento de antes.
create or replace function hub.rpc_cobranca_config_lista()
returns table(cliente_id uuid, cliente_nome text, config_id uuid, metodo text, ativo boolean, dia_vencimento smallint, whatsapp_e164 text)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    c.id, c.nome, cc.id, cc.metodo, coalesce(cc.ativo, false),
    (select ct.dia_vencimento from hub.contratos ct
       where ct.cliente_id = c.id and ct.status = 'ativo'
       order by ct.created_at desc limit 1),
    (hub.contato_do_papel(c.id, 'financeiro')).whatsapp_e164
  from hub.clientes c
  left join hub.cobranca_config cc on cc.cliente_id = c.id
  where c.status = 'ativo'
  order by c.nome;
end;
$$;

-- Bot de cobrança: mesma regra. Definição copiada do banco em 07/10 (esta
-- função existia só em produção, fora do repo) — a ÚNICA linha que muda é
-- o lateral `ct`, que passa a perguntar pelo financeiro.
create or replace function hub.bot_cobrancas_do_dia(p_secret text)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $function$
declare
  v_hoje date := (now() at time zone 'America/Recife')::date;
  v_dow int := extract(dow from v_hoje);
  v_fim_de_semana boolean := v_dow in (0,6);
  v_cobrancas jsonb := '[]'::jsonb;
  v_escalacoes jsonb;
begin
  if not hub.check_bot_secret(p_secret) then raise exception 'acesso negado'; end if;

  -- cobrança pro CLIENTE nunca sai no fim de semana; escalação pra ELA continua valendo
  if not v_fim_de_semana then
    select coalesce(jsonb_agg(jsonb_build_object(
        'recebivel_id', r.id, 'bucket', b.bucket, 'cliente_nome', c.nome,
        'whatsapp_e164', ct.whatsapp_e164, 'valor_centavos', r.valor_centavos,
        'falta_centavos', r.falta_centavos, 'vence_em', r.vence_em, 'descricao', r.descricao
      )), '[]'::jsonb)
    into v_cobrancas
    from hub.recebiveis r
    join hub.clientes c on c.id = r.cliente_id
    cross join lateral (
      select case (r.vence_em - v_hoje)
        when 3 then 'd_menos_3' when 0 then 'd0'
        when -2 then 'd_mais_2' when -7 then 'd_mais_7'
      end as bucket
    ) b
    left join lateral (
      select (hub.contato_do_papel(c.id, 'financeiro')).whatsapp_e164
    ) ct on true
    where r.falta_centavos > 0 and r.vence_em is not null and b.bucket is not null
      and ct.whatsapp_e164 is not null
      and not exists (select 1 from hub.cobranca_envios ce where ce.recebivel_id = r.id and ce.bucket = b.bucket);
  end if;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_escalacoes from (
    select jsonb_build_object(
      'recebivel_id', r.id, 'cliente_nome', c.nome, 'motivo', 'vencido_mais_de_7_dias',
      'falta_centavos', r.falta_centavos, 'vence_em', r.vence_em
    ) as x
    from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
    where r.falta_centavos > 0 and r.vence_em is not null and r.vence_em < v_hoje - 7
      and not exists (select 1 from hub.cobranca_envios ce where ce.recebivel_id = r.id and ce.bucket = 'escalado')
    union all
    select jsonb_build_object(
      'recebivel_id', r.id, 'cliente_nome', c.nome, 'motivo', 'sem_vencimento',
      'falta_centavos', r.falta_centavos, 'vence_em', null
    )
    from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
    where r.falta_centavos > 0 and r.vence_em is null
      and not exists (select 1 from hub.cobranca_envios ce where ce.recebivel_id = r.id and ce.bucket = 'escalado')
    union all
    select jsonb_build_object(
      'recebivel_id', r.id, 'cliente_nome', c.nome, 'motivo', 'sem_whatsapp_cadastrado',
      'falta_centavos', r.falta_centavos, 'vence_em', r.vence_em
    )
    from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
    where r.falta_centavos > 0 and r.vence_em is not null
      and not exists (select 1 from hub.contatos ct where ct.cliente_id = c.id and ct.whatsapp_e164 is not null)
      and not exists (select 1 from hub.cobranca_envios ce where ce.recebivel_id = r.id and ce.bucket = 'escalado')
  ) u;

  return jsonb_build_object(
    'hoje', v_hoje, 'fim_de_semana', v_fim_de_semana,
    'cobrancas', v_cobrancas, 'escalacoes', v_escalacoes
  );
end;
$function$;


-- 4 · NOVO CLIENTE — uma transação, idempotente -------------------------
--
-- Payload (jsonb):
--   id (uuid, OBRIGATÓRIO, gerado pelo front ao abrir a tela = chave de
--   idempotência) · nome · slug · segmento · origem · prospect_id
--   recorrente (bool) · valor_mensal_centavos · parcelas_total
--   dia_vencimento · inicio_em (date)
--   tipo_cobranca ('fixo'|'percentual'|'misto') · percentual_comissao
--   porta_saida_tipo ('manutencao_mensal'|'desligamento_build_30')
--   porta_saida_valor_centavos
--   servicos: [{servico_id, valor_centavos?}]
--   contatos: [{nome, papel?, papeis[], whatsapp_e164, email, eh_grupo, is_principal}]
--
-- Erros têm prefixo hub_novo_cliente_* pro front traduzir.
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
  if v_tipo in ('fixo','misto') and (v_valor is null or v_valor <= 0) then
    raise exception 'hub_novo_cliente_sem_valor';
  end if;
  if v_valor is not null and v_valor < 0 then raise exception 'hub_novo_cliente_sem_valor'; end if;
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


-- 5 · CONTRATO ASSINADO — a função única ------------------------------
--
-- Ativa e gera TODAS as parcelas. Regras:
--   • status ativo → no-op (devolve ja_estava_ativo). É isso que torna o
--     duplo clique e o webhook repetido inofensivos, e protege contrato
--     antigo (F7, Dobradinha) de ganhar parcela retroativa.
--   • encerrado/arquivado → recusa.
--   • porta de saída: a guarda do banco continua mandando. Sem tipo →
--     erro; tipo sem "escrita" → só passa se quem chama confirmar
--     (p_porta_escrita), e aí carimba porta_saida_escrita_em.
--   • parcelas: do mês de início (inicio_em, senão a data da assinatura)
--     • parcelas_total = N → as N, de uma vez, "… — parcela n/N";
--     • sem N (mensalidade sem fim) → do início até o mês corrente; daí
--       pra frente a hub.rpc_garantir_recebiveis_mes continua como sempre.
--   • mês que já tem recebível DESTE contrato → pula (idempotente, mesmo
--     índice uq_recebiveis_contrato_mes). Mês com recebível LEGADO (sem
--     contrato_id) do cliente → pula também e conta em `pulados_legado`:
--     é decisão humana, igual a 035 faz.
--   • numeração e descrição = as mesmas da 035 (distância de meses a partir
--     do início; 1º item do contrato, senão "Mensalidade").
--   • percentual puro (sem valor mensal) → ativa sem gerar nada.
create or replace function hub.ativar_contrato_assinado(
  p_contrato_id uuid, p_assinado_em date, p_porta_escrita boolean default false)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_ct hub.contratos;
  v_tipo text;
  v_hoje date := (now() at time zone 'America/Recife')::date;
  v_m0 date;
  v_total int;
  v_ultimo date;
  v_comp date;
  v_k int;
  v_desc_base text;
  v_desc text;
  v_ultimo_dia date;
  v_criadas int := 0;
  v_puladas int := 0;
  v_legado int := 0;
begin
  if p_contrato_id is null then raise exception 'contrato não encontrado'; end if;
  if p_assinado_em is null then raise exception 'hub_assinatura_sem_data'; end if;
  if p_assinado_em > v_hoje + 1 then raise exception 'hub_assinatura_no_futuro'; end if;

  select * into v_ct from hub.contratos where id = p_contrato_id for update;
  if not found then raise exception 'contrato não encontrado'; end if;

  if v_ct.status = 'ativo' then
    return jsonb_build_object('contrato_id', v_ct.id, 'ja_estava_ativo', true,
                              'parcelas_criadas', 0, 'pulados_legado', 0);
  end if;
  if v_ct.status in ('encerrado','arquivado') then
    raise exception 'hub_contrato_nao_pode_assinar: %', v_ct.status;
  end if;

  select c.tipo_cobranca into v_tipo from hub.clientes c where c.id = v_ct.cliente_id;

  if v_ct.porta_saida_tipo is null then
    raise exception 'hub_contrato_ativo_exige_porta_saida';
  end if;
  if v_ct.porta_saida_escrita_em is null and not coalesce(p_porta_escrita, false) then
    raise exception 'hub_contrato_ativo_exige_porta_saida';
  end if;
  if v_ct.valor_mensal_centavos is null and v_tipo is distinct from 'percentual' then
    raise exception 'hub_contrato_sem_valor';
  end if;
  if v_ct.valor_mensal_centavos is not null and v_ct.dia_vencimento is null then
    raise exception 'hub_contrato_sem_vencimento';
  end if;

  update hub.contratos
     set status = 'ativo',
         assinado_em = p_assinado_em,
         inicio_em = coalesce(inicio_em, p_assinado_em),
         porta_saida_escrita_em = coalesce(porta_saida_escrita_em, now())
   where id = v_ct.id
  returning * into v_ct;

  if v_ct.valor_mensal_centavos is null then
    return jsonb_build_object('contrato_id', v_ct.id, 'ja_estava_ativo', false,
                              'parcelas_criadas', 0, 'pulados_legado', 0);
  end if;

  v_m0 := date_trunc('month', v_ct.inicio_em)::date;
  if v_ct.parcelas_total is not null then
    v_total := v_ct.parcelas_total;
  else
    v_ultimo := greatest(v_m0, date_trunc('month', v_hoje)::date);
    v_total := ((extract(year from v_ultimo)::int * 12 + extract(month from v_ultimo)::int)
              - (extract(year from v_m0)::int * 12 + extract(month from v_m0)::int)) + 1;
  end if;

  select ci.descricao into v_desc_base from hub.contrato_itens ci
  where ci.contrato_id = v_ct.id order by ci.created_at asc limit 1;
  if v_desc_base is null or btrim(v_desc_base) = '' then v_desc_base := 'Mensalidade'; end if;

  for v_k in 1..v_total loop
    v_comp := (v_m0 + make_interval(months => v_k - 1))::date;

    if exists (select 1 from hub.recebiveis r
               where r.contrato_id = v_ct.id
                 and date_trunc('month', r.competencia)::date = v_comp) then
      v_puladas := v_puladas + 1;
      continue;
    end if;
    if exists (select 1 from hub.recebiveis r
               where r.cliente_id = v_ct.cliente_id and r.contrato_id is null
                 and r.origem = 'contrato'
                 and date_trunc('month', r.competencia)::date = v_comp) then
      v_legado := v_legado + 1;
      continue;
    end if;

    v_desc := v_desc_base;
    if v_ct.parcelas_total is not null then
      v_desc := v_desc || ' — parcela ' || v_k || '/' || v_ct.parcelas_total;
    end if;
    v_ultimo_dia := (v_comp + interval '1 month - 1 day')::date;

    insert into hub.recebiveis (cliente_id, contrato_id, competencia, descricao, valor_centavos, vence_em, origem)
    values (v_ct.cliente_id, v_ct.id, v_comp, v_desc, v_ct.valor_mensal_centavos,
            make_date(extract(year from v_comp)::int, extract(month from v_comp)::int,
                      least(v_ct.dia_vencimento::int, extract(day from v_ultimo_dia)::int)),
            'contrato');
    v_criadas := v_criadas + 1;
  end loop;

  return jsonb_build_object('contrato_id', v_ct.id, 'ja_estava_ativo', false,
                            'parcelas_criadas', v_criadas, 'ja_existiam', v_puladas,
                            'pulados_legado', v_legado);
end;
$$;
-- Interna. Só funções SECURITY DEFINER do próprio schema chamam.
revoke all on function hub.ativar_contrato_assinado(uuid, date, boolean) from public, anon, authenticated;

-- Botão manual (só admin). p: { contrato_id, assinado_em, porta_escrita }
create or replace function hub.rpc_contrato_assinado(p jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return hub.ativar_contrato_assinado(
    nullif(p->>'contrato_id','')::uuid,
    coalesce(nullif(p->>'assinado_em','')::date, (now() at time zone 'America/Recife')::date),
    coalesce((p->>'porta_escrita')::boolean, false));
end;
$$;


-- 6 · GRANTS + WRAPPERS PÚBLICOS (padrão 004) --------------------------

revoke all on function hub.rpc_novo_cliente(jsonb) from public, anon;
revoke all on function hub.rpc_contrato_assinado(jsonb) from public, anon;
grant execute on function hub.rpc_novo_cliente(jsonb) to authenticated;
grant execute on function hub.rpc_contrato_assinado(jsonb) to authenticated;

create or replace function public.hub_rpc_novo_cliente(p jsonb)
returns jsonb
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_novo_cliente(p); $$;

create or replace function public.hub_rpc_contrato_assinado(p jsonb)
returns jsonb
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_contrato_assinado(p); $$;

revoke all on function public.hub_rpc_novo_cliente(jsonb) from public, anon;
revoke all on function public.hub_rpc_contrato_assinado(jsonb) from public, anon;
grant execute on function public.hub_rpc_novo_cliente(jsonb) to authenticated;
grant execute on function public.hub_rpc_contrato_assinado(jsonb) to authenticated;
