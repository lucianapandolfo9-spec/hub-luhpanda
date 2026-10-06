# Hub — controle de estoque e Contator

Registro da reunião e implementação de 06/10/2026. Complementa o histórico comercial do [PR #2](https://github.com/lucianapandolfo9-spec/hub-luhpanda/pull/2).

## Decisões confirmadas

- O módulo Contator é uma **assessoria contábil estratégica e de planejamento tributário**, voltada a melhorar o lucro. Esta definição amplia a decisão anterior de oferecer apenas orientações fiscais.
- Estoque representa tudo que entra e sai do comércio. O cliente cadastra os itens, limites por mercadoria e espaço útil dos locais.
- Somente os pacotes 1 (R$ 997) e 5 (R$ 1.489) são iniciais e vendidos independentemente. Os demais somam ao preço da base: 2 (+R$ 549), 3 (+R$ 919), 4 / Contator (+R$ 498), 6 / Estoque (+R$ 788). A assinatura continua em R$ 269. Não foram alteradas regras comerciais neste código.
- Um CNPJ, três usuários, locais e aparelhos ilimitados são o objetivo comercial. O acesso atual da Luh continua restrito à administradora; liberar clientes exige a futura camada de membros, licenciamento e cobrança.

## O que entrou no código

Mantém HTML/JavaScript sem framework, o tema, login por link mágico, navegação por hash, moeda em centavos, schema privado `hub`, RPCs e auditoria existentes. Acrescenta `#/estoque` e `#/contador` ao menu Operação. Não altera contratos, recebíveis ou integrações existentes.

### Estoque

| Fluxo | Comportamento |
|---|---|
| Itens | SKU único, categoria, unidade, mínimo, alvo, máximo, embalagem, volume, fornecedor e prazo |
| Locais | Capacidade em litros, ocupação calculada e aviso de medição parcial quando faltam volumes |
| Entrada | Quantidade, lote, validade e custo de aquisição; custo médio ponderado por posição |
| Saída | Venda, consumo, perda e devolução ao fornecedor; valida saldo e registra custo histórico |
| Devolução do cliente | Entrada com custo de aquisição informado e motivo/documento |
| Transferência | Baixa e entrada atômicas, com conservação de quantidade e custo e validação do destino |
| Inventário | Contagem física gera ajuste; recusa salvar se o saldo mudou desde a abertura do formulário |
| Compras | Pedido, reserva de capacidade, cancelamento e recebimentos parciais sem exceder o pedido |
| Reposição | Lista automática quando o saldo atinge o mínimo; desconta compras abertas, arredonda embalagens e limita por máximo e espaço compartilhado |
| Indicadores | Capital imobilizado, custo consumido, perdas, cobertura, curva ABC por custo consumido e lotes próximos de vencer |
| Histórico | Movimentos e motivos auditados; tela e CSV mostram 90 dias, dados antigos continuam no banco |

O custo é gerencial, por produto/local/lote. Devoluções e contagens são movimentos novos: o histórico não é apagado. Vendas não geram recebíveis automaticamente para evitar duplicar o financeiro. Correções quantitativas devem usar contagem com motivo; uma rotina de estorno de custo e conciliação de vendas ainda precisa ser desenhada.

Controles aplicados no servidor: UUID de movimento com reenvio idempotente, bloqueio de saldo negativo, limite por item, capacidade física e lote vencido em vendas/consumo. Validade é conferida pela data de Brasília no servidor. Lote com a mesma identificação não pode receber outra validade. Sugestões compartilham o espaço livre por ordem de SKU, uma prioridade determinística; revisar a lista permite priorizar os itens de maior giro antes de contratar compras. Entradas físicas usam capacidade ocupada; pedidos reservam o espaço futuro, que pode precisar ser reorganizado se chegar mercadoria fora dos pedidos.

A Hub permanece online neste módulo: nenhuma baixa é confirmada antes do servidor. A Logo Ali oferece referências de movimentação e estoque; o mecanismo offline, POS e sincronização daquele projeto não foi transplantado sem validação. O volume em litros considera espaço útil de armazenamento e unidade de controle; não calcula encaixe geométrico, empilhamento ou restrições sanitárias.

### Contator

Fluxo: **diagnóstico → premissas → cenários → revisão → plano de ações → acompanhamento**.

- Cadastro da empresa, CNPJ numérico ou alfanumérico (14 posições, sem pontuação), atividade/CNAE, município/UF, regime atual, contador/CRC e objetivo estratégico.
- Diagnóstico por competência com receita, CMV/custos variáveis, fixos, folha/pró-labore, carga efetiva, outros tributos e créditos elegíveis. Não importar automaticamente recebimentos como receita fiscal: caixa e competência são diferentes.
- Cálculo de lucro gerencial, margem e ponto de equilíbrio. O ponto de equilíbrio pressupõe proporções estáveis de custo variável e taxa, com os outros tributos e créditos informados constantes.
- Cenários para MEI, Simples, Presumido e Real, cada um com premissas, fonte HTTPS, data-base, elegibilidade e revisão declarada. A confirmação exige nome do revisor e evidência; o sistema não verifica credenciamento nem certifica o parecer.
- Comparação de lucro mensal e projeção de 12 meses iguais. Bases operacionais diferentes geram aviso. Somente cenários com elegibilidade declarada confirmada participam da seleção matemática; isso não é uma recomendação automática de regime.
- Calculadora auxiliar de fator R, sem escolher anexo. A composição elegível, atividade, início da empresa e regras especiais precisam ser conferidos.
- Plano de ações/obrigações com instruções, responsável, prazo, valor previsto opcional, status e evidência obrigatória para concluir.
- Guias com fontes oficiais e criação de ações a partir deles. Exportação de dossiê JSON e impressão para revisão com o contador.

**Escopo desta entrega:** ferramentas e fluxo para desenvolver a assessoria e o planejamento com premissas explícitas. Não implementa um motor normativo completo de tributos, apuração oficial, emissão de guias, escrituração, envio ao fisco ou integração com software de contador. A carga efetiva deve ser calculada e documentada pelo responsável considerando atividade, período, local, retenções, créditos e regras vigentes. Não presume alíquota com IA nem promete economia de imposto ou lucro garantido. Evoluir para o planejamento completo contratado exige validar essas regras por segmento e organizar a prestação humana da assessoria.

## Pesquisa e escolhas propostas

Consultas em 06/10/2026, priorizando fontes primárias. Os trechos indexados do Sebrae fundamentam giro, classificação e previsão de demanda; algumas páginas do portal retornaram erro ao abrir. Não foram usadas como documentação tributária.

| Fonte | Aplicação na Hub |
|---|---|
| [Sebrae — Curva ABC](https://meuatendimento.sebrae.com.br/sites/PortalSebrae/artigos/voce-conhece-a-curva-abc-para-controle-de-estoque,5524ef559dc9e710VgnVCM100000d701210aRCRD) | Priorizar análise do consumo em valor; corte gerencial A/B/C em 80%/95%, com classificação pelo acumulado anterior ao item |
| [Sebrae — previsão e giro](https://sebrae.com.br/sites/PortalSebrae/artigos/previsao-e-giro-de-estoque-sao-dois-fatores-decisivos,5e9c438af1c92410VgnVCM100000b272010aRCRD) | Cobertura baseada em consumo registrado dos últimos 30 dias; não confundir ausência de vendas registradas com demanda zero futura |
| [CPC 16 (R1) — Estoques](https://www.cpc.org.br/CPC/Documentos-emitidos/Pronunciamentos/Pronunciamento?Id=47) | Registrar custo e perdas; separar custo gerencial de apuração contábil e avaliação de recuperabilidade |
| [Receita Federal — IRPJ](https://www.gov.br/receitafederal/pt-br/assuntos/orientacao-tributaria/tributos/IRPJ) | Evitar comparar regimes com uma alíquota nominal isolada; documentar carga efetiva e memória de cálculo |
| [Receita Federal — Manual PGDAS-D](https://www8.receita.fazenda.gov.br/SimplesNacional/Arquivos/manual/MANUAL_PGDAS-D_2018_V4.pdf) | Apoio ao fator R com confirmação profissional; não aplicar automaticamente 28% a toda atividade ou empresa |
| [Receita Federal — CNPJ alfanumérico](https://www.gov.br/receitafederal/pt-br/assuntos/noticias/2026/julho/receita-federal-gera-o-primeiro-cnpj-em-formato-alfanumerico) | Cadastro aceita letras nas 12 primeiras posições e mantém dois dígitos finais numéricos; formato não é consulta de situação cadastral |
| [Supabase — funções](https://supabase.com/docs/guides/database/functions) | Fachadas públicas invoker, implementações definer privadas com guarda de sessão, permissões explícitas e search_path fixo |

Próximas melhorias sugeridas: ponto de reposição por demanda durante o prazo do fornecedor e estoque de segurança, aprovação conjunta da lista de compras, alertas programados, leitura de código de barras, conciliação estoque/CMV/financeiro e calendário fiscal validado por atividade. São propostas, não funcionalidades já entregues. Cardápio digital, offline/PWA e permissões comerciais permanecem no roteiro geral.

## Instalação e validação

Pacote completo de instalação e SQLs de conferência: [SUPABASE_ESTOQUE_CONTATOR.md](SUPABASE_ESTOQUE_CONTATOR.md).

1. Revisar a migration `migrations/20261006052445_estoque_contator_estrategico.sql` em homologação, depois da estrutura existente até 036. Nome gerado pelo Supabase CLI 2.119.0 (`migration new estoque_contator_estrategico`) e preservado no diretório de migrations do projeto.
2. A base antiga não é reconstruída automaticamente por estes testes. Confirmar `hub.workspaces`, `hub.default_workspace_id`, `hub.is_admin`, `hub.registrar_auditoria` e os papéis Supabase antes de instalar.
3. Executar a migration completa em transação. Não contém dados de clientes, seeds de produção, extensões novas ou mudanças em tabelas legadas. Não expor o schema `hub` no PostgREST.
4. Publicar o frontend apenas depois de instalar as RPCs; sem a migration, as telas mostram erro com opção de tentar novamente.
5. Em ambiente local: `npm ci --ignore-scripts`, `npm run check` e `npm test`. As dependências npm são para testes; produção continua estática e sem bundler.
6. Em homologação: duas sessões reais disputando o mesmo saldo/capacidade; repetição de requisição após timeout; auditoria antes/depois; conta autorizada, conta não autorizada e anônimo; carga de dados de volume real. Rodar advisors do Supabase para segurança/performance antes de promover.

Os testes SQL usam Postgres embarcado PGlite, executam a migration real com roles e sessão simuladas, mais o trigger de auditoria real. Exercitam operações completas e rollback. PGlite serializa uma conexão; não substitui teste concorrente de duas conexões, PostgREST, Auth real ou advisors do projeto. O PR não aplica esta migration em produção.

As seis tabelas novas têm RLS, workspace obrigatório, FKs compostas, ausência de grants diretos para clientes e auditoria. A sessão exige `auth.uid()` e a guarda atual da Luh. Helpers internos não recebem grant de execução; RPCs privadas de fachada e wrappers públicos recebem apenas o necessário. Registro contábil possui revisão otimista para evitar sobrescrever edições de outra sessão. Snapshot retorna o conjunto do workspace; paginação será necessária para grande volume de itens/ações. Nenhuma chave privilegiada é colocada no navegador.

## Resultado da validação desta entrega

- `npm run check`: sintaxe dos módulos válida; o script inline de `index.html` também foi compilado sem erro.
- `npm test`: **10 testes passaram**, com operações e recusas no Postgres local, auditoria, rollback, privacidade, premissas, revisão e CNPJ alfanumérico.
- `npm run test:browser`: interface real testada com Chromium, Playwright e as RPCs da migration no banco isolado; autenticação simulada. Passaram desktop e celular de 390 px, cadastros, entrada/venda, compra parcial, diagnóstico, cenário, plano, evidência, impressão, exportação, login e acesso negado. Nenhum erro de JavaScript detectado.
- Para repetir a interface: `npx playwright install chromium` e `npm run test:browser`. Se usar um Chromium existente, informe `HUB_CHROMIUM_PATH=/caminho/do/chromium`. O servidor local e o navegador são iniciados pelo próprio teste; o teste não conecta ao Supabase de produção.
- O CLI agent-browser não conseguiu iniciar o daemon neste ambiente e os downloads usuais falharam. Foi utilizado Chromium empacotado para verificar com Playwright; essa adaptação só pertence ao ambiente de testes.
- Não foram executados advisors nem aplicada migration no projeto remoto. Concorrência entre duas conexões reais, integração Auth/PostgREST e grande volume continuam no roteiro de homologação acima.

## Pacote Supabase complementado em 06/10/2026

O mesmo PR inclui agora um [roteiro de instalação](SUPABASE_ESTOQUE_CONTATOR.md), preflight e verificação SQL de acesso/RLS/auditoria. O preflight foi executado em leitura no projeto remoto: 28 verificações passaram. A suite local ampliada passou com 11 testes. Nenhuma migration foi aplicada no projeto remoto.
