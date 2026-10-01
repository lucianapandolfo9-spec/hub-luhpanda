-- =====================================================================
-- 036 — QUARENTENA DO LEGADO CERTO AGRO
-- =====================================================================
-- Projeto: tscnqvuzlfagotirgjbz  ·  Data: 01/10/2026
--
-- CONTEXTO
-- Este projeto Supabase nasceu como o banco do Certo Agro e virou, por
-- falta de slot no plano free (2 projetos ativos por conta), um banco com
-- TRÊS sistemas dentro:
--     public    = Certo Agro      (legado)
--     posta_ai  = aprovi.ai       (vivo)
--     hub       = Hub Luh Panda   (vivo)
--
-- O Certo Agro migrou pro projeto dedicado `zctczffncbtgpmnyxfup`
-- (organização CERTO AGRO) em 30/09/2026. O front já aponta pra lá
-- (commit 95cee98) e os 7 workflows n8n ativos já usam a credencial nova
-- `p8kIYgy2me71bXCX`. O que sobrou aqui é cópia congelada.
--
-- O QUE ESTA MIGRATION FAZ
-- Move os objetos do Certo Agro de `public` para `_legado_certo_agro` e
-- revoga todos os grants. Isso tira as 13 tabelas de `public` — e portanto
-- do PostgREST, que só serve `public`. Ganho de segurança real: a anon key
-- deste projeto é publicada no config.js de dois repos PÚBLICOS
-- (aprovi-ai e hub-luhpanda).
--
-- QUARENTENA, NÃO DROP. Nenhum dado é perdido e o movimento é reversível
-- num comando (ver bloco ROLLBACK no fim). O DROP definitivo vira a
-- migration 037, dias à frente, depois de o Certo Agro novo rodar verde.
--
-- ⚠️ NÃO APLIQUE ESTA MIGRATION no projeto novo do Certo Agro
-- (zctczffncbtgpmnyxfup). Lá o schema `public` é o sistema vivo.
--
-- =====================================================================
-- PRÉ-CHECKS — todos VERDES em 01/10/2026 antes de aplicar
-- =====================================================================
-- 1. Nenhuma das 88 funções vivas (67 hub* + 18 posta_ai_* + 3 rpc_*)
--    referencia qualquer um dos 13 objetos do Certo Agro. Verificado por
--    varredura de `prosrc`, inclusive na forma qualificada
--    (`public.config`, `public.custo`, `public.assinatura` — os três nomes
--    ambíguos que também existem em `hub`).
-- 2. `pg_depend`: nenhuma view ou rule fora de `public` depende das 13.
-- 3. Os 9 triggers que usam as 32 funções do Certo Agro estão TODOS em
--    tabelas do Certo Agro — função e tabela se movem juntas. Nenhum
--    trigger em `auth.users`, `hub.*` ou `posta_ai.*` usa uma delas.
--    (Checado de propósito: `criar_assinatura_trial` está em
--    `public.fazenda`, não em `auth.users` — logo cadastro novo de usuário
--    do aprovi.ai / Hub não dispara nada do Certo Agro.)
-- 4. Os 31 triggers da Hub usam `hub.registrar_auditoria` e
--    `hub.set_updated_at` em tabelas `hub.*`. Intocados.
-- 5. Zero chamada às 13 tabelas pela API nas últimas 24h (edge_logs).
--    Ressalva honesta: a API de logs limita a janela a 24h.
-- 6. Última escrita nas tabelas: cotacao_arroba 28/09, pesagem 19/09,
--    custo 30/07. O workflow de cotação roda dia útil às 19h e não gravou
--    em 29 nem 30/09 → já estava repontado antes desta data.
-- 7. pg_cron tem 2 jobs, os dois do aprovi.ai. Nenhum do Certo Agro.
--
-- ⚠️ PENDÊNCIA CONHECIDA, NÃO BLOQUEANTE: 4 workflows n8n INATIVOS de
--    alerta (Base 5) ainda usam a credencial antiga `lXyU2loKV0NLFefm` e
--    leem estas tabelas:
--      fy63nCZYdAqRp7dd (Alerta 4) · qy31b3R5sSuOzHwC (Alerta 2)
--      cBzEuv2OqcGfATRP (Alerta 3) · 9KjmV9WZO2sbZdXD (breakeven, 2 nós)
--    Os quatro estão `active: false`, `activeVersionId: null`,
--    `triggerCount: 0` — nada dispara. E note: religá-los HOJE, sem esta
--    migration, seria PIOR — eles leriam dado congelado de 28/09 e
--    mandariam WhatsApp pro cliente como se fosse de hoje. Depois desta
--    migration eles falham alto em vez de mentir baixo.
--    ➜ Antes de religar qualquer um: repontar a credencial pra
--      `p8kIYgy2me71bXCX`. Registrado como pendência no vault do Certo Agro.
-- =====================================================================


