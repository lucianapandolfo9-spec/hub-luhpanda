import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync(new URL('../../integrations/delivery/inbox-ui.js',import.meta.url),'utf8');
const index=fs.readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const encode=s=>String(s==null?'':s).replace(/[&<>"']/g, x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const setup=rpc=>{
  const ctx={root:{innerHTML:''},shell:(_active,body)=>body,esc:encode,
    setTimeout:()=>0,console:{warn:()=>{}},hubClient:{rpc}};
  vm.createContext(ctx);
  vm.runInContext(source,ctx,{filename:'integrations/delivery/inbox-ui.js'});
  return ctx;
};
test('integra rota no JS principal com sintaxe valida',()=>{
  assert.match(index,/<script src="integrations\/delivery\/inbox-ui\.js"><\/script>/);
  assert.match(index,/if\(page === 'pedidos'\) return renderPedidosDelivery\(\)/);
  assert.match(index,/'pedidos','Pedidos de delivery'/);
  const inline=[...index.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)?.[1];
  assert.ok(inline);assert.doesNotThrow(()=>new Function(inline));
});
test('interface apresenta pedidos por loja, sem dados pessoais, e filtra status',async()=>{
  const ctx=setup(async()=>({data:[
    {provider:'ifood',loja:'Loja A',external_order_id:'111',status:'novo',atualizado_em:'2026-10-15T12:00:00Z'},
    {provider:'rappi',loja:'Loja <B>',external_order_id:'222',status:'cancelado',atualizado_em:'2026-10-15T13:00:00Z'}
  ],error:null}));
  await ctx.renderPedidosDelivery();
  assert.match(ctx.root.innerHTML,/Loja A/);
  assert.match(ctx.root.innerHTML,/Loja &lt;B&gt;/);
  assert.match(ctx.root.innerHTML,/111/);
  assert.match(ctx.root.innerHTML,/222/);
  ctx.filtroPedidosDelivery('cancelado');
  assert.doesNotMatch(ctx.root.innerHTML,/Pedido 111/);
  assert.match(ctx.root.innerHTML,/Pedido 222/);
  assert.match(ctx.root.innerHTML,/1 de 2 pedidos/);
});
test('sem licenca ou backend indisponivel nao mostra zero pedidos como sucesso',async()=>{
  const ctx=setup(async()=>({data:null,error:{message:'Permission denied'}}));
  await ctx.renderPedidosDelivery();
  assert.match(ctx.root.innerHTML,/central não está disponível/);
  assert.match(ctx.root.innerHTML,/Confira a contratação/);
  assert.doesNotMatch(ctx.root.innerHTML,/Permission denied/);
});
