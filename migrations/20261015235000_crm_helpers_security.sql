-- SEC-HUB: os helpers privados de CRM não são endpoints de leitura pública.
-- 014 e 015 concediam EXECUTE a authenticated para funções SECURITY DEFINER
-- sem portão. Isso permitia correlacionar telefone a cliente/prospect caso
-- o schema hub ficasse exposto, e facilita exploração indireta por RPC futura.
-- Não muda assinatura/contratos da API. NÃO APLICAR sem homologar n8n/Edge.
begin;

create or replace function hub.crm_ids(p_fone_norm text)
returns table (prospect_id uuid, cliente_id uuid)
language plpgsql stable security definer set search_path = pg_catalog as $$
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;
  return query
  select
    (select p.id from hub.prospects p
      where hub.fone_norm(p.contato_whatsapp) = p_fone_norm
      order by coalesce(p.perdido, false) asc, p.created_at desc nulls last
      limit 1),
    (select c.cliente_id from hub.contatos c
      where hub.fone_norm(c.whatsapp_e164) = p_fone_norm
      order by coalesce(c.is_principal, false) desc
      limit 1);
end;
$$;

create or replace function hub.fone_no_crm(p_fone_norm text)
returns boolean
language plpgsql stable security definer set search_path = pg_catalog as $$
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;
  return exists (
    select 1 from hub.prospects p where hub.fone_norm(p.contato_whatsapp) = p_fone_norm
  ) or exists (
    select 1 from hub.contatos c where hub.fone_norm(c.whatsapp_e164) = p_fone_norm
  );
end;
$$;

revoke all on function hub.crm_ids(text) from public, anon, authenticated;
revoke all on function hub.fone_no_crm(text) from public, anon, authenticated;
grant execute on function hub.crm_ids(text) to service_role;
grant execute on function hub.fone_no_crm(text) to service_role;
-- Depois da virada multiempresa, RPCs internas executam sob hub_rpc.
do $$ begin
  if exists(select 1 from pg_roles where rolname='hub_rpc') then
    grant execute on function hub.crm_ids(text) to hub_rpc;
    grant execute on function hub.fone_no_crm(text) to hub_rpc;
  end if;
end $$;
commit;
