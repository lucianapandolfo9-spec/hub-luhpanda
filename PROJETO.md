# Hub Luh Panda — PROJETO.md

Painel único de operação da Luciana: carteira, funil, dinheiro, entrega, conteúdo e infra
num lugar só. Documento mestre — ler antes de mexer em qualquer coisa.

## O que é

Painel de operação — Fase 1 (Fundação + Carteira) e Fase 2 (Financeiro: dash, recebíveis,
custos fixos, cobrança automática) no ar. Desenho completo do sistema inteiro está no
Artifact aprovado (fluxograma) e no Obsidian Canvas dela (`Luh Panda/HUB - Canva Design.canvas`).

## Stack

HTML/JS vanilla + Supabase, mesmo padrão do `aprovi-ai` e do `arroba-certa` — sem build,
sem framework, publica no GitHub Pages. n8n na VPS Hostinger faz o trabalho pesado
(cobrança automática, espelho na planilha).

- `index.html` — a SPA inteira (login + rotas por hash: `#/dash` (padrão), `#/carteira`,
  `#/financeiro`, `#/custos`, `#/catalogo`, `#/cliente/:slug` com abas por pilar)
- `config.js` — URL e chave anon do Supabase (públicas por design; a proteção real é RLS + RPC)
- `style.css` — design system dark, **responsivo** (tabelas viram cards < 720px via `data-label`)
- `migrations/` — SQL versionado, na ordem em que foi aplicado

## Banco

Projeto Supabase **`arroba-certa`** (`tscnqvuzlfagotirgjbz`) — o mesmo do Certo Agro e do
aprovi.ai. **Schema isolado `hub`**, ao lado de `public` (Certo Agro) e `posta_ai` (aprovi.ai).
Nunca tocar nos outros dois schemas a partir daqui.

### Por que dividir em `hub.*` + wrappers em `public.*`

O schema `hub` não é exposto ao PostgREST — nenhuma tabela é alcançável direto pela API,
de propósito. Toda leitura/escrita passa por função `SECURITY DEFINER` dentro de `hub`.

Só que o PostgREST deste projeto só expõe o schema `public`. Por isso existem wrappers
finos em `public.hub_rpc_*` que só repassam pra função real em `hub.*` — **é o mesmo
padrão que o aprovi.ai já usa em produção** (`public.posta_ai_admin_*` envolvendo as
tabelas de `posta_ai`). Prefixo `hub_` evita qualquer colisão de nome.

O front-end (`index.html`) só chama `hubClient.rpc('hub_rpc_...')` — nunca acessa tabela
direto.

### Guardas embutidas no banco (não em lembrete)

- `hub.is_admin()` — `coalesce(auth.email(),'') = 'lucianapandolfo9@gmail.com'`. O `coalesce`
  é obrigatório: sem ele, uma sessão sem e-mail (`NULL = 'email'` → `NULL`) passaria pela
  checagem. Bug real, já pago uma vez no aprovi.ai (ver `PROJETO.md` dele, linhas 87-97).
- **Contrato não vira `ativo` sem porta de saída escrita** — `CHECK` físico na tabela
  `hub.contratos`. Testado: um `UPDATE` que tenta ativar sem `porta_saida_escrita_em` é
  recusado pelo Postgres, não pela aplicação.
- **`tem_contrato` na carteira só é `true` para contrato `assinado`/`ativo`** — não basta
  existir uma linha de contrato. Isso é o que faz o alerta "sem contrato formal" aparecer
  pra 7 dos 8 clientes hoje (só Imperio Ruby tem contrato 001/2026 assinado).
- Toda tabela tem trigger de auditoria (`hub.eventos_auditoria`) — quem mudou o quê, quando.
- RLS em todas as tabelas: só `hub.is_admin()` lê/escreve.

## Dados de hoje (seed real, aba "Set 2026" da planilha)

Fonte: `Luh Panda - Financeiro`, id `1XGvkY3nwH-6wV8nKcezseLKmPIwUYbGOQWeX0IKRNq4`.
**Só quem está na planilha entra aqui.** Capitalize, Bolão Fácil e Além Mar são projeto
(não mensalidade) e ficam de fora até ela decidir incluir.

8 clientes · 10 serviços de catálogo · 8 contratos (só Imperio Ruby formal) · 9 recebíveis
Set/2026 · 8 custos fixos.

## A planilha — agora é o hub que manda (Fase 2, decisão nova)

Fase 1 decidiu "hub espelha a planilha". **Na entrevista da Fase 2 ela decidiu o contrário
pro status de pagamento**: o bot de cobrança precisa saber *na hora* quem já pagou, e não
dá pra depender de alguém lembrar de atualizar uma planilha. Então:

- **O hub é a fonte pra "pagou ou não"** — ela marca pago na tela (`#/financeiro`),
  `hub.recebiveis.entrada_centavos`/`entrou_em` são a verdade.
