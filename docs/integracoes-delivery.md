# Hub — integrações oficiais de pedidos (Discovery 15/10/2026)

> STATUS: código de normalização e verificação iFood/Rappi em `integrations/delivery/core.mjs` com testes locais automatizados. **NÃO é um conector em produção**: ainda não há credenciais, onboarding dos parceiros, webhooks implantados, banco de pedidos nem painel ativo no Hub. Não criar pedido real a partir de um evento não autenticado.

## O que foi confirmado nas fontes oficiais

| Canal | Entrada | Segurança | Interações seguintes |
|---|---|---|---|
| iFood Food | Events via polling (~30s) ou webhook (apenas app com autenticação centralizada) | HMAC-SHA256 `X-IFood-Signature` sobre bytes crus do body; secret é o client secret do app | Buscar `GET /orders/{id}` (retry de 404 até 10 min), confirmação/cancelamento, início de preparo; webhook responder 202 em até 5s |
| 99Food | Aderente Open Delivery; evento webhook ou polling, sandbox | Credenciamento + fluxo/autorização definido no portal 99Food; **não assumir token nem assinatura sem sandbox** | Open Delivery: evento → ACK se polling → GET order → confirm/preparing/ready...; confirmar versão efetiva no portal 99Food |
| Rappi restaurantes | webhook `NEW_ORDER`, `ORDER_EVENT_CANCEL`, `ORDER_OTHER_EVENT` ou GET /orders | `Rappi-Signature: t=...,sign=...`: HMAC-SHA256(timestamp + '.' + **body bruto**); OAuth 2.0 client credentials; chamadas usam header `x-authorization: Bearer ...` | `SENT` → `TAKEN` / `REJECTED`, limite de 6 minutos; observar `NEW_ORDER_SCHEDULED` com valores provisórios em zero |

Fontes:
- iFood Food (Order): https://developer.ifood.com.br/pt-BR/docs/guides/order/
- iFood assinatura: https://developer.ifood.com.br/en-US/docs/food/guides/modules/events/webhook-signature
- iFood webhook request: https://developer.ifood.com.br/en-US/docs/food/guides/modules/events/webhook-request
- 99Food Dev: https://developer-food.99app.com/pt-BR/home
- 99Food na vitrine OD: https://aderentes.opendelivery.com.br/companies/68f696345e89f79a1563008a
- Open Delivery Orders: https://docs.opendelivery.com.br/protocol/orders/
- Rappi API: https://dev-portal.rappi.com/en/managing-user-orders/
- Rappi Auth: https://dev-portal.rappi.com/en/authentication-process/
- Rappi Webhooks/HMAC: https://dev-portal.rappi.com/en/webhook-events/
- Rappi contato integradores: https://merchants.rappi.com/pt-br/o-que-ofrecemos/sistema-pos

**Rappi Turbo é API distinta de armazéns/fulfillment**: não reutilizar sua autenticação, eventos ou endpoint para restaurantes convencionais.

## Fluxo de operação no Hub (a implementar)

1. Na plataforma, cadastrar estabelecimento dentro do workspace certo. Um workspace pode ter vários estabelecimentos, mas cada conexão da mesma plataforma é autorizada individualmente.
2. Criar aplicativo de integrador/homologar com as plataformas. O estabelecimento autoriza a loja no fluxo oficial. Salvar tokens somente cifrados no backend/secret manager, sem service_role nem client_secret no PWA.
3. Registrar conexão (provider, provider_store_id, workspace_id, estado, horário do último sync, permissões). O identificador externo é gerado/confirmado na autorização; **não confiar no workspace_id do webhook**.
4. Validar HMAC do body original antes de fazer `JSON.parse` (iFood/Rappi); validar autorização oficial Open Delivery/99 antes do parsing/persistência. Resolver exclusivamente pela associação server-side (provider, store_id); rejeitar loja não vinculada, conexão suspensa ou pacote não ativo.
5. Enfileirar evento em tabela com UNIQUE (provider, store_id, event_id); armazenar metadados mínimos sem PII. Confirmar recebimento apenas após gravação transacional. Webhook iFood precisa resposta rápida (202 em <=5s), não deve aguardar a busca de detalhes.
6. Job por fila, com retentativas e `GET order`, importa detalhes e itens, cruza SKU/cardápio, normaliza valor BRL em centavos e status. Garantir não reverter estado quando eventos atrasados chegarem e nunca transformar pré-aviso Rappi de valores zero em venda de R$0.
7. Tela Pedidos unificada: Novos/Aceitos/Em preparo/Prontos/Entregues/Cancelados, etiqueta de origem, horário, endereço apenas para usuário autorizado, prazo de aceite, impressão, status de conexão, avisos de falha; separação por workspace e estabelecimento em TODAS as queries.
8. Ação Aceitar/Recusar/Pronto deve chamar a API da plataforma através de outbox idempotente; nunca apenas mudar etiqueta local. Se rede falhar, mostrar PENDENTE e motivo, sem afirmar aceite.
9. Estoque: baixar apenas após etapa configurada por loja e **movimento idempotente** por pedido/item/status; cancelamento com compensação (não duplicar receita nem reserva). Conciliação separada da venda, custos/taxas/frete em colunas distintas.
10. Monitoramento: lag do webhook, mensagens não processadas, credenciais expiradas, limitações API, incidentes. Exportação/cancelamento respeitam política LGPD e prazo de retenção.

## Implementado neste PR (sem deploy e sem mexer nos dados existentes)

- Normalizador testável para eventos de iFood, 99Food/Open Delivery e Rappi que **não guarda dados pessoais**.
- `verifyIFood()` — HMAC bruto testado contra vetor oficial de `dummysecret`, sem reserialização do JSON.
- `verifyRappi()` — HMAC do timestamp/body, valida assinatura e rejeita timestamp fora da janela configurável.
- Deduplicação com namespace por provider+loja+pedido+evento e reconciliador anti-regressão.
- CI Node 22 sem dependências externas.

O normalizador **não identifica sozinho a legitimidade da chamada**. A aplicação somente poderá invocá-lo depois de checar assinatura/credenciais e licenças no servidor. 99Food depende de capturar/examinar os payloads e a autenticação reais homologados, não pode ser conectado com HMAC fictício.

## Bloqueadores antes de habilitar

- [ ] Resolver PR #15 multiempresa e #24 gate por módulo; criar entitlement de `pedidos_delivery` independente de pacotes até definição comercial.
- [ ] Conexões por loja, tabela de eventos/pedidos isolada, RLS/roles/storage, enfileiramento e Edge Function com resposta rápida.
- [ ] Conta de desenvolvedor iFood e homologação, webhook, fluxo OAuth e lojas autorizadas.
- [ ] 99Food cadastro/certificação e aprovação de aplicativo + sandbox, versão Open Delivery, authorization e exemplos reais.
- [ ] Rappi credenciais e habilitação webhook + sandbox, fluxo de captura/aceite/recusa, limites de tempo.
- [ ] Tela Pedidos completa e testes E2E: pedido, duplicata, 404/retry, agendado, cancelamento, falha, dois tenants mesma loja em provedores diferentes, token revogado e reconexão.
- [ ] Configurar credenciais por plataforma via painel admin/backend, nunca salvar no GitHub. Testar contra lojas fictícias antes da produção.

**Não mergear como se fosse integração funcionando ao vivo**: este PR é camada de domínio/autenticidade inicial, não produto completo.
