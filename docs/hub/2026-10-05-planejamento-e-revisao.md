# Hub — planejamento modular e revisão inicial
**Registro:** reunião de 05/10/2026 · **Fuso:** America/Sao_Paulo
**Versão:** 1.2 · **Participantes do registro:** Isabella; projeto compartilhado com Luciana
**Finalidade:** preservar o escopo informado, registrar a revisão do código existente e organizar a validação das próximas entregas.

## 1. Situação deste documento
Este registro contém requisitos da Isabella, decisões comerciais e operacionais confirmadas durante a conversa e propostas de evolução. Não afirma que as funcionalidades planejadas já estão implementadas. A presente alteração é somente documental: não modifica banco, pagamentos, automações, credenciais ou aplicação em produção.

| Classificação | Significado |
|---|---|
| Informado | Pedido expresso da Isabella nesta reunião |
| Confirmado | Decisão esclarecida nesta conversa |
| Proposto | Recomendação para avaliação de Isabella e Luciana |
| Pendente | Exige definição antes de implementação ou venda |
| Encontrado no código | Evidência estática; não comprova funcionamento em produção |
| Decisão anterior da Luh | Escolha explicitamente registrada em documentos/comentários do projeto |
| Verificado no ambiente | Consulta somente leitura de catálogo, migrations ou código implantado; não equivale a teste funcional |

## 2. Visão do produto
**Informado:** a Hub será um sistema de gestão de empresas, em PWA, com saúde do negócio, financeiro, carteira de clientes, cobrança, CRM, contratos, reuniões, orientação fiscal, marketing, estoque, cardápio digital e novas funcionalidades futuras.

O produto será organizado por funcionalidades comercializáveis, com habilitação por empresa. Cada empresa terá sua própria configuração, dados, usuários, módulos contratados e conexões externas.

