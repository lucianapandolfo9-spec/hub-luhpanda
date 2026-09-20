-- ============================================================
-- HUB LUH PANDA — 002: núcleo da carteira
-- ============================================================

create table hub.empresas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cnpj text,
  tipo text not null check (tipo in ('mei','produto','servico')),
  teto_anual_centavos bigint,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table hub.clientes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references hub.empresas(id),
  slug text not null unique,
  nome text not null,
  razao_social text,
  documento text,
  segmento text,
  origem text,
  status text not null default 'ativo' check (status in ('prospect','ativo','pausado','encerrado')),
  entrou_em date,
  saiu_em date,
  motivo_saida text,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table hub.contatos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references hub.clientes(id) on delete cascade,
  nome text not null,
  papel text,
  email text,
  whatsapp_e164 text,
  is_principal boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table hub.servicos (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  nome text not null,
  modalidade text not null check (modalidade in ('recorrente','projeto','bloco_horas','por_evento','hospedagem')),
  preco_referencia_centavos bigint,
  unidade text,
  inclui text,
  observacao text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table hub.contratos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references hub.clientes(id) on delete cascade,
  numero text,
  status text not null default 'rascunho'
    check (status in ('rascunho','emitido','enviado','assinado','ativo','encerrado')),
  inicio_em date,
  fim_minimo_em date,
  dia_vencimento smallint check (dia_vencimento between 1 and 28),
  valor_mensal_centavos bigint,
  porta_saida_tipo text check (porta_saida_tipo in ('manutencao_mensal','desligamento_build_30','nenhuma')),
  porta_saida_valor_centavos bigint,
  porta_saida_escrita_em timestamptz,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- guarda de negócio: contrato ativo tem que ter porta de saída escrita
  constraint hub_contrato_ativo_exige_porta_saida
    check (status <> 'ativo' or porta_saida_escrita_em is not null)
);

create table hub.contrato_itens (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references hub.contratos(id) on delete cascade,
  servico_id uuid references hub.servicos(id),
  descricao text not null,
  valor_centavos bigint,
  recorrencia text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['empresas','clientes','contatos','servicos','contratos','contrato_itens']
  loop
    execute format('create trigger trg_%1$s_updated_at before update on hub.%1$s for each row execute function hub.set_updated_at();', t);
    execute format('create trigger trg_%1$s_auditoria after insert or update or delete on hub.%1$s for each row execute function hub.registrar_auditoria();', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array['empresas','clientes','contatos','servicos','contratos','contrato_itens']
  loop
    execute format('alter table hub.%1$s enable row level security;', t);
    execute format('create policy hub_%1$s_admin_all on hub.%1$s for all using (hub.is_admin()) with check (hub.is_admin());', t);
  end loop;
end $$;
