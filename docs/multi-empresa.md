# Hub: base multi-empresa

> **Estado (08/10/2026):** o grill de banco com a Luciana foi feito (§0).
> **050 e 051** só acrescentam (não mudam nada pra ninguém) e estão **autorizadas** a ir
> pra produção. Ver o registro de aplicação no `00 — Hub Dev.md`.
> **052 (a virada) e `20261008112355` (integração da Isa): 🔴 NÃO APLICAR.** Entram juntas
> só na entrada do 1º cliente pagante, com backup novo e ela testando junto (P12).
>
> Escrito em 07/10/2026 a partir das decisões do grill de 06/10 e 07/10 (seção B), do
> banco de produção lido **só com SELECT** e da pesquisa regulatória do Contator de 07/10.

## 0. Decisões do grill de banco (08/10/2026)

| # | Decisão | Onde está |
|---|---|---|
| P1 | Header `x-workspace-id`, automático com 1 workspace. Quem tem 2 ou mais tem um **workspace padrão** (`workspace_membros.padrao`), usado quando o front não manda header | 050 `current_workspace_id()` + `rpc_definir_workspace_padrao` |
| P2 | 3 vagas de qualquer papel; **contador fora da conta** | 050 (trigger de vagas) |
| P3 | **MUDOU:** ela e a Isa podem abrir o workspace de um cliente **só pra leitura**, numa **sessão de suporte** com motivo obrigatório e expiração curta (padrão 30 min, máx. 2h). **Escrita nunca.** Cada sessão fica registrada e **qualquer membro do cliente vê o log** | 050 `sessoes_suporte`, `rpc_plataforma_abrir_suporte` / `encerrar` / `rpc_suporte_acessos` |
| P4 | Isa é admin da plataforma já. Ela ainda não tem conta no projeto: o admin fica **pendente pelo e-mail** e vale no 1º login com esse e-mail (ninguém cria a conta). O e-mail dela **não entra no repo** (público): é inserido à parte, na aplicação | 050 `plataforma_admins(email, user_id)` |
| P5 | **Vários CNPJs** por workspace (CNPJ repetido no mesmo workspace continua proibido) | 050 + ajuste na `20261008112355` |
| P6 | **MUDOU:** dois workspaces dela: **Luh Panda** (nº 1, com freelas e Pandoka) e **Certo Agro**. O Certo Agro nasce **vazio**. Nenhum dado é movido sem ela confirmar a lista | 050 (seed) |
| P7 | aprovi.ai passa a usar `hub.workspaces`, em etapa própria (não agora) | — |
| P8 | BrasilAPI + CNPJá aberta de reserva, numa Edge Function com cache. API comercial antes do cadastro aberto | etapa 4 |
| P9 | Sócios: só nome + qualificação | 050 |
| P10 | Faixas do Simples | 050 |
| P11 | Bot de cobrança: n8n → **Edge Function** com `service_role` + **segredo por workspace** | 052 (grant) + etapa 4 |
| P12 | 052 entra na entrada do 1º pagante, com backup e ela testando. 050/051 já | §8 |
| P13 | O Dono do cliente convida o contador (a empresa assinante contrata o contador direto) | 050 |
| P14 | **MUDOU:** convite **só por e-mail** (Supabase Auth). O token **nunca** volta pro navegador: `rpc_criar_convite` devolve só o id, e só a Edge Function de envio (`service_role`) chama `rpc_convite_emitir_token`, monta o link e manda o e-mail | 050 |
| P15 | Cliente que cancela: export + dados apagados 90 dias depois | 050 (`encerrado_em`, `apagar_dados_em`) + job na etapa 6 |
| P16 | Os 4 PDFs vão pra pasta do workspace 1 na etapa 4 | etapa 4 |
| P17 | `migrations/000_baseline_hub_2026-10-08.sql`, gerada da estrutura de produção | repo |

⚠️ **Divergência entre as sócias (para alinhar):** a revisão da Isa no PR (08/10, 11h43 UTC)
tratou como vigentes **1 CNPJ por assinatura** e **contador ocupando vaga**. O grill de banco
com a Luciana decidiu o contrário (P5 e P2). Este PR segue o grill. A migration da Isa que
fazia o contador ocupar vaga foi **preservada** em `migrations/propostas/` (fora da cadeia de
aplicação). Da migration de integração dela, só saiu a trava de 1 CNPJ; o resto ficou intacto.

## 1. O que muda, em uma frase

Hoje o Hub é de **uma pessoa**: toda a segurança é `hub.is_admin()` = "o e-mail é o dela".
Depois da 052, cada linha de dado pertence a um **workspace** (uma empresa assinante), cada
usuário entra num workspace **por convite** com um **papel** (Dono, Operador ou Consulta), e o
banco só deixa ler e escrever o que é do workspace da requisição. Os dados dela viram o
**workspace nº 1**, e a experiência dela não muda.

