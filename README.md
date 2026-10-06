# Hub

> **"Hub" é nome provisório.** O nome comercial será escolhido depois. Até lá, este README e
> os demais documentos usam "Hub".

Sistema de gestão de pequenas empresas, em PWA, vendido por pacotes: financeiro, clientes e
cobrança, CRM/contratos/reuniões, orientação fiscal, marketing e estoque. Um banco único
atende várias empresas, cada uma isolada no seu workspace.

**Este README manda no produto.** Notas externas (vault, planilhas, conversas) apontam para
cá; se houver divergência, vale o que está aqui. O histórico técnico de construção está no
[`PROJETO.md`](PROJETO.md) e o registro da reunião de 05/10/2026 está no PR #2.

---

## 1. Estado deste documento

Escrito em 06/10/2026, a partir de: PR #2 (planejamento e revisão), decisões fechadas por
Luciana e Isa no desenho de 06/10/2026, estado real da `main` e especificação do Contator
(v1.0, 29/09/2026).

Marcação usada em todo o documento:

| Marca | Significado |
|---|---|
| **No ar** | está na `main` e funciona hoje, para uso de **um único usuário** (a dona do projeto) |
| **Em branch** | existe em branch/PR aberto, **não** está na `main` |
| **Proposto** | desenhado ou recomendado, sem código |
| **A fazer** | decidido, ainda não construído |
| **Em aberto** | ninguém decidiu. Está listado na seção 16 e **não deve ser presumido** |

---

## 2. O que é

O Hub nasceu como painel interno de operação da Luciana (carteira, financeiro, CRM,
contratos, cobrança). A decisão é transformá-lo em **produto comercial de gestão total** para
outras empresas, com o antigo "Business OS" da Isa fundido nele: **um produto só**.

- Por empresa cliente: dados próprios, usuários próprios, módulos contratados e conexões
  externas próprias.
- Funcionalidades comercializáveis separadamente (pacotes, seção 4).
- PWA: instala na tela inicial do celular.

## 3. Quem faz e como se vende

- **Sociedade:** Luciana e Isa, **50/50 em tudo**. Tudo o que está nos PRs da Isa pertence às
  duas.
- **Venda:** no começo, pelo CNPJ da Isa. A formalização da sociedade vem depois; forma e
  data estão em aberto.
- **Venda por link de pagamento**; o comprador escolhe como pagar.
- **Um CNPJ por contratação**, três usuários, aparelhos e locais ilimitados (direito de
  acesso, não promessa de armazenamento nem de consumo ilimitado de fornecedores).

## 4. Pacotes e preços (aprovados)

A margem desses preços **ainda precisa ser validada pelo financeiro antes da primeira
venda** (seção 16).

| # | Pacote | Compra | Liberação |
|---|---|---|---:|
| 1 | Financeiro | inicial, vende sozinho | R$ 997 |
| 2 | Clientes e cobrança | adicional | R$ 549 |
| 3 | CRM, contratos e reuniões | adicional | R$ 919 |
| 4 | Orientação fiscal (Contator) | adicional | R$ 498 |
| 5 | Marketing | inicial, vende sozinho | R$ 1.489 |
| 6 | Estoque | adicional | R$ 788 |

- **Mensalidade única: R$ 269**, independente dos módulos liberados.
- Regra de composição, confirmada pela Isa em 05/10/2026: só os pacotes 1 e 5 são compra
  inicial; 2, 3, 4 e 6 somam ao valor do inicial escolhido. Comprar um pacote não libera os
  outros.
- Exemplo: 1 + 2 = R$ 1.546 de liberação + R$ 269/mês.
- **Em aberto:** desconto à vista (percentual), número máximo de parcelas, início da
  mensalidade, segundo pacote inicial na mesma empresa, política de cancelamento.
- O servidor precisa validar o pacote inicial antes de habilitar qualquer adicional.
  Esconder item de menu é só apresentação. **A fazer.**

## 5. Módulos e estado

