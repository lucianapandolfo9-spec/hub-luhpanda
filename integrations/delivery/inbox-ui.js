// Hub — visualizacao de pedidos persistidos (055); sem mock que se passe por pedido real.
// Nunca apresenta um pedido como aceito na plataforma; confirmar/recusar sera
// integrado aos conectores oficiais com idempotencia em PR posterior.
let pedidosDelivery = [];
let pedidosDeliveryFiltro = 'todos';
let pedidosDeliveryErro = '';
const PEDIDOS_STATUS = {
  agendado: 'Agendado', novo: 'Novo', confirmado: 'Confirmado',
  preparando: 'Em preparo', pronto: 'Pronto',
  em_entrega: 'Em entrega', concluido: 'Concluído',
  cancelado: 'Cancelado', revisar: 'Revisar'
};
const PEDIDOS_ORIGEM = {ifood:'iFood',rappi:'Rappi','99food':'99Food'};
const safeIsoDate = value => {
  if (!value) return '—';
  const dt = new Date(value);
  return Number.isNaN(dt.getTime()) ? '—' : dt.toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'});
};
async function renderPedidosDelivery(){
  root.innerHTML = shell('pedidos', '<div class="empty"><div class="spinner" style="margin:0 auto;"></div>Carregando pedidos...</div>');
  pedidosDeliveryErro = '';
  try {
    const resposta = await Promise.race([
      hubClient.rpc('hub_rpc_delivery_orders',{p_limit:100}),
      new Promise((_,reject)=>setTimeout(()=>reject(new Error('Tempo limite ao consultar pedidos.')),10000))
    ]);
    if (resposta.error) throw resposta.error;
    if (!Array.isArray(resposta.data)) throw new Error('Formato inesperado na consulta de pedidos.');
    pedidosDelivery = resposta.data;
  } catch(error){
    console.warn('hub_rpc_delivery_orders indisponivel:',error?.message||error);
    pedidosDelivery = [];
    pedidosDeliveryErro = 'A central não está disponível para esta empresa. Confira a contratação do módulo, a conexão e a instalação da base de dados.';
  }
  desenharPedidosDelivery();
}
function filtroPedidosDelivery(status){
  pedidosDeliveryFiltro = Object.prototype.hasOwnProperty.call(PEDIDOS_STATUS,status) ? status : 'todos';
  desenharPedidosDelivery();
}
function desenharPedidosDelivery(){
  const rows = pedidosDeliveryFiltro==='todos' ? pedidosDelivery
    : pedidosDelivery.filter(p=>p.status===pedidosDeliveryFiltro);
  const totais = pedidosDelivery.reduce((acc,p)=>{
    if(Object.prototype.hasOwnProperty.call(PEDIDOS_STATUS,p.status)) acc[p.status]=(acc[p.status]||0)+1;
    return acc;
  },{});
  const itens = rows.map(p=>'<div class="rowcard" style="margin-bottom:8px;">'+
    '<div class="l">'+
      '<div class="t">'+esc(PEDIDOS_ORIGEM[p.provider]||p.provider||'Plataforma')+' · '+esc(p.loja||'Loja')+'</div>'+
      '<div class="s">Pedido '+esc(p.external_order_id||'—')+' · '+esc(safeIsoDate(p.atualizado_em))+'</div>'+
    '</div>'+
    '<div class="r"><span class="badge '+(p.status==='cancelado'?'badge-warn':p.status==='concluido'?'badge-ok':'badge-muted')+'">'+esc(PEDIDOS_STATUS[p.status]||'Revisar')+'</span></div>'+
    '</div>').join('');
  const statusOptions = ['todos',...Object.keys(PEDIDOS_STATUS)].map(k=>
    '<option value="'+k+'" '+(pedidosDeliveryFiltro===k?'selected':'')+'>'+esc(k==='todos'?'Todos os pedidos':PEDIDOS_STATUS[k])+
    (k==='todos'?'':(' ('+(totais[k]||0)+')'))+'</option>').join('');
  root.innerHTML = shell('pedidos',
    '<div class="row-between"><h2 class="section-title">Pedidos de delivery</h2>'+
      '<button type="button" class="btn btn-outline btn-sm" onclick="renderPedidosDelivery()">Atualizar</button></div>'+
    '<p class="muted" style="margin:0 0 14px;">Pedidos registrados pelas integrações autorizadas. Aceite, preparo e cancelamento ainda precisam de confirmação diretamente nas plataformas.</p>'+
    (pedidosDeliveryErro ? '<div class="flag" role="alert">'+esc(pedidosDeliveryErro)+'</div>' : '')+
    '<div class="row" style="margin:16px 0;"><label for="pedidos-filtro">Status</label>'+
    '<select id="pedidos-filtro" onchange="filtroPedidosDelivery(this.value)">'+statusOptions+'</select>'+
    '<span class="muted">'+rows.length+' de '+pedidosDelivery.length+' pedidos</span></div>'+
    (itens || '<div class="card"><p class="muted">Nenhum pedido registrado neste filtro. Pedidos só aparecem após conexão e recebimento autenticado dos provedores.</p></div>')
  );
}
