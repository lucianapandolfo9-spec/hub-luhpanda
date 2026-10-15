# CRM lateral do WhatsApp — desenho fechado (grill de 15/10/2026)

> **Status:** desenho aprovado pela Luciana, **nada construído**.
> Esta PR é o ponto de partida: quem for construir commita **nesta mesma branch**
> (`docs/crm-lateral-desenho`), marca a checklist da PR e, quando tudo estiver testado,
> a Luciana faz o merge.
>
> Pesquisa completa (RD Station, concorrentes, repos de referência, riscos com fonte e data):
> vault, `Luh Panda/Dev/Hub — Pesquisa CRM lateral WhatsApp (out-2026).md`.

---

## 1. O que é

Um painel na lateral do **WhatsApp Web** (extensão do Chrome), no estilo do painel do
RD Station CRM: ao abrir uma conversa, mostra **quem é a pessoa na Hub**, em que **etapa
do kanban** ela está, o **próximo follow-up** e as **anotações**. Dá para mudar tudo ali
sem sair do WhatsApp.

**O kanban continua morando na Hub** (`#/crm`). A extensão é só uma janela para ele.

## 2. Decisões (não reabrir sem falar com a Luciana)

| # | Tema | Decisão |
|---|---|---|
| D1 | Escopo da V1 | **Etapa do kanban + follow-up, anotações, "virar prospect".** Mensagens prontas / "Usar no chat" ficam **fora** da V1 |
| D2 | Follow-up | Tabela própria **`hub.crm_followups`**, vale para **prospect e cliente**, guarda histórico (feito / não feito) |
| D3 | Anotações | **Linha do tempo** em **`hub.crm_notas`** (cada nota com data). O texto atual de `prospects.nota` migra como 1ª nota de cada prospect |
| D4 | Identificar o contato | **Lendo a tela (DOM)** — número ou nome no cabeçalho da conversa — **+ vínculo manual** quando só aparecer o nome salvo (a extensão lembra o vínculo). **Sem wa-js** e sem mexer nos módulos internos do WhatsApp |
| D5 | De quem são os contatos | **Só Luh Panda.** Contatos da Lead Performance continuam no RD deles; nada de lead da Lead no banco da Hub |
| D6 | Login da extensão | **Google** (Supabase OAuth via `chrome.identity`). Não mexe no modelo de e-mail do Auth (compartilhado com o aprovi.ai) |
| D7 | Lembrete do follow-up | **Só na Hub**: bloco "Follow-ups de hoje" no Dash + selo de atrasado no card do kanban. Sem WhatsApp/n8n na V1 |
| D8 | Distribuição | **Só da Luciana**, instalada "sem empacotar" (modo desenvolvedor) a partir de `extensao/` neste repo. Chrome Web Store só quando a Hub for vendida |
| D9 | Ordem | **Fase 1:** banco + follow-up e notas **dentro da Hub** → Luciana testa → **Fase 2:** extensão |

### Regras que valem para tudo

- **A extensão nunca envia mensagem, nunca clica nada no WhatsApp.** Só lê o cabeçalho da conversa e escreve na Hub. (Banimento é associado a envio automatizado; ler fica no patamar de RD/WaSeller.)
- **Se a extensão falhar, ela some** — nunca trava nem cobre o WhatsApp.
- **Sem `service_role` na extensão, nunca.** Só URL + anon key públicas (as do `config.js`) e a sessão da Luciana.
- Sessão do Supabase só no `chrome.storage.local` do **service worker** — nunca em `localStorage` da página do WhatsApp nem no content script.
- `host_permissions` só `https://web.whatsapp.com/*` e `https://tscnqvuzlfagotirgjbz.supabase.co/*`.
- O portão de tudo continua sendo `hub.is_admin()`. Nenhuma RLS muda.

---

## 3. Fase 1 — banco + Hub (sem extensão)

### 3.1 Migration `046_crm_followups_notas.sql`

Padrão do repo: arquivo em `migrations/` (raiz, **não** `supabase/migrations/`), schema `hub`,
RPC `security definer` + `set search_path to 'pg_catalog'` + `if not hub.is_admin() then raise exception 'acesso negado'`
na 1ª linha + wrapper `public.hub_rpc_*` (`grant execute` só para `authenticated`; `revoke` de `public, anon`).

**Tabelas**