## 2. O que já existia (levantado no banco em 07/10, só leitura)

| | |
|---|---|
| Tabelas no schema `hub` | 20 |
| Com `workspace_id` (migration 010, de 22/09) | 14. A coluna existe, mas **nenhuma policy usa**: o default é o workspace fixo `luhpanda` |
| Sem `workspace_id` | `recebiveis`, `custos_fixos`, `cobranca_envios`, `mensagens`, `eventos_auditoria`, `config` |
| 🔴 Tabelas **sem migration no repo** | `recebiveis`, `custos_fixos`, `config`, `cobranca_envios`. Só existem em produção. O schema real agora está versionado em `tests/multi-empresa/fixtures/hub_schema_prod_2026-10-08.sql` (só estrutura, sem dados) |
| RPCs de negócio (`rpc_*`, `bot_*`) | 68 em `hub`, quase todas com wrapper `public.hub_rpc_*`. 59 checam `hub.is_admin()` |
| Posse das RPCs | todas `SECURITY DEFINER` do `postgres`, que tem **BYPASSRLS**. A RLS não vale dentro delas: a única trava é o `if not hub.is_admin()` |
| Policies | 19, todas `hub.is_admin()` |
| Unicidade global | `clientes.slug`, `servicos.slug`, `conversas.fone_norm`, `mensagens.evolution_msg_id`, `cobranca_mensagens.etapa`, `eventos_agenda.google_event_id`, `reunioes.meetily_meeting_id`, `config.chave` |
| Storage | bucket `contratos` (privado), 4 PDFs em `<slug>/<arquivo>`, 4 policies com `is_admin()` |
| Auth | 8 usuários no projeto (o banco é dividido com o aprovi.ai) |
| aprovi.ai | tem o **próprio** `posta_ai.workspaces` (2 linhas) e `brands` (3). Não conversa com `hub.workspaces` (pergunta P7) |

## 3. Modelo de dados

```
auth.users ──< hub.workspace_membros >── hub.workspaces ──< hub.empresas (perfil fiscal)
                (papel, eh_contador)          │  status, vagas
hub.plataforma_admins (ela, Isa)              ├──< hub.convites (token só em hash)
                                              ├──< hub.workspace_modulos >── hub.modulos
                                              ├──< hub.workspace_canais (instância Evolution…)
                                              ├──< hub.workspace_aceites (termos, DPA)
                                              ├──< hub.acessos_sensiveis (leitura de dado fiscal)
                                              └──< TODA tabela de dado (workspace_id NOT NULL)
```

| Tabela | Para quê | Regras no banco |
|---|---|---|
| `hub.workspaces` (já existia) | a empresa assinante | + `status` (`onboarding`/`ativo`/`suspenso`/`encerrado`), `vagas` (padrão 3) |
| `hub.plataforma_admins` | quem pode criar workspace e convite (ela, Isa) | **não** dá acesso a dado de cliente (P3) |
| `hub.workspace_membros` | usuário × workspace × papel | `papel` ∈ dono/operador/consulta · contador = `consulta` + `eh_contador`, **não ocupa vaga** (P2) · `padrao` (P1) · trigger barra o 4º usuário e impede ficar sem dono |
| `hub.convites` | entrada por convite | token aleatório, só o **sha256** fica no banco · 7 dias · aceita só logado com o **mesmo e-mail** · uso único |
| `hub.modulos` / `hub.workspace_modulos` | módulos contratados | **sem preço** (repo público; preço fica no vault/planilha) · histórico `desde`/`ate` |
| `hub.workspace_canais` | como uma automação descobre o workspace | `(tipo, identificador)` único: `evolution_instancia`, `meta_phone_number_id`, `google_calendar`, `docuseal`, `meetily` |
| `hub.workspace_aceites` | LGPD: aceite de termos de uso / acordo de tratamento de dados, com versão e autor | único por documento+versão |
| `hub.acessos_sensiveis` | LGPD: trilha de **leitura** do perfil fiscal (a escrita já vai pra auditoria) | gravado pela própria RPC de leitura |
| `hub.empresas` (já existia) | o CNPJ que fatura dentro do workspace. Vira o **perfil fiscal** | ver §4 |

**Por que o perfil fiscal mora em `hub.empresas` e não numa tabela nova:** `hub.empresas` já é
"o CNPJ que emite" (hoje: o MEI dela, com `teto_anual_centavos`), e `clientes.empresa_id` já
aponta pra ela. Um workspace pode ter **vários CNPJs** (P5, grill 08/10); o mesmo CNPJ não se repete dentro do workspace.

## 4. Primeiro acesso: CNPJ → Receita → o dono confirma

1. Ela ou a Isa chamam `hub_rpc_plataforma_criar_workspace({nome, email_dono, modulos[]})`.
   Volta o `workspace_id` e o **token** do convite (o único momento em que ele existe em claro).
