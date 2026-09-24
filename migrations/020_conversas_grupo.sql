-- ============================================================
-- HUB LUH PANDA — 020: grupos de WhatsApp na conversa (Fase 3, Bloco C+)
--
-- Decisões do /grill-me de 24/09/2026:
--   • Whitelist por grupo — nenhum grupo entra sozinho, ela liga um a um
--     na ficha do cliente/prospect (mesmo campo de WhatsApp, um seletor
--     "Tipo: Grupo" ao lado).
--   • Autoria visível — cada mensagem de grupo guarda quem escreveu
--     (remetente_fone/remetente_nome), não só o texto.
--   • Envio de dentro do Hub — mesmo padrão do 1-a-1.
--   • Rascunho da IA — mesmo padrão do 1-a-1, ela sempre edita antes de
--     mandar.
--   • Uma vez que ela ligou o grupo, mensagem de QUALQUER participante
--     vira linha — o consentimento é dela, ao escolher o grupo, não por
--     pessoa dentro dele.
--
-- DESENHO: não cria tabela paralela. hub.fone_norm() já devolve o ID de
-- grupo intacto (verificado na 013: "grupo @g.us passa intacto") — então
-- hub.conversas.fone_norm continua sendo a chave, só ganha um `eh_grupo`
-- pra saber como tratar a linha. hub.fone_no_crm() já funciona pra grupo
-- de graça: ela só checa se o identificador normalizado está cadastrado
-- em contatos/prospects, não importa se é telefone ou ID de grupo.
--
-- NÃO faz nesta migration (fica pro n8n e pra Edge Function):
--   • Parar de descartar grupo no workflow — só passar eh_grupo=true pros
--     grupos que baterem na whitelist (a guarda de banco já recusa o
--     resto sozinha).
--   • wa-send montar JID @g.us em vez de @s.whatsapp.net quando eh_grupo.
-- ============================================================

-- ---------- colunas novas ----------

alter table hub.contatos add column if not exists eh_grupo boolean not null default false;
alter table hub.prospects add column if not exists contato_eh_grupo boolean not null default false;
alter table hub.conversas add column if not exists eh_grupo boolean not null default false;
alter table hub.mensagens add column if not exists remetente_fone text;
alter table hub.mensagens add column if not exists remetente_nome text;

comment on column hub.contatos.eh_grupo is
  'true = whatsapp_e164 guarda um ID de grupo (@g.us), não telefone de pessoa.';
comment on column hub.prospects.contato_eh_grupo is
  'true = contato_whatsapp guarda um ID de grupo (@g.us), não telefone de pessoa.';
comment on column hub.conversas.eh_grupo is
  'Herdado do contato/prospect que originou a conversa — decide @g.us vs @s.whatsapp.net no envio.';
comment on column hub.mensagens.remetente_fone is
  'Só preenchido quando a conversa é de grupo — de qual participante veio a mensagem.';

-- ---------- hub.rpc_salvar_contato — aproveitando pra registrar a versão
-- que só existia direto no banco (pendência antiga, nunca commitada) ----------

