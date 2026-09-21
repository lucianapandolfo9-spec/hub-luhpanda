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

## Convenções

- Dinheiro sempre em **centavos** (`bigint`), nunca `numeric`/`float`.
- Todo `slug` é o identificador estável — nunca renomear silenciosamente.
- Toda alteração de schema é uma migration nova em `migrations/`, nunca editar uma antiga.
- Nunca commitar `service_role` key — este projeto não usa nenhuma; tudo roda com a chave
  `anon` + RLS + RPC.