2. O dono abre o link, faz login com o e-mail convidado e chama `hub_rpc_aceitar_convite(token)`.
3. Tela de CNPJ → **Edge Function `cnpj-consultar`** (a construir, etapa 4) consulta a fonte
   pública, normaliza e devolve os campos. O front mostra e o dono revisa.
4. `hub_rpc_onboarding_salvar_empresa(...)` grava razão, fantasia, CNAEs, natureza, abertura (`aberta_em`, a mesma coluna da 043 que calcula o teto do MEI),
   situação, endereço, sócios (**só nome + qualificação**, o CPF mascarado é descartado),
   Simples/MEI com datas e a **sugestão** de regime, com fonte e ano.
5. `hub_rpc_onboarding_confirmar_regime({empresa_id, regime, faixa_faturamento})`: **só o Dono**,
   grava quem confirmou e quando (o check do banco recusa `regime` sem confirmação).
6. `hub_rpc_aceitar_termos({documento, versao})` e convites dos outros usuários e do contador.

**CNPJ é `text`, nunca número.** O CNPJ alfanumérico (IN RFB 2.229/2024) vale para novas
inscrições desde jul/2026. `hub.cnpj_valido()` aceita os dois formatos (12 posições `[0-9A-Z]`
+ 2 DV; valor do caractere = ASCII − 48; mesmo módulo 11) e aceita a pontuação já gravada.
Testado com o exemplo da Receita `12.ABC.345/01DE-35` e com o CNPJ do Banco do Brasil.

**Regime:** `simples_optante`/`simei_optante` vêm da Receita. `null` quer dizer "a fonte não
informou", e é diferente de `false`. Presumido/Real a consulta **não garante**. A BrasilAPI traz
`regime_tributario[]` por ano, vindo da ECF, com uns 2 anos de atraso (no teste, o último ano era
2024). Isso só **pré-preenche** `regime_sugerido` + `regime_sugerido_fonte` +
`regime_sugerido_ano`. O que vale é `regime`, sempre confirmado pelo dono.

**Faixa de faturamento** (proposta, P10): `ate_81k` (MEI) · `81k_360k` (ME) · `360k_4_8m` (EPP)
· `acima_4_8m`. São os cortes da LC 123. Para empresa aberta no ano, o limite do MEI é
proporcional, e isso fica com o módulo Fiscal.

### Fontes de consulta de CNPJ, testadas em 07/10/2026 (~23h20, Recife)

Consulta real com um CNPJ público (Banco do Brasil):

| Fonte | Respondeu | Simples/MEI | Presumido/Real | Limite / termos (o que foi possível confirmar) |
|---|---|---|---|---|
| **BrasilAPI** `brasilapi.com.br/api/cnpj/v1/{cnpj}` | 200 | `opcao_pelo_simples`, `opcao_pelo_mei` + datas de opção/exclusão | ✅ `regime_tributario[]` (ano, `forma_de_tributacao`) | Sem chave. O README do projeto diz: "Estamos em beta e ainda elaborando os Termos de Uso", "não abuse", "o volume deve ter a natureza de uma pessoa real", sem crawling. **Não fala de uso comercial.** Limite não publicado |
| **CNPJá aberta** `open.cnpja.com/office/{cnpj}` | 200 | `company.simples` / `company.simei` (`optant`, `since`, `history`) | ❌ | 5 consultas/min por IP (página oficial, via busca). Os termos proíbem usar a API para recriar serviço concorrente e sobrecarregar a infraestrutura. Existe API comercial com chave. A página de termos devolveu 429 na leitura direta |
| **ReceitaWS** `receitaws.com.br/v1/cnpj/{cnpj}` | 200 | `simples` / `simei` (`optante`, `data_opcao`, `data_exclusao`) | ❌ | Header `x-ratelimit-limit: 3` observado. Preço e termos de uso comercial **não confirmados** (a página não renderiza sem JS) |

Leitura (não é fato): para o volume de **convite** (dezenas de consultas por mês, 1 por cliente),
**BrasilAPI como principal + CNPJá aberta como reserva**, dentro de uma Edge Function com cache,
é aceitável. É a mesma conclusão da nota regulatória de 07/10. Antes do **cadastro aberto** ou de
revalidação periódica (alerta de exclusão do Simples), o uso fica comercial e recorrente: contratar
uma API com termos comerciais escritos (CNPJá comercial ou equivalente). Pergunta P8.

## 5. Isolamento: RLS + troca de dono das RPCs

### 5.1 Workspace da requisição: `hub.current_workspace_id()`

| Quem chama | Como o workspace é decidido |
|---|---|
| **Usuário logado** | header `x-workspace-id` **ou** o único workspace ativo dele. Se o header aponta para um workspace do qual ele não é membro ativo, a função devolve `NULL` e o acesso é negado. Com 2 ou mais workspaces e sem header, também devolve `NULL` (obriga escolher) |
| **Automação** (`service_role`, ou segredo do bot validado) | o GUC `hub.workspace_id`, que a **própria RPC** define a partir do canal (`hub.ingestor_definir_workspace('evolution_instancia', p->>'instancia')`) ou do segredo (`check_bot_secret` agora diz de qual workspace o segredo é). **Sem canal, cai no workspace 1: compat da etapa 3**, removida na etapa 5 |
| **anon** sem segredo | `NULL` |

