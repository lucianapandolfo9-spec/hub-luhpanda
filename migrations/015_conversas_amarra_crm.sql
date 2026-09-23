-- ============================================================
-- HUB LUH PANDA — 015: a conversa descobre sozinha de quem ela é
--
-- Aplicada em 23/09/2026. Bug achado no teste ponta a ponta, não em revisão
-- de código — só apareceu rodando o workflow de verdade contra o banco.
--
-- O QUE ESTAVA ERRADO: a conversa nascia com `prospect_id` e `cliente_id`
-- NULOS. A 013/014 só preenchia esses campos se o chamador mandasse os ids —
-- e o n8n só conhece o telefone que chegou no webhook, nunca o id interno.
--
-- POR QUE ISSO SERIA CARO: o card do kanban casa a conversa por
-- `prospect_id`. Sem a amarra, a prévia da última mensagem e o badge de
-- não-lida nunca apareceriam, mesmo com a conversa gravada corretamente.
-- Metade do módulo ficaria invisível — e o sintoma ("o kanban não mostra
-- nada") apontaria pro front-end, que está certo.
--
-- Quem sabe resolver isso é o banco, que já fazia esse mesmo lookup em
-- `hub.fone_no_crm` só pra responder sim/não. Agora devolve os ids e grava.
-- ============================================================

create or replace function hub.crm_ids(p_fone_norm text)
returns table (prospect_id uuid, cliente_id uuid)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    -- prospect ativo ganha de prospect perdido com o mesmo telefone
    (select p.id from hub.prospects p
      where hub.fone_norm(p.contato_whatsapp) = p_fone_norm
      order by coalesce(p.perdido, false) asc, p.created_at desc nulls last
      limit 1),
    -- contato principal ganha dos secundários
    (select c.cliente_id from hub.contatos c
      where hub.fone_norm(c.whatsapp_e164) = p_fone_norm
      order by coalesce(c.is_principal, false) desc
      limit 1);
$$;

revoke all on function hub.crm_ids(text) from public, anon;
grant execute on function hub.crm_ids(text) to authenticated, service_role;

create or replace function hub.rpc_registrar_mensagem(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_direcao text;
  v_corpo text;
  v_tipo text;
  v_enviada_em timestamptz;
  v_prospect uuid;
  v_cliente uuid;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  -- O banco descobre de quem é o telefone. Não sendo de ninguém do CRM,
  -- nada entra — a guarda de privacidade da 014, agora com a amarra junto.
  select ci.prospect_id, ci.cliente_id into v_prospect, v_cliente
  from hub.crm_ids(v_fone) ci;

  if v_prospect is null and v_cliente is null then
    return null;
  end if;

  v_direcao := coalesce(p->>'direcao', 'entrada');
  v_corpo := p->>'corpo';
  v_tipo := coalesce(p->>'tipo', 'texto');
  v_enviada_em := coalesce((p->>'enviada_em')::timestamptz, now());

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao)
  values (v_fone, v_prospect, v_cliente, p->>'nome_exibicao')
  on conflict (fone_norm) do update set
    prospect_id   = coalesce(excluded.prospect_id, hub.conversas.prospect_id),
    cliente_id    = coalesce(excluded.cliente_id, hub.conversas.cliente_id),
    nome_exibicao = coalesce(excluded.nome_exibicao, hub.conversas.nome_exibicao)
  returning id into v_conversa_id;

  insert into hub.mensagens (
    conversa_id, direcao, corpo, tipo, transcrito, enviada_em, evolution_msg_id
  )
  values (
    v_conversa_id, v_direcao, v_corpo, v_tipo,
    coalesce((p->>'transcrito')::boolean, false),
    v_enviada_em,
    p->>'evolution_msg_id'
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
$$;

-- mesma amarra no caminho de saída (ela respondendo de dentro do Hub)
create or replace function hub.rpc_enfileirar_saida(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_fone text;
  v_conversa_id uuid;
  v_msg_id uuid;
  v_corpo text;
  v_prospect uuid;
  v_cliente uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;
  v_corpo := p->>'corpo';

  select ci.prospect_id, ci.cliente_id into v_prospect, v_cliente
  from hub.crm_ids(v_fone) ci;

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao)
  values (v_fone, v_prospect, v_cliente, p->>'nome_exibicao')
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
$$;

revoke all on function hub.rpc_registrar_mensagem(jsonb) from public, anon;
revoke all on function hub.rpc_enfileirar_saida(jsonb) from public, anon;
grant execute on function hub.rpc_registrar_mensagem(jsonb) to authenticated, service_role;
grant execute on function hub.rpc_enfileirar_saida(jsonb) to authenticated;
