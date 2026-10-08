-- ============================================================
-- HUB — 050: base multi-empresa (ETAPA 1 de 3, ADITIVA)
--
-- ⚠️ DRAFT — NÃO APLICAR. Depende do /grill-me de banco com a Luciana
-- (perguntas em docs/multi-empresa.md §10). Testada só em PGlite.
--
-- O que faz: cria as tabelas de conta (membros, convites, módulos, canais,
-- aceite de termos, trilha de acesso a dado fiscal, admins da plataforma),
-- o perfil fiscal em hub.empresas, os helpers de workspace e as RPCs de
-- convite/onboarding.
-- O que NÃO faz: não troca nenhuma policy, nenhum default, nenhuma RPC
-- existente. Depois desta migration o Hub dela funciona exatamente igual.
-- Reverter: migrations/rollback/050_down.sql
--
-- Depende de: 010 (hub.workspaces) e do schema real de produção.
-- Numeração 050+ reservada pra não colidir com a tela "Novo cliente" (041+).
-- ============================================================

-- ---------- auditoria: aguenta tabela sem coluna `id` ----------
-- (hub.workspace_modulos tem PK composta; o trigger da 037 lia new.id e quebrava)
create or replace function hub.registrar_auditoria()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_novo jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
  v_velho jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_id text := coalesce(v_novo->>'id', v_velho->>'id');
begin
  insert into hub.eventos_auditoria (tabela, registro_id, acao, dados_antes, dados_depois, ator_email)
  values (
    tg_table_name,
    case when v_id ~ '^[0-9a-f-]{36}$' then v_id::uuid end,
    lower(tg_op),
    v_velho,
    v_novo,
    coalesce(auth.email(), 'sistema')
  );
  return coalesce(new, old);
end;
$$;

-- ---------- workspaces: estado da conta e vagas ----------
alter table hub.workspaces
  add column if not exists status text not null default 'ativo'
    check (status in ('onboarding','ativo','suspenso','encerrado')),
  add column if not exists vagas smallint not null default 3 check (vagas between 1 and 50),
  add column if not exists criado_por uuid;

-- ---------- admins da plataforma (Luciana, Isa) ----------
-- Criam empresa e mandam convite. NÃO enxergam dado de cliente por serem
-- admin: pra ver um workspace, precisam ser membro dele (pergunta P3).
create table hub.plataforma_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);
alter table hub.plataforma_admins enable row level security;
-- sem policy: só função SECURITY DEFINER lê

-- ---------- membros e papéis ----------
create table hub.workspace_membros (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  papel text not null check (papel in ('dono','operador','consulta')),
  eh_contador boolean not null default false,
  -- contador do cliente entra como Consulta e não ocupa vaga (grill 06/10)
  ocupa_vaga boolean generated always as (not eh_contador) stored,
  ativo boolean not null default true,
  convite_id uuid,
  criado_em timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workspace_membros_unico unique (workspace_id, user_id),
  constraint contador_e_consulta check (not eh_contador or papel = 'consulta')
);
create index idx_workspace_membros_user on hub.workspace_membros (user_id) where ativo;
alter table hub.workspace_membros enable row level security;

create trigger trg_workspace_membros_updated_at before update on hub.workspace_membros
  for each row execute function hub.set_updated_at();
create trigger trg_workspace_membros_auditoria after insert or update or delete on hub.workspace_membros
  for each row execute function hub.registrar_auditoria();

-- vagas + sempre 1 dono ativo
create or replace function hub.trg_membros_regras()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_vagas smallint;
  v_ocupadas int;
  v_donos int;