Helpers: `hub.papel_atual()`, `hub.pode_ler()`, `hub.pode_escrever()` (Dono/Operador ou
automação), `hub.eh_dono()`, `hub.is_plataforma_admin()`, `hub.modulo_ativo(slug)`.

### 5.2 O pulo do gato: não reescrever as 68 RPCs

As RPCs são `SECURITY DEFINER` do `postgres`, que tem **BYPASSRLS**: a RLS não vale dentro delas.
Reescrever as 68 colocando `where workspace_id = ...` em cada consulta custaria 20 a 30h e
deixaria uma porta aberta a cada RPC esquecida. A 052 faz outra coisa:

1. cria o papel **`hub_rpc`** (`NOLOGIN`, **sem** BYPASSRLS);
2. passa a **posse** de toda `rpc_*`/`bot_*` (e `crm_ids`/`fone_no_crm`) para `hub_rpc`;
3. troca as 19 policies `is_admin()` por 4 policies por tabela:
   - **ler**: `workspace_id = (select hub.current_workspace_id())`
   - **inserir/alterar/apagar**: o mesmo **e** `(select hub.pode_escrever())`
4. `hub.is_admin()` passa a significar "tem workspace válido nesta requisição".

A partir daí, **qualquer** consulta dentro de **qualquer** RPC já passa pela RLS do workspace.
Funções novas também entram, inclusive as da tela "Novo cliente" (041+), desde que se chamem
`rpc_*`/`bot_*`. O `(select …)` em volta das funções faz o Postgres avaliar uma vez por consulta,
não uma vez por linha.

Ficam com o `postgres` (precisam enxergar além de um workspace): os helpers de identidade, as
funções de trigger, o `check_bot_secret` e as RPCs de conta/convite da 050, que fazem a
checagem explicitamente.

**Papel Consulta:** lê tudo do workspace. Se tentar **inserir**, a RLS devolve erro. Se tentar
**alterar ou apagar**, a linha simplesmente não é afetada. Os testes provam os dois casos. Na
etapa 4, as RPCs de escrita ganham `hub.pode_escrever()` explícito, pra devolver uma mensagem
amigável.

### 5.3 Integridade entre tenants: FK composta (051)

FK não passa por RLS. Sem cuidado, alguém do workspace B poderia criar um recebível **dele**
apontando pro `cliente_id` de A. A 051 dá a todo pai um `UNIQUE (workspace_id, id)` e troca as
17 FKs de uma coluna por **FKs compostas** `(workspace_id, pai_id)`. Também troca a 18ª,
`prospects.cliente_id`, que vem da 041 (tela "Novo cliente"); se a 041 ainda não tiver rodado, ela é pulada. A 052 **aborta**
se sobrar FK entre tabelas de dado sem `workspace_id`, para pegar coluna nova de migration futura. Nas que eram
`ON DELETE SET NULL`, usa `SET NULL (coluna)` (PG15+), pra nunca zerar o `workspace_id`.

### 5.4 Unicidade por workspace (052)

Os 8 `UNIQUE` globais da §2 viram `(workspace_id, …)`: o mesmo telefone ou slug pode existir em
duas empresas. Cinco RPCs usavam `ON CONFLICT` nessas chaves e foram reescritas **só na lista do
ON CONFLICT**, com texto idêntico ao de produção: `rpc_registrar_mensagem`,
`rpc_enfileirar_saida`, `rpc_eventos_agenda_vincular`, `rpc_criar_rascunho_reuniao_agenda` e
`rpc_registrar_reuniao`. A `rpc_registrar_mensagem` também passa a ler `p->>'instancia'`, se vier.
`docuseal_submission_id` continua global, porque é por ele que o webhook acha o workspace.

### 5.5 Storage

Caminho novo: `<workspace_id>/<slug>/<arquivo>`. As policies olham a 1ª pasta. Os 4 PDFs de hoje
(`<slug>/<arquivo>`) contam como do workspace 1 até serem movidos (etapa 4).

### 5.6 Auditoria

`hub.eventos_auditoria` ganha `workspace_id`, preenchido pelo trigger a partir da própria linha.
Só Dono/Operador leem a do próprio workspace. A 050 também conserta o trigger para tabela sem
coluna `id`: a 037 lia `new.id` e quebraria em `workspace_modulos`.

## 6. Inventário: cada tabela `hub.*` e o que acontece com ela