- **O workflow `HUB — Espelho Planilha` escreve de volta** na aba do mês (só `Entrada` e
  `Data que entrou` — nunca `Falta`/`Status`, que são fórmula). Ela continua podendo abrir
  o Google Sheets pra olhar, só não digita mais lá.
- Isso só cobre a aba **Set 2026** por enquanto (decisão "só setembro" da Fase 2). Quando
  Out/Nov/Dez entrarem, o workflow precisa de um mapa competência→aba.

## As esteiras n8n (Fase 2)

Dois workflows na VPS (`mcp.luhpanda.com.br`), **criados INATIVOS de propósito** — regra
dela: confirmação antes de produção, primeiro disparo sempre assistido.

### `HUB — Cobrança Automática` (id `f18z9gLSG8yfyIUY`)
Diário 08h America/Recife → `hub_bot_cobrancas_do_dia` → régua D-3/D0/D+2/D+7 pro cliente
via WhatsApp (Evolution, instância `LuhPessoal`, credencial `Custom Auth account` reusada)
com a chave Pix no texto → se vencido +7 dias, sem vencimento ou sem WhatsApp cadastrado,
escala pra ELA em vez do cliente → `hub_bot_registrar_envio` trava duplicata (nunca manda
o mesmo lembrete duas vezes) → nunca cobra no fim de semana (escalação continua valendo).
Testado com pinData: as duas mensagens (cobrança e escalação) saem com tom e valor certos.

**Antes de ativar** (checklist no sticky do próprio workflow):
1. Colar o segredo do bot no node "Configuração" (ela recebeu o valor no chat)
2. Colar a chave Pix Itaú no mesmo node
3. Preencher a credencial n8n "Supabase Hub Anon" (httpTemplatedCustomAuth) com a chave anon
4. Confirmar fuso America/Recife nas Settings do workflow (já setado, só conferir)
5. Rodar execução manual e olhar o resultado antes de publicar/ativar

### `HUB — Espelho Planilha` (id `JbFQYb7Jy6vdnFOn`)
A cada hora → `hub_bot_pagamentos_pendentes_sync` → lê a aba Set 2026 → casa cada pagamento
pendente com a linha certa por nome do cliente (**por prefixo normalizado**, não igualdade
exata — "Pandoka" no hub tem o nome completo "Pandoka (eventos da família)", a planilha só
tem "Pandoka"; testado com pinData incluindo o caso das DUAS linhas "Pandoka" na planilha,
desambiguado pela que ainda está `Status ≠ Pago`) → escreve só `Entrada`/`Data que entrou`
via Sheets API `batchUpdate` (nunca toca `Falta`/`Status`/`Vence dia`) → confirma sync.
Mesma checklist de segredo/credencial antes de ativar.

**Segredo do bot**: gerado uma vez, guardado só como hash SHA-256 em `hub.config` — o valor
em claro só existe no n8n (nos dois workflows) e foi entregue a ela fora do código/repo.

## Deploy

GitHub Pages, repo `lucianapandolfo9-spec/hub-luhpanda` (público — exigência do plano
grátis; sem segredo real no código, a chave anon é pública por design e a proteção é RLS).

## O que NÃO está nesta fase

Sentinela de infra, projetos/fases, funil de venda, esteiras de conteúdo/tráfego, portal
do cliente, domínio próprio, Meetily→escopo→preço, importar Out-Dez. Ver o desenho completo
(Artifact do fluxograma) para o roadmap inteiro. Próximo passo natural: grill-me do módulo
Comercial, a partir do Canvas dela.

## Fase 3, Bloco 1.5 — ajustes da revisão dela (21/09/2026)

Seis ajustes pedidos depois do Bloco A no ar (detalhe no plano
`~/.claude/plans/users-luhpanda-quero-q-puxe-shimmying-grove.md`, seção A2):

1. **Dash** — visão padrão voltou a ser "Receita por mês" (chip **Ano**, série `por_mes`
   do `hub_rpc_dash` que já existia — sem RPC nova); os chips 7 dias/30 dias/Mês/
   Personalizado continuam.
2. **Clientes arquiváveis** — "Arquivar" na ficha (→ `status='encerrado'` + `saiu_em` +
   motivo opcional), toggle Ativos/Arquivados na Carteira, "Reativar" reverte. Nunca
   DELETE; usa colunas/CHECK que já existiam. De quebra, corrigido bug latente: salvar a
   ficha não apaga mais `razao_social`/`documento`/`origem`/`entrou_em` (o upsert
   sobrescreve tudo — agora tem passthrough).
3. **Demandas por cliente** — `migrations/007_demandas.sql` (tabela `hub.demandas` +
   3 RPCs no padrão), seção "Demandas" na ficha com data de entrega, flag 🔴 atrasada,
   criar/editar/apagar/marcar entregue.
