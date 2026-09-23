-- ============================================================
-- HUB LUH PANDA — 016: o n8n precisa LER a thread, não só escrever
--
-- Aplicada em 23/09/2026. Terceiro achado do mesmo teste ponta a ponta.
--
-- Sintoma: 403 `permission denied for function rpc_conversa_thread`.
--
-- Causa: na 013 eu troquei o guard para `hub.is_ingestor()` só nas funções
-- de ESCRITA. Mas o nó de IA precisa ler a conversa para ter contexto antes
-- de sugerir a resposta — e a leitura continuava admin-only, ou seja, só
-- funcionava com a Luciana logada no navegador.
--
-- Liberar a leitura da thread para o service_role não amplia superfície:
-- quem tem a service key já lê as tabelas direto. O que isso preserva é a
-- regra de ouro do projeto — ninguém toca tabela, tudo passa por RPC.
-- ============================================================

create or replace function hub.rpc_conversa_thread(p_fone text)
returns jsonb
language plpgsql stable security definer set search_path = pg_catalog
as $$
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
$$;

revoke all on function hub.rpc_conversa_thread(text) from public, anon;
grant execute on function hub.rpc_conversa_thread(text) to authenticated, service_role;
grant execute on function public.hub_rpc_conversa_thread(text) to service_role;