| Tabela | `workspace_id` hoje | Backfill | FK composta (051) | Unicidade (052) | RLS (052) |
|---|---|---|---|---|---|
| `empresas` | ✅ | já era ws1 | pai | — | 4 policies |
| `clientes` | ✅ | — | `empresa_id` → empresas | `(ws, slug)` | 4 |
| `contatos` | ✅ | — | `cliente_id` | — | 4 |
| `servicos` | ✅ | — | pai | `(ws, slug)` | 4 |
| `contratos` | ✅ | — | `cliente_id` | — | 4 |
| `contrato_itens` | ✅ | — | `contrato_id`, `servico_id` | — | 4 |
| `demandas` | ✅ | — | `cliente_id` | — | 4 |
| `prospects` | ✅ | — | pai | — | 4 |
| `cobranca_config` | ✅ | — | `cliente_id` | — | 4 |
| `cobranca_mensagens` | ✅ | — | — | `(ws, etapa)` | 4 |
| `conversas` | ✅ | — | `cliente_id`, `prospect_id` | `(ws, fone_norm)` | 4 |
| `reunioes` | ✅ | — | `cliente_id`, `prospect_id` | `(ws, meetily_meeting_id)` | 4 |
| `eventos_agenda` | ✅ | — | `cliente_id`, `prospect_id` | `(ws, google_event_id)` | 4 |
| `recebiveis` | ❌ → 051 | via `clientes.workspace_id` | `cliente_id`, `contrato_id` | — | 4 |
| `custos_fixos` | ❌ → 051 | ws1 | — | — | 4 |
| `cobranca_envios` | ❌ → 051 | via `recebiveis` | `recebivel_id` | — | 4 |
| `mensagens` | ❌ → 051 | via `conversas` | `conversa_id` | `(ws, evolution_msg_id)` | 4 |
| `config` | ❌ → 051 | ws1 | — | PK `(ws, chave)` | sem policy (só `check_bot_secret`) |
| `eventos_auditoria` | ❌ → 051 (nullable) | do JSON da linha, senão ws1 | — | — | leitura Dono/Operador |
| `workspaces` | — | — | — | — | lê o próprio |
| **novas (050)** | `workspace_membros`, `convites`, `workspace_modulos`, `workspace_canais`, `workspace_aceites`, `acessos_sensiveis`, `plataforma_admins`, `modulos` | — | — | — | só via RPC de conta |

A 052 termina com uma **trava**: aborta se sobrar tabela sem `workspace_id NOT NULL`, policy que
dependa de `is_admin`, tabela sem RLS ou FK entre tabelas de dado sem `workspace_id`.

## 7. Impacto em Edge Functions, n8n e scripts

| Peça | Hoje | Depois da 052 (sem mudar nada) | O que muda na etapa 4 |
|---|---|---|---|
| `wa-send`, `reuniao-analisar`, `docuseal-integrar`, `agenda-google` (repassam o JWT dela) | `is_admin` = e-mail | funcionam: ela tem 1 workspace | repassar o header `x-workspace-id` quando o usuário tiver 2 ou mais · `wa-send`: instância vem de `workspace_canais`, não de `EVOLUTION_INSTANCIA` · `docuseal-integrar`: `EMAIL_CONTRATADA`/`NOME_CONTRATADA` (hoje fixos no código) vêm do perfil da empresa · `agenda-google`: refresh token e lista de calendários **por workspace**, não secret global |
| `docuseal-webhook` (`service_role`) | `is_ingestor` | cai no ws1 (compat) | achar o workspace pelo `docuseal_submission_id` (helper do `postgres`) e definir o GUC antes da RPC |
| `wa-groups`, `google-oauth-callback` | ver riscos R2/R3 | iguais | por workspace + checagem de membro |
| n8n `HUB — Conversas WhatsApp` (`bYWqiukkixOla1GN`, publicado) | `is_ingestor` (service_role) | cai no ws1 (compat) | mandar `"instancia": "<nome>"` no payload. Cliente com Meta Cloud API: `meta_phone_number_id` |
| n8n `HUB — Cobrança Automática` / `Espelho Planilha` (inativos) | segredo do bot + chave anon | ver R1: **não rodam hoje** | segredo **por workspace** (`hub.config` já tem `workspace_id`) · porta definida na P11 |
| `scripts/subir-reuniao` (segredo do bot) | `check_bot_secret` | o segredo dela é do ws1: funciona | nada |
| Front (`index.html`) | — | — (a tela única não é tocada neste PR) | seletor de workspace + `global.headers` no supabase-js · upload em `<ws>/<slug>/…` · telas de convite, onboarding e membros · esconder escrita para Consulta |

## 8. Plano de migração em etapas reversíveis