create schema if not exists _legado_certo_agro;

comment on schema _legado_certo_agro is
  'QUARENTENA 01/10/2026. Objetos do Certo Agro, que migrou pro projeto '
  'zctczffncbtgpmnyxfup em 30/09/2026. Fora de public = fora do PostgREST. '
  'Sem grants para anon/authenticated/service_role. DROP definitivo (037) '
  'só depois de dias verdes no projeto novo. NAO reutilizar este schema.';


-- ---------------------------------------------------------------------
-- 1. VIEW antes das tabelas
-- ---------------------------------------------------------------------
-- Tecnicamente a ordem é indiferente (dependências são por OID), mas mover
-- a view é OBRIGATÓRIO: se ela ficasse em `public` lendo tabelas do
-- legado, continuaria exposta via PostgREST — justamente o que estamos
-- fechando.
alter view public.vw_lote_analise set schema _legado_certo_agro;


-- ---------------------------------------------------------------------
-- 2. As 13 tabelas
-- ---------------------------------------------------------------------
-- Índices, constraints, policies de RLS e triggers acompanham a tabela
-- automaticamente (são objetos dependentes, referenciados por OID).
--
-- 📌 A FK que cruza pra fora: `fazenda.owner_id -> auth.users(id)`
--    ON DELETE CASCADE. O schema `auth` não se move, a FK continua válida.
--    Nada a fazer.
--
-- 📌 Depois daqui, RLS deixa de ser a defesa destas tabelas. A defesa
--    passa a ser o revoke do passo 5 + estar fora do PostgREST.
alter table public.fazenda         set schema _legado_certo_agro;
alter table public.lote            set schema _legado_certo_agro;
alter table public.pesagem         set schema _legado_certo_agro;
alter table public.custo           set schema _legado_certo_agro;
alter table public.nutricao        set schema _legado_certo_agro;
alter table public.sanitario       set schema _legado_certo_agro;
alter table public.cotacao_arroba  set schema _legado_certo_agro;
alter table public.config          set schema _legado_certo_agro;
alter table public.acesso_beta     set schema _legado_certo_agro;
alter table public.plano_faixa     set schema _legado_certo_agro;
alter table public.assinatura      set schema _legado_certo_agro;
alter table public.ciclo_cobranca  set schema _legado_certo_agro;
alter table public.admin_sistema   set schema _legado_certo_agro;


-- ---------------------------------------------------------------------
-- 3. Sequences — varredura guardada, não statement fixo
-- ---------------------------------------------------------------------
-- 📌 APRENDIDO NA PRÁTICA, 01/10/2026: sequence com `OWNED BY` apontando pra
--    uma coluna da tabela **se move junto com a tabela**, automaticamente.
--    A primeira versão desta migration tinha
--        alter sequence public.plano_faixa_id_seq set schema _legado_certo_agro;
--    e falhou com `42P01: relation "public.plano_faixa_id_seq" does not
--    exist` — porque o passo 2 já a tinha levado. A transação rolou de volta
--    inteira (nada foi perdido), mas o statement fixo era frágil nas duas
--    direções: quebra se a sequence acompanha, e esquece se não acompanha.
--
-- Esta varredura resolve os dois casos: se todas acompanharam, o laço é
-- vazio e não faz nada; se sobrou alguma órfã em `public`, ela é movida e
-- o nome aparece no NOTICE.
--
-- ⚠️ Pega QUALQUER sequence que sobre em `public`. Hoje isso é seguro
--    porque nem a Hub nem o aprovi.ai usam sequence — os dois usam
--    `gen_random_uuid()` em tudo. A verificação confere isso asserindo
--    `public_sequences = 0` no fim. Se algum dia um dos dois passar a usar
--    sequence em `public`, troque este laço por lista fechada de nomes.
do $$
declare s record;
begin
  for s in select sequencename from pg_sequences where schemaname = 'public' loop
    execute format('alter sequence public.%I set schema _legado_certo_agro;', s.sequencename);
    raise notice 'sequence orfa movida para a quarentena: %', s.sequencename;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 4. As 32 funções — allowlist POSITIVA de nomes
