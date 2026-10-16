import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../../integrations/delivery/inbox-ui.js',import.meta.url),'utf8');
const index = fs.readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const encode=s=>String(s==null?'':s).replace(/[&<>"']/g,
  x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const setup=(rpc,route=()=>({page:'pedidos'}))=>{
  const ctx={root:{innerHTML:''},shell:(_active,body)=>body,esc:encode,
    currentRoute:route,setTimeout:()=>0,console:{warn:()=>{}},hubClient:{rpc}};
  vm.createContext(ctx);
  vm.runInContext(source,ctx,{filename:'integrations/delivery/inbox-ui.js'});
  return ctx;
};
const examples=[
  {connection_id:'loja-a',provider:'ifood',loja:'Loja A',
    external_order_id:'111',status:'novo',atualizado_em:'2026-10-15T12:00:00Z'},
  {connection_id:'loja-b',provider:'rappi',loja:'Loja <B>',
    external_order_id:'222',status:'cancelado',atualizado_em:'2026-10-15T13:00:00Z'},
  {connection_id:'loja-c',provider:'ifood',loja:'Loja C',
    external_order_id:'333',status:'concluido',atualizado_em:'2026-10-15T14:00:00Z'}
];
test('integra rota no JS principal com sintaxe valida',()=>{
  assert.match(index,/<script src="integrations\/delivery\/inbox-ui\.js"><\/script>/);
  assert.match(index,/if\(page === 'pedidos'\) return renderPedidosDelivery\(\)/);
  assert.match(index,/'pedidos','Pedidos de delivery'/);
  const inline=[...index.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)?.[1];
  assert.ok(inline); assert.doesNotThrow(()=>new Function(inline));
});
test('lista pedidos, escapa XSS e filtra plataforma, estabelecimento e status',async()=>{
  const ctx=setup(async()=>({data:examples,error:null}));
  await ctx.renderPedidosDelivery();
  assert.match(ctx.root.innerHTML,/Pedido 111/);
  assert.match(ctx.root.innerHTML,/Loja &lt;B&gt;/);
  assert.doesNotMatch(ctx.root.innerHTML,/Loja <B>/);
  assert.match(ctx.root.innerHTML,/Pedido 333/);
  ctx.filtroPedidosDeliveryProvedor('ifood');
  assert.match(ctx.root.innerHTML,/Pedido 111/);
  assert.match(ctx.root.innerHTML,/Pedido 333/);
  assert.doesNotMatch(ctx.root.innerHTML,/Pedido 222/);
  ctx.filtroPedidosDeliveryLoja('loja-a');
  assert.match(ctx.root.innerHTML,/Pedido 111/);
  assert.doesNotMatch(ctx.root.innerHTML,/Pedido 333/);
  ctx.filtroPedidosDelivery('concluido');
  assert.doesNotMatch(ctx.root.innerHTML,/Pedido 111/);
  assert.match(ctx.root.innerHTML,/Nenhum pedido registrado/);
  ctx.filtroPedidosDelivery('novo');
  assert.match(ctx.root.innerHTML,/Pedido 111/);
  assert.match(ctx.root.innerHTML,/1 de 1 pedidos/);
  ctx.filtroPedidosDeliveryLoja('inexistente');
  assert.match(ctx.root.innerHTML,/Pedido 111/,'loja arbitrária não pode afetar filtro');
  ctx.filtroPedidosDeliveryProvedor('rappi');
  assert.match(ctx.root.innerHTML,/Pedido 222/,'trocar provedor limpa a loja anterior');
});
test('erro de licença e falha de rede não são exibidos como lista vazia válida',async()=>{
  const ctx=setup(async()=>({data:null,error:{message:'Permission denied'}}));
  await ctx.renderPedidosDelivery();
  assert.match(ctx.root.innerHTML,/central não está disponível/);
  assert.match(ctx.root.innerHTML,/Confira a contratação/);
  assert.doesNotMatch(ctx.root.innerHTML,/Permission denied/);
  assert.doesNotMatch(ctx.root.innerHTML,/Nenhum pedido registrado/);
});
test('resposta antiga não substitui a atualização mais recente',async()=>{
  let aResolve, bResolve;
  let n=0;
  const ctx=setup(()=>new Promise(resolve=>{
    ++n;
    if(n===1) aResolve=resolve;
    else bResolve=resolve;
  }));
  const primeira=ctx.renderPedidosDelivery();
  const segunda=ctx.renderPedidosDelivery();
  bResolve({data:[examples[1]],error:null});
  await segunda;
  assert.match(ctx.root.innerHTML,/Pedido 222/);
  aResolve({data:[examples[0]],error:null});
  await primeira;
  assert.match(ctx.root.innerHTML,/Pedido 222/);
  assert.doesNotMatch(ctx.root.innerHTML,/Pedido 111/);
});
test('resposta chegando depois de sair da rota não redesenha a tela',async()=>{
  let resolve;
  let page='pedidos';
  const ctx=setup(()=>new Promise(r=>resolve=r),()=>({page}));
  const request=ctx.renderPedidosDelivery();
  page='dash'; ctx.root.innerHTML='TELA DE DASH';
  resolve({data:examples,error:null});
  await request;
  assert.equal(ctx.root.innerHTML,'TELA DE DASH');
});
test('100 pedidos mostra aviso de limite, sem induzir totais globais',async()=>{
  const rows=Array.from({length:100},(_,i)=>({...examples[0],external_order_id:'P'+i}));
  const ctx=setup(async()=>({data:rows,error:null}));
  await ctx.renderPedidosDelivery();
  assert.match(ctx.root.innerHTML,/Exibindo somente os 100 pedidos mais recentes/);
  assert.match(ctx.root.innerHTML,/não de todos os pedidos históricos/);
});