| Etapa | O quê | Muda comportamento? | Volta |
|---|---|---|---|
| **1 · 050** | tabelas de conta, perfil fiscal, helpers, RPCs de convite/onboarding/suporte, seed (ela = dono do ws1 **padrão** + dono do **Certo Agro** vazio + admin da plataforma + instância `LuhPessoal`). Na aplicação, fora do repo: Isa como admin pendente pelo e-mail | **não** | `rollback/050_down.sql` |
| **2 · 051** | `workspace_id` nas 6 tabelas + backfill + FKs compostas + índices + auditoria com workspace | **não** (default continua ws1) | `rollback/051_down.sql` |
| **3 · 052 + `20261008112355`** 🔴 não aplicar | a virada: `hub_rpc`, policies, defaults, unicidade, 5 RPCs, storage, `check_bot_secret` por workspace | **sim**, pra todo mundo menos ela | `rollback/052_down.sql` (recusa rodar se já houver dado de outro workspace) |
| 4 · (PR futuro) | Edge Functions e n8n mandam workspace · velocímetro do MEI no Dash só quando a empresa do workspace for MEI (hoje mostra o teto do MEI até pra workspace de Simples/Presumido) · `cnpj-consultar` · telas de convite/onboarding/membros · mover os 4 PDFs · RPCs de escrita com `pode_escrever()` explícito · seed das 4 mensagens de cobrança por workspace | sim | por PR |
| 5 · (PR futuro) | remover o **fallback ws1** das automações (sem canal = erro) | sim | 1 função |
| 6 · (PR futuro) | trava de módulo no banco (`modulo_ativo`) · Asaas · cadastro aberto | sim | — |

**Ordem obrigatória:** 037–044, 041/042 e `20261008112314`/`20261008112347` (todas já no ar em
08/10) antes; 050 → 051 agora; 052 + `20261008112355` juntas, na janela do 1º pagante.
A proposta da Isa em `migrations/propostas/` **não** está na cadeia. Pontos de aplicação:
- **Antes da 050:** dump completo do schema `hub` + dados. O projeto **não tem backup** (Free).
- **Depois da 052:** abrir o Hub logada e passar pelas telas, `get_advisors` (security) e
  `curl` sem sessão nas RPCs. Primeiro disparo do n8n assistido.

## 9. Testes (sem pgTAP: PGlite não traz a extensão; asserções em Node, mesma ideia)

```
cd tests/multi-empresa && npm install && node isolamento.test.mjs && node compat.test.mjs
```

- `fixtures/supabase_stub.sql`: o mínimo do Supabase (roles `anon`/`authenticated`/`service_role`,
  `auth.uid()/email()/role()` lendo `request.jwt.claims`, storage).
- `fixtures/hub_schema_prod_2026-10-08.sql`: **estrutura** do `hub` de produção (sem dados).
- **`isolamento.test.mjs` (90 verificações, todas passando):** backfill sem perda · CNPJ
  numérico e alfanumérico · a Luciana igual · convite (e-mail errado, reuso, token fora do banco)
  · vagas e contador · onboarding fiscal com rastro LGPD · **isolamento** (carteira, ficha por slug,
  recebíveis, dash, custos, CRM, conversas; sobrescrever, apagar, pendurar e marcar pago no outro
  workspace) · header forjado · papéis · automação por instância (mesmo telefone em 2 workspaces)
  e por segredo · storage por pasta · tabelas fechadas pra acesso direto · **rollback** completo.
- **`compat.test.mjs`:** chama **todas** as 76 RPCs `public.hub_rpc_*` como ela, antes e depois.
  As 64 que já existiam devolvem exatamente o mesmo resultado (ok ou a mesma mensagem).
  Rodado também com a **041 (PR #12) aplicada antes**: 78 RPCs, as 66 existentes iguais, e a FK
  nova da 041 convertida pela 051.

Quando houver Supabase local ou branch, os mesmos cenários viram pgTAP (`supabase test db`).

## 10. Perguntas do `/grill-me` de banco — respondidas em 08/10 (ver §0)

Formato: opções, com ⭐ na recomendação. Tudo que dava para descobrir lendo repo e banco já está acima.

**P1. Como o usuário escolhe em qual empresa está?**
a) ⭐ Header `x-workspace-id`, automático quando ele só tem uma (já implementado)
b) Workspace "atual" salvo no perfil do usuário (duas abas brigam)
c) Parâmetro em cada RPC (reescreve as 68)

**P2. As 3 vagas são:**
a) ⭐ 3 usuários de qualquer papel, com pelo menos 1 Dono; contador fora da conta — **DECIDIDO 08/10**
b) Exatamente 1 Dono + 1 Operador + 1 Consulta
c) Vagas por plano (mensalidade maior = mais vagas); o campo `vagas` já permite

**P3. Você e a Isa, como admins da plataforma, enxergam os dados do cliente?**
a) ⭐ Não. Só se o dono convidar vocês (como Consulta), e com rastro. Combina com "Isa TecInfo = operadora" da LGPD (implementado)
b) Leitura de suporte com registro, sem convite
c) Acesso total

**P4. A Isa entra como admin da plataforma já na 050?**
a) ⭐ Sim (preciso do e-mail de login dela)
b) Depois

