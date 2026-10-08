-- Estrutura do schema hub para os testes (PGlite). Gerado por
-- scripts/sanitizar-fixture-schema.mjs: sem dados, sem comentários,
-- e-mail da admin trocado por admin@hub.test. Não aplicar em banco nenhum.
set check_function_bodies = off;
create schema if not exists hub;
CREATE OR REPLACE FUNCTION hub.default_workspace_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select id from hub.workspaces where slug = 'luhpanda' limit 1;
$function$
;
create table hub.eventos_auditoria (id uuid default gen_random_uuid() not null, tabela text not null, registro_id uuid, acao text not null, dados_antes jsonb, dados_depois jsonb, ator_email text, criado_em timestamp with time zone default now() not null);
create table hub.empresas (id uuid default gen_random_uuid() not null, nome text not null, cnpj text, tipo text not null, teto_anual_centavos bigint, ativo boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null, aberta_em date);
create table hub.clientes (id uuid default gen_random_uuid() not null, empresa_id uuid not null, slug text not null, nome text not null, razao_social text, documento text, segmento text, origem text, status text default 'ativo'::text not null, entrou_em date, saiu_em date, motivo_saida text, observacao text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null, recorrente boolean default true not null, endereco text, tipo_cobranca text default 'fixo'::text not null, percentual_comissao numeric(5,2));
create table hub.contatos (id uuid default gen_random_uuid() not null, cliente_id uuid not null, nome text not null, papel text, email text, whatsapp_e164 text, is_principal boolean default false not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null, eh_grupo boolean default false not null, papeis text[] default '{}'::text[] not null);
create table hub.servicos (id uuid default gen_random_uuid() not null, slug text not null, nome text not null, modalidade text not null, preco_referencia_centavos bigint, unidade text, inclui text, observacao text, ativo boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null, anexo_escopo text);
create table hub.contratos (id uuid default gen_random_uuid() not null, cliente_id uuid not null, numero text, status text default 'rascunho'::text not null, inicio_em date, fim_minimo_em date, dia_vencimento smallint, valor_mensal_centavos bigint, porta_saida_tipo text, porta_saida_valor_centavos bigint, porta_saida_escrita_em timestamp with time zone, observacao text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null, arquivo_path text, arquivo_nome text, arquivo_tipo text, arquivo_em timestamp with time zone, parcelas_total smallint, recorrencia_ativa boolean default true not null, docuseal_submission_id bigint, docuseal_audit_log_url text, assinado_em date);
create table hub.contrato_itens (id uuid default gen_random_uuid() not null, contrato_id uuid not null, servico_id uuid, descricao text not null, valor_centavos bigint, recorrencia text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null);
create table hub.recebiveis (id uuid default gen_random_uuid() not null, cliente_id uuid not null, competencia date not null, descricao text not null, valor_centavos bigint not null, entrada_centavos bigint default 0 not null, entrou_em date, vence_em date, origem text default 'contrato'::text not null, observacao text, falta_centavos bigint generated always as (GREATEST((valor_centavos - entrada_centavos), (0)::bigint)) stored, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, sincronizado_planilha boolean default false not null, contrato_id uuid, valor_travado boolean default false not null);
create table hub.custos_fixos (id uuid default gen_random_uuid() not null, nome text not null, funcao text, categoria text not null, valor_centavos bigint not null, dia_vencimento smallint, fim_em date, parcelas_restantes integer, ativo boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table hub.cobranca_envios (id uuid default gen_random_uuid() not null, recebivel_id uuid not null, bucket text not null, enviado_em timestamp with time zone default now() not null);
create table hub.config (chave text not null, valor_hash text not null, updated_at timestamp with time zone default now() not null);
create table hub.demandas (id uuid default gen_random_uuid() not null, cliente_id uuid not null, titulo text not null, descricao text, entrega_em date, status text default 'aberta'::text not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, workspace_id uuid default hub.default_workspace_id() not null);
create table hub.workspaces (id uuid default gen_random_uuid() not null, nome text not null, slug text not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table hub.prospects (id uuid default gen_random_uuid() not null, workspace_id uuid default hub.default_workspace_id() not null, nome text not null, origem text, contato_whatsapp text, contato_email text, coluna smallint default 0 not null, valor_estimado_centavos bigint, nota text, gravacao boolean default false not null, entrou_em date default CURRENT_DATE not null, fechado_em date, perdido boolean default false not null, motivo_perda text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, contato_eh_grupo boolean default false not null, cliente_id uuid);
create table hub.cobranca_config (id uuid default gen_random_uuid() not null, workspace_id uuid default hub.default_workspace_id() not null, cliente_id uuid not null, metodo text default 'pix'::text not null, ativo boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table hub.cobranca_mensagens (id uuid default gen_random_uuid() not null, workspace_id uuid default hub.default_workspace_id() not null, etapa text not null, texto text not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table hub.conversas (id uuid default gen_random_uuid() not null, workspace_id uuid default hub.default_workspace_id() not null, fone_norm text not null, prospect_id uuid, cliente_id uuid, nome_exibicao text, ultima_msg_em timestamp with time zone, ultima_msg_previa text, ultima_msg_direcao text, rascunho_sugerido text, criada_em timestamp with time zone default now() not null, eh_grupo boolean default false not null, sugestao_reuniao jsonb);
create table hub.mensagens (id uuid default gen_random_uuid() not null, conversa_id uuid not null, direcao text not null, corpo text, tipo text default 'texto'::text not null, transcrito boolean default false not null, enviada_em timestamp with time zone default now() not null, evolution_msg_id text, status text, erro text, remetente_fone text, remetente_nome text);
create table hub.reunioes (id uuid default gen_random_uuid() not null, workspace_id uuid default hub.default_workspace_id() not null, meetily_meeting_id text not null, prospect_id uuid, cliente_id uuid, titulo text, realizada_em timestamp with time zone, transcricao text, resumo text, key_points text, action_items text, analise jsonb, criada_em timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table hub.eventos_agenda (id uuid default gen_random_uuid() not null, workspace_id uuid default hub.default_workspace_id() not null, google_event_id text not null, cliente_id uuid, prospect_id uuid, criado_por text default 'hub'::text not null, criado_em timestamp with time zone default now() not null, calendario_id text default 'primary'::text not null);
alter table hub.clientes add constraint clientes_slug_key UNIQUE (slug);
alter table hub.mensagens add constraint mensagens_evolution_msg_id_key UNIQUE (evolution_msg_id);
alter table hub.cobranca_envios add constraint cobranca_envios_recebivel_id_bucket_key UNIQUE (recebivel_id, bucket);
alter table hub.conversas add constraint conversas_fone_norm_key UNIQUE (fone_norm);
alter table hub.servicos add constraint servicos_slug_key UNIQUE (slug);
alter table hub.eventos_agenda add constraint eventos_agenda_google_event_id_key UNIQUE (google_event_id);
alter table hub.cobranca_mensagens add constraint cobranca_mensagens_etapa_key UNIQUE (etapa);
alter table hub.cobranca_config add constraint cobranca_config_cliente_id_key UNIQUE (cliente_id);
alter table hub.workspaces add constraint workspaces_slug_key UNIQUE (slug);
alter table hub.reunioes add constraint reunioes_meetily_meeting_id_key UNIQUE (meetily_meeting_id);
alter table hub.empresas add constraint empresas_pkey PRIMARY KEY (id);
alter table hub.eventos_auditoria add constraint eventos_auditoria_pkey PRIMARY KEY (id);
alter table hub.clientes add constraint clientes_pkey PRIMARY KEY (id);
alter table hub.contatos add constraint contatos_pkey PRIMARY KEY (id);
alter table hub.servicos add constraint servicos_pkey PRIMARY KEY (id);
alter table hub.contratos add constraint contratos_pkey PRIMARY KEY (id);
alter table hub.contrato_itens add constraint contrato_itens_pkey PRIMARY KEY (id);
alter table hub.recebiveis add constraint recebiveis_pkey PRIMARY KEY (id);
alter table hub.custos_fixos add constraint custos_fixos_pkey PRIMARY KEY (id);
alter table hub.cobranca_envios add constraint cobranca_envios_pkey PRIMARY KEY (id);
alter table hub.config add constraint config_pkey PRIMARY KEY (chave);
alter table hub.demandas add constraint demandas_pkey PRIMARY KEY (id);
alter table hub.workspaces add constraint workspaces_pkey PRIMARY KEY (id);
alter table hub.prospects add constraint prospects_pkey PRIMARY KEY (id);
alter table hub.cobranca_config add constraint cobranca_config_pkey PRIMARY KEY (id);
alter table hub.cobranca_mensagens add constraint cobranca_mensagens_pkey PRIMARY KEY (id);
alter table hub.conversas add constraint conversas_pkey PRIMARY KEY (id);
alter table hub.mensagens add constraint mensagens_pkey PRIMARY KEY (id);
alter table hub.reunioes add constraint reunioes_pkey PRIMARY KEY (id);
alter table hub.eventos_agenda add constraint eventos_agenda_pkey PRIMARY KEY (id);
alter table hub.contatos add constraint contatos_papeis_validos CHECK ((papeis <@ ARRAY['financeiro'::text, 'decisor'::text, 'operacional'::text]));
alter table hub.contratos add constraint contratos_parcelas_total_check CHECK (((parcelas_total IS NULL) OR (parcelas_total > 0)));
alter table hub.contratos add constraint hub_contrato_ativo_exige_porta_saida CHECK (((status <> 'ativo'::text) OR ((porta_saida_escrita_em IS NOT NULL) AND (porta_saida_tipo IS NOT NULL))));
alter table hub.clientes add constraint clientes_status_check CHECK ((status = ANY (ARRAY['prospect'::text, 'ativo'::text, 'pausado'::text, 'encerrado'::text])));
alter table hub.prospects add constraint prospects_coluna_check CHECK (((coluna >= 0) AND (coluna <= 5)));
alter table hub.contratos add constraint contratos_status_check CHECK ((status = ANY (ARRAY['rascunho'::text, 'emitido'::text, 'enviado'::text, 'assinado'::text, 'ativo'::text, 'encerrado'::text, 'arquivado'::text])));
alter table hub.cobranca_config add constraint cobranca_config_metodo_check CHECK ((metodo = ANY (ARRAY['pix'::text, 'mp_link'::text])));
alter table hub.clientes add constraint clientes_tipo_cobranca_check CHECK ((tipo_cobranca = ANY (ARRAY['fixo'::text, 'percentual'::text, 'misto'::text])));
alter table hub.recebiveis add constraint recebiveis_competencia_dia_1 CHECK ((competencia = (date_trunc('month'::text, (competencia)::timestamp with time zone))::date));
alter table hub.cobranca_mensagens add constraint cobranca_mensagens_etapa_check CHECK ((etapa = ANY (ARRAY['d_menos_3'::text, 'd0'::text, 'd_mais_2'::text, 'd_mais_7'::text])));
alter table hub.eventos_agenda add constraint eventos_agenda_criado_por_check CHECK ((criado_por = ANY (ARRAY['hub'::text, 'google'::text])));
alter table hub.empresas add constraint empresas_tipo_check CHECK ((tipo = ANY (ARRAY['mei'::text, 'produto'::text, 'servico'::text])));
alter table hub.conversas add constraint conversas_ultima_msg_direcao_check CHECK ((ultima_msg_direcao = ANY (ARRAY['entrada'::text, 'saida'::text])));
alter table hub.contratos add constraint contratos_dia_vencimento_check CHECK (((dia_vencimento >= 1) AND (dia_vencimento <= 28)));
alter table hub.contratos add constraint contratos_porta_saida_tipo_check CHECK ((porta_saida_tipo = ANY (ARRAY['manutencao_mensal'::text, 'desligamento_build_30'::text, 'nenhuma'::text])));
alter table hub.demandas add constraint demandas_status_check CHECK ((status = ANY (ARRAY['aberta'::text, 'fazendo'::text, 'entregue'::text, 'arquivado'::text])));
alter table hub.eventos_auditoria add constraint eventos_auditoria_acao_check CHECK ((acao = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])));
alter table hub.recebiveis add constraint recebiveis_valor_centavos_check CHECK ((valor_centavos >= 0));
alter table hub.recebiveis add constraint recebiveis_entrada_centavos_check CHECK ((entrada_centavos >= 0));
alter table hub.recebiveis add constraint recebiveis_origem_check CHECK ((origem = ANY (ARRAY['contrato'::text, 'extra'::text, 'comissao'::text, 'aula'::text, 'evento'::text])));
alter table hub.mensagens add constraint mensagens_direcao_check CHECK ((direcao = ANY (ARRAY['entrada'::text, 'saida'::text])));
alter table hub.custos_fixos add constraint custos_fixos_categoria_check CHECK ((categoria = ANY (ARRAY['negocio'::text, 'pessoal'::text])));
alter table hub.custos_fixos add constraint custos_fixos_valor_centavos_check CHECK ((valor_centavos >= 0));
alter table hub.custos_fixos add constraint custos_fixos_dia_vencimento_check CHECK (((dia_vencimento >= 1) AND (dia_vencimento <= 31)));
alter table hub.mensagens add constraint mensagens_tipo_check CHECK ((tipo = ANY (ARRAY['texto'::text, 'audio'::text, 'imagem'::text, 'documento'::text, 'outro'::text])));
alter table hub.cobranca_envios add constraint cobranca_envios_bucket_check CHECK ((bucket = ANY (ARRAY['d_menos_3'::text, 'd0'::text, 'd_mais_2'::text, 'd_mais_7'::text, 'escalado'::text])));
alter table hub.mensagens add constraint mensagens_status_check CHECK (((status IS NULL) OR (status = ANY (ARRAY['enviando'::text, 'enviado'::text, 'erro'::text]))));
alter table hub.servicos add constraint servicos_modalidade_check CHECK ((modalidade = ANY (ARRAY['recorrente'::text, 'projeto'::text, 'bloco_horas'::text, 'por_evento'::text, 'hospedagem'::text])));
alter table hub.prospects add constraint prospects_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.recebiveis add constraint recebiveis_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES hub.contratos(id) ON DELETE SET NULL;
alter table hub.clientes add constraint clientes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hub.empresas(id);
alter table hub.contatos add constraint contatos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.contratos add constraint contratos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.contrato_itens add constraint contrato_itens_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES hub.contratos(id) ON DELETE CASCADE;
alter table hub.contrato_itens add constraint contrato_itens_servico_id_fkey FOREIGN KEY (servico_id) REFERENCES hub.servicos(id);
alter table hub.recebiveis add constraint recebiveis_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.cobranca_envios add constraint cobranca_envios_recebivel_id_fkey FOREIGN KEY (recebivel_id) REFERENCES hub.recebiveis(id) ON DELETE CASCADE;
alter table hub.demandas add constraint demandas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.empresas add constraint empresas_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.clientes add constraint clientes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.contatos add constraint contatos_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.servicos add constraint servicos_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.contratos add constraint contratos_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.contrato_itens add constraint contrato_itens_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.demandas add constraint demandas_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.prospects add constraint prospects_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.cobranca_config add constraint cobranca_config_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.cobranca_config add constraint cobranca_config_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.cobranca_mensagens add constraint cobranca_mensagens_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.conversas add constraint conversas_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.conversas add constraint conversas_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES hub.prospects(id) ON DELETE SET NULL;
alter table hub.conversas add constraint conversas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.mensagens add constraint mensagens_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES hub.conversas(id) ON DELETE CASCADE;
alter table hub.reunioes add constraint reunioes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.reunioes add constraint reunioes_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES hub.prospects(id) ON DELETE SET NULL;
alter table hub.reunioes add constraint reunioes_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.eventos_agenda add constraint eventos_agenda_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES hub.workspaces(id);
alter table hub.eventos_agenda add constraint eventos_agenda_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.eventos_agenda add constraint eventos_agenda_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES hub.prospects(id) ON DELETE SET NULL;
CREATE INDEX idx_reunioes_realizada ON hub.reunioes USING btree (realizada_em DESC NULLS LAST);
CREATE INDEX idx_reunioes_prospect ON hub.reunioes USING btree (prospect_id) WHERE (prospect_id IS NOT NULL);
CREATE INDEX idx_reunioes_cliente ON hub.reunioes USING btree (cliente_id) WHERE (cliente_id IS NOT NULL);
CREATE INDEX idx_mensagens_conversa_enviada ON hub.mensagens USING btree (conversa_id, enviada_em DESC);
CREATE UNIQUE INDEX uq_contatos_um_principal ON hub.contatos USING btree (cliente_id) WHERE is_principal;
CREATE UNIQUE INDEX idx_contratos_docuseal_submission ON hub.contratos USING btree (docuseal_submission_id) WHERE (docuseal_submission_id IS NOT NULL);
CREATE INDEX idx_eventos_agenda_cliente ON hub.eventos_agenda USING btree (cliente_id) WHERE (cliente_id IS NOT NULL);
CREATE INDEX idx_eventos_agenda_prospect ON hub.eventos_agenda USING btree (prospect_id) WHERE (prospect_id IS NOT NULL);
CREATE INDEX idx_prospects_cliente_id ON hub.prospects USING btree (cliente_id) WHERE (cliente_id IS NOT NULL);
CREATE INDEX idx_recebiveis_competencia ON hub.recebiveis USING btree (competencia);
CREATE INDEX idx_recebiveis_vence_em ON hub.recebiveis USING btree (vence_em);
CREATE INDEX idx_recebiveis_contrato_id ON hub.recebiveis USING btree (contrato_id) WHERE (contrato_id IS NOT NULL);
CREATE UNIQUE INDEX uq_recebiveis_contrato_mes ON hub.recebiveis USING btree (contrato_id, ((date_trunc('month'::text, (competencia)::timestamp without time zone))::date)) WHERE (contrato_id IS NOT NULL);
CREATE OR REPLACE FUNCTION hub.default_workspace_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select id from hub.workspaces where slug = 'luhpanda' limit 1;
$function$
;
CREATE OR REPLACE FUNCTION hub.default_empresa_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select id from hub.empresas where nome = 'Luh Panda' limit 1;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_apagar_prospect(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.prospects where id = p_id;
  if not found then raise exception 'prospect não encontrado'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_converter_prospect_em_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_recebiveis_cliente(p_cliente_id uuid)
 RETURNS TABLE(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, contrato_id uuid, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_hoje date := (now() at time zone 'America/Recife')::date;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select r.id, r.cliente_id, c.nome, c.slug, r.competencia, r.descricao,
    r.valor_centavos, r.entrada_centavos, r.falta_centavos, r.entrou_em, r.vence_em,
    r.origem, r.observacao, r.contrato_id,
    case
      when r.valor_centavos = 0 then 'sem_cobranca'
      when r.falta_centavos = 0 then 'pago'
      when r.entrada_centavos > 0 then 'parcial'
      when r.vence_em is not null and r.vence_em < v_hoje then 'vencido'
      else 'aberto'
    end as status
  from hub.recebiveis r
  join hub.clientes c on c.id = r.cliente_id
  where r.cliente_id = p_cliente_id
  order by r.competencia desc, r.vence_em nulls last, r.created_at;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.mei_limites(p_ano integer)
 RETURNS TABLE(ano integer, teto_anual_centavos bigint, meses integer, teto_centavos bigint, tolerancia_centavos bigint, ano_abertura boolean, aberta_em date, retroage_a date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_anual bigint;
  v_aberta date;
  v_meses int := 12;
  v_teto bigint;
begin
  select e.teto_anual_centavos, e.aberta_em into v_anual, v_aberta
    from hub.empresas e where e.tipo = 'mei' order by e.created_at limit 1;
  v_anual := coalesce(v_anual, 8100000);

  if v_aberta is not null and extract(year from v_aberta)::int = p_ano then
    v_meses := 13 - extract(month from v_aberta)::int;
    v_teto := round(v_anual::numeric / 12 * v_meses)::bigint;
  elsif v_aberta is not null and extract(year from v_aberta)::int > p_ano then
    v_meses := 0; v_teto := 0;
  else
    v_teto := v_anual;
  end if;

  return query select p_ano, v_anual, v_meses, v_teto,
    round(v_teto::numeric * 1.2)::bigint,
    (v_aberta is not null and extract(year from v_aberta)::int = p_ano),
    v_aberta,
    case when v_aberta is not null and extract(year from v_aberta)::int = p_ano
         then v_aberta else make_date(p_ano, 1, 1) end;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_recebiveis(p_competencia date)
 RETURNS TABLE(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_hoje date := (now() at time zone 'America/Recife')::date;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select r.id, r.cliente_id, c.nome, c.slug, r.competencia, r.descricao,
    r.valor_centavos, r.entrada_centavos, r.falta_centavos, r.entrou_em, r.vence_em,
    r.origem, r.observacao,
    case
      when r.valor_centavos = 0 then 'sem_cobranca'
      when r.falta_centavos = 0 then 'pago'
      when r.entrada_centavos > 0 then 'parcial'
      when r.vence_em is not null and r.vence_em < v_hoje then 'vencido'
      else 'aberto'
    end as status
  from hub.recebiveis r
  join hub.clientes c on c.id = r.cliente_id
  where date_trunc('month', r.competencia) = date_trunc('month', p_competencia)
  order by c.nome;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.contato_do_papel(p_cliente_id uuid, p_papel text, p_canal text DEFAULT 'whatsapp'::text)
 RETURNS hub.contatos
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select k.* from hub.contatos k
  where k.cliente_id = p_cliente_id
    and case p_canal when 'email' then k.email is not null and btrim(k.email) <> ''
                     else k.whatsapp_e164 is not null end
  order by (p_papel = any(k.papeis)) desc, k.is_principal desc, k.created_at
  limit 1;
$function$
;
CREATE OR REPLACE FUNCTION hub.prospect_com_contato_do_cliente(p hub.prospects)
 RETURNS hub.prospects
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_prospects()
 RETURNS SETOF hub.prospects
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select q.* from hub.prospects p
  cross join lateral hub.prospect_com_contato_do_cliente(p) q
  order by p.perdido, p.coluna, p.created_at;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_prospect(p_id uuid)
 RETURNS hub.prospects
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_row hub.prospects;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  select * into v_row from hub.prospects where id = p_id;
  if not found then return null; end if;
  return hub.prospect_com_contato_do_cliente(v_row);
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.bot_cobrancas_do_dia(p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_hoje date := (now() at time zone 'America/Recife')::date;
  v_dow int := extract(dow from v_hoje);
  v_fim_de_semana boolean := v_dow in (0,6);
  v_cobrancas jsonb := '[]'::jsonb;
  v_escalacoes jsonb;
begin
  if not hub.check_bot_secret(p_secret) then raise exception 'acesso negado'; end if;

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
$function$
;
CREATE OR REPLACE FUNCTION hub.ativar_contrato_assinado(p_contrato_id uuid, p_assinado_em date, p_porta_escrita boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
  if coalesce(v_ct.valor_mensal_centavos, 0) <= 0 and v_tipo is distinct from 'percentual' then
    raise exception 'hub_contrato_sem_valor';
  end if;
  if coalesce(v_ct.valor_mensal_centavos, 0) > 0 and v_ct.dia_vencimento is null then
    raise exception 'hub_contrato_sem_vencimento';
  end if;

  update hub.contratos
     set status = 'ativo',
         assinado_em = p_assinado_em,
         inicio_em = coalesce(inicio_em, p_assinado_em),
         porta_saida_escrita_em = coalesce(porta_saida_escrita_em, now())
   where id = v_ct.id
  returning * into v_ct;

  if coalesce(v_ct.valor_mensal_centavos, 0) <= 0 then
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_contrato_assinado(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return hub.ativar_contrato_assinado(
    nullif(p->>'contrato_id','')::uuid,
    coalesce(nullif(p->>'assinado_em','')::date, (now() at time zone 'America/Recife')::date),
    coalesce((p->>'porta_escrita')::boolean, false));
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_novo_cliente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_ws uuid := hub.default_workspace_id();
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

  perform pg_advisory_xact_lock(hashtextextended('hub.novo_cliente:' || v_id::text, 0));
  if exists (select 1 from hub.clientes where id = v_id) then
    return (
      select jsonb_build_object(
        'cliente_id', c.id, 'slug', c.slug, 'ja_existia', true,
        'contrato_id', (select ct.id from hub.contratos ct where ct.cliente_id = c.id order by ct.created_at limit 1),
        'prospect_id', (select pr.id from hub.prospects pr where pr.cliente_id = c.id order by pr.created_at limit 1))
      from hub.clientes c where c.id = v_id);
  end if;

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
  if v_tipo = 'percentual' and v_valor = 0 then v_valor := null; end if;
  if v_tipo in ('fixo','misto') and (v_valor is null or v_valor <= 0) then
    raise exception 'hub_novo_cliente_sem_valor';
  end if;
  if v_valor is not null and v_valor <= 0 then raise exception 'hub_novo_cliente_sem_valor'; end if;
  if v_parcelas is not null and v_parcelas < 1 then raise exception 'hub_novo_cliente_parcelas_invalidas'; end if;
  if not v_recorrente and v_valor is not null and v_parcelas is null then
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

  perform pg_advisory_xact_lock(hashtextextended('hub.novo_cliente.slug:' || v_ws::text || ':' || v_slug_base, 0));
  v_slug := v_slug_base;
  while exists (select 1 from hub.clientes where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_slug_base || '-' || v_n;
  end loop;

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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_rascunho(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  update hub.conversas
  set rascunho_sugerido = p->>'rascunho'
  where fone_norm = v_fone
  returning id into v_conversa_id;

  return v_conversa_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select coalesce(auth.email(), '') = 'admin@hub.test';
$function$
;
CREATE OR REPLACE FUNCTION hub.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.registrar_auditoria()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  insert into hub.eventos_auditoria (tabela, registro_id, acao, dados_antes, dados_depois, ator_email)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    coalesce(auth.email(), 'sistema')
  );
  return coalesce(new, old);
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_cliente(p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_cliente hub.clientes;
  v_result jsonb;
begin
  if not hub.is_admin() then
    raise exception 'acesso negado';
  end if;

  select * into v_cliente from hub.clientes where slug = p_slug;
  if not found then
    return null;
  end if;

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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_excluir_recebivel(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.recebiveis where id = p_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_servico(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_catalogo()
 RETURNS SETOF hub.servicos
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then
    raise exception 'acesso negado';
  end if;

  return query select * from hub.servicos order by nome;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.check_bot_secret(p_secret text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions'
AS $function$
  select exists (
    select 1 from hub.config
    where chave = 'bot_secret'
      and valor_hash = encode(digest(coalesce(p_secret,''), 'sha256'), 'hex')
  );
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_dash()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_hoje date := (now() at time zone 'America/Recife')::date;
  v_mes date := date_trunc('month', (now() at time zone 'America/Recife'))::date;
  v_ano_inicio date := date_trunc('year', v_hoje)::date;
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select jsonb_build_object(
    'hoje', v_hoje,
    'por_mes', coalesce((
      select jsonb_agg(m order by m->>'competencia')
      from (
        select jsonb_build_object(
          'competencia', date_trunc('month', competencia)::date,
          'previsto_centavos', sum(valor_centavos),
          'entrado_centavos', sum(entrada_centavos)
        ) as m
        from hub.recebiveis
        group by date_trunc('month', competencia)::date
      ) x
    ), '[]'::jsonb),
    'clientes_ativos', (select count(*) from hub.clientes where status = 'ativo'),
    'velocimetro_mei', (
      select jsonb_build_object(
        'entrado_ano_centavos', coalesce((
          select sum(entrada_centavos) from hub.recebiveis
          where entrou_em >= v_ano_inicio and entrou_em < v_ano_inicio + interval '1 year'
        ), 0),
        'ano', l.ano,
        'teto_centavos', l.teto_centavos,
        'tolerancia_centavos', l.tolerancia_centavos,
        'teto_anual_centavos', l.teto_anual_centavos,
        'meses', l.meses,
        'ano_abertura', l.ano_abertura,
        'aberta_em', l.aberta_em,
        'retroage_a', l.retroage_a
      )
      from hub.mei_limites(extract(year from v_hoje)::int) l
    ),
    'custos_fixos', jsonb_build_object(
      'negocio_centavos', coalesce((select sum(valor_centavos) from hub.custos_fixos where categoria='negocio' and ativo), 0),
      'pessoal_centavos', coalesce((select sum(valor_centavos) from hub.custos_fixos where categoria='pessoal' and ativo), 0)
    ),
    'vencidos_hoje_ou_antes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recebivel_id', r.id, 'cliente_id', c.id, 'cliente_nome', c.nome, 'cliente_slug', c.slug,
        'descricao', r.descricao, 'competencia', r.competencia,
        'falta_centavos', r.falta_centavos, 'vence_em', r.vence_em
      ) order by c.nome, r.vence_em)
      from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
      where r.falta_centavos > 0 and r.vence_em is not null and r.vence_em <= v_hoje
        and c.status <> 'encerrado'
    ), '[]'::jsonb),
    'sem_vencimento', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recebivel_id', r.id, 'cliente_id', c.id, 'cliente_nome', c.nome, 'cliente_slug', c.slug,
        'descricao', r.descricao, 'competencia', r.competencia,
        'falta_centavos', r.falta_centavos
      ) order by c.nome, r.competencia)
      from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
      where r.falta_centavos > 0 and r.vence_em is null
        and r.competencia <= v_mes
        and c.status <> 'encerrado'
    ), '[]'::jsonb),
    'futuros_por_cliente', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cliente_id', f.cliente_id, 'quantidade', f.n,
        'proximo_vence_em', f.prox, 'falta_centavos', f.falta
      ))
      from (
        select r.cliente_id, count(*) n, min(r.vence_em) prox, sum(r.falta_centavos) falta
        from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
        where r.falta_centavos > 0 and c.status <> 'encerrado'
          and ((r.vence_em is not null and r.vence_em > v_hoje)
               or (r.vence_em is null and r.competencia > v_mes))
        group by r.cliente_id
      ) f
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_marcar_pago(p_id uuid, p_valor_centavos bigint, p_data date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.recebiveis
  set entrada_centavos = entrada_centavos + p_valor_centavos,
      entrou_em = p_data,
      sincronizado_planilha = false
  where id = p_id;

  return p_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_custos()
 RETURNS SETOF hub.custos_fixos
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query select * from hub.custos_fixos order by categoria, nome;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_custo(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.custos_fixos (id, nome, funcao, categoria, valor_centavos, dia_vencimento, fim_em, parcelas_restantes, ativo)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), p->>'nome', p->>'funcao', p->>'categoria',
    (p->>'valor_centavos')::bigint, (p->>'dia_vencimento')::smallint, (p->>'fim_em')::date,
    (p->>'parcelas_restantes')::int, coalesce((p->>'ativo')::boolean, true)
  )
  on conflict (id) do update set
    nome=excluded.nome, funcao=excluded.funcao, categoria=excluded.categoria,
    valor_centavos=excluded.valor_centavos, dia_vencimento=excluded.dia_vencimento,
    fim_em=excluded.fim_em, parcelas_restantes=excluded.parcelas_restantes, ativo=excluded.ativo
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_excluir_custo(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.custos_fixos where id = p_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_excluir_contato(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.contatos where id = p_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.bot_pagamentos_pendentes_sync(p_secret text)
 RETURNS TABLE(recebivel_id uuid, cliente_nome text, competencia date, entrada_centavos bigint, entrou_em date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.check_bot_secret(p_secret) then raise exception 'acesso negado'; end if;

  return query
  select r.id, c.nome, r.competencia, r.entrada_centavos, r.entrou_em
  from hub.recebiveis r
  join hub.clientes c on c.id = r.cliente_id
  where r.sincronizado_planilha = false and r.entrada_centavos > 0;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.bot_confirmar_sync(p_secret text, p_recebivel_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.check_bot_secret(p_secret) then raise exception 'acesso negado'; end if;
  update hub.recebiveis set sincronizado_planilha = true where id = p_recebivel_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_dash_periodo(p_desde date, p_ate date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_previsto bigint;
  v_entrado bigint;
  v_vencidos int;
  v_bucket text;
  v_series jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_desde is null or p_ate is null or p_desde > p_ate then
    raise exception 'período inválido';
  end if;

  select coalesce(sum(valor_centavos), 0), coalesce(sum(entrada_centavos), 0)
    into v_previsto, v_entrado
  from hub.recebiveis
  where vence_em between p_desde and p_ate;

  select count(*) into v_vencidos
  from hub.recebiveis
  where vence_em between p_desde and p_ate
    and vence_em < current_date
    and falta_centavos > 0;

  v_bucket := case when (p_ate - p_desde) <= 31 then 'dia' else 'mes' end;

  if v_bucket = 'dia' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'rotulo', to_char(d.dia, 'DD/MM'),
      'previsto_centavos', coalesce(r.previsto, 0),
      'entrado_centavos', coalesce(r.entrado, 0)
    ) order by d.dia), '[]'::jsonb) into v_series
    from generate_series(p_desde, p_ate, interval '1 day') d(dia)
    left join (
      select vence_em, sum(valor_centavos) previsto, sum(entrada_centavos) entrado
      from hub.recebiveis
      where vence_em between p_desde and p_ate
      group by vence_em
    ) r on r.vence_em = d.dia::date;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'rotulo', initcap(to_char(m.mes, 'Mon/YY')),
      'previsto_centavos', coalesce(r.previsto, 0),
      'entrado_centavos', coalesce(r.entrado, 0)
    ) order by m.mes), '[]'::jsonb) into v_series
    from generate_series(date_trunc('month', p_desde), date_trunc('month', p_ate), interval '1 month') m(mes)
    left join (
      select date_trunc('month', vence_em) as mes, sum(valor_centavos) previsto, sum(entrada_centavos) entrado
      from hub.recebiveis
      where vence_em between p_desde and p_ate
      group by 1
    ) r on r.mes = m.mes;
  end if;

  return jsonb_build_object(
    'desde', p_desde,
    'ate', p_ate,
    'previsto_centavos', v_previsto,
    'entrado_centavos', v_entrado,
    'falta_centavos', v_previsto - v_entrado,
    'vencidos_count', v_vencidos,
    'granularidade', v_bucket,
    'serie', v_series
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_empresas()
 RETURNS SETOF hub.empresas
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query select * from hub.empresas order by nome;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_demandas_cliente(p_cliente_id uuid)
 RETURNS SETOF hub.demandas
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select * from hub.demandas
  where cliente_id = p_cliente_id
  order by (status = 'entregue'), entrega_em nulls last, created_at;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.bot_registrar_envio(p_secret text, p_recebivel_id uuid, p_bucket text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_inserted boolean;
begin
  if not hub.check_bot_secret(p_secret) then raise exception 'acesso negado'; end if;

  insert into hub.cobranca_envios (recebivel_id, bucket)
  values (p_recebivel_id, p_bucket)
  on conflict (recebivel_id, bucket) do nothing
  returning true into v_inserted;

  return jsonb_build_object('registrado', coalesce(v_inserted, false));
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_demanda(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.demandas (id, cliente_id, titulo, descricao, entrega_em, status)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()),
    (p->>'cliente_id')::uuid,
    p->>'titulo',
    p->>'descricao',
    (p->>'entrega_em')::date,
    coalesce(p->>'status', 'aberta')
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, titulo=excluded.titulo, descricao=excluded.descricao,
    entrega_em=excluded.entrega_em, status=excluded.status
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_apagar_demanda(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.demandas where id = p_id;
  if not found then raise exception 'demanda não encontrada'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_desmarcar_pago(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.recebiveis
  set entrada_centavos = 0, entrou_em = null
  where id = p_id;

  if not found then
    raise exception 'recebível não encontrado';
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_apagar_contrato(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.contratos where id = p_id;
  if not found then raise exception 'contrato não encontrado'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_apagar_recebivel(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  delete from hub.recebiveis where id = p_id;
  if not found then raise exception 'recebível não encontrado'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_prospect(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_cobranca_mensagens()
 RETURNS SETOF hub.cobranca_mensagens
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select * from hub.cobranca_mensagens
  order by case etapa when 'd_menos_3' then 0 when 'd0' then 1 when 'd_mais_2' then 2 when 'd_mais_7' then 3 end;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_cobranca_envios_recentes(p_limit integer DEFAULT 20)
 RETURNS TABLE(cliente_id uuid, cliente_nome text, etapa text, enviado_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select c.id, c.nome, ce.bucket, ce.enviado_em
  from hub.cobranca_envios ce
  join hub.recebiveis r on r.id = ce.recebivel_id
  join hub.clientes c on c.id = r.cliente_id
  order by ce.enviado_em desc
  limit coalesce(p_limit, 20);
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_cobranca_config_lista()
 RETURNS TABLE(cliente_id uuid, cliente_nome text, config_id uuid, metodo text, ativo boolean, dia_vencimento smallint, whatsapp_e164 text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_cobranca_config(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.cobranca_config (id, cliente_id, metodo, ativo)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()),
    (p->>'cliente_id')::uuid,
    coalesce(p->>'metodo', 'pix'),
    coalesce((p->>'ativo')::boolean, true)
  )
  on conflict (cliente_id) do update set
    metodo=excluded.metodo, ativo=excluded.ativo
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_cobranca_mensagem(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  update hub.cobranca_mensagens
  set texto = p->>'texto'
  where etapa = p->>'etapa'
  returning id into v_id;

  if v_id is null then raise exception 'etapa de régua inválida'; end if;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.fone_norm(p_fone text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v text;
  v_ddd int;
  v_resto text;
begin
  if p_fone is null then
    return null;
  end if;

  v := split_part(p_fone, '@', 1);
  v := regexp_replace(v, '\D', '', 'g');

  if v = '' then
    return null;
  end if;

  if length(v) = 10 or (length(v) = 11 and left(v, 1) <> '1') then
    v := '55' || v;
  end if;

  if left(v, 2) = '55' and length(v) in (12, 13) then
    v_ddd := substring(v from 3 for 2)::int;
    v_resto := substring(v from 5);

    if v_ddd >= 31 and length(v_resto) = 9 and left(v_resto, 1) = '9' then
      v_resto := substring(v_resto from 2);
      v := '55' || lpad(v_ddd::text, 2, '0') || v_resto;
    end if;
  end if;

  return v;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.is_ingestor()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select hub.is_admin()
      or coalesce(auth.role(), '') = 'service_role'
      or current_user = 'service_role';
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_conversa_thread(p_fone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa hub.conversas;
  v_result jsonb;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p_fone);
  select * into v_conversa from hub.conversas where fone_norm = v_fone;
  if not found then return null; end if;

  select jsonb_build_object(
    'conversa', to_jsonb(v_conversa),
    'mensagens', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.enviada_em)
      from hub.mensagens m
      where m.conversa_id = v_conversa.id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_status_contrato(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.fone_no_crm(p_fone_norm text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select exists (
    select 1 from hub.prospects p
    where hub.fone_norm(p.contato_whatsapp) = p_fone_norm
  ) or exists (
    select 1 from hub.contatos c
    where hub.fone_norm(c.whatsapp_e164) = p_fone_norm
  );
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_registrar_mensagem(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_direcao text;
  v_corpo text;
  v_tipo text;
  v_enviada_em timestamptz;
  v_eh_grupo boolean;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  if not hub.fone_no_crm(v_fone) then
    return null;
  end if;

  v_direcao := coalesce(p->>'direcao', 'entrada');
  v_corpo := p->>'corpo';
  v_tipo := coalesce(p->>'tipo', 'texto');
  v_enviada_em := coalesce((p->>'enviada_em')::timestamptz, now());
  v_eh_grupo := coalesce((p->>'eh_grupo')::boolean, false);

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao, eh_grupo)
  values (
    v_fone,
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid,
    p->>'nome_exibicao',
    v_eh_grupo
  )
  on conflict (fone_norm) do update set
    prospect_id   = coalesce(excluded.prospect_id, hub.conversas.prospect_id),
    cliente_id    = coalesce(excluded.cliente_id, hub.conversas.cliente_id),
    nome_exibicao = coalesce(excluded.nome_exibicao, hub.conversas.nome_exibicao)
  returning id into v_conversa_id;

  insert into hub.mensagens (
    conversa_id, direcao, corpo, tipo, transcrito, enviada_em, evolution_msg_id,
    remetente_fone, remetente_nome
  )
  values (
    v_conversa_id, v_direcao, v_corpo, v_tipo,
    coalesce((p->>'transcrito')::boolean, false),
    v_enviada_em,
    p->>'evolution_msg_id',
    p->>'remetente_fone', p->>'remetente_nome'
  )
  on conflict (evolution_msg_id) do nothing
  returning id into v_msg_id;

  if v_msg_id is not null then
    update hub.conversas
    set ultima_msg_em = v_enviada_em,
        ultima_msg_previa = left(coalesce(v_corpo, '[' || v_tipo || ']'), 200),
        ultima_msg_direcao = v_direcao
    where id = v_conversa_id;
  end if;

  return v_conversa_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.crm_ids(p_fone_norm text)
 RETURNS TABLE(prospect_id uuid, cliente_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select
    (select p.id from hub.prospects p
      where hub.fone_norm(p.contato_whatsapp) = p_fone_norm
      order by coalesce(p.perdido, false) asc, p.created_at desc nulls last
      limit 1),
    (select c.cliente_id from hub.contatos c
      where hub.fone_norm(c.whatsapp_e164) = p_fone_norm
      order by coalesce(c.is_principal, false) desc
      limit 1);
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_eventos_agenda_do_contato(p jsonb)
 RETURNS SETOF hub.eventos_agenda
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_cliente uuid := (p->>'cliente_id')::uuid;
  v_prospect uuid := (p->>'prospect_id')::uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if v_cliente is null and v_prospect is null then
    raise exception 'informe cliente_id ou prospect_id';
  end if;
  return query
  select * from hub.eventos_agenda ea
  where (v_cliente is not null and ea.cliente_id = v_cliente)
     or (v_prospect is not null and ea.prospect_id = v_prospect)
  order by ea.criado_em desc;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_eventos_agenda_vincular(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_google_id text;
  v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_google_id := nullif(btrim(coalesce(p->>'google_event_id', '')), '');
  if v_google_id is null then raise exception 'google_event_id é obrigatório'; end if;

  insert into hub.eventos_agenda (google_event_id, cliente_id, prospect_id, criado_por)
  values (
    v_google_id,
    (p->>'cliente_id')::uuid,
    (p->>'prospect_id')::uuid,
    coalesce(p->>'criado_por', 'hub')
  )
  on conflict (google_event_id) do update set
    cliente_id  = excluded.cliente_id,
    prospect_id = excluded.prospect_id
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_marcar_envio(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_status text;
  v_evo_id text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_status := coalesce(p->>'status', 'erro');
  if v_status not in ('enviado', 'erro') then
    raise exception 'status inválido: %', v_status;
  end if;

  v_evo_id := nullif(p->>'evolution_msg_id', '');

  update hub.mensagens
  set status = v_status,
      erro   = case when v_status = 'erro'
                    then left(coalesce(p->>'erro', 'falha desconhecida'), 500)
                    else null end,
      evolution_msg_id = coalesce(v_evo_id, evolution_msg_id)
  where id = (p->>'msg_id')::uuid;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_contato(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
        v_cliente uuid := (p->>'cliente_id')::uuid;
        v_principal boolean := coalesce((p->>'is_principal')::boolean, false);
        v_papeis text[];
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_enfileirar_saida(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_corpo text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;
  v_corpo := p->>'corpo';

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao, eh_grupo)
  values (
    v_fone, (p->>'prospect_id')::uuid, (p->>'cliente_id')::uuid, p->>'nome_exibicao',
    coalesce((p->>'eh_grupo')::boolean, false)
  )
  on conflict (fone_norm) do update set
    prospect_id = coalesce(excluded.prospect_id, hub.conversas.prospect_id),
    cliente_id  = coalesce(excluded.cliente_id, hub.conversas.cliente_id)
  returning id into v_conversa_id;

  insert into hub.mensagens (conversa_id, direcao, corpo, tipo, status)
  values (v_conversa_id, 'saida', v_corpo, coalesce(p->>'tipo', 'texto'), 'enviando')
  returning id into v_msg_id;

  update hub.conversas
  set ultima_msg_em = now(),
      ultima_msg_previa = left(coalesce(v_corpo, ''), 200),
      ultima_msg_direcao = 'saida'
  where id = v_conversa_id;

  return v_msg_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_preparar_envio(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_msg_id uuid;
  v_fone text;
  v_eh_grupo boolean;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  v_msg_id := hub.rpc_enfileirar_saida(p);

  select eh_grupo into v_eh_grupo from hub.conversas where fone_norm = v_fone;

  return jsonb_build_object(
    'msg_id', v_msg_id, 'fone_norm', v_fone, 'eh_grupo', coalesce(v_eh_grupo, false)
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_criar_rascunho_reuniao_agenda(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_google_id text;
  v_mid text;
  v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_google_id := nullif(btrim(coalesce(p->>'google_event_id', '')), '');
  if v_google_id is null then raise exception 'google_event_id é obrigatório'; end if;
  v_mid := 'agenda-' || v_google_id;

  insert into hub.reunioes (meetily_meeting_id, titulo, realizada_em, prospect_id, cliente_id)
  values (
    v_mid,
    nullif(btrim(coalesce(p->>'titulo', '')), ''),
    (p->>'realizada_em')::timestamptz,
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid
  )
  on conflict (meetily_meeting_id) do nothing
  returning id into v_id;

  if v_id is null then
    select r.id into v_id from hub.reunioes r where r.meetily_meeting_id = v_mid;
  end if;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_apagar_servico(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_clientes text;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select string_agg(distinct cl.nome, ', ' order by cl.nome)
    into v_clientes
  from hub.contrato_itens ci
  join hub.contratos co on co.id = ci.contrato_id
  join hub.clientes  cl on cl.id = co.cliente_id
  where ci.servico_id = p_id;

  if v_clientes is not null then
    raise exception 'hub_servico_em_uso: %', v_clientes;
  end if;

  delete from hub.servicos where id = p_id;
  if not found then raise exception 'serviço não encontrado'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_arquivo_contrato(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.clientes (id, empresa_id, slug, nome, razao_social, documento, segmento, origem, status, entrou_em, saiu_em, motivo_saida, observacao, recorrente, endereco, tipo_cobranca, percentual_comissao)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'empresa_id')::uuid, p->>'slug', p->>'nome',
    p->>'razao_social', p->>'documento', p->>'segmento', p->>'origem',
    coalesce(p->>'status','ativo'), (p->>'entrou_em')::date, (p->>'saiu_em')::date, p->>'motivo_saida', p->>'observacao',
    coalesce((p->>'recorrente')::boolean, true), p->>'endereco',
    coalesce(p->>'tipo_cobranca', 'fixo'), (p->>'percentual_comissao')::numeric
  )
  on conflict (id) do update set
    empresa_id=excluded.empresa_id, slug=excluded.slug, nome=excluded.nome, razao_social=excluded.razao_social,
    documento=excluded.documento, segmento=excluded.segmento, origem=excluded.origem, status=excluded.status,
    entrou_em=excluded.entrou_em, saiu_em=excluded.saiu_em, motivo_saida=excluded.motivo_saida, observacao=excluded.observacao,
    recorrente=coalesce((p->>'recorrente')::boolean, hub.clientes.recorrente),
    endereco=case when p ? 'endereco' then p->>'endereco' else hub.clientes.endereco end,
    tipo_cobranca=case when p ? 'tipo_cobranca' then coalesce(p->>'tipo_cobranca', 'fixo') else hub.clientes.tipo_cobranca end,
    percentual_comissao=case when p ? 'percentual_comissao' then (p->>'percentual_comissao')::numeric else hub.clientes.percentual_comissao end
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_reunioes()
 RETURNS TABLE(id uuid, meetily_meeting_id text, titulo text, realizada_em timestamp with time zone, resumo text, prospect_id uuid, prospect_nome text, cliente_id uuid, cliente_nome text, cliente_slug text, tem_transcricao boolean, transcricao_chars integer, tem_analise boolean, criada_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    r.id,
    r.meetily_meeting_id,
    r.titulo,
    r.realizada_em,
    r.resumo,
    r.prospect_id,
    pr.nome,
    r.cliente_id,
    cl.nome,
    cl.slug,
    (r.transcricao is not null and r.transcricao <> '') as tem_transcricao,
    coalesce(length(r.transcricao), 0)                  as transcricao_chars,
    (r.analise is not null)                             as tem_analise,
    r.criada_em
  from hub.reunioes r
  left join hub.prospects pr on pr.id = r.prospect_id
  left join hub.clientes  cl on cl.id = r.cliente_id
  order by r.realizada_em desc nulls last, r.criada_em desc;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_reuniao(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v hub.reunioes;
  v_result jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  select * into v from hub.reunioes where id = p_id;
  if not found then return null; end if;

  select jsonb_build_object(
    'reuniao', to_jsonb(v),
    'prospect', (select to_jsonb(pr) from hub.prospects pr where pr.id = v.prospect_id),
    'cliente',  (select to_jsonb(cl) from hub.clientes  cl where cl.id = v.cliente_id)
  ) into v_result;

  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_registrar_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_ok boolean;
  v_mid text;
  v_id uuid;
begin
  v_ok := coalesce(hub.check_bot_secret(p->>'secret'), false) or hub.is_ingestor();
  p := p - 'secret';
  if not v_ok then raise exception 'acesso negado'; end if;

  v_mid := nullif(btrim(coalesce(p->>'meetily_meeting_id', '')), '');
  if v_mid is null then
    raise exception 'meetily_meeting_id é obrigatório';
  end if;

  insert into hub.reunioes (
    meetily_meeting_id, titulo, realizada_em,
    transcricao, resumo, key_points, action_items,
    prospect_id, cliente_id
  )
  values (
    v_mid,
    nullif(btrim(coalesce(p->>'titulo', '')), ''),
    (p->>'realizada_em')::timestamptz,
    nullif(p->>'transcricao', ''),
    nullif(p->>'resumo', ''),
    nullif(p->>'key_points', ''),
    nullif(p->>'action_items', ''),
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid
  )
  on conflict (meetily_meeting_id) do update set
    titulo       = coalesce(excluded.titulo,       hub.reunioes.titulo),
    realizada_em = coalesce(excluded.realizada_em, hub.reunioes.realizada_em),
    transcricao  = coalesce(excluded.transcricao,  hub.reunioes.transcricao),
    resumo       = coalesce(excluded.resumo,       hub.reunioes.resumo),
    key_points   = coalesce(excluded.key_points,   hub.reunioes.key_points),
    action_items = coalesce(excluded.action_items, hub.reunioes.action_items),
    prospect_id  = coalesce(hub.reunioes.prospect_id, excluded.prospect_id),
    cliente_id   = coalesce(hub.reunioes.cliente_id,  excluded.cliente_id)
  where
    hub.reunioes.titulo       is distinct from coalesce(excluded.titulo,       hub.reunioes.titulo)
    or hub.reunioes.realizada_em is distinct from coalesce(excluded.realizada_em, hub.reunioes.realizada_em)
    or hub.reunioes.transcricao  is distinct from coalesce(excluded.transcricao,  hub.reunioes.transcricao)
    or hub.reunioes.resumo       is distinct from coalesce(excluded.resumo,       hub.reunioes.resumo)
    or hub.reunioes.key_points   is distinct from coalesce(excluded.key_points,   hub.reunioes.key_points)
    or hub.reunioes.action_items is distinct from coalesce(excluded.action_items, hub.reunioes.action_items)
    or hub.reunioes.prospect_id  is distinct from coalesce(hub.reunioes.prospect_id, excluded.prospect_id)
    or hub.reunioes.cliente_id   is distinct from coalesce(hub.reunioes.cliente_id,  excluded.cliente_id)
  returning id into v_id;

  if v_id is null then
    select r.id into v_id from hub.reunioes r where r.meetily_meeting_id = v_mid;
  end if;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_amarrar_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_id uuid;
  v_prospect uuid;
  v_cliente uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_id := (p->>'id')::uuid;
  if v_id is null then raise exception 'id da reunião é obrigatório'; end if;

  v_prospect := (p->>'prospect_id')::uuid;
  v_cliente  := (p->>'cliente_id')::uuid;

  if v_prospect is not null and not exists (select 1 from hub.prospects where id = v_prospect) then
    raise exception 'prospect não encontrado';
  end if;
  if v_cliente is not null and not exists (select 1 from hub.clientes where id = v_cliente) then
    raise exception 'cliente não encontrado';
  end if;

  update hub.reunioes
  set prospect_id = v_prospect,
      cliente_id  = v_cliente
  where id = v_id
  returning id into v_id;

  if v_id is null then raise exception 'reunião não encontrada'; end if;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_analise(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_id uuid;
  v_analise jsonb;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_id := (p->>'id')::uuid;
  if v_id is null then raise exception 'id da reunião é obrigatório'; end if;

  v_analise := p->'analise';
  if v_analise is null or jsonb_typeof(v_analise) <> 'object' then
    raise exception 'analise precisa ser um objeto jsonb';
  end if;

  update hub.reunioes
  set analise = v_analise
  where id = v_id
  returning id into v_id;

  if v_id is null then raise exception 'reunião não encontrada'; end if;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_sugestao_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  update hub.conversas
  set sugestao_reuniao = p->'sugestao'
  where fone_norm = v_fone
  returning id into v_conversa_id;

  return v_conversa_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_limpar_sugestao_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_fone text;
  v_conversa_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  update hub.conversas
  set sugestao_reuniao = null
  where fone_norm = v_fone
  returning id into v_conversa_id;

  return v_conversa_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_conversas_resumo()
 RETURNS TABLE(fone_norm text, prospect_id uuid, cliente_id uuid, nome_exibicao text, ultima_msg_previa text, ultima_msg_em timestamp with time zone, ultima_msg_direcao text, nao_lida boolean, eh_grupo boolean, tem_sugestao_reuniao boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    c.fone_norm, c.prospect_id, c.cliente_id, c.nome_exibicao,
    c.ultima_msg_previa, c.ultima_msg_em, c.ultima_msg_direcao,
    coalesce(c.ultima_msg_direcao = 'entrada', false) as nao_lida,
    c.eh_grupo,
    (c.sugestao_reuniao is not null) as tem_sugestao_reuniao
  from hub.conversas c
  order by c.ultima_msg_em desc nulls last;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_eventos_agenda_desvincular(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_google_id text;
  v_mid text;
  v_rascunho_apagado boolean := false;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_google_id := nullif(btrim(coalesce(p->>'google_event_id', '')), '');
  if v_google_id is null then raise exception 'google_event_id é obrigatório'; end if;

  delete from hub.eventos_agenda where google_event_id = v_google_id;

  v_mid := 'agenda-' || v_google_id;
  delete from hub.reunioes
  where meetily_meeting_id = v_mid
    and transcricao  is null
    and resumo       is null
    and key_points    is null
    and action_items is null
    and analise      is null;
  if found then
    v_rascunho_apagado := true;
  end if;

  return jsonb_build_object('ok', true, 'rascunho_apagado', v_rascunho_apagado);
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_reativar_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_cliente_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_cliente_id := (p->>'cliente_id')::uuid;
  if v_cliente_id is null then raise exception 'cliente_id é obrigatório'; end if;

  update hub.clientes
  set status = 'ativo', saiu_em = null, motivo_saida = null
  where id = v_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;

  update hub.contratos
  set status = 'ativo'
  where cliente_id = v_cliente_id and status = 'arquivado';

  update hub.demandas
  set status = 'aberta'
  where cliente_id = v_cliente_id and status = 'arquivado';

  return v_cliente_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_carteira()
 RETURNS TABLE(cliente_id uuid, slug text, nome text, status text, recorrente boolean, servico text, valor_mensal_centavos bigint, dia_vencimento smallint, contrato_status text, tem_contrato boolean, tem_vencimento boolean, tem_whatsapp boolean, tipo_cobranca text, percentual_comissao numeric, demandas_abertas integer, demandas_atrasadas integer, demandas_previa jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  return query
  select
    c.id, c.slug, c.nome, c.status, c.recorrente,
    coalesce(
      (select string_agg(distinct ci.descricao, ' + ') from hub.contrato_itens ci where ci.contrato_id = ct.id),
      ct.observacao
    ) as servico,
    ct.valor_mensal_centavos, ct.dia_vencimento, ct.status,
    coalesce(ct.status in ('assinado','ativo'), false) as tem_contrato,
    (ct.dia_vencimento is not null) as tem_vencimento,
    (
      (select k.whatsapp_e164 from hub.contatos k
         where k.cliente_id = c.id and k.whatsapp_e164 is not null
         order by k.is_principal desc limit 1)
      is not null
    ) as tem_whatsapp,
    c.tipo_cobranca, c.percentual_comissao,
    coalesce(dm.abertas, 0) as demandas_abertas,
    coalesce(dm.atrasadas, 0) as demandas_atrasadas,
    coalesce(dm.previa, '[]'::jsonb) as demandas_previa
  from hub.clientes c

  left join lateral (
    select x.*
    from hub.contratos x
    where x.cliente_id = c.id
    order by
      case x.status
        when 'ativo'     then 0
        when 'assinado'  then 1
        when 'enviado'   then 2
        when 'emitido'   then 3
        when 'rascunho'  then 4
        when 'encerrado' then 5
        else 6
      end,
      (case when x.dia_vencimento is null then 1 else 0 end)
        + (case when x.valor_mensal_centavos is null then 1 else 0 end),
      x.created_at desc
    limit 1
  ) ct on true

  left join lateral (
    select
      (count(*) filter (where d.status <> 'entregue'))::int as abertas,
      (count(*) filter (
        where d.status <> 'entregue'
          and d.entrega_em is not null
          and d.entrega_em < current_date
      ))::int as atrasadas,
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'titulo',     p.titulo,
                   'entrega_em', p.entrega_em,
                   'status',     p.status
                 )
                 order by p.entrega_em asc nulls last, p.created_at asc
               )
        from (
          select d2.titulo, d2.entrega_em, d2.status, d2.created_at
          from hub.demandas d2
          where d2.cliente_id = c.id
            and d2.status <> 'entregue'
          order by d2.entrega_em asc nulls last, d2.created_at asc
          limit 2
        ) p
      ) as previa
    from hub.demandas d
    where d.cliente_id = c.id
  ) dm on true

  order by c.nome;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_arquivar_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_cliente_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_cliente_id := (p->>'cliente_id')::uuid;
  if v_cliente_id is null then raise exception 'cliente_id é obrigatório'; end if;

  update hub.clientes
  set status = 'encerrado',
      saiu_em = coalesce((p->>'saiu_em')::date, current_date),
      motivo_saida = nullif(btrim(coalesce(p->>'motivo_saida', '')), '')
  where id = v_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;

  update hub.contratos
  set status = 'arquivado'
  where cliente_id = v_cliente_id and status = 'ativo';

  update hub.demandas
  set status = 'arquivado'
  where cliente_id = v_cliente_id and status in ('aberta','fazendo');

  return v_cliente_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_garantir_recebiveis_mes(p_competencia date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_comp date;
  v_hoje date;
  v_piso date;
  v_ultimo_dia date;
  rec record;
  v_ja_existe boolean;
  v_legado_n int;
  v_legado_id uuid;
  v_base date;
  v_parcela_num int;
  v_descricao text;
  v_vence date;
  v_n int;
  v_criados int := 0;
  v_ajustados int := 0;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_competencia is null then raise exception 'competência é obrigatória'; end if;

  v_comp := date_trunc('month', p_competencia)::date;
  v_ultimo_dia := (v_comp + interval '1 month - 1 day')::date;

  v_hoje := (now() at time zone 'America/Recife')::date;
  v_piso := greatest(v_comp, date_trunc('month', v_hoje)::date);

  for rec in
    select ct.id as contrato_id, ct.cliente_id, ct.valor_mensal_centavos,
           ct.dia_vencimento, ct.parcelas_total, ct.inicio_em,
           count(*) over (partition by ct.cliente_id) as contratos_do_cliente
    from hub.contratos ct
    join hub.clientes cl on cl.id = ct.cliente_id
    where ct.status = 'ativo'
      and ct.recorrencia_ativa
      and ct.valor_mensal_centavos is not null
      and ct.valor_mensal_centavos > 0
      and coalesce(cl.recorrente, true) is not false
    order by ct.id
  loop


    select exists (
      select 1 from hub.recebiveis r
      where r.contrato_id = rec.contrato_id
        and date_trunc('month', r.competencia)::date = v_comp
    ) into v_ja_existe;

    if not v_ja_existe then
      select count(*), (array_agg(r.id order by r.id))[1] into v_legado_n, v_legado_id
      from hub.recebiveis r
      where r.cliente_id = rec.cliente_id
        and r.origem = 'contrato'
        and r.contrato_id is null
        and date_trunc('month', r.competencia)::date = v_comp;

      if v_legado_n = 1 and rec.contratos_do_cliente = 1 then
        update hub.recebiveis set contrato_id = rec.contrato_id where id = v_legado_id;

      elsif v_legado_n > 0 then
        null;

      else
        v_base := date_trunc('month', coalesce(
                    rec.inicio_em,
                    (select min(r.competencia) from hub.recebiveis r
                      where r.contrato_id = rec.contrato_id),
                    v_comp))::date;

        v_parcela_num := ((extract(year from v_comp)::int * 12 + extract(month from v_comp)::int)
                        - (extract(year from v_base)::int * 12 + extract(month from v_base)::int)) + 1;

        if v_parcela_num >= 1
           and (rec.parcelas_total is null or v_parcela_num <= rec.parcelas_total)
        then
          select ci.descricao into v_descricao
          from hub.contrato_itens ci
          where ci.contrato_id = rec.contrato_id
          order by ci.created_at asc
          limit 1;
          if v_descricao is null or btrim(v_descricao) = '' then
            v_descricao := 'Mensalidade';
          end if;
          if rec.parcelas_total is not null then
            v_descricao := v_descricao || ' — parcela ' || v_parcela_num || '/' || rec.parcelas_total;
          end if;

          v_vence := case when rec.dia_vencimento is not null
            then make_date(
              extract(year from v_comp)::int, extract(month from v_comp)::int,
              least(rec.dia_vencimento::int, extract(day from v_ultimo_dia)::int)
            )
            else null end;

          insert into hub.recebiveis
            (cliente_id, contrato_id, competencia, descricao, valor_centavos, vence_em, origem)
          values
            (rec.cliente_id, rec.contrato_id, v_comp, v_descricao, rec.valor_mensal_centavos, v_vence, 'contrato');

          v_criados := v_criados + 1;
        end if;
      end if;
    end if;

    update hub.recebiveis r
       set valor_centavos = rec.valor_mensal_centavos,
           sincronizado_planilha = false
     where r.contrato_id = rec.contrato_id
       and r.origem = 'contrato'
       and date_trunc('month', r.competencia)::date >= v_piso
       and coalesce(r.entrada_centavos, 0) = 0
       and r.entrou_em is null
       and not r.valor_travado
       and r.valor_centavos is distinct from rec.valor_mensal_centavos;

    get diagnostics v_n = row_count;
    v_ajustados := v_ajustados + v_n;

    if rec.dia_vencimento is not null then
      update hub.recebiveis r
         set vence_em = make_date(
               extract(year from r.competencia)::int, extract(month from r.competencia)::int,
               least(rec.dia_vencimento::int,
                     extract(day from (date_trunc('month', r.competencia) + interval '1 month - 1 day'))::int)),
             sincronizado_planilha = false
       where r.contrato_id = rec.contrato_id
         and r.origem = 'contrato'
         and r.vence_em is null
         and date_trunc('month', r.competencia)::date >= v_piso
         and coalesce(r.entrada_centavos, 0) = 0
         and r.entrou_em is null;

      get diagnostics v_n = row_count;
      v_ajustados := v_ajustados + v_n;
    end if;

  end loop;

  return v_criados + v_ajustados;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_contrato(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  if (p->>'id') is null
     and nullif(btrim(coalesce(p->>'numero','')), '') is null
     and nullif(btrim(coalesce(p->>'valor_mensal_centavos','')), '') is null
     and nullif(btrim(coalesce(p->>'dia_vencimento','')), '') is null
     and nullif(btrim(coalesce(p->>'observacao','')), '') is null
  then
    raise exception 'hub_contrato_vazio_nao_cria';
  end if;

  insert into hub.contratos (id, cliente_id, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_valor_centavos, porta_saida_escrita_em, observacao, parcelas_total, recorrencia_ativa)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, p->>'numero',
    coalesce(p->>'status','rascunho'), (p->>'inicio_em')::date, (p->>'fim_minimo_em')::date,
    (p->>'dia_vencimento')::smallint, (p->>'valor_mensal_centavos')::bigint, p->>'porta_saida_tipo',
    (p->>'porta_saida_valor_centavos')::bigint, (p->>'porta_saida_escrita_em')::timestamptz, p->>'observacao',
    nullif(p->>'parcelas_total','')::smallint, coalesce((p->>'recorrencia_ativa')::boolean, true)
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, numero=excluded.numero, status=excluded.status, inicio_em=excluded.inicio_em,
    fim_minimo_em=excluded.fim_minimo_em, dia_vencimento=excluded.dia_vencimento, valor_mensal_centavos=excluded.valor_mensal_centavos,
    porta_saida_tipo=excluded.porta_saida_tipo, porta_saida_valor_centavos=excluded.porta_saida_valor_centavos,
    porta_saida_escrita_em=excluded.porta_saida_escrita_em, observacao=excluded.observacao,
    parcelas_total=case when p ? 'parcelas_total' then nullif(p->>'parcelas_total','')::smallint else hub.contratos.parcelas_total end,
    recorrencia_ativa=case when p ? 'recorrencia_ativa' then coalesce((p->>'recorrencia_ativa')::boolean, true) else hub.contratos.recorrencia_ativa end
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_apagar_cliente(p_cliente_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_contratos int; v_recebiveis int; v_demandas int;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_cliente_id is null then raise exception 'cliente_id é obrigatório'; end if;

  select count(*) into v_contratos from hub.contratos where cliente_id = p_cliente_id;
  select count(*) into v_recebiveis from hub.recebiveis where cliente_id = p_cliente_id;
  select count(*) into v_demandas from hub.demandas where cliente_id = p_cliente_id;

  if v_contratos > 0 or v_recebiveis > 0 or v_demandas > 0 then
    raise exception 'hub_cliente_com_historico: % contrato(s), % recebível(is), % demanda(s) — arquive em vez de apagar.',
      v_contratos, v_recebiveis, v_demandas;
  end if;

  delete from hub.contatos where cliente_id = p_cliente_id;
  delete from hub.clientes where id = p_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_docuseal_marcar_enviado(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_docuseal_registrar_evento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_contrato hub.contratos;
  v_cliente_slug text;
  v_submission_id bigint;
  v_status text;
  v_audit_url text;
  v_assinado_em date;
  v_ativacao jsonb;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_submission_id := (p->>'docuseal_submission_id')::bigint;
  v_status := nullif(btrim(coalesce(p->>'status', '')), '');
  v_audit_url := nullif(btrim(coalesce(p->>'audit_log_url', '')), '');
  v_assinado_em := coalesce(nullif(p->>'assinado_em', '')::date,
                            (now() at time zone 'America/Recife')::date);
  if v_submission_id is null then raise exception 'docuseal_submission_id é obrigatório'; end if;
  if v_status is distinct from 'assinado' then
    raise exception 'status inválido pro webhook do DocuSeal: %', v_status;
  end if;

  select * into v_contrato from hub.contratos
   where docuseal_submission_id = v_submission_id
   for update;
  if v_contrato.id is null then
    raise exception 'nenhum contrato com docuseal_submission_id = %', v_submission_id;
  end if;

  update hub.contratos
     set docuseal_audit_log_url = coalesce(v_audit_url, docuseal_audit_log_url)
   where id = v_contrato.id;

  if v_contrato.status = 'ativo' then
    v_ativacao := jsonb_build_object('ja_estava_ativo', true);
  else
    begin
      v_ativacao := hub.ativar_contrato_assinado(v_contrato.id, v_assinado_em, false);
    exception when others then
      update hub.contratos set status = 'assinado', assinado_em = v_assinado_em
       where id = v_contrato.id and status not in ('encerrado','arquivado');
      v_ativacao := jsonb_build_object('ativado', false, 'erro', sqlerrm);
    end;
  end if;

  select cl.slug into v_cliente_slug from hub.clientes cl where cl.id = v_contrato.cliente_id;

  return jsonb_build_object('contrato_id', v_contrato.id, 'cliente_slug', v_cliente_slug,
                            'ativacao', v_ativacao);
end;
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_arquivo_contrato_ingestor(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_contratos()
 RETURNS TABLE(contrato_id uuid, numero text, status text, cliente_id uuid, cliente_nome text, cliente_slug text, servico text, valor_mensal_centavos bigint, dia_vencimento smallint, inicio_em date, fim_minimo_em date, porta_saida_tipo text, porta_saida_escrita_em timestamp with time zone, tem_arquivo boolean, arquivo_path text, arquivo_nome text, arquivo_em timestamp with time zone, docuseal_submission_id bigint, observacao text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION hub.rpc_salvar_recebivel(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_id uuid;
        v_comp date;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_comp := date_trunc('month', (p->>'competencia')::date)::date;
  if v_comp is null then raise exception 'competência é obrigatória'; end if;

  insert into hub.recebiveis (id, cliente_id, competencia, descricao, valor_centavos, entrada_centavos, entrou_em, vence_em, origem, observacao, valor_travado)
  values (coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, v_comp, p->>'descricao', (p->>'valor_centavos')::bigint, coalesce((p->>'entrada_centavos')::bigint, 0), (p->>'entrou_em')::date, (p->>'vence_em')::date, coalesce(p->>'origem','contrato'), p->>'observacao', coalesce((p->>'valor_travado')::boolean, false))
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, competencia=excluded.competencia, descricao=excluded.descricao,
    valor_centavos=excluded.valor_centavos, vence_em=excluded.vence_em, origem=excluded.origem,
    observacao=excluded.observacao, sincronizado_planilha=false,
    valor_travado = case
      when p ? 'valor_travado' then coalesce((p->>'valor_travado')::boolean, false)
      when hub.recebiveis.valor_centavos is distinct from excluded.valor_centavos then true
      else hub.recebiveis.valor_travado
    end
  returning id into v_id;

  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.hub_bot_cobrancas_do_dia(p_secret text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.bot_cobrancas_do_dia(p_secret); $function$
;
CREATE OR REPLACE FUNCTION public.hub_bot_confirmar_sync(p_secret text, p_recebivel_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.bot_confirmar_sync(p_secret, p_recebivel_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_bot_pagamentos_pendentes_sync(p_secret text)
 RETURNS TABLE(recebivel_id uuid, cliente_nome text, competencia date, entrada_centavos bigint, entrou_em date)
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.bot_pagamentos_pendentes_sync(p_secret); $function$
;
CREATE OR REPLACE FUNCTION public.hub_bot_registrar_envio(p_secret text, p_recebivel_id uuid, p_bucket text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.bot_registrar_envio(p_secret, p_recebivel_id, p_bucket); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_amarrar_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_amarrar_reuniao(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_apagar_cliente(p_cliente_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_apagar_cliente(p_cliente_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_apagar_contrato(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_apagar_contrato(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_apagar_demanda(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_apagar_demanda(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_apagar_prospect(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_apagar_prospect(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_apagar_recebivel(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_apagar_recebivel(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_apagar_servico(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_apagar_servico(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_arquivar_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_arquivar_cliente(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_arquivo_contrato(p jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_arquivo_contrato(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_arquivo_contrato_ingestor(p jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_arquivo_contrato_ingestor(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_carteira()
 RETURNS TABLE(cliente_id uuid, slug text, nome text, status text, recorrente boolean, servico text, valor_mensal_centavos bigint, dia_vencimento smallint, contrato_status text, tem_contrato boolean, tem_vencimento boolean, tem_whatsapp boolean, tipo_cobranca text, percentual_comissao numeric, demandas_abertas integer, demandas_atrasadas integer, demandas_previa jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_carteira(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_catalogo()
 RETURNS SETOF hub.servicos
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_catalogo(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_cliente(p_slug text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_cliente(p_slug); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_cobranca_config_lista()
 RETURNS TABLE(cliente_id uuid, cliente_nome text, config_id uuid, metodo text, ativo boolean, dia_vencimento smallint, whatsapp_e164 text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_cobranca_config_lista(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_cobranca_envios_recentes(p_limit integer)
 RETURNS TABLE(cliente_id uuid, cliente_nome text, etapa text, enviado_em timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_cobranca_envios_recentes(p_limit); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_cobranca_mensagens()
 RETURNS SETOF hub.cobranca_mensagens
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_cobranca_mensagens(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_contrato_assinado(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_contrato_assinado(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_contratos()
 RETURNS TABLE(contrato_id uuid, numero text, status text, cliente_id uuid, cliente_nome text, cliente_slug text, servico text, valor_mensal_centavos bigint, dia_vencimento smallint, inicio_em date, fim_minimo_em date, porta_saida_tipo text, porta_saida_escrita_em timestamp with time zone, tem_arquivo boolean, arquivo_path text, arquivo_nome text, arquivo_em timestamp with time zone, docuseal_submission_id bigint, observacao text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_contratos(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_conversa_thread(p_fone text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_conversa_thread(p_fone); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_conversas_resumo()
 RETURNS TABLE(fone_norm text, prospect_id uuid, cliente_id uuid, nome_exibicao text, ultima_msg_previa text, ultima_msg_em timestamp with time zone, ultima_msg_direcao text, nao_lida boolean, eh_grupo boolean, tem_sugestao_reuniao boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_conversas_resumo(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_converter_prospect_em_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_converter_prospect_em_cliente(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_criar_rascunho_reuniao_agenda(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_criar_rascunho_reuniao_agenda(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_custos()
 RETURNS SETOF hub.custos_fixos
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_custos(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_dash()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_dash(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_dash_periodo(p_desde date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_dash_periodo(p_desde, p_ate); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_demandas_cliente(p_cliente_id uuid)
 RETURNS SETOF hub.demandas
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_demandas_cliente(p_cliente_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_desmarcar_pago(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_desmarcar_pago(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_docuseal_marcar_enviado(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_docuseal_marcar_enviado(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_docuseal_registrar_evento(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_docuseal_registrar_evento(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_empresas()
 RETURNS SETOF hub.empresas
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_empresas(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_enfileirar_saida(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_enfileirar_saida(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_eventos_agenda_desvincular(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_eventos_agenda_desvincular(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_eventos_agenda_do_contato(p jsonb)
 RETURNS SETOF hub.eventos_agenda
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_eventos_agenda_do_contato(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_eventos_agenda_vincular(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_eventos_agenda_vincular(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_excluir_contato(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_excluir_contato(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_excluir_custo(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_excluir_custo(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_excluir_recebivel(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_excluir_recebivel(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_garantir_recebiveis_mes(p_competencia date)
 RETURNS integer
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_garantir_recebiveis_mes(p_competencia); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_limpar_sugestao_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_limpar_sugestao_reuniao(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_marcar_envio(p jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_marcar_envio(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_marcar_pago(p_id uuid, p_valor_centavos bigint, p_data date)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_marcar_pago(p_id, p_valor_centavos, p_data); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_novo_cliente(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_novo_cliente(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_preparar_envio(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_preparar_envio(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_prospect(p_id uuid)
 RETURNS hub.prospects
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_prospect(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_prospects()
 RETURNS SETOF hub.prospects
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_prospects(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_reativar_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_reativar_cliente(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_recebiveis(p_competencia date)
 RETURNS TABLE(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_recebiveis(p_competencia); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_recebiveis_cliente(p_cliente_id uuid)
 RETURNS TABLE(id uuid, cliente_id uuid, cliente_nome text, cliente_slug text, competencia date, descricao text, valor_centavos bigint, entrada_centavos bigint, falta_centavos bigint, entrou_em date, vence_em date, origem text, observacao text, contrato_id uuid, status text)
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_recebiveis_cliente(p_cliente_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_registrar_mensagem(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_registrar_mensagem(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_registrar_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_registrar_reuniao(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_reuniao(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_reuniao(p_id); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_reunioes()
 RETURNS TABLE(id uuid, meetily_meeting_id text, titulo text, realizada_em timestamp with time zone, resumo text, prospect_id uuid, prospect_nome text, cliente_id uuid, cliente_nome text, cliente_slug text, tem_transcricao boolean, transcricao_chars integer, tem_analise boolean, criada_em timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ select * from hub.rpc_reunioes(); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_analise(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_analise(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_cliente(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_cliente(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_cobranca_config(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_cobranca_config(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_cobranca_mensagem(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_cobranca_mensagem(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_contato(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_contato(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_contrato(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_contrato(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_custo(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_custo(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_demanda(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_demanda(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_prospect(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_prospect(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_rascunho(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_rascunho(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_recebivel(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_recebivel(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_servico(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_servico(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_salvar_sugestao_reuniao(p jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_salvar_sugestao_reuniao(p); $function$
;
CREATE OR REPLACE FUNCTION public.hub_rpc_status_contrato(p jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ select hub.rpc_status_contrato(p); $function$
;
alter table hub.cobranca_config enable row level security;
alter table hub.cobranca_mensagens enable row level security;
alter table hub.eventos_auditoria enable row level security;
alter table hub.demandas enable row level security;
alter table hub.empresas enable row level security;
alter table hub.workspaces enable row level security;
alter table hub.clientes enable row level security;
alter table hub.servicos enable row level security;
alter table hub.reunioes enable row level security;
alter table hub.conversas enable row level security;
alter table hub.contrato_itens enable row level security;
alter table hub.mensagens enable row level security;
alter table hub.contatos enable row level security;
alter table hub.contratos enable row level security;
alter table hub.custos_fixos enable row level security;
alter table hub.cobranca_envios enable row level security;
alter table hub.config enable row level security;
alter table hub.eventos_agenda enable row level security;
alter table hub.prospects enable row level security;
alter table hub.recebiveis enable row level security;
create policy hub_eventos_auditoria_admin_select on hub.eventos_auditoria for SELECT using (hub.is_admin());
create policy hub_empresas_admin_all on hub.empresas for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_clientes_admin_all on hub.clientes for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_contatos_admin_all on hub.contatos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_servicos_admin_all on hub.servicos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_contratos_admin_all on hub.contratos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_contrato_itens_admin_all on hub.contrato_itens for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_recebiveis_admin_all on hub.recebiveis for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_custos_fixos_admin_all on hub.custos_fixos for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_cobranca_envios_admin_select on hub.cobranca_envios for SELECT using (hub.is_admin());
create policy hub_demandas_admin_all on hub.demandas for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_workspaces_admin_all on hub.workspaces for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_prospects_admin_all on hub.prospects for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_cobranca_config_admin_all on hub.cobranca_config for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_cobranca_mensagens_admin_all on hub.cobranca_mensagens for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_conversas_admin_all on hub.conversas for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_mensagens_admin_all on hub.mensagens for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_reunioes_admin_all on hub.reunioes for ALL using (hub.is_admin()) with check (hub.is_admin());
create policy hub_eventos_agenda_admin_all on hub.eventos_agenda for ALL using (hub.is_admin()) with check (hub.is_admin());
CREATE TRIGGER trg_empresas_updated_at BEFORE UPDATE ON hub.empresas FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_empresas_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.empresas FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_clientes_updated_at BEFORE UPDATE ON hub.clientes FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_clientes_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.clientes FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_contatos_updated_at BEFORE UPDATE ON hub.contatos FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_contatos_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.contatos FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_servicos_updated_at BEFORE UPDATE ON hub.servicos FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_servicos_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.servicos FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_contratos_updated_at BEFORE UPDATE ON hub.contratos FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_contratos_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.contratos FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_contrato_itens_updated_at BEFORE UPDATE ON hub.contrato_itens FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_contrato_itens_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.contrato_itens FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_recebiveis_updated_at BEFORE UPDATE ON hub.recebiveis FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_recebiveis_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.recebiveis FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_custos_fixos_updated_at BEFORE UPDATE ON hub.custos_fixos FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_custos_fixos_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.custos_fixos FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_demandas_updated_at BEFORE UPDATE ON hub.demandas FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_demandas_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.demandas FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_workspaces_updated_at BEFORE UPDATE ON hub.workspaces FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_workspaces_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.workspaces FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_prospects_updated_at BEFORE UPDATE ON hub.prospects FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_prospects_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.prospects FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_cobranca_config_updated_at BEFORE UPDATE ON hub.cobranca_config FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_cobranca_config_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.cobranca_config FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_cobranca_mensagens_updated_at BEFORE UPDATE ON hub.cobranca_mensagens FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_cobranca_mensagens_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.cobranca_mensagens FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_conversas_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.conversas FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_mensagens_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.mensagens FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_reunioes_updated_at BEFORE UPDATE ON hub.reunioes FOR EACH ROW EXECUTE FUNCTION hub.set_updated_at();
CREATE TRIGGER trg_reunioes_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.reunioes FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
CREATE TRIGGER trg_eventos_agenda_auditoria AFTER INSERT OR DELETE OR UPDATE ON hub.eventos_agenda FOR EACH ROW EXECUTE FUNCTION hub.registrar_auditoria();
revoke all on schema hub from anon, authenticated, public; grant usage on schema hub to authenticated, service_role;
revoke all on function hub.default_workspace_id() from public;grant execute on function hub.default_workspace_id() to authenticated;
revoke all on function hub.default_empresa_id() from public;grant execute on function hub.default_empresa_id() to authenticated;
revoke all on function hub.rpc_apagar_prospect(uuid) from public;grant execute on function hub.rpc_apagar_prospect(uuid) to authenticated;
revoke all on function hub.rpc_converter_prospect_em_cliente(jsonb) from public;grant execute on function hub.rpc_converter_prospect_em_cliente(jsonb) to authenticated;
revoke all on function hub.rpc_recebiveis_cliente(uuid) from public;grant execute on function hub.rpc_recebiveis_cliente(uuid) to authenticated;
revoke all on function hub_rpc_recebiveis_cliente(uuid) from public;grant execute on function hub_rpc_recebiveis_cliente(uuid) to authenticated; grant execute on function hub_rpc_recebiveis_cliente(uuid) to service_role;
revoke all on function hub.mei_limites(integer) from public;
revoke all on function hub_rpc_salvar_demanda(jsonb) from public;grant execute on function hub_rpc_salvar_demanda(jsonb) to authenticated; grant execute on function hub_rpc_salvar_demanda(jsonb) to service_role;
revoke all on function hub_rpc_apagar_demanda(uuid) from public;grant execute on function hub_rpc_apagar_demanda(uuid) to authenticated; grant execute on function hub_rpc_apagar_demanda(uuid) to service_role;
revoke all on function hub_rpc_demandas_cliente(uuid) from public;grant execute on function hub_rpc_demandas_cliente(uuid) to authenticated; grant execute on function hub_rpc_demandas_cliente(uuid) to service_role;
revoke all on function hub_rpc_prospect(uuid) from public;grant execute on function hub_rpc_prospect(uuid) to authenticated; grant execute on function hub_rpc_prospect(uuid) to service_role;
revoke all on function hub_rpc_prospects() from public;grant execute on function hub_rpc_prospects() to authenticated; grant execute on function hub_rpc_prospects() to service_role;
revoke all on function hub.rpc_recebiveis(date) from public;grant execute on function hub.rpc_recebiveis(date) to authenticated;
revoke all on function hub.contato_do_papel(uuid,text,text) from public;
revoke all on function hub.prospect_com_contato_do_cliente(hub.prospects) from public;
revoke all on function hub.rpc_prospects() from public;grant execute on function hub.rpc_prospects() to authenticated;
revoke all on function hub.rpc_prospect(uuid) from public;grant execute on function hub.rpc_prospect(uuid) to authenticated;
revoke all on function hub.bot_cobrancas_do_dia(text) from public;grant execute on function hub.bot_cobrancas_do_dia(text) to anon; grant execute on function hub.bot_cobrancas_do_dia(text) to authenticated;
revoke all on function hub.ativar_contrato_assinado(uuid,date,boolean) from public;
revoke all on function hub.rpc_contrato_assinado(jsonb) from public;grant execute on function hub.rpc_contrato_assinado(jsonb) to authenticated;
revoke all on function hub.rpc_novo_cliente(jsonb) from public;grant execute on function hub.rpc_novo_cliente(jsonb) to authenticated;
revoke all on function hub_rpc_novo_cliente(jsonb) from public;grant execute on function hub_rpc_novo_cliente(jsonb) to authenticated; grant execute on function hub_rpc_novo_cliente(jsonb) to service_role;
revoke all on function hub_rpc_contrato_assinado(jsonb) from public;grant execute on function hub_rpc_contrato_assinado(jsonb) to authenticated; grant execute on function hub_rpc_contrato_assinado(jsonb) to service_role;
revoke all on function hub_rpc_salvar_prospect(jsonb) from public;grant execute on function hub_rpc_salvar_prospect(jsonb) to authenticated; grant execute on function hub_rpc_salvar_prospect(jsonb) to service_role;
revoke all on function hub_rpc_apagar_prospect(uuid) from public;grant execute on function hub_rpc_apagar_prospect(uuid) to authenticated; grant execute on function hub_rpc_apagar_prospect(uuid) to service_role;
revoke all on function hub_rpc_converter_prospect_em_cliente(jsonb) from public;grant execute on function hub_rpc_converter_prospect_em_cliente(jsonb) to authenticated; grant execute on function hub_rpc_converter_prospect_em_cliente(jsonb) to service_role;
revoke all on function hub_rpc_salvar_analise(jsonb) from public;grant execute on function hub_rpc_salvar_analise(jsonb) to authenticated; grant execute on function hub_rpc_salvar_analise(jsonb) to service_role;
revoke all on function hub_rpc_recebiveis(date) from public;grant execute on function hub_rpc_recebiveis(date) to authenticated; grant execute on function hub_rpc_recebiveis(date) to service_role;
revoke all on function hub_rpc_salvar_recebivel(jsonb) from public;grant execute on function hub_rpc_salvar_recebivel(jsonb) to authenticated; grant execute on function hub_rpc_salvar_recebivel(jsonb) to service_role;
revoke all on function hub_rpc_excluir_recebivel(uuid) from public;grant execute on function hub_rpc_excluir_recebivel(uuid) to authenticated; grant execute on function hub_rpc_excluir_recebivel(uuid) to service_role;
revoke all on function hub_rpc_custos() from public;grant execute on function hub_rpc_custos() to authenticated; grant execute on function hub_rpc_custos() to service_role;
revoke all on function hub_rpc_salvar_custo(jsonb) from public;grant execute on function hub_rpc_salvar_custo(jsonb) to authenticated; grant execute on function hub_rpc_salvar_custo(jsonb) to service_role;
revoke all on function hub_rpc_excluir_custo(uuid) from public;grant execute on function hub_rpc_excluir_custo(uuid) to authenticated; grant execute on function hub_rpc_excluir_custo(uuid) to service_role;
revoke all on function hub_rpc_dash() from public;grant execute on function hub_rpc_dash() to authenticated; grant execute on function hub_rpc_dash() to service_role;
revoke all on function hub_rpc_marcar_pago(uuid,bigint,date) from public;grant execute on function hub_rpc_marcar_pago(uuid,bigint,date) to authenticated; grant execute on function hub_rpc_marcar_pago(uuid,bigint,date) to service_role;
revoke all on function hub.rpc_salvar_rascunho(jsonb) from public;grant execute on function hub.rpc_salvar_rascunho(jsonb) to authenticated; grant execute on function hub.rpc_salvar_rascunho(jsonb) to service_role;
revoke all on function hub_rpc_salvar_contato(jsonb) from public;grant execute on function hub_rpc_salvar_contato(jsonb) to authenticated; grant execute on function hub_rpc_salvar_contato(jsonb) to service_role;
revoke all on function hub_rpc_excluir_contato(uuid) from public;grant execute on function hub_rpc_excluir_contato(uuid) to authenticated; grant execute on function hub_rpc_excluir_contato(uuid) to service_role;
revoke all on function hub_bot_cobrancas_do_dia(text) from public;grant execute on function hub_bot_cobrancas_do_dia(text) to anon; grant execute on function hub_bot_cobrancas_do_dia(text) to authenticated; grant execute on function hub_bot_cobrancas_do_dia(text) to service_role;
revoke all on function hub_bot_pagamentos_pendentes_sync(text) from public;grant execute on function hub_bot_pagamentos_pendentes_sync(text) to anon; grant execute on function hub_bot_pagamentos_pendentes_sync(text) to authenticated; grant execute on function hub_bot_pagamentos_pendentes_sync(text) to service_role;
revoke all on function hub_bot_confirmar_sync(text,uuid) from public;grant execute on function hub_bot_confirmar_sync(text,uuid) to anon; grant execute on function hub_bot_confirmar_sync(text,uuid) to authenticated; grant execute on function hub_bot_confirmar_sync(text,uuid) to service_role;
revoke all on function hub_rpc_cobranca_envios_recentes(integer) from public;grant execute on function hub_rpc_cobranca_envios_recentes(integer) to authenticated; grant execute on function hub_rpc_cobranca_envios_recentes(integer) to service_role;
revoke all on function hub_rpc_cobranca_config_lista() from public;grant execute on function hub_rpc_cobranca_config_lista() to authenticated; grant execute on function hub_rpc_cobranca_config_lista() to service_role;
revoke all on function hub_rpc_salvar_cobranca_config(jsonb) from public;grant execute on function hub_rpc_salvar_cobranca_config(jsonb) to authenticated; grant execute on function hub_rpc_salvar_cobranca_config(jsonb) to service_role;
revoke all on function hub_rpc_cobranca_mensagens() from public;grant execute on function hub_rpc_cobranca_mensagens() to authenticated; grant execute on function hub_rpc_cobranca_mensagens() to service_role;
revoke all on function hub_rpc_salvar_cobranca_mensagem(jsonb) from public;grant execute on function hub_rpc_salvar_cobranca_mensagem(jsonb) to authenticated; grant execute on function hub_rpc_salvar_cobranca_mensagem(jsonb) to service_role;
revoke all on function hub_rpc_salvar_cliente(jsonb) from public;grant execute on function hub_rpc_salvar_cliente(jsonb) to authenticated; grant execute on function hub_rpc_salvar_cliente(jsonb) to service_role;
revoke all on function hub_rpc_salvar_contrato(jsonb) from public;grant execute on function hub_rpc_salvar_contrato(jsonb) to authenticated; grant execute on function hub_rpc_salvar_contrato(jsonb) to service_role;
revoke all on function hub_rpc_salvar_servico(jsonb) from public;grant execute on function hub_rpc_salvar_servico(jsonb) to authenticated; grant execute on function hub_rpc_salvar_servico(jsonb) to service_role;
revoke all on function hub_rpc_limpar_sugestao_reuniao(jsonb) from public;grant execute on function hub_rpc_limpar_sugestao_reuniao(jsonb) to authenticated; grant execute on function hub_rpc_limpar_sugestao_reuniao(jsonb) to service_role;
revoke all on function hub_rpc_eventos_agenda_vincular(jsonb) from public;grant execute on function hub_rpc_eventos_agenda_vincular(jsonb) to authenticated; grant execute on function hub_rpc_eventos_agenda_vincular(jsonb) to service_role;
revoke all on function hub_rpc_eventos_agenda_do_contato(jsonb) from public;grant execute on function hub_rpc_eventos_agenda_do_contato(jsonb) to authenticated; grant execute on function hub_rpc_eventos_agenda_do_contato(jsonb) to service_role;
revoke all on function hub_rpc_criar_rascunho_reuniao_agenda(jsonb) from public;grant execute on function hub_rpc_criar_rascunho_reuniao_agenda(jsonb) to authenticated; grant execute on function hub_rpc_criar_rascunho_reuniao_agenda(jsonb) to service_role;
revoke all on function hub_rpc_salvar_sugestao_reuniao(jsonb) from public;grant execute on function hub_rpc_salvar_sugestao_reuniao(jsonb) to authenticated; grant execute on function hub_rpc_salvar_sugestao_reuniao(jsonb) to service_role; grant execute on function hub_rpc_salvar_sugestao_reuniao(jsonb) to anon;
revoke all on function hub.rpc_cliente(text) from public;grant execute on function hub.rpc_cliente(text) to authenticated;
revoke all on function hub.rpc_excluir_recebivel(uuid) from public;grant execute on function hub.rpc_excluir_recebivel(uuid) to authenticated;
revoke all on function hub.rpc_salvar_servico(jsonb) from public;grant execute on function hub.rpc_salvar_servico(jsonb) to authenticated;
revoke all on function hub.rpc_catalogo() from public;grant execute on function hub.rpc_catalogo() to authenticated;
revoke all on function hub_rpc_catalogo() from public;grant execute on function hub_rpc_catalogo() to authenticated; grant execute on function hub_rpc_catalogo() to service_role;
revoke all on function hub_rpc_cliente(text) from public;grant execute on function hub_rpc_cliente(text) to authenticated; grant execute on function hub_rpc_cliente(text) to service_role;
revoke all on function hub.rpc_dash() from public;grant execute on function hub.rpc_dash() to authenticated;
revoke all on function hub.rpc_marcar_pago(uuid,bigint,date) from public;grant execute on function hub.rpc_marcar_pago(uuid,bigint,date) to authenticated;
revoke all on function hub.rpc_custos() from public;grant execute on function hub.rpc_custos() to authenticated;
revoke all on function hub.rpc_salvar_custo(jsonb) from public;grant execute on function hub.rpc_salvar_custo(jsonb) to authenticated;
revoke all on function hub.rpc_excluir_custo(uuid) from public;grant execute on function hub.rpc_excluir_custo(uuid) to authenticated;
revoke all on function hub.rpc_excluir_contato(uuid) from public;grant execute on function hub.rpc_excluir_contato(uuid) to authenticated;
revoke all on function hub.bot_pagamentos_pendentes_sync(text) from public;grant execute on function hub.bot_pagamentos_pendentes_sync(text) to anon; grant execute on function hub.bot_pagamentos_pendentes_sync(text) to authenticated;
revoke all on function hub.bot_confirmar_sync(text,uuid) from public;grant execute on function hub.bot_confirmar_sync(text,uuid) to anon; grant execute on function hub.bot_confirmar_sync(text,uuid) to authenticated;
revoke all on function hub.rpc_dash_periodo(date,date) from public;grant execute on function hub.rpc_dash_periodo(date,date) to authenticated;
revoke all on function hub_rpc_dash_periodo(date,date) from public;grant execute on function hub_rpc_dash_periodo(date,date) to authenticated; grant execute on function hub_rpc_dash_periodo(date,date) to service_role;
revoke all on function hub_rpc_desmarcar_pago(uuid) from public;grant execute on function hub_rpc_desmarcar_pago(uuid) to authenticated; grant execute on function hub_rpc_desmarcar_pago(uuid) to service_role;
revoke all on function hub.rpc_empresas() from public;grant execute on function hub.rpc_empresas() to authenticated;
revoke all on function hub_rpc_empresas() from public;grant execute on function hub_rpc_empresas() to authenticated; grant execute on function hub_rpc_empresas() to service_role;
revoke all on function hub.rpc_demandas_cliente(uuid) from public;grant execute on function hub.rpc_demandas_cliente(uuid) to authenticated;
revoke all on function hub.bot_registrar_envio(text,uuid,text) from public;grant execute on function hub.bot_registrar_envio(text,uuid,text) to anon; grant execute on function hub.bot_registrar_envio(text,uuid,text) to authenticated;
revoke all on function hub_bot_registrar_envio(text,uuid,text) from public;grant execute on function hub_bot_registrar_envio(text,uuid,text) to anon; grant execute on function hub_bot_registrar_envio(text,uuid,text) to authenticated; grant execute on function hub_bot_registrar_envio(text,uuid,text) to service_role;
revoke all on function hub.rpc_salvar_demanda(jsonb) from public;grant execute on function hub.rpc_salvar_demanda(jsonb) to authenticated;
revoke all on function hub.rpc_apagar_demanda(uuid) from public;grant execute on function hub.rpc_apagar_demanda(uuid) to authenticated;
revoke all on function hub.rpc_desmarcar_pago(uuid) from public;grant execute on function hub.rpc_desmarcar_pago(uuid) to authenticated;
revoke all on function hub.rpc_apagar_contrato(uuid) from public;grant execute on function hub.rpc_apagar_contrato(uuid) to authenticated;
revoke all on function hub_rpc_apagar_contrato(uuid) from public;grant execute on function hub_rpc_apagar_contrato(uuid) to authenticated; grant execute on function hub_rpc_apagar_contrato(uuid) to service_role;
revoke all on function hub.rpc_apagar_recebivel(uuid) from public;grant execute on function hub.rpc_apagar_recebivel(uuid) to authenticated;
revoke all on function hub_rpc_apagar_recebivel(uuid) from public;grant execute on function hub_rpc_apagar_recebivel(uuid) to authenticated; grant execute on function hub_rpc_apagar_recebivel(uuid) to service_role;
revoke all on function hub.rpc_salvar_prospect(jsonb) from public;grant execute on function hub.rpc_salvar_prospect(jsonb) to authenticated;
revoke all on function hub.rpc_cobranca_mensagens() from public;grant execute on function hub.rpc_cobranca_mensagens() to authenticated;
revoke all on function hub.rpc_cobranca_envios_recentes(integer) from public;grant execute on function hub.rpc_cobranca_envios_recentes(integer) to authenticated;
revoke all on function hub.rpc_cobranca_config_lista() from public;grant execute on function hub.rpc_cobranca_config_lista() to authenticated;
revoke all on function hub.rpc_salvar_cobranca_config(jsonb) from public;grant execute on function hub.rpc_salvar_cobranca_config(jsonb) to authenticated;
revoke all on function hub.rpc_salvar_cobranca_mensagem(jsonb) from public;grant execute on function hub.rpc_salvar_cobranca_mensagem(jsonb) to authenticated;
revoke all on function hub.fone_norm(text) from public;grant execute on function hub.fone_norm(text) to authenticated; grant execute on function hub.fone_norm(text) to service_role;
revoke all on function hub.is_ingestor() from public;grant execute on function hub.is_ingestor() to authenticated; grant execute on function hub.is_ingestor() to service_role;
revoke all on function hub.rpc_conversa_thread(text) from public;grant execute on function hub.rpc_conversa_thread(text) to authenticated; grant execute on function hub.rpc_conversa_thread(text) to service_role;
revoke all on function hub.rpc_status_contrato(jsonb) from public;grant execute on function hub.rpc_status_contrato(jsonb) to authenticated;
revoke all on function hub_rpc_status_contrato(jsonb) from public;grant execute on function hub_rpc_status_contrato(jsonb) to authenticated; grant execute on function hub_rpc_status_contrato(jsonb) to service_role;
revoke all on function hub_rpc_conversa_thread(text) from public;grant execute on function hub_rpc_conversa_thread(text) to authenticated; grant execute on function hub_rpc_conversa_thread(text) to service_role;
revoke all on function hub_rpc_registrar_mensagem(jsonb) from public;grant execute on function hub_rpc_registrar_mensagem(jsonb) to authenticated; grant execute on function hub_rpc_registrar_mensagem(jsonb) to service_role;
revoke all on function hub_rpc_enfileirar_saida(jsonb) from public;grant execute on function hub_rpc_enfileirar_saida(jsonb) to authenticated; grant execute on function hub_rpc_enfileirar_saida(jsonb) to service_role;
revoke all on function hub_rpc_salvar_rascunho(jsonb) from public;grant execute on function hub_rpc_salvar_rascunho(jsonb) to authenticated; grant execute on function hub_rpc_salvar_rascunho(jsonb) to service_role;
revoke all on function hub.fone_no_crm(text) from public;grant execute on function hub.fone_no_crm(text) to authenticated; grant execute on function hub.fone_no_crm(text) to service_role;
revoke all on function hub.rpc_registrar_mensagem(jsonb) from public;grant execute on function hub.rpc_registrar_mensagem(jsonb) to authenticated; grant execute on function hub.rpc_registrar_mensagem(jsonb) to service_role;
revoke all on function hub.crm_ids(text) from public;grant execute on function hub.crm_ids(text) to authenticated; grant execute on function hub.crm_ids(text) to service_role;
revoke all on function hub_rpc_preparar_envio(jsonb) from public;grant execute on function hub_rpc_preparar_envio(jsonb) to authenticated; grant execute on function hub_rpc_preparar_envio(jsonb) to service_role;
revoke all on function hub_rpc_marcar_envio(jsonb) from public;grant execute on function hub_rpc_marcar_envio(jsonb) to authenticated; grant execute on function hub_rpc_marcar_envio(jsonb) to service_role;
revoke all on function hub.rpc_eventos_agenda_do_contato(jsonb) from public;grant execute on function hub.rpc_eventos_agenda_do_contato(jsonb) to authenticated;
revoke all on function hub.rpc_eventos_agenda_vincular(jsonb) from public;grant execute on function hub.rpc_eventos_agenda_vincular(jsonb) to authenticated;
revoke all on function hub.rpc_marcar_envio(jsonb) from public;grant execute on function hub.rpc_marcar_envio(jsonb) to authenticated;
revoke all on function hub.rpc_salvar_contato(jsonb) from public;grant execute on function hub.rpc_salvar_contato(jsonb) to authenticated;
revoke all on function hub.rpc_enfileirar_saida(jsonb) from public;grant execute on function hub.rpc_enfileirar_saida(jsonb) to authenticated;
revoke all on function hub.rpc_preparar_envio(jsonb) from public;grant execute on function hub.rpc_preparar_envio(jsonb) to authenticated;
revoke all on function hub.rpc_criar_rascunho_reuniao_agenda(jsonb) from public;grant execute on function hub.rpc_criar_rascunho_reuniao_agenda(jsonb) to authenticated;
revoke all on function hub.rpc_apagar_servico(uuid) from public;grant execute on function hub.rpc_apagar_servico(uuid) to authenticated;
revoke all on function hub_rpc_apagar_servico(uuid) from public;grant execute on function hub_rpc_apagar_servico(uuid) to authenticated; grant execute on function hub_rpc_apagar_servico(uuid) to service_role;
revoke all on function hub.rpc_arquivo_contrato(jsonb) from public;grant execute on function hub.rpc_arquivo_contrato(jsonb) to authenticated;
revoke all on function hub_rpc_arquivo_contrato(jsonb) from public;grant execute on function hub_rpc_arquivo_contrato(jsonb) to authenticated; grant execute on function hub_rpc_arquivo_contrato(jsonb) to service_role;
revoke all on function hub.rpc_salvar_cliente(jsonb) from public;grant execute on function hub.rpc_salvar_cliente(jsonb) to authenticated;
revoke all on function hub.rpc_reunioes() from public;grant execute on function hub.rpc_reunioes() to authenticated;
revoke all on function hub.rpc_reuniao(uuid) from public;grant execute on function hub.rpc_reuniao(uuid) to authenticated;
revoke all on function hub.rpc_registrar_reuniao(jsonb) from public;grant execute on function hub.rpc_registrar_reuniao(jsonb) to authenticated; grant execute on function hub.rpc_registrar_reuniao(jsonb) to service_role;
revoke all on function hub_rpc_amarrar_reuniao(jsonb) from public;grant execute on function hub_rpc_amarrar_reuniao(jsonb) to authenticated; grant execute on function hub_rpc_amarrar_reuniao(jsonb) to service_role;
revoke all on function hub.rpc_amarrar_reuniao(jsonb) from public;grant execute on function hub.rpc_amarrar_reuniao(jsonb) to authenticated;
revoke all on function hub.rpc_salvar_analise(jsonb) from public;grant execute on function hub.rpc_salvar_analise(jsonb) to authenticated;
revoke all on function hub_rpc_registrar_reuniao(jsonb) from public;grant execute on function hub_rpc_registrar_reuniao(jsonb) to authenticated; grant execute on function hub_rpc_registrar_reuniao(jsonb) to service_role; grant execute on function hub_rpc_registrar_reuniao(jsonb) to anon;
revoke all on function hub_rpc_reunioes() from public;grant execute on function hub_rpc_reunioes() to authenticated; grant execute on function hub_rpc_reunioes() to service_role;
revoke all on function hub_rpc_reuniao(uuid) from public;grant execute on function hub_rpc_reuniao(uuid) to authenticated; grant execute on function hub_rpc_reuniao(uuid) to service_role;
revoke all on function hub.rpc_salvar_sugestao_reuniao(jsonb) from public;grant execute on function hub.rpc_salvar_sugestao_reuniao(jsonb) to authenticated; grant execute on function hub.rpc_salvar_sugestao_reuniao(jsonb) to service_role;
revoke all on function hub.rpc_limpar_sugestao_reuniao(jsonb) from public;grant execute on function hub.rpc_limpar_sugestao_reuniao(jsonb) to authenticated;
revoke all on function hub.rpc_conversas_resumo() from public;grant execute on function hub.rpc_conversas_resumo() to authenticated;
revoke all on function hub.rpc_eventos_agenda_desvincular(jsonb) from public;grant execute on function hub.rpc_eventos_agenda_desvincular(jsonb) to authenticated;
revoke all on function hub_rpc_conversas_resumo() from public;grant execute on function hub_rpc_conversas_resumo() to authenticated; grant execute on function hub_rpc_conversas_resumo() to service_role;
revoke all on function hub_rpc_eventos_agenda_desvincular(jsonb) from public;grant execute on function hub_rpc_eventos_agenda_desvincular(jsonb) to authenticated; grant execute on function hub_rpc_eventos_agenda_desvincular(jsonb) to service_role;
revoke all on function hub.rpc_reativar_cliente(jsonb) from public;grant execute on function hub.rpc_reativar_cliente(jsonb) to authenticated;
revoke all on function hub_rpc_arquivar_cliente(jsonb) from public;grant execute on function hub_rpc_arquivar_cliente(jsonb) to authenticated; grant execute on function hub_rpc_arquivar_cliente(jsonb) to service_role;
revoke all on function hub_rpc_reativar_cliente(jsonb) from public;grant execute on function hub_rpc_reativar_cliente(jsonb) to authenticated; grant execute on function hub_rpc_reativar_cliente(jsonb) to service_role;
revoke all on function hub.rpc_carteira() from public;grant execute on function hub.rpc_carteira() to authenticated;
revoke all on function hub_rpc_carteira() from public;grant execute on function hub_rpc_carteira() to authenticated; grant execute on function hub_rpc_carteira() to service_role;
revoke all on function hub.rpc_arquivar_cliente(jsonb) from public;grant execute on function hub.rpc_arquivar_cliente(jsonb) to authenticated;
revoke all on function hub_rpc_arquivo_contrato_ingestor(jsonb) from public;grant execute on function hub_rpc_arquivo_contrato_ingestor(jsonb) to service_role;
revoke all on function hub.rpc_garantir_recebiveis_mes(date) from public;grant execute on function hub.rpc_garantir_recebiveis_mes(date) to authenticated;
revoke all on function hub_rpc_garantir_recebiveis_mes(date) from public;grant execute on function hub_rpc_garantir_recebiveis_mes(date) to authenticated; grant execute on function hub_rpc_garantir_recebiveis_mes(date) to service_role;
revoke all on function hub.rpc_salvar_contrato(jsonb) from public;grant execute on function hub.rpc_salvar_contrato(jsonb) to authenticated;
revoke all on function hub.rpc_apagar_cliente(uuid) from public;grant execute on function hub.rpc_apagar_cliente(uuid) to authenticated;
revoke all on function hub_rpc_apagar_cliente(uuid) from public;grant execute on function hub_rpc_apagar_cliente(uuid) to authenticated; grant execute on function hub_rpc_apagar_cliente(uuid) to service_role;
revoke all on function hub.rpc_docuseal_marcar_enviado(jsonb) from public;grant execute on function hub.rpc_docuseal_marcar_enviado(jsonb) to authenticated;
revoke all on function hub_rpc_docuseal_marcar_enviado(jsonb) from public;grant execute on function hub_rpc_docuseal_marcar_enviado(jsonb) to authenticated; grant execute on function hub_rpc_docuseal_marcar_enviado(jsonb) to service_role;
revoke all on function hub.rpc_docuseal_registrar_evento(jsonb) from public;grant execute on function hub.rpc_docuseal_registrar_evento(jsonb) to service_role;
revoke all on function hub_rpc_docuseal_registrar_evento(jsonb) from public;grant execute on function hub_rpc_docuseal_registrar_evento(jsonb) to service_role;
revoke all on function hub.rpc_arquivo_contrato_ingestor(jsonb) from public;grant execute on function hub.rpc_arquivo_contrato_ingestor(jsonb) to service_role;
revoke all on function hub.rpc_contratos() from public;grant execute on function hub.rpc_contratos() to authenticated;
revoke all on function hub_rpc_contratos() from public;grant execute on function hub_rpc_contratos() to authenticated; grant execute on function hub_rpc_contratos() to service_role;
revoke all on function hub.rpc_salvar_recebivel(jsonb) from public;grant execute on function hub.rpc_salvar_recebivel(jsonb) to authenticated;
set check_function_bodies = on;
create policy hub_contratos_admin_select on storage.objects for select using ((bucket_id = 'contratos'::text) and hub.is_admin());
create policy hub_contratos_admin_insert on storage.objects for insert with check ((bucket_id = 'contratos'::text) and hub.is_admin());
create policy hub_contratos_admin_update on storage.objects for update using ((bucket_id = 'contratos'::text) and hub.is_admin()) with check ((bucket_id = 'contratos'::text) and hub.is_admin());
create policy hub_contratos_admin_delete on storage.objects for delete using ((bucket_id = 'contratos'::text) and hub.is_admin());