begin
  -- (coluna gerada ainda não existe no BEFORE: usar eh_contador)
  if tg_op in ('INSERT','UPDATE') and new.ativo and not new.eh_contador then
    select vagas into v_vagas from hub.workspaces where id = new.workspace_id for update;
    select count(*) into v_ocupadas from hub.workspace_membros
      where workspace_id = new.workspace_id and ativo and ocupa_vaga and id <> new.id;
    if v_ocupadas >= v_vagas then
      raise exception 'sem vaga: o plano tem % usuário(s) (contador não conta)', v_vagas
        using errcode = 'P0001';
    end if;
  end if;

  if tg_op in ('UPDATE','DELETE') and old.papel = 'dono' and old.ativo then
    if tg_op = 'DELETE' or not new.ativo or new.papel <> 'dono' then
      select count(*) into v_donos from hub.workspace_membros
        where workspace_id = old.workspace_id and papel = 'dono' and ativo and id <> old.id;
      if v_donos = 0 and exists (select 1 from hub.workspaces where id = old.workspace_id) then
        raise exception 'o workspace precisa de pelo menos 1 dono ativo';
      end if;
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
create trigger trg_workspace_membros_regras before insert or update or delete on hub.workspace_membros
  for each row execute function hub.trg_membros_regras();

-- ---------- convites ----------
create table hub.convites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) on delete cascade,
  email text not null check (email = lower(btrim(email)) and email like '%_@_%'),
  papel text not null check (papel in ('dono','operador','consulta')),
  eh_contador boolean not null default false check (not eh_contador or papel = 'consulta'),
  token_hash text not null unique,          -- sha256 do token; o token em claro só sai 1 vez
  criado_por uuid,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '7 days',
  aceito_em timestamptz,
  aceito_por uuid,
  revogado_em timestamptz
);
create unique index uq_convites_pendente on hub.convites (workspace_id, email)
  where aceito_em is null and revogado_em is null;
alter table hub.convites enable row level security;
create trigger trg_convites_auditoria after insert or update or delete on hub.convites
  for each row execute function hub.registrar_auditoria();

-- ---------- módulos ----------
-- Sem preço aqui de propósito: o repo é público. Preço mora no vault/planilha.
create table hub.modulos (
  slug text primary key,
  nome text not null,
  ordem smallint not null default 0
);
insert into hub.modulos (slug, nome, ordem) values
  ('financeiro',  'Financeiro', 1),
  ('marketing',   'Marketing', 2),
  ('clientes_cobranca', 'Clientes e cobrança', 3),
  ('crm_contratos_reunioes', 'CRM, contratos e reuniões', 4),
  ('fiscal',      'Fiscal', 5),
  ('estoque',     'Estoque', 6);
alter table hub.modulos enable row level security;

create table hub.workspace_modulos (
  workspace_id uuid not null references hub.workspaces(id) on delete cascade,
  modulo_slug text not null references hub.modulos(slug),
  ativo boolean not null default true,
  desde date not null default current_date,
  ate date,
  primary key (workspace_id, modulo_slug)
);
alter table hub.workspace_modulos enable row level security;
create trigger trg_workspace_modulos_auditoria after insert or update or delete on hub.workspace_modulos
  for each row execute function hub.registrar_auditoria();

-- ---------- canais: como uma automação descobre o workspace ----------
-- n8n/Edge Function (service_role ou segredo do bot) não tem usuário. O
-- workspace sai do identificador do canal: instância da Evolution, phone
-- number id da Meta, etc. Ver docs §6.
create table hub.workspace_canais (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) on delete cascade,
  tipo text not null check (tipo in ('evolution_instancia','meta_phone_number_id','google_calendar','docuseal','meetily')),
  identificador text not null,
  criado_em timestamptz not null default now(),
  constraint workspace_canais_unico unique (tipo, identificador)
);
alter table hub.workspace_canais enable row level security;
create trigger trg_workspace_canais_auditoria after insert or update or delete on hub.workspace_canais
  for each row execute function hub.registrar_auditoria();

-- ---------- LGPD: aceite de termos por workspace ----------
-- Assinante = controlador, Isa TecInfo = operador (pesquisa regulatória 07/10).
create table hub.workspace_aceites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references hub.workspaces(id) on delete cascade,
  documento text not null check (documento in ('termos_de_uso','acordo_tratamento_dados','politica_privacidade')),
  versao text not null,
  aceito_por uuid not null,
  aceito_em timestamptz not null default now(),
  constraint workspace_aceites_unico unique (workspace_id, documento, versao)
);
alter table hub.workspace_aceites enable row level security;

