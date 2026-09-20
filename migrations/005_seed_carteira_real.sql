-- ============================================================
-- HUB LUH PANDA — 005: seed com dados reais
-- Fonte: planilha "Luh Panda - Financeiro"
-- (1XGvkY3nwH-6wV8nKcezseLKmPIwUYbGOQWeX0IKRNq4), aba Set 2026
-- + "Serviços & Preços". Só quem está na planilha entra aqui —
-- Capitalize / Bolão Fácil / Além Mar ficam de fora até ela mandar.
-- ============================================================

insert into hub.empresas (nome, cnpj, tipo, teto_anual_centavos)
values ('Luh Panda', '66.521.744/0001-60', 'mei', 8100000);

insert into hub.servicos (slug, nome, modalidade, preco_referencia_centavos, unidade, inclui, observacao) values
('trafego-pago', 'Gestão de Tráfego Pago', 'recorrente', 60000, 'mês',
 'Criação e gestão de campanhas Meta Ads, otimização contínua e relatório mensal de resultado.',
 'Âncora de abertura, negociável caso a caso. Verba de anúncio é do cliente — nunca é receita.'),
('sistemas-automacoes', 'Construção de Sistemas e Automações', 'bloco_horas', 18000, 'hora',
 'Bots de WhatsApp, automações n8n, integrações entre ferramentas, sistemas sob medida.',
 'Orçar por estimativa de horas. Fechar a estimativa por escrito antes de começar.'),
('manutencao-mensal', 'Manutenção Mensal de Sistema', 'recorrente', 50000, 'mês',
 'Monitoramento ativo do sistema entregue + pequenos ajustes ao longo do mês.',
 'Oferecer sempre que entregar sistema. Alternativa: manutenção avulsa.'),
('manutencao-avulsa', 'Manutenção Avulsa', 'bloco_horas', 18000, 'hora',
 'Ajuste pontual em sistema já entregue, só quando o cliente chamar.',
 'Sem monitoramento incluso. Para quem não quer mensalidade.'),
('hospedagem-n8n', 'Hospedagem no n8n', 'hospedagem', 13000, 'mês',
 'Hospedagem de qualquer coisa no meu servidor.',
 'Sem monitoramento incluso.'),
('consultoria-financeira', 'Consultoria financeira', 'recorrente', null, 'mês',
 null, 'Preço negociado caso a caso (ex.: Régis/Dobradinha R$ 1.200/mês).'),
('robo-atendimento', 'Robô de atendimento (WhatsApp)', 'projeto', null, null,
 'Bot de atendimento/SDR via WhatsApp.', 'Ex.: Daniel Magnus, parcelado.'),
('social-media', 'Social Media', 'recorrente', null, 'mês',
 'Produção e agendamento de conteúdo.', 'Combinado com tráfego em alguns contratos (ex.: GL4/Gio).'),
('salario-comercial', 'Salário comercial (fixo)', 'recorrente', 250000, 'mês',
 'Atuação comercial fixa para a Lead Performance + comissão de 20% por venda.',
 'Caso específico: ela é cliente E onde presta serviço de plataforma/BI/Teatro OS/Lidinha.'),
('evento-comissao', 'Comissão de evento (Pandoka)', 'por_evento', null, 'evento',
 'Comissão sobre orçamento de evento executado.', 'Ex.: casamento Amanda & Megane, comissão R$ 1.599.');

insert into hub.clientes (empresa_id, slug, nome, segmento, status, entrou_em, observacao)
select e.id, v.slug, v.nome, v.segmento, v.status, v.entrou_em::date, v.observacao
from hub.empresas e,
(values
  ('lead-performance', 'Lead Performance', 'Agência', 'ativo', null,
   'Ela é cliente (salário comercial fixo) e também onde presta serviço de plataforma/BI/Teatro OS/Lidinha.'),
  ('gio-lymphatic', 'GL4 / Gio (Lymphatic by Gigi)', 'Estética', 'ativo', null, null),
  ('dobradinha-do-regis', 'Régis / Dobradinha do Régis', 'Restaurante', 'ativo', '2026-06-10', null),
  ('f7-som-iluminacao', 'F7 Som e Iluminação', 'Eventos', 'ativo', null,
   'Cliente novo (set/2026). Falta definir o dia de vencimento e assinar contrato.'),
  ('daniel-magnus-advogados', 'Daniel Magnus Advogados', 'Advocacia', 'ativo', null, 'Parcela 1 de 6.'),
  ('manu-pestana', 'Manu Pestana', 'Artista', 'ativo', null, 'Valor com desconto (padrão R$ 600).'),
  ('imperio-ruby', 'Imperio Ruby', 'Lanchonete/Espetaria', 'ativo', '2026-09-16',
   'Contrato assinado 16/09. Valor negociado - Vivi RP.'),
  ('pandoka', 'Pandoka (eventos da família)', 'Eventos', 'ativo', null,
   'Comissão por evento + aulas de IA avulsas. Não é mensalidade fixa.')
) as v(slug, nome, segmento, status, entrou_em, observacao)
where e.nome = 'Luh Panda';