```sql
hub.crm_followups (
  id uuid pk default gen_random_uuid(),
  workspace_id uuid not null default hub.default_workspace_id() references hub.workspaces(id),
  prospect_id uuid null references hub.prospects(id) on delete cascade,
  cliente_id  uuid null references hub.clientes(id)  on delete cascade,
  quando timestamptz not null,
  o_que text not null,
  feito_em timestamptz null,
  origem text not null default 'hub' check (origem in ('hub','extensao')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (prospect_id is not null or cliente_id is not null)
)
-- índice: (feito_em, quando) where feito_em is null

hub.crm_notas (
  id uuid pk default gen_random_uuid(),
  workspace_id uuid not null default hub.default_workspace_id() references hub.workspaces(id),
  prospect_id uuid null references hub.prospects(id) on delete cascade,
  cliente_id  uuid null references hub.clientes(id)  on delete cascade,
  texto text not null check (btrim(texto) <> ''),
  origem text not null default 'hub' check (origem in ('hub','extensao','migracao')),
  created_at timestamptz not null default now(),
  check (prospect_id is not null or cliente_id is not null)
)

hub.crm_vinculos_whatsapp (            -- D4: vínculo manual "nome na tela → contato"
  id uuid pk default gen_random_uuid(),
  workspace_id uuid not null default hub.default_workspace_id() references hub.workspaces(id),
  chave text not null unique,          -- nome exibido no cabeçalho (normalizado: lower + trim)
  prospect_id uuid null references hub.prospects(id) on delete cascade,
  cliente_id  uuid null references hub.clientes(id)  on delete cascade,
  created_at timestamptz not null default now(),
  check (prospect_id is not null or cliente_id is not null)
)
```

RLS ligada nas 3, policy `hub.is_admin()` (igual às outras tabelas `hub`). Trigger de auditoria
(`hub.registrar_auditoria`) e `set_updated_at` como nas demais.

**Migração de dado:** `insert into hub.crm_notas (prospect_id, texto, origem, created_at)
select id, nota, 'migracao', coalesce(updated_at, created_at) from hub.prospects where nullif(btrim(nota),'') is not null;`
— `prospects.nota` **continua existindo** (não apagar coluna).

**RPCs novas**

| RPC | O que faz |
|---|---|
| `rpc_crm_por_fone(p_fone text, p_nome text)` | Um JSON só para o painel: tipo (`prospect` / `cliente` / `fora`), ids, nome, etapa (`coluna`, `perdido`), valor estimado, próximo follow-up em aberto, últimas 10 notas, link da Hub. Busca por **`hub.fone_norm(p_fone)`** (nunca normalizar em JS); sem número, tenta `crm_vinculos_whatsapp` pela chave do nome |
| `rpc_prospect_mover(p jsonb)` | `{id, coluna, perdido, motivo_perda}` — **só** esses campos. ⚠️ **Nunca** usar `rpc_salvar_prospect` para trocar etapa: é upsert de todas as colunas e chamada parcial apaga nome/e-mail/valor/nota |
| `rpc_followup_salvar(p jsonb)` | cria/edita follow-up (`prospect_id` ou `cliente_id`, `quando`, `o_que`, `origem`) |
| `rpc_followup_concluir(p_id uuid)` | marca `feito_em = now()` |
| `rpc_followups_abertos(p_ate date)` | lista em aberto até a data (Dash e kanban) com nome e link |
| `rpc_nota_adicionar(p jsonb)` | `{prospect_id \| cliente_id, texto, origem}` |
| `rpc_notas(p jsonb)` | linha do tempo de um prospect ou cliente |
| `rpc_vincular_whatsapp(p jsonb)` | `{chave, prospect_id \| cliente_id}` (upsert pela chave) |

"Virar prospect" reaproveita `rpc_salvar_prospect` (é insert novo, com payload completo, origem `'WhatsApp'`).

**Segurança junto (achado de 15/10):** `hub.crm_ids(text)` e `hub.fone_no_crm(text)` são
`security definer`, executáveis por **qualquer** `authenticated` e **sem** `is_admin()`; o
cadastro do Auth é aberto por causa do aprovi.ai. Nesta migration: `revoke execute ... from authenticated`
e deixar só para quem realmente usa (conferir quem chama — workflow `HUB — Conversas WhatsApp`/edge
functions usam `service_role`). Conferir também em Settings → API → Exposed schemas se `hub` está exposto.

**Testes** (padrão `tests/novo-cliente/`, PGlite, `npm test`): portão `acesso negado` para não-admin
em todas as RPCs novas; `rpc_prospect_mover` não apaga campos; follow-up exige vínculo; migração
copia a nota; `rpc_crm_por_fone` acha por número com e sem nono dígito e pelo vínculo manual.
Depois de aplicar em produção: `get_advisors` (security) sem achado novo.

### 3.2 Telas da Hub (`index.html` + `style.css`)

- **Ficha do prospect (`#/prospect/:id`) e do cliente (`#/cliente/:id`):** seção **"Follow-up e notas"** — próximo follow-up (data/hora + o que fazer, botão "Feito", atalhos +1d / +3d / +7d), histórico de follow-ups feitos, linha do tempo de notas (mais nova em cima) com campo "nova nota".
- **Kanban (`#/crm`):** selo no card — 🔴 follow-up atrasado / 🟡 é hoje. Continua **sem drag-and-drop** (decisão de 22/09).
- **Dash:** bloco **"Follow-ups de hoje"** (atrasados + de hoje), cada linha com link para a ficha.
- Formulários novos usam `modalErro()` no `catch` (padrão de 29/09). Cuidado com **passthrough** em upsert (ver comentários de `salvarContrato`/`salvarClienteFicha`).

