-- ============================================================
-- HUB LUH PANDA — 014: guardas do módulo de conversas
--
-- Aplicada em 23/09/2026, logo depois da 013 (mesma sessão).
--
-- Dois consertos sobre a 013:
--
-- 1) service_role não tinha `usage` no schema hub — a 001 revogou de
--    public/anon/authenticated e só devolveu pra authenticated. Sem isto o
--    n8n toma "permission denied for schema hub" mesmo chamando o wrapper
--    público, porque o wrapper é security invoker: quem executa o corpo é
--    o chamador, não o dono.
--
-- 2) GUARDA FÍSICA DA WHITELIST — o conserto que importa.
--    A decisão do /grill-me foi "só grava telefone já cadastrado no CRM",
--    pra conversa pessoal dela nunca virar linha no banco. Na 013 isso
--    dependia exclusivamente de um nó do n8n estar configurado certo. Um
--    erro ali despejaria o WhatsApp pessoal inteiro no Postgres — e não dá
--    pra "desvazar" o que já foi gravado.
--    Agora o banco recusa sozinho: telefone que não casa com nenhum
--    prospect nem contato de cliente simplesmente não entra. Mesmo espírito
--    do `falta_centavos` GENERATED — a regra mora no banco, não na boa
--    vontade da camada de cima.
--
-- ⚠️ Nota sobre `hub.is_ingestor()` (criada na 013): a cláusula
--    `current_user = 'service_role'` nunca é verdadeira, porque a função é
--    SECURITY DEFINER e current_user vira o dono (postgres). Quem de fato
--    identifica o n8n é `auth.role()`, lendo a claim do JWT — testado e
--    confirmado. A cláusula fica como no-op defensivo; não remover sem
--    reconfirmar que auth.role() cobre todos os caminhos de chamada.
-- ============================================================

grant usage on schema hub to service_role;

-- o telefone está no CRM? (prospect OU contato de cliente)
-- Normaliza os DOIS lados na comparação, porque
-- hub.prospects.contato_whatsapp e hub.contatos.whatsapp_e164 são text livre
-- em formatos diferentes, sem validação nenhuma no banco.
create or replace function hub.fone_no_crm(p_fone_norm text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1 from hub.prospects p
    where hub.fone_norm(p.contato_whatsapp) = p_fone_norm
  ) or exists (
    select 1 from hub.contatos c
    where hub.fone_norm(c.whatsapp_e164) = p_fone_norm
  );
$$;

revoke all on function hub.fone_no_crm(text) from public, anon;
grant execute on function hub.fone_no_crm(text) to authenticated, service_role;

-- ingestão com a guarda embutida.
-- Telefone fora do CRM devolve null em silêncio: não é erro, é o filtro
-- funcionando (a mãe dela mandando mensagem não é uma exceção a logar).
-- Só entrada inválida de verdade continua levantando.
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
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  -- GUARDA: fora do CRM não entra. Nem a conversa, nem a mensagem.
  if not hub.fone_no_crm(v_fone) then
    return null;
  end if;

  v_direcao := coalesce(p->>'direcao', 'entrada');
  v_corpo := p->>'corpo';
  v_tipo := coalesce(p->>'tipo', 'texto');
  v_enviada_em := coalesce((p->>'enviada_em')::timestamptz, now());

  insert into hub.conversas (fone_norm, prospect_id, cliente_id, nome_exibicao)
  values (
    v_fone,
    (p->>'prospect_id')::uuid,
    (p->>'cliente_id')::uuid,
    p->>'nome_exibicao'
  )
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

revoke all on function hub.rpc_registrar_mensagem(jsonb) from public, anon;
grant execute on function hub.rpc_registrar_mensagem(jsonb) to authenticated, service_role;
