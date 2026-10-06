# Instalar Estoque e Contator no Supabase

Pacote de banco incluído no PR #3. Projeto existente: **HUB Luh Panda**, ID `tscnqvuzlfagotirgjbz`. Não criar outro projeto ou substituir a base existente.

## Arquivos e ordem de execução

| Ordem | Arquivo | Finalidade |
|---|---|---|
| 1 | [`_preflight_estoque_contator.sql`](../migrations/_preflight_estoque_contator.sql) | Verificar dependências e ausência dos objetos novos; somente leitura |
| 2 | [`20261006052445_estoque_contator_estrategico.sql`](../migrations/20261006052445_estoque_contator_estrategico.sql) | Instalar tabelas, RPCs, índices, RLS, permissões e auditoria em uma transação |
| 3 | [`_verificacao_estoque_contator.sql`](../migrations/_verificacao_estoque_contator.sql) | Verificar instalação, acesso, RLS e auditoria; somente leitura |

## Antes de instalar

1. Conferir o projeto acima no Dashboard e validar primeiro em homologação com a base atual da Hub. Esta migration depende da estrutura já existente até 036; não é uma instalação da Hub inteira.
2. Executar o preflight no SQL Editor como administrador do banco. Todas as linhas devem retornar `ok=true`. Se objetos novos já existirem, conferir o histórico: a migration não deve ser reaplicada sem análise.
3. Com os pré-requisitos presentes, conferir o workspace: `select hub.default_workspace_id() is not null as workspace_configurado;`. Deve retornar `true`. O preflight só verifica a existência das dependências; não certifica que a base legada está toda correta.
4. Conferir backup/recuperação da base e as políticas atuais antes da janela de instalação. A migration é aditiva e não altera recebíveis, contratos ou dados legados.

## Aplicação

Executar **o arquivo completo**, mantendo `begin;` e `commit;`, no SQL Editor do projeto correto. Ele também pode ser aplicado pelo mecanismo de migrations de quem administra a implantação; usar o mesmo SQL versionado no PR.

Se um comando falhar, não executar os comandos restantes isoladamente: encerrar a transação abortada com `rollback;`, corrigir a causa e conferir o estado antes de repetir. A conclusão do arquivo já envia `notify pgrst, 'reload schema';` para atualizar o cache da API.

Não mover as tabelas para `public`, não expor `hub` nas configurações de schemas da Data API e não conceder acesso direto às tabelas para fazer a tela funcionar. A interface usa as RPCs públicas abaixo.

## O que será criado

- **Seis tabelas privadas:** `hub.stock_locations`, `hub.stock_products`, `hub.stock_positions`, `hub.stock_orders`, `hub.stock_movements`, `hub.advisory_records`.
- **Cinco RPCs públicas:** `hub_rpc_modules_snapshot`, `hub_rpc_stock_save`, `hub_rpc_stock_move`, `hub_rpc_stock_order`, `hub_rpc_advisory_save`.
- Funções internas privadas, índices, FKs de workspace, RLS, triggers de auditoria e grants explícitos. Helpers internos não são executáveis pelo cliente; as fachadas exigem sessão válida e a guarda atual da Luh.
- Não exige novos buckets, Edge Functions, APIs pagas, variáveis de ambiente ou chaves privilegiadas no navegador. O código mantém a conexão existente de `config.js`.

## Conferência depois da instalação

1. Executar a verificação: deve retornar **19 linhas com `ok=true`**. Uma falha interrompe a liberação do frontend até corrigir a causa; não resolver abrindo permissões gerais.
2. Rodar os advisors de segurança/performance do Supabase. Distinguir os alertas dos objetos novos daqueles já existentes no projeto.
3. Entrar na Hub com a conta autorizada e validar `#/estoque` e `#/contador`: cadastro, gravação e recarga dos dados. Conferir entrada/saída, transferência, contagem e compra parcial; no Contator, diagnóstico, cenário, ação e revisão.
4. Conferir negação para sessão ausente ou outro usuário. A consulta no SQL Editor não substitui Auth/PostgREST: o editor não carrega a sessão da pessoa que usa a tela.
5. Validar duas sessões concorrendo pelo mesmo saldo/capacidade e uma repetição após timeout. Os testes locais usam conexão serializada e não substituem essa conferência.
6. Só depois integrar/publicar o frontend do PR. Mesclar o PR **não instala automaticamente o SQL no Supabase**; o workflow apenas executa checks.

## Reversão sem apagar dados

Se houver falha após a liberação, reverter o frontend para a versão anterior e suspender o uso dos dois módulos enquanto o banco é corrigido por uma migration nova. Preservar as tabelas e a auditoria. Não existe `DROP` automático de rollback neste pacote porque, após uso real, isso apagaria movimentações e dados contábeis.

## Validação entregue

A migration já passou nos testes locais de operações, transações, regras e acesso. Os scripts de implantação são testados contra Postgres local, inclusive com falhas introduzidas de RLS, permissões e função ausente para conferir que a verificação as detecta.

Conferência do projeto remoto em 06/10/2026: as 28 verificações de pré-instalação retornaram `ok=true`; os objetos novos ainda não existem. Foi executada somente a consulta de leitura. O teste local completo passou com **11 testes**, incluindo os scripts novos.

Esta atualização do PR prepara a instalação; **não aplica a migration no projeto remoto, não integra o PR e não publica o frontend**.

Referências: [funções e permissões](https://supabase.com/docs/guides/database/functions), [atualização do cache do PostgREST](https://supabase.com/docs/guides/troubleshooting/refresh-postgrest-schema).
