-- DRAFT. Depois de 050–052 e da correção de integração.
-- A decisão vigente é três usuários. A exceção do contador permanece proposta.
begin;
do $$ begin
 if exists(select 1 from hub.workspace_membros m join hub.workspaces w on w.id=m.workspace_id
  where m.ativo group by m.workspace_id,w.vagas having count(*)>w.vagas) then
  raise exception 'Há mais usuários ativos que vagas: resolver antes de aplicar, sem remoção automática';
 end if;
end $$;
alter table hub.workspace_membros drop column ocupa_vaga;
alter table hub.workspace_membros add column ocupa_vaga boolean generated always as (true) stored;
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
  if tg_op in ('INSERT','UPDATE') and new.ativo then
    select vagas into v_vagas from hub.workspaces where id = new.workspace_id for update;
    select count(*) into v_ocupadas from hub.workspace_membros
      where workspace_id = new.workspace_id and ativo and id <> new.id;
    if v_ocupadas >= v_vagas then
      raise exception 'sem vaga: o plano tem % usuário(s) (incluindo contador)', v_vagas
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
notify pgrst,'reload schema';
commit;
