-- ============================================================
-- HUB — ROLLBACK da 051. ⚠️ DRAFT. Rodar só depois do 052_down.
-- Volta as FKs de 1 coluna (texto de produção, 07/10/2026) e tira o
-- workspace_id das 6 tabelas que não tinham.
-- ============================================================
do $$
declare r record;
begin
  for r in select conrelid::regclass as t, conname from pg_constraint
           where connamespace = 'hub'::regnamespace and contype = 'f' and conname like '%\_ws\_fkey' loop
    execute format('alter table %s drop constraint %I', r.t, r.conname);
  end loop;
  for r in select conrelid::regclass as t, conname from pg_constraint
           where connamespace = 'hub'::regnamespace and contype = 'u' and conname like '%\_ws\_id\_key' loop
    execute format('alter table %s drop constraint %I', r.t, r.conname);
  end loop;
end $$;

alter table hub.recebiveis add constraint recebiveis_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES hub.contratos(id) ON DELETE SET NULL;
alter table hub.clientes add constraint clientes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES hub.empresas(id);
alter table hub.contatos add constraint contatos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.contratos add constraint contratos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.contrato_itens add constraint contrato_itens_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES hub.contratos(id) ON DELETE CASCADE;
alter table hub.contrato_itens add constraint contrato_itens_servico_id_fkey FOREIGN KEY (servico_id) REFERENCES hub.servicos(id);
alter table hub.recebiveis add constraint recebiveis_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.cobranca_envios add constraint cobranca_envios_recebivel_id_fkey FOREIGN KEY (recebivel_id) REFERENCES hub.recebiveis(id) ON DELETE CASCADE;
alter table hub.demandas add constraint demandas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.cobranca_config add constraint cobranca_config_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE CASCADE;
alter table hub.conversas add constraint conversas_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES hub.prospects(id) ON DELETE SET NULL;
alter table hub.conversas add constraint conversas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.mensagens add constraint mensagens_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES hub.conversas(id) ON DELETE CASCADE;
alter table hub.reunioes add constraint reunioes_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES hub.prospects(id) ON DELETE SET NULL;
alter table hub.reunioes add constraint reunioes_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.eventos_agenda add constraint eventos_agenda_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES hub.clientes(id) ON DELETE SET NULL;
alter table hub.eventos_agenda add constraint eventos_agenda_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES hub.prospects(id) ON DELETE SET NULL;

-- índices de workspace criados pela 051
do $$
declare i record;
begin
  for i in select indexname from pg_indexes where schemaname = 'hub' and indexname like 'idx\_%\_ws' loop
    execute format('drop index hub.%I', i.indexname);
  end loop;
end $$;

-- auditoria volta à versão da 050 (sem workspace)
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
  values (tg_table_name, case when v_id ~ '^[0-9a-f-]{36}$' then v_id::uuid end, lower(tg_op),
          v_velho, v_novo, coalesce(auth.email(), 'sistema'));
  return coalesce(new, old);
end;
$$;

alter table hub.eventos_auditoria drop column workspace_id;
alter table hub.recebiveis drop column workspace_id;
alter table hub.custos_fixos drop column workspace_id;
alter table hub.cobranca_envios drop column workspace_id;
alter table hub.mensagens drop column workspace_id;
alter table hub.config drop column workspace_id;