-- ---------- LGPD: trilha de LEITURA de dado fiscal ----------
-- (a escrita já vai pra hub.eventos_auditoria pelo trigger)
create table hub.acessos_sensiveis (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references hub.workspaces(id) on delete cascade,
  user_id uuid,
  recurso text not null,
  registro_id uuid,
  em timestamptz not null default now()
);
create index idx_acessos_sensiveis_ws on hub.acessos_sensiveis (workspace_id, em desc);
alter table hub.acessos_sensiveis enable row level security;

-- ---------- perfil fiscal: mora em hub.empresas ----------
-- hub.empresas já é "o CNPJ que fatura" dentro do workspace (Luh Panda MEI).
-- 1 workspace pode ter N empresas (pergunta P5); o onboarding cria a 1ª.
create or replace function hub.cnpj_normalizar(p text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$ select nullif(upper(regexp_replace(coalesce(p,''), '[^0-9A-Za-z]', '', 'g')), '') $$;

-- CNPJ numérico E alfanumérico (IN RFB 2.229/2024, novas inscrições desde
-- jul/2026): 12 posições [0-9A-Z] + 2 DV numéricos. Valor do caractere =
-- código ASCII - 48; pesos e módulo 11 iguais ao CNPJ numérico.
create or replace function hub.cnpj_valido(p text)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  c text := hub.cnpj_normalizar(p);
  pesos1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2];
  pesos2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2];
  s int; r int; dv1 int; dv2 int; i int;
begin
  if c is null or c !~ '^[0-9A-Z]{12}[0-9]{2}$' then return false; end if;
  if c ~ '^(.)\1{13}$' then return false; end if;
  s := 0;
  for i in 1..12 loop s := s + (ascii(substr(c,i,1)) - 48) * pesos1[i]; end loop;
  r := s % 11; dv1 := case when r < 2 then 0 else 11 - r end;
  s := 0;
  for i in 1..13 loop
    s := s + (case when i = 13 then dv1 else ascii(substr(c,i,1)) - 48 end) * pesos2[i];
  end loop;
  r := s % 11; dv2 := case when r < 2 then 0 else 11 - r end;
  return substr(c,13,1)::int = dv1 and substr(c,14,1)::int = dv2;
end;
$$;

alter table hub.empresas
  add column if not exists razao_social text,
  add column if not exists nome_fantasia text,
  add column if not exists cnae_principal text,
  add column if not exists cnaes_secundarios text[],
  add column if not exists natureza_juridica text,
  add column if not exists abertura_em date,
  add column if not exists situacao_cadastral text,
  add column if not exists endereco jsonb,
  -- só nome + qualificação; nunca CPF (pergunta P9)
  add column if not exists socios jsonb,
  add column if not exists simples_optante boolean,
  add column if not exists simples_desde date,
  add column if not exists simei_optante boolean,
  add column if not exists simei_desde date,
  -- sugestão automática (Simples/MEI da Receita; Presumido/Real da ECF via BrasilAPI, ~2 anos de atraso)
  add column if not exists regime_sugerido text,
  add column if not exists regime_sugerido_fonte text,
  add column if not exists regime_sugerido_ano smallint,
  -- o que vale: SEMPRE confirmado pelo dono
  add column if not exists regime text,
  add column if not exists regime_confirmado_por uuid,
  add column if not exists regime_confirmado_em timestamptz,
  add column if not exists faixa_faturamento text,
  add column if not exists receita_fonte text,
  add column if not exists receita_consultada_em timestamptz;

alter table hub.empresas
  add constraint empresas_regime_check check (regime is null or regime in ('mei','simples','presumido','real','arbitrado')),
  add constraint empresas_regime_sugerido_check check (regime_sugerido is null or regime_sugerido in ('mei','simples','presumido','real','arbitrado')),
  add constraint empresas_regime_confirmado check (regime is null or (regime_confirmado_por is not null and regime_confirmado_em is not null)),
  add constraint empresas_faixa_check check (faixa_faturamento is null or faixa_faturamento in ('ate_81k','81k_360k','360k_4_8m','acima_4_8m')),
  add constraint empresas_receita_fonte_check check (receita_fonte is null or receita_fonte in ('brasilapi','cnpja','receitaws','manual')),
  -- CNPJ é text sempre; aceita o formato com pontuação que já está gravado
  add constraint empresas_cnpj_valido check (cnpj is null or hub.cnpj_valido(cnpj)) not valid;