4. **Contrato apagável** — `migrations/008_apagar_contrato.sql` (`rpc_apagar_contrato`,
   delete real; itens cascateiam e auditoria guarda o `dados_antes`), botão "Apagar"
   com modal de confirmação na ficha.
5. **Preços & Serviços** — `#/catalogo` virou grid de cards do mockup v2 (badge
   MENSAL/ÚNICO derivado da modalidade, preço laranja, "inclui", observação, lápis);
   campo "Inclui" entrou no formulário de serviço; rótulo renomeado (rota intocada).
6. **PDF de apresentação** — "Montar apresentação" entra em modo seleção → "Gerar
   PDF (N)" abre página branca com marca/contato + só os serviços marcados →
   `window.print()` (100% client-side, `@media print` esconde o app inteiro).

⚠️ **Migrations 007/008 nasceram como rascunho não aplicado** (sessão sem Supabase MCP,
mesmo caso da 006 no Bloco A). O front degrada com aviso amigável até aplicarem. Checklist
de aplicação no cabeçalho de cada arquivo.

## Fase 3, Bloco B — CRM (Kanban) + configuração de cobrança (22/09/2026)

Plano de 7 blocos, seção B (`~/.claude/plans/users-luhpanda-quero-q-puxe-shimmying-grove.md`).
Decisões da Luciana nesta rodada: (a) multi-tenant **opção mínima** — só coluna
`workspace_id` (default = workspace dela), sem `workspace_members` nem policy por
workspace; (b) textos da régua de cobrança nascem **placeholder** (RASCUNHO — copiar do
node Configuração do workflow `HUB — Cobrança Automática` antes de ativar o bot); (c)
Kanban **sem drag-and-drop** — mover de coluna é ação na ficha do prospect.

⚠️ **Migrations 010/011/012 nasceram como rascunho não aplicado** (sessão sem Supabase MCP,
mesmo caso das anteriores). Checklist de aplicação no cabeçalho de cada arquivo. Resumo:

- `010_multitenant.sql` — `hub.workspaces` (+ seed "Luh Panda") e coluna `workspace_id`
  retroativa em `empresas`/`clientes`/`contatos`/`servicos`/`contratos`/`contrato_itens`/
  `demandas`, via `hub.default_workspace_id()`. RLS não muda.
- `011_crm_prospects.sql` — `hub.prospects` (kanban de 6 colunas: Reunião marcada →
  Reunião feita → Precificando → Orçamento enviado → Contrato emitido → Cliente aberto;
  onboarding de 7 passos derivado da `coluna`, sem tabela extra) + RPCs (listar, detalhe,
  salvar, apagar, `rpc_converter_prospect_em_cliente`). `#/crm` (kanban) e `#/prospect/:id`
  (ficha) no front, portados de `vCRM`/`vProspect`/`KCOLS`/`ONBOARD` do
  `mockup-v2-frontend.html`.
- `012_cobranca_config.sql` — `hub.cobranca_config` (por cliente: método pix/mp_link, dia
  de vencimento, WhatsApp), `hub.cobranca_mensagens` (régua D-3/D0/D+2/D+7, texto
  placeholder) e `hub.cobranca_envios` (log, vazio até o bot ligar). Tela `#/cobrancas`
  **sem mockup de referência** — desenhada no design system das telas `#/custos`/
  `#/catalogo` (cards + modal). Não ativa o bot (D19/D20 continuam pendentes: chip
  dedicado + disparo assistido).

CRM e Cobranças saíram de `soon:false` pra `true` na sidebar (Contratos e Reuniões
continuam "em breve" — blocos C13/C15 seguintes).

**Verificado nesta sessão** (sem Supabase/Chrome MCP): sintaxe do `index.html` inteiro
parseada com sucesso (`new Function`), CSS com chaves balanceadas, e as funções de render
(`desenharCRM`, `desenharProspect` nos estados etapa-0/etapa-5-fechado/perdido,
`desenharCobrancas` vazio e com envio, todos os modais de prospect e de cobrança) rodadas
num harness Node com dados mock — nenhuma lançou exceção. **Isso não substitui a
verificação real**: falta aplicar as 3 migrations, testar as RPCs contra o banco de
verdade e navegar logada no Chrome (checklist completo no `Hub Dev.md`).

## Convenções

- Dinheiro sempre em **centavos** (`bigint`), nunca `numeric`/`float`.
- Todo `slug` é o identificador estável — nunca renomear silenciosamente.
- Toda alteração de schema é uma migration nova em `migrations/`, nunca editar uma antiga.
- Nunca commitar `service_role` key — este projeto não usa nenhuma; tudo roda com a chave
  `anon` + RLS + RPC.