### 3.3 Critério de aceite da Fase 1

- [ ] Migration 046 com testes PGlite verdes e CI verde
- [ ] Aplicada em produção **só com OK da Luciana** (quem aplica é a sessão com MCP do Supabase)
- [ ] Notas antigas aparecem como 1ª nota de cada prospect
- [ ] Criar / concluir follow-up pela ficha; selo aparece no kanban; bloco no Dash
- [ ] `crm_ids` / `fone_no_crm` fechadas, nada do Bloco C (conversas) quebrou
- [ ] Luciana testou e deu ok → só então começa a Fase 2

---

## 4. Fase 2 — extensão Chrome (`extensao/`)

### 4.1 Arquitetura (Manifest V3)

```
extensao/
  manifest.json        MV3; content_scripts em web.whatsapp.com; permissions: storage, identity
  service-worker.js    supabase-js (storage = chrome.storage.local), login Google, chama as RPCs
  content.js           lê o cabeçalho da conversa aberta, monta o painel num Shadow DOM
  seletores.js         ⚠️ TODOS os seletores do WhatsApp num arquivo só (quebra = mexer só aqui)
  painel.css           tokens visuais da Hub (ver style.css: --fundo, --laranja, --ok, --warn, --bad...)
  vendor/supabase.js   versão fixada, sem CDN em runtime
```

- **Detecção (D4):** observar a troca de conversa (MutationObserver no cabeçalho) → extrair número
  (quando o título é `+55 ...`) ou nome. Mandar **cru** para `rpc_crm_por_fone(p_fone, p_nome)`.
  Grupo (`@g.us`): mostrar o cliente ligado ao grupo, se houver.
- **Vínculo manual:** quando só há nome e a RPC volta `fora`, botão **"Vincular"** com busca por
  nome de prospect/cliente → `rpc_vincular_whatsapp`. Próxima vez, acha sozinho.
- **Login (D6):** `chrome.identity.launchWebAuthFlow` + `signInWithOAuth({provider:'google'})`,
  redirect `https://<id-da-extensao>.chromiumapp.org/`. Fixar o ID com `key` no manifest e
  cadastrar o redirect no Supabase Auth (provider Google — o projeto no Google Cloud é o mesmo da
  Agenda). A conta Google precisa ter o e-mail `lucianapandolfo9@gmail.com` (é o que `is_admin()` checa).
- **Painel:** cabeçalho (nome, telefone, selo Prospect / Cliente / Fora do CRM) · **etapa** (6
  botões das colunas + "Perdido" com motivo) · **próximo follow-up** (data/hora, o que fazer, "Feito",
  +1d/+3d/+7d) · **notas** (lista + campo) · **valor estimado** · **"Abrir na Hub"** · **"Virar
  prospect"** (nome e número já preenchidos, origem "WhatsApp") · botão de recolher.
- **Efeito colateral a avisar a Luciana:** virar prospect faz o número entrar no CRM, e a partir
  daí o espelhamento da instância `LuhPessoal` (Bloco C) começa a gravar as mensagens **novas** dele
  na ficha. As antigas não entram.

### 4.2 Critério de aceite da Fase 2

- [ ] Instalada "sem empacotar" no Chrome dela, login Google ok, sessão sobrevive a fechar o Chrome
- [ ] Testado no WhatsApp real: prospect, cliente, grupo, número de fora (EUA), contato só com nome (vínculo manual), contato fora do CRM (virar prospect)
- [ ] Nenhuma ação de envio/clique no WhatsApp no código (revisar `content.js`)
- [ ] Desligar a internet / derrubar o Supabase → painel some, WhatsApp segue normal
- [ ] Registro no vault: `Luh Panda/Dev/00 — Hub Dev.md` (seção 🧠 Hub Luh Panda)

---

## 5. Estimativa

| Bloco | O quê | Horas |
|---|---|---|
| F1-a | Migration 046 + testes PGlite + segurança `crm_ids`/`fone_no_crm` | 3–4 h |
| F1-b | Ficha (prospect e cliente), selo no kanban, bloco no Dash | 2–3 h |
| F2-a | Esqueleto MV3, service worker, login Google | 3–4 h |
| F2-b | Detecção por DOM + vínculo manual | 2–3 h |
| F2-c | Painel (Shadow DOM) | 4–5 h |
| F2-d | Teste real + revisão de segurança + registro | 2 h |
| **Total** | | **16–21 h** |

## 6. Fora da V1 (backlog)

Mensagens prontas / "Usar no chat" · lembrete no WhatsApp via n8n · wa-js (só se o DOM ficar
inviável) · contatos da Lead Performance · publicação na Chrome Web Store.