insert into hub.contratos (cliente_id, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_escrita_em, observacao)
select c.id, v.numero, v.status, v.inicio_em::date, v.fim_minimo_em::date, v.dia_vencimento::smallint,
       v.valor_mensal_centavos::bigint, v.porta_saida_tipo, v.porta_saida_escrita_em::timestamptz, v.observacao
from hub.clientes c,
(values
  ('lead-performance', null, 'rascunho', null, null, 1, 250000, null, null,
   'Salário comercial fixo — sem contrato de prestação de serviço registrado.'),
  ('gio-lymphatic', null, 'rascunho', null, null, 1, 150000, null, null,
   'Tráfego + Social Media, sem contrato formal registrado.'),
  ('dobradinha-do-regis', null, 'rascunho', null, null, 12, 120000, null, null,
   'Consultoria financeira, sem contrato formal registrado.'),
  ('f7-som-iluminacao', null, 'rascunho', null, null, null, 60000, null, null,
   'Falta definir o dia de vencimento e assinar contrato.'),
  ('daniel-magnus-advogados', null, 'rascunho', null, null, 5, 50000, null, null,
   'Robô de atendimento, parcela 1 de 6, sem contrato formal registrado.'),
  ('manu-pestana', null, 'rascunho', null, null, 5, 50000, null, null,
   'Tráfego pago, sem contrato formal registrado.'),
  ('imperio-ruby', '001/2026', 'ativo', '2026-09-16', '2026-12-23', 23, 40000, 'nenhuma', '2026-09-16',
   'Contrato assinado 16/09. Vigência mínima até 23/12/2026 (trava contratual — não é sistema, sem taxa de build).'),
  ('pandoka', null, 'rascunho', null, null, null, null, null, null,
   'Extras do mês — aula de IA (paga) e comissão de evento (pendente). Não é mensalidade fixa.')
) as v(slug, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_escrita_em, observacao)
where c.slug = v.slug;

insert into hub.contrato_itens (contrato_id, servico_id, descricao, valor_centavos, recorrencia)
select ct.id, s.id, v.descricao, v.valor_centavos::bigint, v.recorrencia
from hub.contratos ct
join hub.clientes c on c.id = ct.cliente_id
join (values
  ('lead-performance', 'salario-comercial', 'Salário comercial (fixo)', 250000, 'mensal'),
  ('gio-lymphatic', null, 'Tráfego Pago + Social Media', 150000, 'mensal'),
  ('dobradinha-do-regis', 'consultoria-financeira', 'Consultoria financeira', 120000, 'mensal'),
  ('f7-som-iluminacao', 'trafego-pago', 'Gestão de Tráfego Pago', 60000, 'mensal'),
  ('daniel-magnus-advogados', 'robo-atendimento', 'Robô de atendimento (advocacia)', 50000, 'parcela 1/6'),
  ('manu-pestana', 'trafego-pago', 'Gestão de Tráfego Pago', 50000, 'mensal'),
  ('imperio-ruby', 'trafego-pago', 'Gestão de Tráfego Pago', 40000, 'mensal'),
  ('pandoka', null, 'Aula de IA', 120000, 'pontual'),
  ('pandoka', 'evento-comissao', '% Casamento Amanda e Megane', 159900, 'pontual')
) as v(cliente_slug, servico_slug, descricao, valor_centavos, recorrencia)
  on v.cliente_slug = c.slug
left join hub.servicos s on s.slug = v.servico_slug
where ct.id = (select id from hub.contratos where cliente_id = c.id order by created_at desc limit 1);