**P5. Quantos CNPJs por assinatura? — DECIDIDO 08/10 (grill com a Luciana): vários.**
(A revisão da Isa registrou "um único CNPJ"; ver a divergência na §0.)

**P6. O que é seu e não é Luh Panda (Certo Agro, freelas, Pandoka) fica onde?**
a) ⭐ Tudo continua no workspace 1, como hoje
b) Cada negócio vira um workspace (você alterna pelo seletor)

**P7. O aprovi.ai tem `posta_ai.workspaces` próprio. Na fusão:**
a) ⭐ O aprovi.ai passa a usar `hub.workspaces` (1 conta = 1 cadastro), numa etapa própria depois desta
b) Mantém os dois separados e liga por tabela de vínculo

**P8. Consulta de CNPJ:**
a) ⭐ BrasilAPI (única que traz Presumido/Real da ECF) + CNPJá aberta de reserva, numa Edge Function com cache. Contratar API comercial antes do cadastro aberto
b) Contratar já uma API paga (CNPJá comercial)
c) Só ReceitaWS

**P9. Sócios vindos da Receita:**
a) ⭐ Guardar só nome + qualificação (implementado; o CPF mascarado é descartado)
b) Não guardar sócio nenhum
c) Guardar tudo o que vier

**P10. Faixas de faturamento estimado:**
a) ⭐ As do Simples: até 81 mil / até 360 mil / até 4,8 mi / acima (implementado)
b) Faixas comerciais próprias (quais?)

**P11. O bot de cobrança hoje não roda por nenhuma porta (R1). Qual porta?**
a) ⭐ O n8n chama uma Edge Function com o segredo do workspace; ela usa `service_role` (a 052 já libera `service_role` nas `bot_*`)
b) Dar USAGE do schema `hub` pro `anon` (desfaz a guarda documentada no `.gitignore`)
c) Wrappers `public.hub_bot_*` como SECURITY DEFINER

**P12. Quando aplicar a 052 (a virada)?**
a) ⭐ Na entrada do 1º cliente pagante, com dump manual antes e você testando junto
b) Já, mesmo sem cliente
c) Só depois do Supabase Pro (backup diário)

**P13. Quem convida o contador do cliente?**
a) ⭐ O Dono do cliente, direto (implementado)
b) Só vocês, pela plataforma

**P14. Como o convite chega?**
a) ⭐ E-mail pelo Supabase Auth (convite/magic link), com o token no link, válido por 7 dias
b) Vocês copiam o link e mandam no WhatsApp
c) Os dois

**P15. Cliente que cancela:**
a) ⭐ Workspace `encerrado`, export entregue, dados apagados em 90 dias (LGPD + porta de saída)
b) Guardar indefinidamente
c) Apagar na hora

**P16. Os 4 PDFs de contrato de hoje:**
a) ⭐ Mover pra `<ws1>/<slug>/…` na etapa 4 e tirar a regra de legado
b) Deixar como estão pra sempre

**P17. As 4 tabelas que só existem em produção** (`recebiveis`, `custos_fixos`, `config`, `cobranca_envios`):
a) ⭐ Uma migration `000_baseline` gerada da fixture, pra um banco novo nascer igual ao de produção
b) Deixar só a fixture de teste

## 11. Riscos

- **R1 (achado, pré-existente):** o bot de cobrança não roda hoje. Os wrappers `public.hub_bot_*`
  são SECURITY INVOKER, o `anon` não tem USAGE no `hub` e o `service_role` não tem EXECUTE nas
  `bot_*`. Os workflows estão inativos, por isso ninguém viu. O teste reproduz o erro.
- **R2 (achado, pré-existente, @seguranca):** `agenda-google` (ações `calendarios`/`listar`/`obter`)
  e `wa-groups` só exigem **qualquer** sessão válida do projeto. Elas não checam se é ela. O
  projeto tem 8 usuários (aprovi.ai junto), então qualquer um deles poderia listar a agenda e os
  grupos de WhatsApp dela. Conferir no painel se o cadastro está aberto.
