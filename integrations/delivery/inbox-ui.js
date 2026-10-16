// Hub — visualização de pedidos persistidos (migration 055).
// Somente leitura: ações operacionais exigem confirmação real na plataforma.
// Os dados vêm da RPC isolada por workspace e licença no servidor.
let pedidosDelivery = [];
let pedidosDeliveryFiltro = 'todos';
let pedidosDeliveryProvedor = 'todos';
let pedidosDeliveryLoja = 'todas';
let pedidosDeliveryErro = '';
let pedidosDeliveryRequisicao = 0;

const PEDIDOS_STATUS = Object.freeze({
  agendado: 'Agendado', novo: 'Novo', confirmado: 'Confirmado',
  preparando: 'Em preparo', pronto: 'Pronto',
  em_entrega: 'Em entrega', concluido: 'Concluído',
  cancelado: 'Cancelado', revisar: 'Revisar'
});
const PEDIDOS_ORIGEM = Object.freeze({ ifood: 'iFood', rappi: 'Rappi', '99food': '99Food' });
const safeIsoDate = value => {
  if (!value) return '—';
  const dt = new Date(value);
  return Number.isNaN(dt.getTime()) ? '—'
    : dt.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
};
// Nunca manter o pedido A/B visível após sair da rota durante uma solicitação.
function pedidosDeliveryNaRota() {
  if (typeof currentRoute === 'function') return currentRoute().page === 'pedidos';
  return true; // Harness de testes isolados, sem roteador da aplicação.
}
async function renderPedidosDelivery() {
  const requisicao = ++pedidosDeliveryRequisicao;
  root.innerHTML = shell('pedidos',
    '<div class="empty" role="status" aria-live="polite"><div class="spinner" style="margin:0 auto;"></div>Carregando pedidos...</div>');
  pedidosDeliveryErro = '';
  try {
    const resposta = await Promise.race([
      hubClient.rpc('hub_rpc_delivery_orders', { p_limit: 100 }),
      new Promise((_, reject) => setTimeout(() => reject(new Error('Tempo limite de consulta.')), 10000))
    ]);
    if (requisicao !== pedidosDeliveryRequisicao || !pedidosDeliveryNaRota()) return;
    if (resposta.error) throw resposta.error;
    if (!Array.isArray(resposta.data)) throw new Error('Formato inesperado na consulta de pedidos.');
    // A lista não é fonte de verdade para autorizar uma ação ou somar vendas.
    pedidosDelivery = resposta.data.filter(p => p && typeof p === 'object');
  } catch (error) {
    if (requisicao !== pedidosDeliveryRequisicao || !pedidosDeliveryNaRota()) return;
    console.warn('Consulta de delivery indisponível:', error?.message || error);
    pedidosDelivery = [];
    pedidosDeliveryErro =
      'A central não está disponível para esta empresa. Confira a contratação do módulo, a conexão e a instalação da base de dados.';
  }
  if (pedidosDeliveryNaRota()) desenharPedidosDelivery();
}
function filtroPedidosDelivery(status) {
  pedidosDeliveryFiltro = Object.prototype.hasOwnProperty.call(PEDIDOS_STATUS, status)
    ? status : 'todos';
  desenharPedidosDelivery();
}
function filtroPedidosDeliveryProvedor(provider) {
  pedidosDeliveryProvedor = Object.prototype.hasOwnProperty.call(PEDIDOS_ORIGEM, provider)
    ? provider : 'todos';
  pedidosDeliveryLoja = 'todas';
  pedidosDeliveryFiltro = 'todos'; // Outro canal pode não conter o status do canal anterior.
  desenharPedidosDelivery();
}
function filtroPedidosDeliveryLoja(connectionId) {
  // A lista vem do servidor, não aceita identificador arbitrário na UI.
  const lojas = new Set(pedidosDelivery
    .filter(p => pedidosDeliveryProvedor === 'todos' || p.provider === pedidosDeliveryProvedor)
    .map(p => String(p.connection_id || '')));
  pedidosDeliveryLoja = lojas.has(connectionId) ? connectionId : 'todas';
  desenharPedidosDelivery();
}
function desenharPedidosDelivery() {
  if (!pedidosDeliveryNaRota()) return;
  const doProvedor = pedidosDelivery.filter(p =>
    pedidosDeliveryProvedor === 'todos' || p.provider === pedidosDeliveryProvedor);
  const conexoes = [...new Map(doProvedor
    .filter(p => p.connection_id)
    .map(p => [String(p.connection_id),
      { id: String(p.connection_id), provider: p.provider, name: p.loja || 'Loja sem nome' }])
  ).values()].sort((a, b) => String(a.name).localeCompare(String(b.name), 'pt-BR'));

  if (pedidosDeliveryLoja !== 'todas' && !conexoes.some(c => c.id === pedidosDeliveryLoja))
    pedidosDeliveryLoja = 'todas';

  const disponiveis = doProvedor.filter(p =>
    pedidosDeliveryLoja === 'todas' || String(p.connection_id) === pedidosDeliveryLoja);
  const rows = disponiveis.filter(p =>
    pedidosDeliveryFiltro === 'todos' || p.status === pedidosDeliveryFiltro);
  const totais = disponiveis.reduce((acc, p) => {
    if (Object.prototype.hasOwnProperty.call(PEDIDOS_STATUS, p.status))
      acc[p.status] = (acc[p.status] || 0) + 1;
    return acc;
  }, {});

  const itens = rows.map(p =>
    '<div class="rowcard" style="margin-bottom:8px;">' +
    '<div class="l">' +
      '<div class="t">' + esc(PEDIDOS_ORIGEM[p.provider] || p.provider || 'Plataforma') +
        ' · ' + esc(p.loja || 'Loja') + '</div>' +
      '<div class="s">Pedido ' + esc(p.external_order_id || '—') +
        ' · ' + esc(safeIsoDate(p.atualizado_em)) + '</div>' +
    '</div>' +
    '<div class="r"><span class="badge ' +
    (p.status === 'cancelado' ? 'badge-warn' :
      p.status === 'concluido' ? 'badge-ok' : 'badge-muted') + '">' +
    esc(PEDIDOS_STATUS[p.status] || 'Revisar') + '</span></div></div>'
  ).join('');

  const statusOptions = ['todos', ...Object.keys(PEDIDOS_STATUS)].map(k =>
    '<option value="' + esc(k) + '" ' +
    (pedidosDeliveryFiltro === k ? 'selected' : '') + '>' +
    esc(k === 'todos' ? 'Todos os status' : PEDIDOS_STATUS[k]) +
    (k === 'todos' ? '' : ' (' + (totais[k] || 0) + ')') + '</option>'
  ).join('');
  const providerOptions = [
    '<option value="todos">Todas as plataformas</option>',
    ...Object.keys(PEDIDOS_ORIGEM).map(k => '<option value="' + esc(k) + '" ' +
      (pedidosDeliveryProvedor === k ? 'selected' : '') + '>' +
      esc(PEDIDOS_ORIGEM[k]) + '</option>')
  ].join('');
  const lojaOptions = [
    '<option value="todas">Todos os estabelecimentos</option>',
    ...conexoes.map(c => '<option value="' + esc(c.id) + '" ' +
      (pedidosDeliveryLoja === c.id ? 'selected' : '') + '>' +
      esc((PEDIDOS_ORIGEM[c.provider] || c.provider) + ' · ' + c.name) + '</option>')
  ].join('');
  const alcance = pedidosDelivery.length === 100
    ? '<p class="muted" style="font-size:12px;">Exibindo somente os 100 pedidos mais recentes. Totais e filtros são desta amostra, não de todos os pedidos históricos.</p>'
    : '';
  root.innerHTML = shell('pedidos',
    '<div class="row-between"><h2 class="section-title">Pedidos de delivery</h2>' +
      '<button type="button" class="btn btn-outline btn-sm" onclick="renderPedidosDelivery()">Atualizar</button></div>' +
    '<p class="muted" style="margin:0 0 14px;">Leitura dos pedidos registrados. Confirmação, preparo e cancelamento devem ser feitos na plataforma de origem enquanto não houver integração operacional homologada.</p>' +
    (pedidosDeliveryErro ? '<div class="flag" role="alert">' + esc(pedidosDeliveryErro) + '</div>' : '') +
    '<div class="row" style="margin:16px 0;flex-wrap:wrap;gap:12px;">' +
      '<div><label for="pedidos-provedor">Plataforma</label>' +
        '<select id="pedidos-provedor" onchange="filtroPedidosDeliveryProvedor(this.value)">' +
        providerOptions + '</select></div>' +
      '<div><label for="pedidos-loja">Estabelecimento</label>' +
        '<select id="pedidos-loja" onchange="filtroPedidosDeliveryLoja(this.value)">' +
        lojaOptions + '</select></div>' +
      '<div><label for="pedidos-filtro">Status</label>' +
        '<select id="pedidos-filtro" onchange="filtroPedidosDelivery(this.value)">' +
        statusOptions + '</select></div>' +
    '</div>' +
    '<p class="muted" role="status" aria-live="polite">' + rows.length +
      ' de ' + disponiveis.length + ' pedidos da seleção</p>' + alcance +
    (itens || (pedidosDeliveryErro ? '' :
      '<div class="card"><p class="muted">Nenhum pedido registrado neste filtro. Pedidos só aparecem após conexão e recebimento autenticado dos provedores.</p></div>'))
  );
}