-- ---------------------------------------------------------------------
-- 🔴 Statements GERADOS por introspecção
--    (format + pg_get_function_identity_arguments), não digitados.
--
-- 🔴 NUNCA use filtro negativo aqui (`not like 'hub%' and not like
--    'posta_ai%'`). Três funções do aprovi.ai — rpc_proximo_post_agendado,
--    rpc_marcar_resultado_publicacao, rpc_validar_upload — não têm o
--    prefixo `posta_ai_`, e um filtro negativo as arrastaria pra
--    quarentena. O aprovi.ai pararia de publicar e só se descobriria
--    quando o próximo post vencesse.
--
-- Contagem asserida: `public` sai de 120 para 88 funções
-- (67 hub* + 18 posta_ai_* + 3 rpc_*), com ZERO órfã.
alter function public.acesso_liberado() set schema _legado_certo_agro;
alter function public.admin_contas_pendentes() set schema _legado_certo_agro;
alter function public.admin_dashboard_clientes() set schema _legado_certo_agro;
alter function public.admin_set_acesso_beta(p_email text, p_ativo boolean) set schema _legado_certo_agro;
alter function public.admin_set_assinatura(p_fazenda_id uuid, p_plano_faixa_id integer, p_ciclo text, p_status text) set schema _legado_certo_agro;
alter function public.assinatura_em_modo_leitura(p_fazenda_id uuid) set schema _legado_certo_agro;
alter function public.bloqueia_escrita_trial_expirado() set schema _legado_certo_agro;
alter function public.cabecas_ativas_fazenda(p_fazenda_id uuid) set schema _legado_certo_agro;
alter function public.calc_arrobas(peso_vivo_kg numeric, rendimento numeric) set schema _legado_certo_agro;
alter function public.calc_conversao_alimentar(consumo_ms_total_kg numeric, ganho_peso_total_kg numeric) set schema _legado_certo_agro;
alter function public.calc_custo_arroba_produzida(peso_carc_inicial_kg numeric, peso_carc_final_kg numeric, custo_do_periodo numeric) set schema _legado_certo_agro;
alter function public.calc_custo_cabeca(custo_compra_magro numeric, custo_diario numeric, dias numeric, custos_fixos_rateados numeric) set schema _legado_certo_agro;
alter function public.calc_dias_para_meta(peso_atual_kg numeric, peso_meta_kg numeric, gmd numeric) set schema _legado_certo_agro;
alter function public.calc_gmd(peso_inicial_kg numeric, peso_final_kg numeric, dias numeric) set schema _legado_certo_agro;
alter function public.calc_lotacao(soma_peso_vivo_kg numeric, area_ha numeric) set schema _legado_certo_agro;
alter function public.calc_margem_pct(arrobas_totais numeric, preco_arroba_venda numeric, custo_cab numeric) set schema _legado_certo_agro;
alter function public.calc_margem_por_arroba(arrobas_totais numeric, preco_arroba_venda numeric, custo_cab numeric) set schema _legado_certo_agro;
alter function public.calc_margem_total(arrobas_totais numeric, preco_arroba_venda numeric, custo_cab numeric) set schema _legado_certo_agro;
alter function public.calc_peso_carcaca(peso_vivo_kg numeric, rendimento numeric) set schema _legado_certo_agro;
alter function public.calc_peso_projetado(peso_atual_kg numeric, gmd numeric, dias_futuros numeric) set schema _legado_certo_agro;
alter function public.calc_pico_cabecas(p_fazenda_id uuid, p_inicio date, p_fim date) set schema _legado_certo_agro;
alter function public.calc_preco_breakeven(custo_cab numeric, arrobas_totais numeric) set schema _legado_certo_agro;
alter function public.calc_receita(arrobas_totais numeric, preco_arroba_venda numeric) set schema _legado_certo_agro;
alter function public.calc_relacao_troca(preco_boi_magro numeric, preco_arroba_gordo numeric) set schema _legado_certo_agro;
alter function public.calc_simulador_vender_vs_segurar(peso_atual_kg numeric, rendimento numeric, gmd numeric, dias_segurar numeric, preco_arroba_hoje numeric, preco_arroba_futuro numeric, custo_diario numeric) set schema _legado_certo_agro;
alter function public.cancelar_minha_assinatura(p_fazenda_id uuid) set schema _legado_certo_agro;
alter function public.criar_assinatura_trial() set schema _legado_certo_agro;
alter function public.eh_admin() set schema _legado_certo_agro;
alter function public.faixa_do_pico(p_pico integer) set schema _legado_certo_agro;
alter function public.limite_uso_fazenda(p_fazenda_id uuid) set schema _legado_certo_agro;
alter function public.lote_verifica_limite_plano() set schema _legado_certo_agro;
alter function public.solicitar_acesso_beta(p_email text, p_codigo text) set schema _legado_certo_agro;


