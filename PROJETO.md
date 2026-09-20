# Hub Luh Panda — PROJETO.md

Painel único de operação da Luciana: carteira, funil, dinheiro, entrega, conteúdo e infra
num lugar só. Documento mestre — ler antes de mexer em qualquer coisa.

## O que é

Fase 1 de um hub maior (desenho completo aprovado em Artifact, ver histórico de sessão).
Esta fase entrega: **carteira de clientes** com contrato, valor, vencimento e as guardas
de negócio embutidas no banco (nunca em lembrete).

## Stack

HTML/JS vanilla + Supabase, mesmo padrão do `aprovi-ai` e do `arroba-certa` — sem build,
sem framework, publica no GitHub Pages.

- `index.html` — a SPA inteira (login + rotas por hash: `#/carteira`, `#/catalogo`, `#/cliente/:slug`)
- `config.js` — URL e chave anon do Supabase (públicas por design; a proteção real é RLS + RPC)
- `style.css` — design system dark (mesmos tokens do fluxograma aprovado)
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

8 clientes · 10 serviços de catálogo · 8 contratos (só Imperio Ruby formal) · 9 itens.

## A planilha continua mandando

O hub **espelha** a planilha financeira, nunca o contrário — decisão explícita dela.
Nenhuma automação escreve nas colunas `Falta` e `Status` da planilha (são fórmula). Isso
é trabalho de fase futura (régua de cobrança); por ora o hub só lê o que já está decidido.

## Deploy

GitHub Pages, repo `lucianapandolfo9-spec/hub-luhpanda` (público — exigência do plano
grátis; sem segredo real no código, a chave anon é pública por design e a proteção é RLS).

## O que NÃO está nesta fase

Recebíveis/régua de cobrança, sentinela de infra, projetos/fases, funil de venda,
esteiras de conteúdo/tráfego, portal do cliente, domínio próprio. Ver o desenho completo
(Artifact do fluxograma) para o roadmap inteiro.

## Convenções

- Dinheiro sempre em **centavos** (`bigint`), nunca `numeric`/`float`.
- Todo `slug` é o identificador estável — nunca renomear silenciosamente.
- Toda alteração de schema é uma migration nova em `migrations/`, nunca editar uma antiga.
- Nunca commitar `service_role` key — este projeto não usa nenhuma; tudo roda com a chave
  `anon` + RLS + RPC.
