-- ============================================================
-- HUB — 051: workspace_id em TODA tabela de dado (ETAPA 2 de 3, ADITIVA)
--
-- ⚠️ DRAFT — NÃO APLICAR. Testada só em PGlite.
--
-- 1) As 6 tabelas que ainda não têm workspace_id ganham a coluna, com
--    backfill pro workspace 1 (todo dado de hoje é dela):
--      recebiveis · custos_fixos · cobranca_envios · mensagens ·
--      eventos_auditoria · config
--    (as 4 primeiras + config só existem em produção, sem migration no repo)
-- 2) Todo pai ganha UNIQUE (workspace_id, id) e todo filho passa a apontar
--    com FK COMPOSTA (workspace_id, pai_id). É isso que impede, no banco, um
--    recebível do workspace B apontar pra cliente do workspace A — a RLS
--    sozinha não pega isso (FK não passa por RLS).
-- 3) Índice em workspace_id (a RLS da etapa 3 filtra por ele).
--
-- Nada muda pro usuário: o default continua hub.default_workspace_id()
-- (= workspace 1). A troca de default e de policy é a 052.
-- Reverter: migrations/rollback/051_down.sql
-- ============================================================

-- ---------- 1) coluna + backfill ----------
alter table hub.recebiveis add column workspace_id uuid;
update hub.recebiveis r set workspace_id = c.workspace_id from hub.clientes c where c.id = r.cliente_id;

alter table hub.custos_fixos add column workspace_id uuid;
update hub.custos_fixos set workspace_id = hub.default_workspace_id();

alter table hub.cobranca_envios add column workspace_id uuid;
update hub.cobranca_envios e set workspace_id = r.workspace_id from hub.recebiveis r where r.id = e.recebivel_id;

alter table hub.mensagens add column workspace_id uuid;
update hub.mensagens m set workspace_id = c.workspace_id from hub.conversas c where c.id = m.conversa_id;

alter table hub.config add column workspace_id uuid;
update hub.config set workspace_id = hub.default_workspace_id();

-- auditoria: nullable de propósito (evento de tabela global, ex. hub.modulos)
alter table hub.eventos_auditoria add column workspace_id uuid references hub.workspaces(id) on delete set null;
update hub.eventos_auditoria set workspace_id = coalesce(
    nullif(dados_depois->>'workspace_id','')::uuid,
    nullif(dados_antes->>'workspace_id','')::uuid,
    case when tabela = 'workspaces' then registro_id end,
    hub.default_workspace_id());
create index idx_eventos_auditoria_ws on hub.eventos_auditoria (workspace_id, criado_em desc);

do $$
declare t text;
begin
  foreach t in array array['recebiveis','custos_fixos','cobranca_envios','mensagens','config'] loop
    execute format('alter table hub.%I alter column workspace_id set default hub.default_workspace_id()', t);
    execute format('alter table hub.%I alter column workspace_id set not null', t);
    execute format('alter table hub.%I add constraint %I foreign key (workspace_id) references hub.workspaces(id)',
                   t, t || '_workspace_id_fkey');
  end loop;
end $$;

-- auditoria passa a gravar o workspace do registro
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
  v_ws text := coalesce(v_novo->>'workspace_id', v_velho->>'workspace_id',
                        case when tg_table_name = 'workspaces' then v_id end);
begin
  insert into hub.eventos_auditoria (tabela, registro_id, acao, dados_antes, dados_depois, ator_email, workspace_id)
  values (
    tg_table_name,
    case when v_id ~ '^[0-9a-f-]{36}$' then v_id::uuid end,
    lower(tg_op),
    v_velho,
    v_novo,
    coalesce(auth.email(), 'sistema'),
    case when tg_table_name = 'workspaces' and tg_op = 'DELETE' then null else v_ws::uuid end
  );
  return coalesce(new, old);
end;
$$;

-- ---------- 2) chave (workspace_id, id) nos pais ----------
do $$
declare t text;
begin
  foreach t in array array['empresas','clientes','contratos','servicos','prospects','conversas','recebiveis'] loop
    execute format('alter table hub.%I add constraint %I unique (workspace_id, id)', t, t || '_ws_id_key');
  end loop;
end $$;

-- ---------- FKs compostas (troca as de 1 coluna) ----------
-- formato: tabela | coluna | pai | ação no delete
-- `on delete set null (col)` (PG15+) zera só a coluna do pai, nunca o workspace_id.
do $$
declare
  r record;
  v_old text;
begin
  for r in select * from (values
      ('clientes',        'empresa_id',  'empresas',   'no action'),
      ('contatos',        'cliente_id',  'clientes',   'cascade'),
      ('contratos',       'cliente_id',  'clientes',   'cascade'),
      ('contrato_itens',  'contrato_id', 'contratos',  'cascade'),
      ('contrato_itens',  'servico_id',  'servicos',   'no action'),
      ('demandas',        'cliente_id',  'clientes',   'cascade'),
      ('cobranca_config', 'cliente_id',  'clientes',   'cascade'),
      ('cobranca_envios', 'recebivel_id','recebiveis', 'cascade'),
      ('recebiveis',      'cliente_id',  'clientes',   'cascade'),
      ('recebiveis',      'contrato_id', 'contratos',  'set null'),
      ('conversas',       'cliente_id',  'clientes',   'set null'),
      ('conversas',       'prospect_id', 'prospects',  'set null'),
      ('mensagens',       'conversa_id', 'conversas',  'cascade'),
      ('eventos_agenda',  'cliente_id',  'clientes',   'set null'),
      ('eventos_agenda',  'prospect_id', 'prospects',  'set null'),
      ('reunioes',        'cliente_id',  'clientes',   'set null'),
      ('reunioes',        'prospect_id', 'prospects',  'set null')
    ) as v(tabela, coluna, pai, acao)
  loop
    -- derruba a FK antiga de 1 coluna (nome vem do catálogo, não chutado)
    select c.conname into v_old
    from pg_constraint c
    where c.conrelid = ('hub.' || r.tabela)::regclass and c.contype = 'f'
      and c.confrelid = ('hub.' || r.pai)::regclass
      and c.conkey = array[(select attnum from pg_attribute
                            where attrelid = ('hub.' || r.tabela)::regclass and attname = r.coluna)]::int2[];
    if v_old is not null then
      execute format('alter table hub.%I drop constraint %I', r.tabela, v_old);
    end if;

    execute format(
      'alter table hub.%I add constraint %I foreign key (workspace_id, %I) references hub.%I (workspace_id, id) on delete %s not valid',
      r.tabela, r.tabela || '_' || r.coluna || '_ws_fkey', r.coluna, r.pai,
      case r.acao when 'set null' then format('set null (%I)', r.coluna) else r.acao end);
    execute format('alter table hub.%I validate constraint %I', r.tabela, r.tabela || '_' || r.coluna || '_ws_fkey');
  end loop;
end $$;

-- ---------- 3) índices pra RLS ----------
do $$
declare t text;
begin
  for t in
    select c.relname from pg_class c
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'workspace_id' and not a.attisdropped
    where c.relnamespace = 'hub'::regnamespace and c.relkind = 'r'
      and c.relname not in ('workspace_membros','convites','workspace_modulos','workspace_canais',
                            'workspace_aceites','acessos_sensiveis','eventos_auditoria')
  loop
    execute format('create index if not exists %I on hub.%I (workspace_id)', 'idx_' || t || '_ws', t);
  end loop;
end $$;