-- ---------------------------------------------------------------------
-- 5. REVOKE — é isto que fecha a porta
-- ---------------------------------------------------------------------
-- 🔴 Grants de objeto VIAJAM COM O OBJETO. As 13 tabelas chegam no schema
--    de quarentena ainda com os grants de `anon` e `authenticated` que
--    tinham em `public`. Sem este bloco, o movimento seria só cosmético:
--    PostgREST não as serviria, mas qualquer caminho que não passe por
--    PostgREST continuaria lendo.
revoke all   on all tables    in schema _legado_certo_agro from anon, authenticated, service_role;
revoke all   on all sequences in schema _legado_certo_agro from anon, authenticated, service_role;
revoke all   on all functions in schema _legado_certo_agro from anon, authenticated, service_role, public;

-- Schema novo não concede USAGE a anon/authenticated por default. Explícito
-- de propósito: a intenção fica legível, e protege contra um
-- `grant usage on all schemas` futuro.
revoke usage on schema _legado_certo_agro from anon, authenticated, service_role;


-- ---------------------------------------------------------------------
-- 6. Avisar o PostgREST
-- ---------------------------------------------------------------------
-- Sem isto o cache de schema do PostgREST continua anunciando as 13
-- tabelas até o próximo reload — e elas responderiam 500 em vez de 404,
-- o que confunde o diagnóstico.
notify pgrst, 'reload schema';


-- =====================================================================
-- ROLLBACK — escrito ANTES de aplicar, não depois
-- =====================================================================
-- Reverte tudo. Os grants originais NÃO são restaurados por este bloco:
-- o Certo Agro está fora deste projeto, então restaurar acesso de anon a
-- estas tabelas seria um retrocesso. Se um dia for necessário de verdade,
-- os grants originais eram os default do Supabase
-- (anon/authenticated com select/insert/update/delete + RLS como defesa).
--
-- begin;
--   alter view     _legado_certo_agro.vw_lote_analise   set schema public;
--   alter table    _legado_certo_agro.fazenda           set schema public;
--   alter table    _legado_certo_agro.lote              set schema public;
--   alter table    _legado_certo_agro.pesagem           set schema public;
--   alter table    _legado_certo_agro.custo             set schema public;
--   alter table    _legado_certo_agro.nutricao          set schema public;
--   alter table    _legado_certo_agro.sanitario         set schema public;
--   alter table    _legado_certo_agro.cotacao_arroba    set schema public;
--   alter table    _legado_certo_agro.config            set schema public;
--   alter table    _legado_certo_agro.acesso_beta       set schema public;
--   alter table    _legado_certo_agro.plano_faixa       set schema public;
--   alter table    _legado_certo_agro.assinatura        set schema public;
--   alter table    _legado_certo_agro.ciclo_cobranca    set schema public;
--   alter table    _legado_certo_agro.admin_sistema     set schema public;
--   alter sequence _legado_certo_agro.plano_faixa_id_seq set schema public;
--   -- as 32 funções: gerar os statements inversos com
--   --   select format('alter function _legado_certo_agro.%I(%s) set schema public;',
--   --                 p.proname, pg_get_function_identity_arguments(p.oid))
--   --   from pg_proc p where p.pronamespace='_legado_certo_agro'::regnamespace;
--   drop schema if exists _legado_certo_agro;  -- só se ficar vazio
-- commit;
-- notify pgrst, 'reload schema';
-- =====================================================================
