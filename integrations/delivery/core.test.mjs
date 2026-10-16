import { test } from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { normalizarEvento, verifyIFood, verifyRappi, dedupeKey, reconciliarEstado } from "./core.mjs";

test("iFood: HMAC do payload bruto e vetor oficial do portal", async () => {
  const raw='{"code":"PLC","createdAt":"2023-02-20T18:19:03.20162269Z","fullCode":"PLACED","id":"a38ba215-f949-4b2c-982a-0582a9d0c10e","merchantId":"cad65e8f-6fc6-438a-b159-e64a902a6b9a","orderId":"2c97e104-35ed-4c18-85d7-854a40b6b9e3"}';
  const sig="6f9ed23a7b505a3b6907c5f6eb2ad1b056fbf35a643d365a9a072ed7aabca153";
  const bytes=new TextEncoder().encode(raw);
  assert.equal(await verifyIFood(bytes,sig,"dummysecret"),true);
  assert.equal(await verifyIFood(new TextEncoder().encode(raw+" "),sig,"dummysecret"),false);
  assert.equal(await verifyIFood(bytes,sig,"errado"),false);
  assert.equal(await verifyIFood(bytes,"assinatura-invalida","dummysecret"),false);
  const evt=normalizarEvento("ifood",JSON.parse(raw));
  assert.equal(evt.status,"novo");
  assert.equal(evt.needsOrderFetch,true);
  assert.equal(evt.externalStoreId,"cad65e8f-6fc6-438a-b159-e64a902a6b9a");
});

test("Rappi: HMAC timestamp.body, replay, order e cancelamento", async () => {
  const raw='{"order_detail":{"order_id":"2150","items":[{"sku":"SKU1","quantity":2}]},"store":{"external_id":"loja-1"},"customer":{"email":"privado@exemplo.test"}}';
  const body=new TextEncoder().encode(raw), t=Math.floor(Date.now()/1000);
  const sig=createHmac("sha256","segredo-ficticio").update(t+"."+raw).digest("hex");
  assert.equal(await verifyRappi(body,`t=${t},sign=${sig}`,"segredo-ficticio"),true);
  assert.equal(await verifyRappi(body,`t=${t},sign=${sig}`,"outro"),false);
  assert.equal(await verifyRappi(body,`t=${t},sign=${sig}`,"segredo-ficticio",(t+700)*1000),false);
  const evt=normalizarEvento("rappi",JSON.parse(raw));
  assert.equal(evt.status,"novo");
  assert.equal(evt.needsOrderFetch,false);
  assert.equal(evt.externalStoreId,"loja-1");
  assert.equal(JSON.stringify(evt).includes("privado@exemplo.test"),false,"sem PII no objeto normalizado");
  const cancel=normalizarEvento("rappi",{event:"canceled_with_charge",order_id:"2150",store_id:"loja-1"});
  assert.equal(cancel.status,"cancelado");
  assert.equal(reconciliarEstado("confirmado",cancel),"cancelado");
});

test("Rappi: pré-aviso de pedido agendado não finge venda nem pagamento",()=>{
  const e=normalizarEvento("rappi",{order_detail:{order_id:"e1",items:[{name:"Banana",price:0}],place_at:"2026-10-20 17:00:00"},store:{external_id:"00001"},action:"scheduled",customer:{phone_number:"123"}});
  assert.equal(e.status,"agendado");
  assert.equal(e.scheduledPreview,true);
  assert.equal(e.needsOrderFetch,true);
  assert.equal(e.total_centavos,undefined);
  assert.equal(reconciliarEstado("novo",e),"novo");
});
test("99Food: envelope Open Delivery vira evento; exige vínculo de loja",()=>{
  const a=normalizarEvento("99food",{id:"ev-1",orderId:"pedido-1",merchantId:"loja-1",type:"CREATED",createdAt:"2026-10-15T13:00:00Z",customer:{document:"privado"}});
  const b=normalizarEvento("99food",{id:"ev-1",orderId:"pedido-1",merchantId:"loja-2",type:"CREATED"});
  assert.equal(a.status,"novo");
  assert.notEqual(dedupeKey(a),dedupeKey(b),"lojas diferentes nao colidem");
  assert.equal(a.needsOrderFetch,true);
  assert.equal(JSON.stringify(a).includes("privado"),false);
});
test("identificador e status desconhecidos falham fechados",()=>{
  assert.throws(()=>normalizarEvento("rappi",{event:"NEW_ORDER",store_id:"loja"}),/identificador/);
  assert.throws(()=>normalizarEvento("random",{orderId:"x"}),/provedor/);
  assert.equal(normalizarEvento("99food",{id:"e",orderId:"o",merchantId:"s",type:"STATUS_NOVO"}).status,"revisar");
  const novo=normalizarEvento("ifood",{id:"e",orderId:"o",merchantId:"s",fullCode:"PLACED"});
  assert.equal(reconciliarEstado("pronto",novo),"pronto","evento velho nao regride preparo");
  assert.equal(reconciliarEstado("concluido",novo),"concluido");
  assert.equal(reconciliarEstado("cancelado",novo),"cancelado");
});