Fontes a combinar:
- Hub da Luciana: [hub-luhpanda](https://github.com/lucianapandolfo9-spec/hub-luhpanda).
- Contator: documento existente `Contator_especificacao_produto_fiscal_v1.md`, de 29/09/2026, lido integralmente nesta revisão.
- Estoque da Logo Ali: [logo-ali-mercearia](https://github.com/isacustodio/logo-ali-mercearia).

**Proposto:** manter a operação atual da Luciana e evoluir a base gradualmente. Portar regras e componentes da Logo Ali para um modelo comum; o Contator fornece a especificação fiscal, ainda não um backend fiscal pronto.

## 3. Pacotes e preços registrados
### 3.1 Decisão comercial confirmada — atualização de 05/10/2026
**Somente os pacotes 1 e 5 são opções iniciais e podem ser comprados sozinhos.** Os pacotes 2, 3, 4 e 6 são adicionais: seu valor é somado ao do pacote inicial escolhido. Esta definição substitui a interpretação anterior de uma sequência obrigatória de 1 a 5.

A assinatura permanece **única de R$269/mês**, independentemente dos módulos liberados. Comprar o pacote 5 sozinho não libera automaticamente os pacotes 1, 2, 3 e 4.

| Pacote / módulo | Tipo de compra | Valor de liberação | Funcionalidades |
|---|---|---:|---|
| 1 — Financeiro | Inicial; pode ser comprado sozinho | R$997,00 | Visão geral financeira, vencimentos, ganhos, custos fixos, custos do negócio e pessoais, quem não pagou e o que está para vencer |
| 2 — Clientes e cobrança | Adicional a um pacote inicial | R$549,00 | Carteira com dados do cliente e valor fechado; bot de cobrança |
| 3 — CRM, contratos e reuniões | Adicional a um pacote inicial | R$919,00 | Quadro de tarefas, contrato automático, transcrição para histórico/contrato e agenda Google |
| 4 — Orientação fiscal / Contator | Adicional a um pacote inicial | R$498,00 | Orientação sobre obrigações do CNPJ, o que fazer/pagar/emitir, como fazer e o que encaminhar ao contador |
| 5 — Marketing | Inicial; pode ser comprado sozinho | R$1.489,00 | Editor de vídeo, gestão de tráfego, controle/programação de postagens e orientação para instalar e usar API Meta |
| 6 — Estoque | Adicional a um pacote inicial | R$788,00 | Mínimos e avisos, lista de compras, entradas/saídas e baixa, máximo considerando armazenamento |

### 3.2 Composição comercial e exemplos
O cliente escolhe o pacote inicial 1 ou 5 e acrescenta os módulos desejados. Os adicionais não podem ser vendidos como compra inicial isolada. A aquisição de um adicional não libera gratuitamente os outros módulos.

| Exemplo de contratação | Valor de liberação | Assinatura |
|---|---:|---:|
| Somente 1 — Financeiro | R$997,00 | R$269/mês |
| Somente 5 — Marketing | R$1.489,00 | R$269/mês |
| 1 + 2 — Financeiro, clientes e cobrança | R$1.546,00 | R$269/mês |
| 5 + 2 — Marketing, clientes e cobrança | R$2.038,00 | R$269/mês |
| 1 + 6 — Financeiro e estoque | R$1.785,00 | R$269/mês |
| 5 + 6 — Marketing e estoque | R$2.277,00 | R$269/mês |
| 1 + adicionais 2, 3, 4 e 6 | R$3.751,00 | R$269/mês |
| 5 + adicionais 2, 3, 4 e 6 | R$4.243,00 | R$269/mês |
| Todos os seis módulos, se contratados | R$5.240,00 | R$269/mês |

**Proposto para implementação:** validar no servidor a existência de ao menos um pacote inicial antes de habilitar 2, 3, 4 ou 6. Uma dependência técnica entre módulos não deve impor compra extra sem definição comercial: funcionalidades mínimas de cliente/documentos necessárias ao módulo contratado podem integrar seu núcleo interno, sem liberar telas e recursos de outros módulos.

**Confirmado:** venda por link de pagamento; o comprador escolhe como pagar. Poderá haver desconto à vista, com percentual ainda não definido. No parcelamento, o comprador absorve os encargos de crédito conforme condições exibidas no checkout. Um CNPJ por contratação, três usuários, aparelhos e locais ilimitados.

**Pendente:** compra/ativação do segundo pacote inicial na mesma empresa, percentual de desconto, número máximo de parcelas e início da mensalidade. Os exemplos acima usam preço cheio. Tarifa de processamento e juros do parcelamento são componentes distintos; o repasse dos juros não elimina automaticamente a tarifa cobrada do vendedor pelo gateway.

### 3.3 Mensalidade e custos variáveis
**Proposto:** os R$269/mês mantêm acesso aos módulos liberados, hospedagem, atualizações e suporte com condições definidas. **Confirmado:** mensagens usarão a API oficial da Meta e seu consumo ficará a cargo do cliente. Consultas fiscais e assinaturas eletrônicas ainda terão limites avaliados. Minutos de análise por IA, processamento de vídeo e arquivos também precisam de orçamento.

Aparelhos e locais ilimitados são direitos de acesso, e não promessa de armazenamento, processamento ou consumo de fornecedores ilimitados. Propor limites desses recursos separadamente, sem reduzir os aparelhos/locais confirmados.

Não existe evidência suficiente nesta revisão para garantir margem positiva nessa mensalidade. Modelar:
`receita recorrente − infraestrutura − consumo de APIs − suporte − tributos − taxas de cobrança`.
O orçamento gasto em anúncios do cliente é separado do preço do software. Registrar limites, excedentes e tratamento de falhas antes da proposta comercial.

## 4. Escopo funcional e critérios de aceite
### 4.1 Pacote 1 — Financeiro e saúde do negócio
**Informado:** entradas, vencimentos, custos fixos/pessoais/do negócio, inadimplência e próximos vencimentos.

**Proposto para completar o fluxo:**
- Contas a receber e a pagar com competência, vencimento, valor, categoria, origem, pessoa relacionada e comprovantes.
- Pagamento parcial, atraso, cancelamento, estorno, parcelamento e recorrência.
- Custos fixos geram contas de cada competência; editar o modelo não reescreve pagamentos anteriores.
- Separação de contas pessoais e empresariais; retiradas/aportes vinculados evitam contar a mesma transferência duas vezes. Despesa pessoal não reduz automaticamente o resultado operacional da empresa.
- Saldo inicial, caixa realizado e projeção de 30/60/90 dias. Mostrar previsto e recebido separadamente.
- Indicadores: recebimentos, despesas pagas, saldo, inadimplência, concentração de receita e rentabilidade gerencial. Não chamar caixa de lucro contábil.
- Importação OFX/CSV, conciliação manual assistida e exportação; conexão bancária como evolução dependente de fornecedor.

**Aceite mínimo:** lançar uma receita e uma conta recorrente, pagar parcialmente, anexar comprovante, identificar saldo pendente e atraso, filtrar o período e conferir os totais. Falha de carga deve mostrar indisponibilidade, não apresentar zero como se fosse dado confirmado.

**Dependência interna:** o financeiro básico pode guardar nome e identificação simples do pagador sem liberar a carteira completa do pacote 2.

### 4.2 Pacote 2 — Carteira e cobrança
**Informado:** dados do cliente, valor fechado e bot.

**Proposto:** cadastro PF/PJ, contatos, origem, anexos, condições comerciais, serviços contratados, histórico de pagamentos e comunicações. Régua configurável por empresa, prévia, pausar cobrança, horário/fuso, comprovante para conferência e tratamento de contatos inválidos.

Cobrança deve consultar o saldo atualizado antes do envio. Usar identificador único por empresa/recebível/etapa, reserva do envio e registro do retorno do provedor. Pagamento confirmado interrompe as próximas cobranças; pagamento parcial atualiza o texto. Comprovante recebido pelo chat não confirma crédito bancário sozinho.

**Aceite mínimo:** cliente com dois contratos e vencimentos distintos recebe a cobrança correta; reexecutar o trabalho não envia duplicata; pagamento, pausa e mudança de contato são respeitados.

**Confirmado:** API oficial da Meta para o produto; custo de consumo pago pelo cliente. **Proposto:** cada empresa conecta seu próprio número e conta WhatsApp Business, com faturamento direto do fornecedor quando disponível e painel do consumo na Hub. A cobrança oficial considera mensagens entregues e suas categorias/condições, não todo disparo indistintamente. Não fixar tarifa por mensagem no código.

O legado da Luh usa Evolution e inclui grupos. Manter esse caminho na operação atual durante a migração e homologar recursos/permissões da API oficial antes de prometer equivalência, especialmente grupos, histórico e áudio. A régua D-3/D0/D+2/D+7 e os mecanismos de deduplicação podem ser preservados.

### 4.3 Pacote 3 — CRM, contratos, transcrição e agenda
**Informado:** quadro de tarefas, contrato automático, transcrição automática, histórico e Google.

O Kanban de oportunidades e o quadro de tarefas são funções relacionadas, mas diferentes: tarefa tem responsável, prazo, prioridade, checklist e status; oportunidade tem etapa comercial e valor esperado.

**Proposto:** reunião → transcrição → resumo com decisões e tarefas → proposta com catálogo → minuta de contrato versionada → revisão → envio/assinatura → recebíveis conforme condição aprovada.

Preservar a decisão da Luh: a IA analisa a reunião e sugere escopo/proposta; preços são conferidos no catálogo pelo código. O contrato é montado mecanicamente a partir de modelo aprovado, sem IA inventando cláusulas. Usar o resumo revisado para preencher campos do modelo; não transformar toda fala transcrita em obrigação contratual sem revisão. Registrar gravação/transcrição e acesso aos arquivos conforme os consentimentos definidos para o produto.

Agenda: conexão OAuth por empresa/usuário, escolha de calendários, criar/editar/cancelar, fuso, disponibilidade e prevenção de duplicação. Sincronização incremental e paginação precisam tratar eventos excluídos e tokens expirados.

**Aceite mínimo:** agendar em uma conta Google de teste, registrar reunião, conferir resumo, gerar minuta com valores corretos, revisar e completar uma assinatura de teste com retorno autenticado. Reunião longa não pode perder o trecho final silenciosamente.

**Confirmado:** as reuniões serão feitas no Google Meet, com gravação e transcrição vinculadas ao histórico do cliente. Isso substitui, no produto novo, a dependência da ponte local Meetily; a operação atual da Luh permanece como referência.

**Proposto:** agendar com Meet → configurar gravação/transcrição quando a conta permitir → receber/consultar os artefatos disponíveis → importar a transcrição para a Hub → analisar → revisar → montar contrato. Gravação e transcrição são recursos distintos. A transcrição nativa exige edição compatível do Google Workspace e habilitação pelo organizador/administrador; não prometer o mesmo fluxo automático para toda conta Gmail gratuita. Arquivos ficam no Drive do organizador; sugerimos guardar referências de vídeo e o texto/histórico na Hub, com permissões próprias.

A API do Meet mantém as entradas de transcrição por 30 dias após a reunião; essa janela de coleta não define a retenção do histórico na Hub nem a dos arquivos no Drive. Se o artefato não foi gerado ou não está acessível, mostrar o motivo e permitir importação manual como proposta de contingência. **Pendente:** minutos de análise por IA, retenção, consentimentos, edição Workspace exigida e comportamento de contas sem esses recursos.

### 4.4 Pacote 4 — Orientação fiscal e saúde do CNPJ
**Confirmado:** módulo informativo. Explica o que a pessoa precisa fazer, como fazer, o que pagar/emitir e o que pedir para o contador assinar. Não utiliza software de contador como dependência do pacote e não inclui escrituração, transmissão de declarações ou emissão automática de guias.

A especificação Contator é referência para organizar regime, competência, documentos, responsabilidades, fontes e encaminhamentos. Seu escopo mais amplo de motores/conectores não está integralmente contratado para a Hub. Selecionar apenas o fluxo informativo aprovado.

**Proposto:** cadastro do CNPJ/regime/UF/município/atividade; calendário de obrigações; checklist por competência; instruções passo a passo com fonte oficial, data de revisão e link do portal; documentos anexados pelo usuário; lembretes; indicação de quando procurar o contador; dossiê exportável. Conteúdo deve ser revisado por profissional habilitado e versionado por vigência.

Fluxo: identificar obrigação → explicar dados/documentos necessários → orientar o portal e procedimento → indicar o responsável → usuário registra conclusão e anexa guia/recibo. Se o financeiro estiver contratado, uma guia informada pelo usuário poderá originar conta a pagar vinculada, sem duplicação. O fiscal deve continuar utilizável quando adicionado ao pacote 5 sem o pacote 1.

“Saúde fiscal” distingue checklist preenchido de regularidade oficialmente consultada. Exibir fonte/data; sem evidência, mostrar “não verificado”. Não declarar CNPJ regular apenas porque o usuário marcou tarefas como feitas.

**Pendente:** se haverá consultas externas de leitura e quais limites/custos terão; assinatura eletrônica de documentos também depende de limite e fornecedor. Esses consumos não ampliam automaticamente o pacote para software contábil. Honorários e atos profissionais do contador são externos ao preço de R$498.

**Aceite inicial proposto:** informar o perfil da empresa, visualizar obrigações aplicáveis, abrir instrução/fonte, registrar pendência ou conclusão com documento e exportar o material para o contador. Não executar ações fiscais externas como parte desse aceite.

**Limite da revisão:** o Contator original é datado de 29/09/2026. Suas alíquotas, limites e prazos não foram auditados integralmente; não copiá-los como constantes definitivas. Integra Contador permanece referência de uma possível evolução, não fornecedor exigido neste pacote.

### 4.5 Pacote 5 — Marketing
**Informado:** vídeo, tráfego, controle/programação de posts e tutorial da API Meta.

**Confirmado em 05/10/2026:** este é um dos dois pacotes iniciais e pode ser comprado sozinho por R$1.489,00, sem exigir os pacotes 1 a 4. Vídeo e gestão de tráfego pertencem ao pacote 5 e não integram o pacote 1. A implementação de Marketing deve funcionar com seu núcleo interno e conexões próprias.

**Proposta de entrega em etapas:**
1. Calendário editorial, biblioteca, aprovação, programação, fila de publicação e status real do provedor.
2. Relatórios de anúncios e orçamento, com conexão do cliente.
3. Editor inicial de vídeo com cortes, proporção, legendas e exportação.
4. Criação/alteração de campanhas e processamento de vídeo avançado após validação de custo e limites.

**Pendente:** “gestor de tráfego” significa software de acompanhamento, automação de campanhas ou serviço humano? Quais redes, formatos, duração e tamanho de vídeos? Essa definição muda esforço, consumo e suporte.

Conexão guiada deve ajudar a criar/configurar o aplicativo, autorizar contas, conferir permissões, testar e renovar conexão. Tutorial será versionado e validado na documentação do provedor. Reprocessar uma publicação precisa consultar seu estado para não duplicar posts. Alterações de orçamento devem ter limite e trilha de aprovação.

**Aceite mínimo:** conta de teste autorizada, conteúdo revisado e agendado, confirmação externa, falha com motivo e recuperação controlada.

### 4.6 Pacote 6 — Estoque, compras e capacidade
**Informado:** mínimos, aviso, lista automática, movimentação/baixa e máximo pelo espaço.

**Confirmado:** o usuário cadastra os itens e informa o espaço máximo disponível. Os locais são ilimitados para o CNPJ contratado. **Proposto:** formulário guiado por local com capacidade utilizável e, por item, unidade/embalagem, mínimo e volume/dimensões ou máximo manual. Informar apenas o espaço total não permite deduzir quantas unidades de cada mercadoria cabem; é necessário relacionar a ocupação dos itens ao local.

**Reaproveitar da Logo Ali:** produtos/categorias, saldo mínimo, movimentos, venda e baixa, persistência IndexedDB/Dexie, sincronização idempotente e regra de caixa principal offline.

**Adicionar:**
- Unidades e conversões (unidade, caixa, peso, volume), fornecedores, prazos de reposição e preços de compra.
- Locais de estoque: área, prateleira, depósito/freezer, capacidade utilizável, restrições e reserva de espaço para compras a chegar.
- Embalagem/dimensões ou volume por unidade armazenada; máximo operacional configurável por produto.
- Sugestão de compra com estoque disponível, reservas, pedidos a receber, alvo de reposição e restrições do local.
- Lotes/validade e inventário como evolução, especialmente para alimentos e cosméticos.

**Regras propostas:**
- `disponível = físico − reservado`.
- Disparar alerta quando disponível atingir ou ficar abaixo do mínimo.
- `necessidade = max(0, alvo − disponível − compras confirmadas a receber)`.
- Ajustar a sugestão ao máximo do SKU, capacidade compartilhada restante e múltiplo de embalagem.
- Não emitir compra/pagamento automaticamente: a lista é uma sugestão para revisão, salvo nova autorização comercial.
- Vários itens ocupam o mesmo local: não atribuir todo o espaço livre a cada SKU isoladamente.
- Volume estimado não garante encaixe físico. Dimensões, empilhamento, peso, circulação e temperatura podem limitar a quantidade; admitir máximo manual validado.

**Exemplo de aceite:** mínimo 5, saldo 4, alvo 12 e 3 unidades já compradas geram necessidade inicial de 5. Se o local só aceita mais 2 após reservar as compras a chegar, sugerir 2 e explicar a limitação de espaço. Nova execução não duplica a linha da lista.

Venda/entrada/cancelamento precisam alterar movimento, saldo e referência financeira em transação com chave de idempotência. Online, concorrência entre caixas exige validação no servidor. Offline, preservar a regra inicial: só o caixa principal conclui vendas; demais aparelhos consultam/preparam carrinho até reconectar.

### 4.7 Cardápio digital — escopo pendente
Foi incluído na visão geral, sem preço/pacote definido. Não presumir que está incluído nos R$788 de estoque.

**Proposta para validação:** catálogo público por link/QR, categorias, fotos, disponibilidade, adicionais, pedido, retirada/entrega, pagamento e status. Se houver produção própria, ficha técnica permite baixar ingredientes. Se for apenas exposição, não baixar estoque ao visualizar o item. Definir o evento de reserva/baixa/cancelamento antes de implementar pedidos.

## 5. Revisão do projeto existente
### 5.1 Fontes e método
- Hub: branch `main`, commit `e1f80629fdc61fd9ded315d3b1776a6b95d6203b`.
- Logo Ali: branch `main`, commit `237a75f8b8a24140e899a98f634d5714f33d94b0`.
- Inventário remoto completo do Hub reconferido: 54 arquivos, incluindo automação de segurança; análise do frontend, migrations, sete funções, documentação, ponte de reunião e configuração. A main permanecia no commit acima nesta atualização.
- Logo Ali: 48 arquivos textuais recuperados; imagem e lockfile não foram baixados. Foco em modelos, estoque, sincronização, políticas e documentação operacional.
- Contator: leitura integral de 267 linhas.
- Sintaxe do JavaScript inline do Hub validada com `node --check`: passou.
- Complemento de 05/10/2026: consulta somente leitura ao projeto Supabase informado (`tscnqvuzlfagotirgjbz`): histórico de migrations, tabelas/colunas/políticas, definições de funções selecionadas e código das sete Edge Functions da Hub. Todas as sete constavam `ACTIVE`. Não foram lidos registros individuais de clientes, tokens ou segredos.
- Também foi lido o código implantado de `publicar-posts-agendados`, do aprovi.ai, presente no mesmo projeto; isso não é revisão integral do repositório aprovi.ai.
- Sem sessão da Luh no aplicativo, aplicação de migrations, testes que alterem dados ou disparos externos. Implantação confirmada não prova validade de credenciais, conclusão de assinatura ou disponibilidade de gravação.
- Workflows n8n, Canvas aprovado, Obsidian `Hub Dev.md`, modelos externos e skills citadas pela Luh não constam integralmente no repositório nem estão acessíveis nesta sessão. As decisões abaixo são extraídas das referências existentes; não se afirma revisão desses materiais ausentes.

### 5.2 Matriz de reaproveitamento
| Área | Evidência | O que falta para a proposta comercial |
|---|---|---|
| Financeiro | Recebíveis, parcelas/recorrência e dashboard; `index.html`, migrations `006`, `034`, `035` | Contas a pagar com baixa, variáveis, conciliação, saldo e projeção completa |
| Custos | Tela de custos fixos e categorias negócio/pessoal | Despesa por competência com estado de pagamento e comprovante |
| Carteira | Clientes/contatos, contratos e tipos de cobrança; migrations `021` a `024`, `032`, `033` | Permissões por empresa/equipe e rentabilidade |
| Cobrança | Configuração/régua/log; migration `012`; Evolution e n8n descritos em `PROJETO.md` | Workflows n8n não constam no repo; exportação, homologação e credenciais por empresa |
| CRM | Kanban de prospects e demandas; migrations `007`, `011` | Quadro de tarefas com responsáveis e demais regras definidas |
| Contratos | Documento, armazenamento e DocuSeal; migrations `025`, `026`, `028` | Modelo/assinantes por empresa; comprovar assinatura ponta a ponta |
| Reuniões | Registro, ponte Meetily e análise Gemini; migration `027`, `scripts/subir-reuniao`, função `reuniao-analisar` | Integrar artefatos do Meet, verificar edição Workspace, filas, limites e texto longo |
| Agenda | Google OAuth, eventos e vínculos; migrations `029` a `031`, função `agenda-google` | Credenciais por empresa, autorização consistente e sincronização completa |
| Fiscal | Especificação externa Contator; Hub exibe indicador de receita/teto configurado da empresa | Construir orientação fiscal guiada, fontes e checklist; indicador isolado não comprova regularidade fiscal |
| Marketing | Telas Hub em construção; publicador Instagram do aprovi.ai implantado no Supabase compartilhado | Integrar/portar publicação com isolamento; editor de vídeo e tráfego continuam faltantes no Hub |
| Estoque | Implementado no projeto Logo Ali; `src/lib/inventory.ts`, `models.ts`, `sync.ts` | Portar para Hub, compras, máximos e armazenamento |
| PWA | Hub sem manifest/registro de service worker encontrados; Logo Ali usa `VitePWA` | Instalação da Hub, offline seletivo, atualização e ícones próprios |
| Cardápio | Não encontrado como módulo funcional no Hub | Definir escopo, preço e ligação estoque/financeiro |
| Módulos/assinatura | Não encontrado catálogo de direitos de acesso por plano no Hub | Licenças, pagamento da Hub, limites e enforcement no servidor |

### 5.3 Prioridades técnicas
| Prioridade | Achado e evidência | Recomendação |
|---|---|---|
| P0 — acesso | `hub.is_admin()` em `001` e router do `index.html` vinculam acesso ao e-mail original. `010_multitenant.sql` declara explicitamente não criar membros/políticas por workspace | Criar membros, papéis, acesso por empresa e validação em cada RPC; a coluna workspace isolada não torna o sistema multiempresa |
| P0 — integrações | Google usa refresh token global; Evolution usa instância global. Leituras de agenda e `wa-groups` não fazem verificação explícita de associação/administrador no corpo | Validar identidade e autorização antes de chamar o provedor, inclusive leitura; credenciais e IDs vinculados ao workspace |
| P0 — OAuth | Callback sem `state`, `error` refletido em HTML e token para cópia manual; padrões também presentes no código implantado lido | Vincular início/retorno à sessão, estado de uso único, escapar conteúdo e armazenar token protegido por empresa; nenhum teste de exploração foi executado |
| P0 — dados públicos | Migrations/PROJETO existentes incluem seed e referências de operação real | Preparar distribuição com dados fictícios. Revisar exposição existente e permissões antes do produto; documentação nova não replica valores/contatos pessoais |
| P1 — módulos | Sidebar organiza telas, mas não há direitos de acesso comerciais no servidor | Verificar licença por módulo em RPCs, jobs, exportações e armazenamento; esconder menu é só apresentação |
| P1 — financeiro | Custos são cadastros fixos; algumas cargas usam fallback vazio e dashboard usa agregado alternativo se RPC falha | Criar payable por competência e distinguir “sem dados” de falha/visão aproximada |
| P1 — cobrança | `bot_cobrancas_do_dia` implantada filtra saldo/etapa/envios, mas não consulta `cobranca_config.ativo` nem filtra status do cliente | Validar pausa/arquivamento no banco antes do envio; confirmar também o n8n, ainda não acessível |
| P1 — reconstrução | Tabelas/RPCs financeiras iniciais existem no banco, mas não estão todas definidas nas migrations do repo; há referências explícitas a essa lacuna na `027`/`034` | Criar baseline saneado e teste de reconstrução em homologação; não executar migrations históricas cegamente em banco novo |
| P1 — reunião | `reuniao-analisar` corta texto com `slice(0, MAX_TRANSCRICAO)` | Fragmentar/processar em fila ou rejeitar com explicação; registrar cobertura do conteúdo |
| P1 — assinatura | Código DocuSeal declara integração não testada ponta a ponta naquele registro | Conferir payload/assinatura do fornecedor, idempotência, download protegido e cenário real de teste; comentário histórico não prova estado atual |
| P1 — agenda | `listar` pede até 250 eventos e não percorre `nextPageToken` | Paginar e tratar exclusões, revogação de credenciais e recuperação de sync |
| P1 — frontend | SPA concentrada em um HTML grande; Supabase CDN usa versão major `@2` | Extrair módulos gradualmente, fixar dependências e automatizar validações críticas |
| P1 — PWA | Não há manifest/service worker na Hub. Logo Ali declara somente ícone 1536×1536 | Criar manifest próprio e ícones 192/512 e maskable; não copiar configuração sem validação Android/iOS |
| P2 — documentos | `PROJETO.md` possui partes históricas antigas apesar das migrations posteriores | Manter histórico e acrescentar índice/status atual sem reescrever decisões anteriores |

Pontos positivos a preservar: dinheiro em centavos na Hub, auditoria, constraints de negócio, migrations ordenadas, tratamento idempotente de recebíveis, preço de proposta baseado no catálogo, bucket privado e verificação HMAC do webhook no código, além da fila offline da Logo Ali.

A segurança efetiva precisa ser testada em homologação com duas empresas, usuários de papéis distintos e sessão sem acesso. Não houve exploração de endpoints nem prova de vazamento nesta revisão.

### 5.4 Decisões anteriores da Luh — preservar como base
Este inventário distingue escolhas explícitas da Luh de recomendações novas. As referências são relativas ao repositório da Hub. Decisões pessoais da operação dela não são automaticamente regras comerciais de todos os clientes.

| Tema | Decisão registrada / comportamento existente | Evidência | Como tratar no produto |
|---|---|---|---|
| Stack e deploy | HTML/JS vanilla, sem build/framework; GitHub Pages; n8n na VPS Hostinger | `PROJETO.md`, `index.html` | Preservar a base funcional; mudança de stack é proposta, não decisão tomada |
| Banco dedicado | A Luh anunciou um Supabase pago exclusivo da Hub em 22/09; compartilhamento era temporário | `PROJETO.md`, seção Banco | Executar essa intenção com migração planejada; não criar um segundo projeto sem conferir o atual |
| Login | Link mágico por e-mail no Supabase; tela já existe | `index.html`, `renderLogin`/`doLogin` | Adaptar convites e autorização para a equipe; não tratar login como totalmente ausente |
| Acesso atual | Só o e-mail da Luh; multiempresa mínimo apenas com `workspace_id` | `001`, `010`, router; guard/políticas conferidos no banco | Decisão adequada à operação individual; três usuários e vendas a empresas exigem nova autorização |
| Arquitetura de dados | Schema `hub` fora de exposição direta, RPCs/wrappers; centavos, auditoria e novas migrations | `PROJETO.md`, `001`–`004` | Preservar guardas e rastreio; ampliar para workspace em toda operação |
| Pagamentos e planilha | Hub é fonte do pago/não pago; Sheets é espelho, só Entrada/Data; mapa mensal ainda precisava evolução | `PROJETO.md`, Fase 2 | Preservar fonte de verdade; exportar/revisar workflow antes de reutilizar |
| Cobrança | D-3/D0/D+2/D+7, sem cobrança ao cliente no fim de semana; exceções vão à administradora; deduplicação | `PROJETO.md`, `bot_cobrancas_do_dia` implantada | Preservar régua como padrão configurável e homologar pausa; trocar provedor para Meta oficial no novo produto |
| Ativação do bot | Workflows nasceram inativos; primeiro disparo assistido | `PROJETO.md`, Fase 2 e Bloco B | Não presumir que estão ativos; sua condição atual no n8n não foi consultada |
| Conversas | Só contatos/grupos vinculados ao CRM; áudio transcrito, mídia marcada; IA sugere rascunho e pessoa revisa | `013`–`020`, `index.html` | Preservar vínculo e revisão; avaliar compatibilidade de grupos na API oficial |
| CRM | Seis etapas, sem drag-and-drop; onboarding derivado da etapa; demandas por cliente | `011`, `007`, arrays `KCOLS`/`ONBOARD` | Reutilizar funil; quadro de tarefas com responsáveis é complemento |
| Carteira | Exibição privilegia recorrentes; avulsos continuam com ficha, recebíveis e cobrança | `023`, `index.html` | Preservar filtros sem eliminar avulsos de seletores/cobranças |
| Comissão | Valor fixo ou percentual por cliente; percentual é referência, recebível lançado manualmente | `032`, `index.html` | Não prometer cálculo automático de comissão já existente |
| Arquivar/reativar | Pausa contratos ativos e demandas abertas/fazendo; restaura ativo/aberta, simplificação aprovada | `033`; funções conferidas no banco | Preservar histórico; detalhar eventual mudança de restauração antes de implementá-la |
| Recebíveis | Geração idempotente sob demanda ao abrir meses, pausa/fim de parcelas; revisões posteriores corrigem a versão inicial | `034`, `035`, RPC implantada | Reutilizar versão vigente; job programado futuro precisa aprovação de desenho e manter idempotência |
| Reajustes | Contrato atualiza futuros não pagos; valor manual travado prevalece; pago/parcial/passado/descrição não são sobrescritos | `035`; definição vigente lida | Regra central a preservar e verificar em homologação |
| Contrato | Molde mecânico sem IA; porta de saída escrita para ativar; preços do catálogo conferidos pelo código | `021`, `025`, `index.html`, `reuniao-analisar` | IA ajuda no resumo/escopo; modelo e condições são revisados; catálogo da Luh não é catálogo de pacotes da Hub |
| Assinatura | DocuSeal auto-hospedado na VPS; prestadora assina primeiro, cliente depois; webhook atualiza status e guarda PDF privado | `026`, `028`, funções implantadas | Reaproveitar ordem/trilha; limites e teste completo pendentes, assinantes/dados por empresa |
| Reuniões atuais | Meetily local; usuário escolhe uma reunião para subir; sem varrer toda a máquina | `027`, `scripts/subir-reuniao` | Preservar o controle sobre reuniões importadas; adaptar ao Meet por vínculo autorizado, sem captar reuniões pessoais indiscriminadamente |
| Análise de reunião | Gemini no servidor; modelo fixado; catálogo confere preço, sem IA inventar valor | `reuniao-analisar` | Reutilizar validação; modelo/custos/limites precisam homologação antes do lançamento |
| Agenda | Google é fonte do evento; Hub guarda vínculo; lê Gestão PDK e Luh Panda e cria no principal; Meet opcional | `029`–`031`, `agenda-google`, frontend | Manter fonte Google; calendários e OAuth passam a ser configurados por empresa |
| Alterar/cancelar evento | Convidados recebem atualização Google; cancelamento externo antecede desvinculação; conteúdo real de reunião é preservado | `030`, `agenda-google` | Preservar histórico e recuperação se apenas parte do fluxo completar |
| Marketing na Hub | Posts/Tráfego/Criação ainda levam a telas em construção | `NAV_GROUPS`, router | Não vender como editor/tráfego já entregue |
| Publicação existente fora da Hub | aprovi.ai tem publicador Instagram implantado com imagens, reels, carrossel e stories no código | Edge `publicar-posts-agendados` v20 | Candidato a reaproveitamento; ler repo/modelos de aprovação e homologar Meta antes de portar |
| Segurança e evolução | Chaves de fornecedores no servidor; gate de segredos; preservar outros sistemas e migrar sem perda | automação de segurança, `PROJETO.md`, `036` | Manter; não confundir chave publicável Supabase com segredo nem levar dados reais para seed comercial |

### 5.5 O que o ambiente confirmou e o que continua sem prova funcional
- O Supabase informado está ativo com schemas `hub`, `posta_ai` e `_legado_certo_agro`. A quarentena `036` consta aplicada; a descrição inicial de `public` como Certo Agro vivo no `PROJETO.md` está desatualizada. Separar Hub de aprovi.ai continua relevante.
- Há 20 tabelas `hub` com RLS habilitada. O acesso continua baseado em `hub.is_admin()` para o e-mail original; não há `workspace_members` no catálogo consultado. `recebiveis`, `custos_fixos`, `cobranca_envios`, `config` e `eventos_auditoria` ainda não têm `workspace_id` próprio, exigindo mapeamento do isolamento direto/por vínculo.
- O histórico registra as migrations `006`–`036` pelos nomes correspondentes, inclusive `028_docuseal`, e a correção `035b_fix_min_uuid`. Cabeçalhos “não aplicada por esta sessão” são históricos e não significam pendência atual. Não reaplicar por esse comentário.
- As sete Edge Functions da Hub estão implantadas. O código recuperado preserva os mesmos comportamentos principais da fonte; versões de Agenda/OAuth têm diferenças de comentários/formatação. Registrar o deploy consultado e aproximar documentação/código sem afirmar que os arquivos são byte a byte iguais.
- Agenda/OAuth ainda usam token global; callback sem `state` e leitura de grupos/agenda sem autorização empresarial explícita estão presentes no código implantado. Credenciais não foram acessadas e endpoints não foram explorados.
- O publicador aprovi.ai v20 tem um item por execução e espera limitada para processamento de vídeo, com comentário de correção em 05/10. Reaproveitar a fila, estado externo e recuperação; HTTP 200 do executor não é prova de publicação bem-sucedida.
- Contratos/assinatura, agenda, reunião/IA e mensagens não foram executados ponta a ponta. Não se comprova pela inspeção que uma API key esteja válida, que e-mails cheguem ou que a conta Meet permita gravação/transcrição.
- A reconstrução de banco novo precisa reconciliar SQL inicial financeiro ausente do repo, correções aplicadas e configurações externas. Não basta copiar os arquivos e rodá-los em sequência.

## 6. Arquitetura proposta
### 6.1 Núcleo compartilhado
**Confirmado:** um CNPJ, três usuários e aparelhos/locais ilimitados por contratação. **Proposto:** workspace/empresa, membros, papéis, assinatura da Hub, módulos habilitados, consumo, auditoria, documentos e conexões de fornecedores.

A tela de login existente usa link mágico por e-mail no Supabase Auth. Reaproveitá-la, retirar o e-mail pré-preenchido da Luh e substituir a autorização de um único e-mail por convites/permissões de empresa. Proposta inicial: três usuários ativos incluindo o proprietário; perfis administrador, financeiro e operador, com permissões dos módulos comprados. Inclusão do proprietário na contagem e matriz de papéis ainda são detalhes propostos. Login com senha/recuperação ou Google pode ser evolução, sem trocar o método atual por suposição.

O limite é de identidades autorizadas, não de instalações do PWA ou aparelhos conectados. Locais operacionais são cadastrados dentro do mesmo CNPJ; suporte a outro CNPJ exige outra contratação conforme a regra confirmada.

Distinguir o pagamento da assinatura da Hub dos recebíveis que cada empresa cobra de seus clientes. São domínios e credenciais diferentes.

Entidades conceituais novas:
- `workspace_members`, `workspace_roles`, `module_entitlements`, `subscriptions`, `usage_events`;
- `payables`, `payments`, `bank_reconciliations`;
- `integration_connections`, `integration_jobs`, `external_events`;
- `tax_obligations`, `tax_guidance_versions`, `tax_documents` (orientação e evidências, sem motor de transmissão);
- `products`, `stock_locations`, `stock_movements`, `purchase_suggestions`, `purchase_orders`;
- `content_assets`, `scheduled_posts`, `campaign_reports`.

Esses nomes são proposta, não migrations aprovadas. Mapear os equivalentes existentes antes de criar novas tabelas. Todas as relações devem impedir vínculo entre entidades de workspaces diferentes.

### 6.2 PWA e offline
PWA deve instalar pelo navegador, abrir em janela própria e funcionar com navegação adequada no celular. HTTPS e manifest são a base de instalação. Service worker será usado para a experiência offline desejada, sem tratá-lo como requisito universal de instalação.

Cachear a interface e dados locais permitidos; mostrar última sincronização, fila pendente e conflitos. Particionar armazenamento por workspace e usuário; limpar/invalidar cache na saída e mudança de empresa.

Estoque/vendas podem usar o padrão offline da Logo Ali. Cobrança, consultas fiscais externas, postagem, assinatura e chamadas Google continuam dependentes de servidor/conexão; não exibir como concluído apenas porque o pedido foi enfileirado.

Atualizações não devem recarregar a tela durante uma venda não salva. Prever instruções para adicionar à tela inicial no iOS, prompt onde suportado e verificação em Android/iPhone.

### 6.3 Integração dos três projetos
1. Mapear dados/regras, sem copiar bancos de produção.
2. Criar ambiente de homologação dedicado à Hub e dados fictícios.
3. Implementar isolamento/permissões/licenças.
4. Completar financeiro e PWA.
5. Portar estoque com transformação de `establishment_id` para o modelo da Hub e dinheiro consistente em centavos; migrar filas e IDs com cuidado.
6. Reaproveitar do Contator apenas o escopo informativo/guiado aprovado; consultas opcionais de leitura dependem de validação de custo, autorização e limites.
7. Adaptar Google, WhatsApp, assinatura e reunião para cada empresa.
8. Entregar Marketing por etapas.

Frontend React/TypeScript pode facilitar o reaproveitamento da Logo Ali, mas a troca completa de stack não está aprovada. Extrair funcionalidades do HTML atual e manter contratos de RPC permite evoluir sem reescrever tudo de uma vez.

## 7. Plano de entrega proposto
| Etapa | Resultado | Condição de conclusão |
|---|---|---|
| 0 — validação | Opções iniciais 1/5 registradas; custos, limites, dependências internas e cardápio definidos | Decisões comerciais registradas |
| 1 — fundação | Homologação, empresas/equipe, permissões, módulos e cobrança da Hub | Empresa A não acessa dados/arquivos/jobs de B; licença validada no servidor |
| 2 — financeiro/PWA | Contas a pagar/receber, fluxo de caixa, instalação | Totais, recorrências, estornos e uso móvel conferidos |
| 3 — carteira/cobrança | Cadastro, régua e conexões por empresa | Testes sem envio real indevido e sem duplicata |
| 4 — CRM/reuniões/contratos | Pipeline completo e Google por empresa | Reunião até contrato/recebível em cenário de teste |
| 5 — estoque | Portabilidade Logo Ali, reposição e capacidade | Concorrência, queda de rede, reconexão e lista sem duplicação |
| 6 — fiscal | Instruções, obrigações, checklist e documentos exportáveis | Revisão profissional do conteúdo e distinção entre orientação e evidência de regularidade |
| 7 — marketing/cardápio | Escopo aprovado implementado | Custos, permissões e confirmação externa validados |

A numeração de entrega é técnica e pode diferir da ordem comercial dos pacotes. Não definir prazos/horas antes de concluir o levantamento de integrações e tamanho dos fluxos faltantes.

## 8. Decisões confirmadas e propostas operacionais
### 8.1 Definições confirmadas pela Isabella — 05/10/2026
| Item | Definição vigente |
|---|---|
| Compra inicial | Somente pacotes 1 e 5 independentes; 2, 3, 4 e 6 somam ao inicial escolhido |
| Pagamento | Link; comprador escolhe meio; desconto à vista possível; encargos de crédito do parcelamento pelo comprador |
| Licença | Um CNPJ, três usuários, aparelhos e locais ilimitados |
| Login | Sistema deve ter tela de login; a existente da Luh será base para adaptação |
| Mensagens | API oficial da Meta; cliente arca com consumo |
| Fiscal | Informativo: o que fazer e como fazer; sem software de contador como dependência |
| Consultas e assinaturas | Limites ainda a verificar |
| Vídeo e tráfego | Exclusivos do pacote 5; não integram pacote 1 |
| Reuniões | Google Meet para gravação/transcrição, conforme elegibilidade da conta |
| Estoque | Cliente preenche itens e informa espaço máximo disponível |
| Hospedagem e operação | Solicitação de sugestões; recomendações abaixo ainda não aprovadas |

### 8.2 Proposta de hospedagem, recuperação, suporte e integrações
**Hospedagem — continuar a decisão da Luh.** Projeto Supabase pago exclusivo da Hub, separado do aprovi.ai/legado; vários clientes dentro da Hub com isolamento por empresa. Conferir configuração/plano atual antes de contratar ou migrar. Preservar frontend vanilla; GitHub Pages pode continuar inicialmente. Como opção para domínio, preview e PWA, sugerimos Cloudflare com arquivos estáticos. React/TypeScript não é pré-requisito desta evolução.

“Exclusivo da Hub” significa ambiente de produção do produto. Um servidor/projeto separado para cada cliente seria oferta especial com orçamento próprio, não pressuposto dos R$269. O Supabase fornece uma instância Postgres por projeto, mas Micro usa processamento compartilhado; isso não deve ser vendido como CPU física dedicada.

**Referência de custo consultada:** Supabase Pro a partir de US$25/mês para a organização, com créditos de compute cobrindo um Micro; projetos adicionais a partir de US$10/mês. Assets estáticos Cloudflare são gratuitos; Workers pago começa em US$5/mês se precisarmos dele. Cenário mínimo ilustrativo de uma organização Pro com um Micro e Workers pago: US$30/mês para a base do produto, não por cliente e não como custo total. Exclui outros projetos/homologação, VPS existente, domínio, e-mail transacional, backups externos, tráfego excedente, IA, vídeo, Meta, Google Workspace, assinaturas, tributos e suporte. Se mantivermos GitHub Pages ou apenas assets estáticos sem Workers pago, essa linha de US$5 não é necessária.

**VPS e automações.** A Luh já escolheu Hostinger para n8n/Evolution/DocuSeal. Reaproveitar onde fizer sentido após conferir recursos, responsáveis, backups e fronteira entre operação pessoal e SaaS. Não instalar novas ferramentas nem ativar workflows nesta etapa. Jobs de cobrança, publicação e importação precisam de fila, idempotência, retomada e alertas; n8n pode coordenar, enquanto regras financeiras e direitos de acesso permanecem no backend.

**Backup — proposta inicial.** Backup diário do banco, cópia externa criptografada com retenção de 30 dias, backup separado dos arquivos de contratos/anexos e dos serviços da VPS, e teste mensal de restauração em homologação. Supabase Pro oferece backups diários por sete dias; backup do banco não inclui os objetos do Storage. Propor meta inicial de perda máxima de 24h e restauração em até quatro horas, somente após validar em simulado. PITR é opção posterior com custo adicional; não incluí-lo silenciosamente na mensalidade. Vídeos do Meet preferencialmente no Drive do cliente, com referências na Hub; responsabilidades de retenção e acesso precisam constar na contratação.

**Suporte — proposta comercial.** Canal único por WhatsApp/e-mail ou chamados, segunda a sexta, 9h–18h de Brasília; primeira resposta em até um dia útil, incidentes críticos priorizados com meta de resposta em quatro horas úteis. Esses são objetivos propostos, não SLA contratado nem prazo de solução garantido. Incluir onboarding de 30–45 minutos, base de ajuda, correções e atualizações; customizações, operação humana de anúncios e serviços contábeis precisam de orçamento separado. Monitorar falhas de jobs, conexões revogadas, limites de recursos e consumo.

**Pagamento — proposta de fornecedor.** Mercado Pago é candidato coerente com `mp_link` já previsto na cobrança da Luh, mas isso não prova checkout da assinatura Hub implantado. Usar checkout/link com Pix/cartão, desconto configurável e parcelamento com encargos exibidos ao comprador. Definir número de parcelas, desconto e valor líquido esperado considerando tarifa de processamento. Separar compra dos módulos da cobrança recorrente de R$269. Ativar módulos por confirmação autenticada e idempotente do gateway, conferindo pedido, empresa, moeda e valor; retorno do navegador não comprova pagamento.

**Assinatura e consumo.** Reaproveitar DocuSeal escolhido pela Luh e validar domínio, e-mail, trilha de auditoria, credenciais, capacidade e restauração antes de fixar franquia. Começar fiscal sem consulta paga obrigatória, com conteúdo e links oficiais; oferecer consultas de leitura somente após orçamento/limites. API oficial Meta e conta Google do cliente são conexões por empresa, com configuração assistida e histórico de falhas.

**Cancelamento — proposta.** Definir início da mensalidade, aviso de atraso, carência, modo de consulta/exportação e prazo de retenção antes da venda. Sugestão inicial: 30 dias para exportar após cancelamento, sem reativar rotinas automáticas; retenção de documentos específicos deve ser definida conforme responsabilidade e exigências aplicáveis. Política ainda não aprovada.

### 8.3 Pontos realmente pendentes
- Dependências internas dos adicionais quando a compra inicial é o 5; aquisição do outro inicial pela mesma empresa.
- Percentual/condições de desconto à vista, número de parcelas, fornecedor definitivo, início da mensalidade e política de cancelamento/reativação.
- Contagem do proprietário entre os três usuários, matriz de permissões e método de login complementar ao link mágico existente.
- Franquias de análise por IA, vídeo, arquivos, consultas fiscais e assinaturas; plano Workspace e retenção para Meet.
- Escopo de tráfego: acompanhamento de anúncios, automação de campanhas ou serviço humano; formatos de vídeo e redes da primeira entrega.
- Escopo e preço de cardápio digital; peso/volume/unidade, validade e fornecedores do estoque.
- Aprovação das propostas de infraestrutura, backup/restauração e suporte; situação atual do n8n, DocuSeal e fontes externas da Luh.

Regra de continuidade: manter decisões anteriores identificadas na seção 5.4. Quando o produto novo as exigir alterar (usuários, tenants, Meta, Meet), documentar a mudança; não reabrir decisões já claras nem tratar proposta nova como aprovação.

## 9. Registro original da solicitação
O texto abaixo preserva o pedido inicial, anterior ao esclarecimento dos preços:
> Vamos construir a Hub, ela é um sistema de gestão de empresa com controle de saúde de negócio, gestão financeira, controle de estoque, cardápio digital, contrato, agenda de reuniões e mais coisas que vamos incluir, vamos dividir ele em funcionalidades pra conseguir vender tudo separado:
>
> - Pacote 1 (R$997,00): visão geral financeira com vencimentos, entrada de ganhos, custos fixos, custos de negocio e custos pessoais, visão de quem ainda não pagou, o que está pra vencer
> - Pacote 2 (R$549,00): tudo do pacote 1 + carteira de cliente com dados do cliente e valor do que foi fechado, bot de cobrança
> - Pacote 3 (R$919,00): tudo do pacote 1 e 2 + CRM: quadro de tarefas, contrato automático, transcrição de reunião automática pra gerar histórico com cliente e contrato, agenda de reunião vinculada ao google
> - Pacote 4 (R$498,00) tudo dos pacotes 1, 2 e 3 + contabilidade, como está a saude do cnpj com taxas, o que precisa pagar, o que precisa emitir de taxa pra pagar, o que precisa pedir pro contador assinar e como gerar tu (do isso
> - Pacote 5 (R$1.489,00): tudo dos pacotes 1, 2, 3 e 4: editor de video, gestor de tráfego, controle e programação de postagens, passo a passo de como instalar e usar a api meta
> - Pacote 6 (R$788,00): controle de estoque, quantidade minima de mercadoria com aviso pra comprar, criar lista de compra automática quando chegar no minimo dos itens, entrada e saida de mercadoria com baixa de estoque, controle máximo de cada item de mercadoria com o volume do local disponivel de armazenamento
>
> Com assinatura pra continuar usando de R$269,00
>
> Queremos ele em PWA pra pessoa poder ter ele na tela inicial do celular, esse é o repositório da Luh que já tem quase tudo, precisamos juntar com o contador que eu tenho aqui, geramos um contador .md explicando, controle de estoque também temos isso no projeto da logo li, revise todo o projeto, veja se tem alguma melhoria pra nos propor
>
> esse é o repositório da luh: git@github.com:lucianapandolfo9-spec/hub-luhpanda.git
>
> Salve tudo que coloquei agora pra irmos validando depois também, pode abrir um PR no projeto da Luh com isso para termos histórico de reunião

**Primeiro esclarecimento:** escolha “Módulos adicionais”: “Os valores de compra se somam conforme os módulos escolhidos, com uma assinatura única mensal.”

**Correção comercial posterior — 05/10/2026:** “e o pacote 1 e o pacote 5 podem ser comprador sozinhos, os unicos que serão iniciais, os demais sempre vai ser somado ao valor deles”. A regra vigente é a das seções 3.1 e 3.2; a descrição cumulativa no pedido original acima fica preservada somente como histórico.

**Novas definições da Isabella — 05/10/2026:** reafirmou iniciais 1 e 5; pagamento por link com escolha do comprador, desconto à vista possível e taxas de crédito no parcelamento pelo comprador; um CNPJ, três usuários, aparelhos/locais ilimitados; tela de login; Meta oficial com consumo pelo cliente; consultas fiscais/assinaturas com limites a verificar; fiscal informativo, sem software de contador; vídeo/tráfego no 5; gravação/transcrição no Meet; itens/espaço preenchidos no estoque; pediu sugestões de hospedagem e operação.

**Orientação posterior:** “olhe todo o projeto que a Luh já fez e usa pra saber o que ela já tomou de decisão”. Motivou o inventário da seção 5.4 e a verificação somente leitura do ambiente da seção 5.5. Fontes ausentes e testes funcionais continuam identificados como limitações.

## 10. Referências de implementação consultadas
Referências de fornecedores foram consultadas em 05/10/2026; elas orientam a implementação, sem substituir teste de integração ou revisão normativa:
- [Supabase — RLS](https://supabase.com/docs/guides/database/postgres/row-level-security): regras por linha e operação; funções privilegiadas exigem autorização própria.
- [Supabase — changelog](https://supabase.com/changelog): consultar mudanças antes de implementar; endpoint Markdown não retornou conteúdo nesta revisão, página HTML foi acessada.
- [MDN — instalação de PWA](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable): manifest, HTTPS, ícones e diferenças de instalação.
- [Google — OAuth web server](https://developers.google.com/identity/protocols/oauth2/web-server): vincular autorização à sessão e proteger retorno contra CSRF.
- [Google — sincronização Calendar](https://developers.google.com/workspace/calendar/api/guides/sync): paginação, sync incremental e recuperação quando token inválido.
- [Serpro — Integra Contador](https://apicenter.estaleiro.serpro.gov.br/documentacao/api-integra-contador/), [contratação](https://apicenter.estaleiro.serpro.gov.br/documentacao/api-integra-contador/pt/como_contratar/) e [serviços x procurações](https://apicenter.estaleiro.serpro.gov.br/documentacao/api-integra-contador/pt/servicos_vs_procuracoes/): serviços fiscais dependem de contratação e autorização por escopo.
- [Supabase — preços](https://supabase.com/pricing) e [backups](https://supabase.com/docs/guides/platform/backups): custo base, compute, retenção e separação dos arquivos Storage.
- [Cloudflare — preços Workers](https://developers.cloudflare.com/workers/platform/pricing/): assinatura paga e assets estáticos.
- [Google — transcrições Meet](https://support.google.com/meet/answer/12849897?hl=pt-BR), [artefatos Meet API](https://developers.google.com/workspace/meet/api/guides/artifacts) e [configuração de reuniões](https://developers.google.com/workspace/meet/api/guides/meeting-spaces-configuration): elegibilidade, Drive, janela de coleta e configuração automática.
- [WhatsApp Business — preços oficiais](https://whatsappbusiness.com/products/platform-pricing/): cobrança por mensagens entregues e condições por categoria/mercado; tarifas e elegibilidade precisam ser conferidas na implantação.
- [Mercado Pago — link](https://www.mercadopago.com.br/ferramentas-para-vender/link-de-pagamento) e [preferências Checkout Pro](https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/checkout-customization/preferences): meios, parcelas e componentes de tarifa.
- Publicação Instagram e grupos WhatsApp: compatibilidade, quotas, políticas, permissões e versão Meta devem ser homologadas; código legado não comprova suporte atual universal.

## 11. Histórico do PR e alterações
Branch: `docs/hub-reuniao-2026-10-05`. Base revisada: commit do Hub registrado na seção 5.

As tentativas anteriores retornaram **403 — Resource not accessible by integration**, mesmo após a conta reportar escrita. Na nova tentativa de 05/10/2026, a criação da branch foi bem-sucedida. O bloqueio anterior fica registrado como histórico.

Conteúdo da alteração documental:
1. Este documento em `docs/hub/2026-10-05-planejamento-e-revisao.md`.
2. Link no final de `PROJETO.md`, preservando todo o histórico anterior.
3. Pacotes 1 e 5 iniciais; 2, 3, 4 e 6 adicionais; assinatura única de R$269/mês.
4. Novas definições do item 8, inventário de decisões da Luh, checagem somente leitura do Supabase e propostas operacionais.

O PR destina-se à revisão do planejamento. Não aplica migrations, implanta funcionalidades, processa pagamentos nem ativa bots.

**Versão 1.2:** incorporadas definições do item 8, revisão de decisões anteriores da Luh, confirmação de estruturas/deploys no Supabase e propostas de hospedagem, recuperação, suporte e integrações. Alterações de documentação; produção preservada.