| Módulo | Pacote | Estado hoje |
|---|---|---|
| Dashboard, carteira, financeiro, custos, catálogo de serviços | 1 e 2 | **No ar** (uso individual). Contas a pagar com baixa, conciliação, saldo e projeção: **proposto** |
| Cobrança (régua D-3/D0/D+2/D+7, configuração, log) | 2 | Configuração e telas **no ar**. Os fluxos do bot de cobrança existem na automação, **desligados de propósito**. Ligar depende da triagem de segurança (seção 13) |
| CRM (kanban de 6 etapas), demandas por cliente | 3 | **No ar** |
| Contratos (modelo mecânico, assinatura DocuSeal) | 3 | **No ar** como código; assinatura sem teste ponta a ponta registrado |
| Reuniões e análise por IA | 3 | **No ar** na versão atual (ponte local, uso interno). Versão do produto: áudio + API, **a fazer** |
| Agenda Google | 3 | **No ar** com credencial global. Credencial por empresa: **a fazer** |
| Conversas de WhatsApp | 2 | **No ar** na versão atual (uso interno). Versão do produto: API oficial da Meta, **a fazer** |
| Orientação fiscal (Contator) | 4 | **Proposto.** Só existe a especificação |
| Marketing (calendário, posts, tráfego, vídeo) | 5 | **Proposto** no Hub. O publicador do aprovi.ai existe separado e vira este módulo |
| Estoque | 6 | **Em branch** (PR #3), parado como referência. **Último módulo a construir** |
| Cardápio digital | sem pacote | **Proposto**, sem escopo nem preço. Não está incluído no estoque |
| PWA (instalação no celular) | todos | **Em branch** (PR `feat/pwa-favicon-panda`), sem merge ainda |
| Multi-empresa, papéis, módulos por empresa | todos | **A fazer.** Hoje o acesso é de um único usuário |

## 6. Arquitetura: banco único multi-empresa

**Decisão:** um banco único, multi-empresa, **isolado por workspace**. Substitui a ideia de
replicar o sistema por cliente.

- **Hoje:** só existe a coluna `workspace_id` em parte das tabelas, e uma checagem de acesso
  que libera um único usuário. Isso **não** é multi-empresa. Várias tabelas (recebíveis,
  custos fixos, log de cobrança, configuração, auditoria) ainda nem têm workspace próprio.
- **A fazer:** membros por workspace, papéis, módulos habilitados por empresa, isolamento
  verificado em **cada** RPC, job, exportação e arquivo. Toda relação deve impedir vínculo
  entre entidades de workspaces diferentes.
- **Teste de aceite da base:** com duas empresas e usuários de papéis diferentes, a empresa A
  não enxerga dado, arquivo nem job da empresa B.
- Os nomes de tabela propostos no PR #2 (seção 6.1) são sugestão, não migration aprovada.
  Mapear o que já existe antes de criar tabela nova.

Padrões que ficam: dinheiro em centavos, schema `hub` fora da exposição direta (acesso por
RPC), auditoria por trigger, constraints de negócio no banco, migrations em ordem, recebíveis
idempotentes.

## 7. Acesso: papéis e usuários

- **3 usuários por CNPJ.**
- **Papéis por empresa:** Dono, Operador e Consulta.
- O **contador do cliente entra como Consulta e não ocupa vaga** dos 3.
- Login atual: link mágico por e-mail (Supabase Auth). É a base; falta trocar a autorização
  de "um e-mail" por convites e permissões por empresa.
- **Em aberto:** se o Dono conta entre os 3, e a matriz exata de permissão por papel.

## 8. Integrações

| Integração | Decisão |
|---|---|
| **WhatsApp** | **API oficial da Meta.** Cada cliente conecta o **próprio número**; o consumo é pago por ele. **Grupos ficam fora do pacote** (a API oficial limita grupos a no máximo 8 participantes). A instalação não oficial usada hoje fica só no uso interno da Luciana |
| **Reuniões** | **Envio de áudio + transcrição por API** (estimativa de custo com Gemini Flash: ~R$ 1,60 por hora de áudio). A ponte local de transcrição fica só no uso interno. A proposta anterior de usar o Google Meet como fonte saiu do desenho |
| **Cobrança da mensalidade** | **Asaas** |
| **Assinatura de contrato** | **DocuSeal em servidor próprio**. **Autentique é o plano B** |
| **Google Agenda** | OAuth por empresa/usuário (a fazer; hoje é credencial global) |
| **Marketing** | publicador do aprovi.ai (Instagram), a homologar com a Meta antes de portar |

Regra que vale para todas: chave de fornecedor mora no servidor, nunca no front nem no repo.
Execução externa nunca é marcada como concluída só porque entrou numa fila.

## 9. Contator (orientação fiscal, pacote 4)

- **Informativo + prepara o material para o contador.** Explica o que fazer, como fazer, o
  que pagar e emitir e o que levar ao contador.
- **Sem parecer e sem planejamento tributário.** Não faz escrituração, não transmite
  declaração, não emite guia automaticamente.
- "Saúde fiscal" distingue checklist preenchido de regularidade consultada em fonte oficial.
  Sem evidência, aparece "não verificado".
- Honorários e atos do contador são externos ao preço do pacote.
- A especificação completa (v1.0, 29/09/2026) tem escopo bem maior (motor fiscal, conectores,
  transmissão). **Só o fluxo informativo entra.** Alíquotas, limites e prazos dela não foram
  auditados e **não devem virar constante no código**.
- **Em aberto:** o escopo por fase (MVP sem transmissão, depois consulta de leitura via
  Serpro, depois transmissão). Será construído peça por peça depois dos PRs de desenho.
- Conteúdo fiscal precisa de revisão por profissional habilitado e versionamento por vigência.

## 10. Estoque (pacote 6)

- **Último módulo a construir.** O PR #3 não é mergeado agora; fica como referência.
- Regra do produto: o cliente cadastra os itens e informa o espaço máximo de cada local.
  Informar só o espaço total não permite deduzir quanto cabe de cada item, então a ocupação
  por item precisa ser informada.
- Funções previstas: mínimo com aviso, lista de compras sugerida (nunca compra automática),
  entradas e saídas com baixa, máximo por item considerando o armazenamento.
- A parte offline do estoque (vendas) segue o padrão já usado em outro projeto da equipe:
  só o caixa principal conclui venda offline.

## 11. Front, PWA e hospedagem

- Front: HTML/JS vanilla, sem build, uma SPA (`index.html`) com rotas por hash.
- **Hospedagem: GitHub Pages, só por enquanto.** Os termos do GitHub Pages **proíbem SaaS
  comercial**. **A hospedagem precisa ser trocada antes da primeira venda.** Cloudflare Pages
  era a recomendação, mas o uso comercial dele **não foi confirmado** (seção 16).
- **PWA:** em branch. Manifest, service worker de app shell (network-first, **nunca cacheia o
  Supabase**), ícones e favicon. Escopo e nome são do Hub inteiro.
- Offline seletivo, partição de cache por workspace/usuário e limpeza na troca de empresa:
  **a fazer** com a base multi-empresa.

## 12. Banco e infraestrutura

- **Supabase:** o projeto atual, que **hoje divide espaço com o aprovi.ai** (schemas
  separados). O aprovi.ai vira o módulo Marketing do Hub.
- ⚠️ **Risco registrado:** um produto vendido não deveria dividir projeto com dados reais de
  outros sistemas nem com legado em quarentena. A decisão é **migrar depois para um banco
  pago pelas duas sócias**, trazendo a Isa para dentro dele. **Quando e como migrar: em
  aberto.**
- Região do projeto atual (LGPD, o ideal é São Paulo): **a conferir**.
- n8n e DocuSeal rodam em servidor próprio. Reaproveitar só depois de separar o que é uso
  interno do que é produto.
- Backup, suporte e cancelamento: o PR #2 (seção 8.2) tem proposta, **ainda não aprovada**.

## 13. Segurança

A revisão do PR #2 apontou riscos. Sem detalhe de exploração; a triagem fina é do agente de
segurança.

| Prioridade | Tema |
|---|---|
| **P0** | Acesso ligado a um único e-mail; isolamento por workspace incompleto (seção 6) |
| **P0** | Integrações (Google, WhatsApp) com credencial global e sem checagem de empresa na leitura |
| **P0** | Fluxo de autorização OAuth sem vínculo de estado com a sessão |
| **P0** | Dados de operação real no histórico público do repositório |
| **P1** | Módulos sem enforcement de licença no servidor |
| **P1** | Bot de cobrança não respeita a configuração de pausa nem o status do cliente |
| **P1** | Reconstrução do banco do zero não é reprodutível só com as migrations do repo |
| **P1** | Análise de reunião longa pode cortar o final do texto sem avisar |
| **P1** | Assinatura DocuSeal sem teste ponta a ponta; agenda sem paginação completa |

**Regras até resolver:** o bot de cobrança **não é ligado** antes da triagem de segurança.
Nada novo e sensível entra neste repositório, que é **público**.

**Plano para o item de dados reais:** substituir por dados fictícios e recriar o repositório
limpo. Recriar muda a URL e fecha os PRs da Isa, então **só com combinado e OK dela**. Isso
não foi feito.

## 14. Ordem de construção

1. **Subir todos os PRs de desenho e construção**, sem merge (este conjunto).
2. **Base multi-empresa** (seção 6) e ambiente de homologação com dados fictícios.
   **Vem antes das pendências abaixo.**
3. Triagem e correção dos P0/P1 da seção 13.
4. Pendências do que já existe: DocuSeal ponta a ponta, vínculo serviço↔contrato, bot de
   cobrança.
5. Financeiro completo e PWA.
6. Clientes/cobrança com WhatsApp oficial por empresa.
7. CRM, reuniões (áudio + API) e contratos por empresa.
8. Contator, peça por peça (escopo em aberto).
9. Marketing (aprovi.ai como base).
10. **Estoque, por último.**

Troca de hospedagem e decisão do banco pago entram **antes da primeira venda**, em qualquer
ponto desta lista. Esta ordem substitui a numeração de etapas da seção 7 do PR #2.

## 15. Fora do escopo agora

Nada disto é feito neste ciclo: migration multi-empresa, correção dos P0, troca da carga de
dados reais por fictícia, recriação do repositório, troca de hospedagem, código do Estoque e
do Contator, ativação do bot de cobrança.

## 16. Em aberto

Nada daqui deve ser tratado como decidido.

- Nome comercial do produto.
- Forma e data de formalização da sociedade.
- Margem dos preços e da mensalidade (validação do financeiro antes da primeira venda).
- Desconto à vista, número de parcelas, início da mensalidade, política de cancelamento.
- Gateway do link de liberação dos pacotes (Asaas está decidido só para a mensalidade).
- Se o Dono conta entre os 3 usuários; matriz de permissões por papel.
- Escopo do Contator por fase; consultas externas fiscais, seus custos e limites.
- Se o Cloudflare Pages permite uso comercial; qual será a hospedagem definitiva.
- Se a Meta cobra mensagem de atendimento desde 01/10/2026 (afeta o repasse ao cliente).
- Quando e como migrar para o banco pago; região do projeto atual.
- Franquias de IA, vídeo, arquivos e assinaturas.
- Escopo de "gestor de tráfego" (acompanhamento, automação ou serviço humano) e do cardápio.
- Estoque: unidade, peso/volume, validade, fornecedores.
- Um ponto sobre o papel do contador, mencionado no desenho, ainda a esclarecer.

## 17. Como contribuir

- **Gate de segredo:** gitleaks no CI e hook de pré-commit (`.pre-commit-config.yaml`).
  Instalar uma vez por clone com `pre-commit install`.
- Uma branch por assunto, a partir da `main`; um PR por branch; **nada vai para a `main` sem
  OK das duas sócias**. Na `main`, `git push` publica o site.
- Alteração de schema é migration nova em `migrations/`, nunca edição de uma antiga.
- **O repositório é público.** Não colocar dado real de cliente, valor de contrato, documento
  de pessoa ou empresa, chave nem credencial. Use dados fictícios.
- Migration não é aplicada nem função implantada sem confirmação explícita.

## 18. Referências

- [`PROJETO.md`](PROJETO.md): histórico técnico de construção do Hub.
- PR #2: registro da reunião de 05/10/2026, inventário e revisão técnica (base deste README).
- PR #3: Estoque e Contator (referência, parado).
- PR `feat/pwa-favicon-panda`: PWA e favicon.
- `docs/hub/2026-10-05-planejamento-e-revisao.md` (no PR #2): matriz de reaproveitamento,
  decisões anteriores, propostas de hospedagem, backup e suporte.
- Especificação do Contator v1.0 (29/09/2026): fora do repositório, com a Isa e a Luciana.