create or replace function hub.rpc_salvar_contato(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.contatos (id, cliente_id, nome, papel, email, whatsapp_e164, is_principal, eh_grupo)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, p->>'nome',
    p->>'papel', p->>'email', p->>'whatsapp_e164', coalesce((p->>'is_principal')::boolean, false),
    coalesce((p->>'eh_grupo')::boolean, false)
  )
  on conflict (id) do update set
    nome=excluded.nome, papel=excluded.papel, email=excluded.email,
    whatsapp_e164=excluded.whatsapp_e164, is_principal=excluded.is_principal,
    eh_grupo=excluded.eh_grupo
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_contato(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_contato(jsonb) to authenticated;

create or replace function public.hub_rpc_salvar_contato(p jsonb)
returns uuid
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_salvar_contato(p); $$;

revoke all on function public.hub_rpc_salvar_contato(jsonb) from public, anon;
grant execute on function public.hub_rpc_salvar_contato(jsonb) to authenticated;

-- ---------- hub.rpc_salvar_prospect — mesma extensão pro campo único de contato ----------

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
    nome=excluded.nome, origem=excluded.origem, contato_whatsapp=excluded.contato_whatsapp,
    contato_eh_grupo=excluded.contato_eh_grupo,
    contato_email=excluded.contato_email, coluna=excluded.coluna,
    valor_estimado_centavos=excluded.valor_estimado_centavos, nota=excluded.nota,
    gravacao=excluded.gravacao, entrou_em=excluded.entrou_em, fechado_em=excluded.fechado_em,
    perdido=excluded.perdido, motivo_perda=excluded.motivo_perda
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_prospect(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_prospect(jsonb) to authenticated;

-- ---------- hub.rpc_registrar_mensagem — ingestão aceita eh_grupo + remetente ----------

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
  v_eh_grupo boolean;
begin
  if not hub.is_ingestor() then raise exception 'acesso negado'; end if;

  v_fone := hub.fone_norm(p->>'fone');
  if v_fone is null then raise exception 'fone inválido'; end if;

  -- GUARDA: fora do CRM não entra. Vale igual pra grupo — o identificador
  -- normalizado (telefone OU ID de grupo) precisa estar cadastrado.
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
$$;

revoke all on function hub.rpc_registrar_mensagem(jsonb) from public, anon;
grant execute on function hub.rpc_registrar_mensagem(jsonb) to service_role;

-- ---------- hub.rpc_enfileirar_saida — carrega eh_grupo só na primeira vez
-- que a conversa nasce (ela pode mandar a primeira mensagem antes de
-- qualquer entrada ter chegado) ----------

create or replace function hub.rpc_enfileirar_saida(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
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
$$;

revoke all on function hub.rpc_enfileirar_saida(jsonb) from public, anon;

-- ---------- hub.rpc_preparar_envio — devolve eh_grupo pra Edge Function
-- saber montar @g.us em vez de @s.whatsapp.net ----------

create or replace function hub.rpc_preparar_envio(p jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog
as $$
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
$$;

revoke all on function hub.rpc_preparar_envio(jsonb) from public, anon;
grant execute on function hub.rpc_preparar_envio(jsonb) to authenticated;

create or replace function public.hub_rpc_preparar_envio(p jsonb)
returns jsonb
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_preparar_envio(p); $$;

revoke all on function public.hub_rpc_preparar_envio(jsonb) from public, anon;
grant execute on function public.hub_rpc_preparar_envio(jsonb) to authenticated;

-- ---------- hub.rpc_conversas_resumo — muda o formato de retorno (ganha
-- eh_grupo), então precisa DROP antes do CREATE (Postgres não deixa
-- CREATE OR REPLACE mudar o shape de uma RETURNS TABLE) ----------

drop function if exists public.hub_rpc_conversas_resumo();
drop function if exists hub.rpc_conversas_resumo();

create function hub.rpc_conversas_resumo()
returns table (
  fone_norm text,
  prospect_id uuid,
  cliente_id uuid,
  nome_exibicao text,
  ultima_msg_previa text,
  ultima_msg_em timestamptz,
  ultima_msg_direcao text,
  nao_lida boolean,
  eh_grupo boolean
)
language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  return query
  select
    c.fone_norm, c.prospect_id, c.cliente_id, c.nome_exibicao,
    c.ultima_msg_previa, c.ultima_msg_em, c.ultima_msg_direcao,
    coalesce(c.ultima_msg_direcao = 'entrada', false) as nao_lida,
    c.eh_grupo
  from hub.conversas c
  order by c.ultima_msg_em desc nulls last;
end;
$$;

revoke all on function hub.rpc_conversas_resumo() from public, anon;
grant execute on function hub.rpc_conversas_resumo() to authenticated;

create function public.hub_rpc_conversas_resumo()
returns table (
  fone_norm text,
  prospect_id uuid,
  cliente_id uuid,
  nome_exibicao text,
  ultima_msg_previa text,
  ultima_msg_em timestamptz,
  ultima_msg_direcao text,
  nao_lida boolean,
  eh_grupo boolean
)
language sql security invoker set search_path = pg_catalog
as $$ select * from hub.rpc_conversas_resumo(); $$;

revoke all on function public.hub_rpc_conversas_resumo() from public, anon;
grant execute on function public.hub_rpc_conversas_resumo() to authenticated;