-- `not valid`: o registro dela não é revalidado aqui; o teste roda o VALIDATE

-- ---------- helpers de workspace ----------
-- Workspace da requisição. Ordem:
--   1) humano (auth.uid()): header x-workspace-id OU o único workspace dele;
--      header de workspace do qual ele não é membro ativo = NULL (nega tudo).
--   2) automação (service_role, ou segredo do bot validado): o GUC
--      hub.workspace_id que a própria RPC definiu a partir do canal; sem
--      ele, cai no workspace 1 (COMPAT da etapa 3, sai na etapa 5).
--   3) anon sem segredo: NULL.
create or replace function hub.current_workspace_id()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_hdr text;
  v_guc text := nullif(current_setting('hub.workspace_id', true), '');
  v_ws uuid;
begin
  if v_uid is not null then
    begin
      v_hdr := nullif(current_setting('request.headers', true)::json->>'x-workspace-id', '');
    exception when others then v_hdr := null;
    end;
    v_hdr := coalesce(v_hdr, v_guc);
    if v_hdr is not null then
      begin
        v_ws := v_hdr::uuid;
      exception when invalid_text_representation then
        return null;
      end;
      perform 1 from hub.workspace_membros m join hub.workspaces w on w.id = m.workspace_id
        where m.workspace_id = v_ws and m.user_id = v_uid and m.ativo and w.status in ('onboarding','ativo');
      return case when found then v_ws else null end;
    end if;
    select m.workspace_id into v_ws from hub.workspace_membros m join hub.workspaces w on w.id = m.workspace_id
      where m.user_id = v_uid and m.ativo and w.status in ('onboarding','ativo');
    if (select count(*) from hub.workspace_membros m join hub.workspaces w on w.id = m.workspace_id
        where m.user_id = v_uid and m.ativo and w.status in ('onboarding','ativo')) = 1 then
      return v_ws;
    end if;
    return null;  -- 0 ou 2+ workspaces sem header: obriga escolher
  end if;

  if coalesce(auth.role(), '') = 'service_role' or coalesce(current_setting('hub.bot_ok', true), '') = '1' then
    if v_guc is not null then return v_guc::uuid; end if;
    return (select id from hub.workspaces where slug = 'luhpanda');  -- COMPAT etapa 3
  end if;
  return null;
end;
$$;

create or replace function hub.papel_atual()
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select m.papel from hub.workspace_membros m
  where m.user_id = auth.uid() and m.ativo and m.workspace_id = hub.current_workspace_id()
$$;

create or replace function hub.eh_automacao()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select auth.uid() is null
     and (coalesce(auth.role(), '') = 'service_role' or coalesce(current_setting('hub.bot_ok', true), '') = '1')
$$;

create or replace function hub.pode_ler()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$ select hub.current_workspace_id() is not null $$;

create or replace function hub.pode_escrever()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select hub.current_workspace_id() is not null
     and (hub.eh_automacao() or coalesce(hub.papel_atual(), '') in ('dono','operador'))
$$;

create or replace function hub.eh_dono()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$ select coalesce(hub.papel_atual(), '') = 'dono' $$;

create or replace function hub.is_plataforma_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$ select exists (select 1 from hub.plataforma_admins where user_id = auth.uid()) $$;