- **R3:** o OAuth do Google sem `state` (P0 do PR #2) continua. Por workspace, isso vira
  token por cliente e precisa ser resolvido antes.
- **R4:** **sem backup** (Free). A 051 e a 052 mexem em constraint e posse de função. Dump
  manual antes é obrigatório.
- **R5:** CORS do header `x-workspace-id`: o gateway do Supabase precisa aceitar o header no
  preflight. Não dá pra testar em PGlite; testar no 1º deploy. Plano B: o front manda o workspace
  num claim (hook de JWT) ou no corpo da RPC.
- **R6:** fallback ws1 das automações (etapa 3). Enquanto existir, uma automação de outro cliente
  sem `instancia` grava no workspace dela. Por isso a etapa 5 existe e nenhum cliente deve ligar
  n8n antes dela.
- **R7:** a posse `hub_rpc` exige que o `postgres` possa dar `SET ROLE hub_rpc` (PG16+:
  `grant hub_rpc to postgres with set true`, incluído). Validar no projeto real numa branch ou
  em cópia antes.
- **R8:** o produto vendido divide o projeto com os dados reais dela e com o aprovi.ai (já
  registrado no grill de 06/10).
- **R9:** os testes são em PGlite com stub do Supabase, não no Postgres do Supabase.
  `compat.test.mjs` cobre chamada com argumento vazio, não o fluxo completo de cada tela. O
  teste no navegador, logada, continua obrigatório.

## 12. Contator: o que esta base deixa preparado (não implementa)

- **Regras fiscais parametrizadas são privativas de contador** (Res. CFC 1.640/2021, art. 3º,
  XXX, conforme a nota regulatória de 07/10). Quando existir a tabela de regras: `versao`,
  `vigencia_inicio`/`vigencia_fim`, `fonte_legal`, `aprovado_por_nome`, `aprovado_por_crc`,
  `aprovado_em`, e o motor só usa versão aprovada. O contador parceiro entra como **membro
  Consulta com `eh_contador`** no workspace do cliente, ou como papel de plataforma (decidir no
  grill do Contator).
- LGPD: assinante = **controladora**, Isa TecInfo = **operadora**. `workspace_aceites` guarda o
  aceite do acordo de tratamento de dados por versão. `acessos_sensiveis` guarda quem leu dado fiscal.
- O perfil fiscal (§4) é a entrada do Contator: regime confirmado, faixa, CNAEs e opção pelo
  Simples/MEI com datas.

## Revisão de integração — 08/10/2026

**Continua DRAFT; não aplicar nem liberar clientes externos ainda.** A 052 sozinha não cobre os helpers SECURITY DEFINER dos PRs #3 e #12. Em teste combinado, os helpers de estoque/Contator continuam como postgres e usam o workspace fixo da Luh, expondo o snapshot a outro assinante. A ativação contratual e os helpers de contato também precisam obedecer RLS.

A nova `20261008112355_multiempresa_integracao_modulos.sql` vem **depois** de 050/051/052, das migrations de estoque e das migrations 041/042 e suas correções, quando presentes. Ela troca os owners dos helpers por hub_rpc, resolve o workspace atual em estoque e Novo cliente, limita a um CNPJ por assinatura e resolve eventos DocuSeal por submission ID somente para service_role. Não altera migrations históricas. Executar todo o conjunto em manutenção, com tráfego bloqueado, e só reabrir depois da validação; não disponibilizar a 052 isoladamente. Instalar os módulos depois da virada exige uma migration de integração adicional, pois CREATE FUNCTION/REPLACE pode reintroduzir owner postgres.

Rollback: primeiro `rollback/053_integracao_down.sql`, depois 052_down, 051_down e 050_down, ainda em manutenção. A recusa da 052_down quando há dados de outro workspace permanece.

Validação reprodutível: `cd tests/multi-empresa && npm ci --ignore-scripts && npm test`. São 93 verificações de isolamento/rollback, compatibilidade das 64 RPCs existentes e um teste combinado com SQL dos PRs #3, #12 e #11 (snapshots sem dados, em fixtures/prs). Esse teste cobre leitura/escrita de estoque, isolamento Contator, Consulta sem escrita, criação de cliente no workspace correto, recusa de assinar contrato alheio e retry DocuSeal no segundo workspace. Um workflow executa a suíte no CI. As fixtures devem acompanhar novas alterações nesses PRs antes da implantação.

~~P5 (vários CNPJs) deixa de ser pendência: a decisão vigente é um único CNPJ por assinatura.~~ **Superado pelo grill de 08/10: vários CNPJs (§0).** As demais perguntas continuam pendentes, inclusive a proposta de acesso extra para contador fora das três vagas. A revisão técnica não aprova essa proposta comercial. Frontend multiempresa, roteamento de todas as integrações/arquivos e implantação/homologação completos continuam fora do escopo desta correção e impedem liberar o recurso em produção.

~~A correção complementar de limite de usuários aplica a regra vigente de **três usuários incluindo o contador**~~ **(superado pelo grill de 08/10: contador fora da conta; a migration foi para `migrations/propostas/`)**, sem liberar a exceção ainda proposta. O onboarding/convite rejeita o quarto usuário; a coluna ocupa_vaga fica verdadeira para todo usuário. Instalar essa migration nova também, ainda na manutenção, depois da correção de integração. Os testes de vagas cobrem a recusa de contador como quarto usuário. 050/051/052 ficam preservadas como histórico do desenho inicial, e não devem ser usadas isoladamente.

A lista workspace_modulos ainda é cadastro de módulos, não bloqueio de cada RPC por pacote contratado. O enforcement no servidor e o fluxo de contratação precisam ser implementados antes de venda/ativação multiempresa. Credenciais Google/Evolution, jobs, PDFs e UI devem ser homologados por workspace; não basta o teste SQL de isolamento.