create or replace function hub.modulo_ativo(p_slug text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (select 1 from hub.workspace_modulos
    where workspace_id = hub.current_workspace_id() and modulo_slug = p_slug and ativo
      and (ate is null or ate >= current_date))
$$;

-- Automação define o workspace pelo canal (instância Evolution etc.).
-- Canal desconhecido = erro; nunca cai em workspace errado.
create or replace function hub.ingestor_definir_workspace(p_tipo text, p_identificador text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare v_ws uuid;
begin
  if p_identificador is null then return null; end if;
  select workspace_id into v_ws from hub.workspace_canais
    where tipo = p_tipo and identificador = p_identificador;
  if v_ws is null then raise exception 'canal % "%" não pertence a nenhum workspace', p_tipo, p_identificador; end if;
  perform set_config('hub.workspace_id', v_ws::text, true);
  return v_ws;
end;
$$;

-- ---------- RPCs de conta (owner = postgres, checagem explícita) ----------
create or replace function hub.rpc_meus_workspaces()
returns table (workspace_id uuid, nome text, slug text, status text, papel text, eh_contador boolean)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select w.id, w.nome, w.slug, w.status, m.papel, m.eh_contador
  from hub.workspace_membros m join hub.workspaces w on w.id = m.workspace_id
  where m.user_id = auth.uid() and m.ativo
  order by w.nome
$$;

create or replace function hub._gerar_convite(p_ws uuid, p_email text, p_papel text, p_contador boolean)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, extensions
as $$
declare
  v_token text := encode(gen_random_bytes(24), 'hex');
  v_id uuid;
begin
  insert into hub.convites (workspace_id, email, papel, eh_contador, token_hash, criado_por)
  values (p_ws, lower(btrim(p_email)), p_papel, coalesce(p_contador, false),
          encode(digest(v_token, 'sha256'), 'hex'), auth.uid())
  returning id into v_id;
  return jsonb_build_object('convite_id', v_id, 'token', v_token);
end;
$$;
revoke all on function hub._gerar_convite(uuid, text, text, boolean) from public;

-- Ela/Isa criam a empresa e o convite do dono (entrada por convite, grill 07/10)
create or replace function hub.rpc_plataforma_criar_workspace(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_ws uuid;
  v_conv jsonb;
  v_mod text;
begin
  if not hub.is_plataforma_admin() then raise exception 'acesso negado'; end if;
  if nullif(btrim(coalesce(p->>'nome','')), '') is null then raise exception 'nome é obrigatório'; end if;
  if nullif(btrim(coalesce(p->>'email_dono','')), '') is null then raise exception 'email_dono é obrigatório'; end if;

  insert into hub.workspaces (nome, slug, status, vagas, criado_por)
  values (btrim(p->>'nome'),
          coalesce(nullif(p->>'slug',''), 'ws-' || substr(replace(gen_random_uuid()::text,'-',''),1,10)),
          'onboarding', coalesce((p->>'vagas')::smallint, 3), auth.uid())
  returning id into v_ws;

  for v_mod in select jsonb_array_elements_text(coalesce(p->'modulos', '[]'::jsonb)) loop
    insert into hub.workspace_modulos (workspace_id, modulo_slug) values (v_ws, v_mod);
  end loop;

  v_conv := hub._gerar_convite(v_ws, p->>'email_dono', 'dono', false);
  return jsonb_build_object('workspace_id', v_ws) || v_conv;
end;
$$;

create or replace function hub.rpc_plataforma_definir_modulos(p jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare v_ws uuid := (p->>'workspace_id')::uuid;
begin
  if not hub.is_plataforma_admin() then raise exception 'acesso negado'; end if;
  update hub.workspace_modulos set ativo = false, ate = current_date
    where workspace_id = v_ws and ativo
      and modulo_slug not in (select jsonb_array_elements_text(coalesce(p->'modulos','[]'::jsonb)));
  insert into hub.workspace_modulos (workspace_id, modulo_slug)
    select v_ws, m from jsonb_array_elements_text(coalesce(p->'modulos','[]'::jsonb)) m
  on conflict (workspace_id, modulo_slug) do update set ativo = true, ate = null;
end;
$$;

-- Dono convida operador/consulta/contador
create or replace function hub.rpc_criar_convite(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare v_ws uuid := hub.current_workspace_id();
begin
  if v_ws is null or not hub.eh_dono() then raise exception 'acesso negado'; end if;
  if coalesce(p->>'papel','') not in ('dono','operador','consulta') then raise exception 'papel inválido'; end if;
  return hub._gerar_convite(v_ws, p->>'email', p->>'papel', (p->>'eh_contador')::boolean);
end;
$$;

create or replace function hub.rpc_revogar_convite(p_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not (hub.eh_dono() or hub.is_plataforma_admin()) then raise exception 'acesso negado'; end if;
  update hub.convites set revogado_em = now()
    where id = p_id and aceito_em is null
      and (workspace_id = hub.current_workspace_id() or hub.is_plataforma_admin());
end;
$$;

-- Quem foi convidado aceita, logado com o MESMO e-mail do convite
create or replace function hub.rpc_aceitar_convite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, extensions
as $$
declare
  c hub.convites%rowtype;
begin
  if auth.uid() is null then raise exception 'faça login antes de aceitar o convite'; end if;
  select * into c from hub.convites
    where token_hash = encode(digest(coalesce(p_token,''), 'sha256'), 'hex')
    for update;
  if not found or c.revogado_em is not null or c.aceito_em is not null or c.expira_em < now() then
    raise exception 'convite inválido ou expirado';
  end if;
  if lower(coalesce(auth.email(),'')) <> c.email then
    raise exception 'este convite é de outro e-mail';
  end if;

  insert into hub.workspace_membros (workspace_id, user_id, papel, eh_contador, convite_id)
  values (c.workspace_id, auth.uid(), c.papel, c.eh_contador, c.id)
  on conflict (workspace_id, user_id) do update
    set papel = excluded.papel, eh_contador = excluded.eh_contador, ativo = true, convite_id = excluded.convite_id;

  update hub.convites set aceito_em = now(), aceito_por = auth.uid() where id = c.id;
  return c.workspace_id;
end;
$$;

create or replace function hub.rpc_membros()
returns table (id uuid, user_id uuid, email text, papel text, eh_contador boolean, ativo boolean)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select m.id, m.user_id, u.email::text, m.papel, m.eh_contador, m.ativo
  from hub.workspace_membros m join auth.users u on u.id = m.user_id
  where m.workspace_id = hub.current_workspace_id()
    and coalesce(hub.papel_atual(),'') in ('dono','operador')
  order by m.papel, u.email
$$;

create or replace function hub.rpc_alterar_membro(p jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not hub.eh_dono() then raise exception 'acesso negado'; end if;
  update hub.workspace_membros
    set papel = coalesce(p->>'papel', papel),
        ativo = coalesce((p->>'ativo')::boolean, ativo)
    where id = (p->>'id')::uuid and workspace_id = hub.current_workspace_id();
end;
$$;

-- 1º acesso, passo 1: grava o que veio da consulta pública (normalizado no
-- front/Edge Function) + a sugestão de regime. Não confirma regime.
create or replace function hub.rpc_onboarding_salvar_empresa(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_ws uuid := hub.current_workspace_id();
  v_id uuid;
  v_cnpj text := hub.cnpj_normalizar(p->>'cnpj');
begin
  if v_ws is null or not hub.eh_dono() then raise exception 'acesso negado'; end if;
  if not hub.cnpj_valido(v_cnpj) then raise exception 'CNPJ inválido'; end if;

  select id into v_id from hub.empresas
    where workspace_id = v_ws and hub.cnpj_normalizar(cnpj) = v_cnpj;

  if v_id is null then
    insert into hub.empresas (nome, cnpj, tipo, workspace_id)
    values (coalesce(nullif(p->>'nome_fantasia',''), p->>'razao_social', v_cnpj), v_cnpj,
            case when coalesce((p->>'simei_optante')::boolean, false) then 'mei' else 'servico' end, v_ws)
    returning id into v_id;
  end if;

  update hub.empresas set
    razao_social = p->>'razao_social',
    nome_fantasia = p->>'nome_fantasia',
    cnae_principal = p->>'cnae_principal',
    cnaes_secundarios = case when p ? 'cnaes_secundarios'
      then array(select jsonb_array_elements_text(p->'cnaes_secundarios')) else cnaes_secundarios end,
    natureza_juridica = p->>'natureza_juridica',
    abertura_em = (p->>'abertura_em')::date,
    situacao_cadastral = p->>'situacao_cadastral',
    endereco = p->'endereco',
    socios = (select jsonb_agg(jsonb_build_object('nome', s->>'nome', 'qualificacao', s->>'qualificacao'))
              from jsonb_array_elements(coalesce(p->'socios','[]'::jsonb)) s),
    simples_optante = (p->>'simples_optante')::boolean,
    simples_desde = (p->>'simples_desde')::date,
    simei_optante = (p->>'simei_optante')::boolean,
    simei_desde = (p->>'simei_desde')::date,
    regime_sugerido = p->>'regime_sugerido',
    regime_sugerido_fonte = p->>'regime_sugerido_fonte',
    regime_sugerido_ano = (p->>'regime_sugerido_ano')::smallint,
    receita_fonte = coalesce(p->>'receita_fonte', 'manual'),
    receita_consultada_em = coalesce((p->>'receita_consultada_em')::timestamptz, now())
  where id = v_id;
  return v_id;
end;
$$;

-- 1º acesso, passo 2: o dono CONFIRMA (Presumido/Real a consulta não garante)
create or replace function hub.rpc_onboarding_confirmar_regime(p jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare v_ws uuid := hub.current_workspace_id();
begin
  if v_ws is null or not hub.eh_dono() then raise exception 'acesso negado'; end if;
  update hub.empresas set
    regime = p->>'regime',
    faixa_faturamento = coalesce(p->>'faixa_faturamento', faixa_faturamento),
    regime_confirmado_por = auth.uid(),
    regime_confirmado_em = now()
  where id = (p->>'empresa_id')::uuid and workspace_id = v_ws;
  if not found then raise exception 'empresa não encontrada'; end if;
end;
$$;

create or replace function hub.rpc_aceitar_termos(p jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare v_ws uuid := hub.current_workspace_id();
begin
  if v_ws is null or not hub.eh_dono() then raise exception 'acesso negado'; end if;
  insert into hub.workspace_aceites (workspace_id, documento, versao, aceito_por)
  values (v_ws, p->>'documento', p->>'versao', auth.uid())
  on conflict (workspace_id, documento, versao) do nothing;
end;
$$;

-- Leitura do perfil fiscal: deixa rastro (LGPD)
create or replace function hub.rpc_perfil_fiscal()
returns setof jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare v_ws uuid := hub.current_workspace_id();
begin
  if v_ws is null then raise exception 'acesso negado'; end if;
  insert into hub.acessos_sensiveis (workspace_id, user_id, recurso)
  values (v_ws, auth.uid(), 'perfil_fiscal');
  return query
    select to_jsonb(e) - 'teto_anual_centavos' from hub.empresas e where e.workspace_id = v_ws order by e.created_at;
end;
$$;

-- ---------- wrappers públicos (padrão do repo: PostgREST só vê public) ----------
create or replace function public.hub_rpc_meus_workspaces()
returns table (workspace_id uuid, nome text, slug text, status text, papel text, eh_contador boolean)
language sql stable set search_path = pg_catalog as $$ select * from hub.rpc_meus_workspaces() $$;
create or replace function public.hub_rpc_plataforma_criar_workspace(p jsonb) returns jsonb
language sql set search_path = pg_catalog as $$ select hub.rpc_plataforma_criar_workspace(p) $$;
create or replace function public.hub_rpc_plataforma_definir_modulos(p jsonb) returns void
language sql set search_path = pg_catalog as $$ select hub.rpc_plataforma_definir_modulos(p) $$;
create or replace function public.hub_rpc_criar_convite(p jsonb) returns jsonb
language sql set search_path = pg_catalog as $$ select hub.rpc_criar_convite(p) $$;
create or replace function public.hub_rpc_revogar_convite(p_id uuid) returns void
language sql set search_path = pg_catalog as $$ select hub.rpc_revogar_convite(p_id) $$;
create or replace function public.hub_rpc_aceitar_convite(p_token text) returns uuid
language sql set search_path = pg_catalog as $$ select hub.rpc_aceitar_convite(p_token) $$;
create or replace function public.hub_rpc_membros()
returns table (id uuid, user_id uuid, email text, papel text, eh_contador boolean, ativo boolean)
language sql stable set search_path = pg_catalog as $$ select * from hub.rpc_membros() $$;
create or replace function public.hub_rpc_alterar_membro(p jsonb) returns void
language sql set search_path = pg_catalog as $$ select hub.rpc_alterar_membro(p) $$;
create or replace function public.hub_rpc_onboarding_salvar_empresa(p jsonb) returns uuid
language sql set search_path = pg_catalog as $$ select hub.rpc_onboarding_salvar_empresa(p) $$;
create or replace function public.hub_rpc_onboarding_confirmar_regime(p jsonb) returns void
language sql set search_path = pg_catalog as $$ select hub.rpc_onboarding_confirmar_regime(p) $$;
create or replace function public.hub_rpc_aceitar_termos(p jsonb) returns void
language sql set search_path = pg_catalog as $$ select hub.rpc_aceitar_termos(p) $$;
create or replace function public.hub_rpc_perfil_fiscal() returns setof jsonb
language sql set search_path = pg_catalog as $$ select * from hub.rpc_perfil_fiscal() $$;

-- ---------- grants: nada pra anon; authenticated só nas RPCs ----------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'hub' and p.proname in (
             'current_workspace_id','papel_atual','eh_automacao','pode_ler','pode_escrever','eh_dono',
             'is_plataforma_admin','modulo_ativo','ingestor_definir_workspace','cnpj_valido','cnpj_normalizar',
             'trg_membros_regras',
             'rpc_meus_workspaces','rpc_plataforma_criar_workspace','rpc_plataforma_definir_modulos',
             'rpc_criar_convite','rpc_revogar_convite','rpc_aceitar_convite','rpc_membros','rpc_alterar_membro',
             'rpc_onboarding_salvar_empresa','rpc_onboarding_confirmar_regime','rpc_aceitar_termos','rpc_perfil_fiscal'))
       or (n.nspname = 'public' and p.proname in (
             'hub_rpc_meus_workspaces','hub_rpc_plataforma_criar_workspace','hub_rpc_plataforma_definir_modulos',
             'hub_rpc_criar_convite','hub_rpc_revogar_convite','hub_rpc_aceitar_convite','hub_rpc_membros',
             'hub_rpc_alterar_membro','hub_rpc_onboarding_salvar_empresa','hub_rpc_onboarding_confirmar_regime',
             'hub_rpc_aceitar_termos','hub_rpc_perfil_fiscal'))
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    if f.proname not in ('trg_membros_regras','ingestor_definir_workspace') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    if f.proname in ('current_workspace_id','eh_automacao','pode_ler','pode_escrever','ingestor_definir_workspace') then
      execute format('grant execute on function %s to service_role', f.sig);
    end if;
  end loop;
end $$;

-- ---------- seed: os dados dela viram o workspace nº 1 ----------
-- Ela vira dono do workspace 1 e admin da plataforma. Se o usuário dela não
-- existir, a migration ABORTA (melhor do que trancar ela fora na etapa 3).
do $$
declare
  v_uid uuid;
  v_ws uuid := (select id from hub.workspaces where slug = 'luhpanda');
begin
  select id into v_uid from auth.users where email = 'lucianapandolfo9@gmail.com';
  if v_uid is null or v_ws is null then
    raise exception '050: usuário dela ou workspace luhpanda não encontrado — abortando';
  end if;
  insert into hub.plataforma_admins (user_id) values (v_uid) on conflict do nothing;
  insert into hub.workspace_membros (workspace_id, user_id, papel) values (v_ws, v_uid, 'dono')
    on conflict (workspace_id, user_id) do nothing;
  insert into hub.workspace_modulos (workspace_id, modulo_slug)
    select v_ws, slug from hub.modulos on conflict do nothing;
  -- a instância que o Hub dela já usa (nome já está no código de wa-send/wa-groups)
  insert into hub.workspace_canais (workspace_id, tipo, identificador)
    values (v_ws, 'evolution_instancia', 'LuhPessoal') on conflict do nothing;
end $$;
