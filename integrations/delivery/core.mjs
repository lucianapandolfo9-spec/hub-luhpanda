/**
 * Hub — núcleo de eventos de delivery (sem rede e sem dados pessoais).
 * Event parsing NUNCA autentica o remetente. Execute verifyIFood / verifyRappi,
 * ou a autorizacao OAuth/Open Delivery, ANTES de chamar normalizarEvento.
 * Estados canônicos não significam que um pedido foi aceito na plataforma.
 */
const provs = new Set(["ifood", "99food", "rappi"]);
const id = v => typeof v === "string" || typeof v === "number" ? String(v).trim() : "";
const safeId = v => { const s=id(v); if (!s || s.length>180 || /[\u0000-\u001f]/.test(s)) throw Error("identificador ausente ou invalido"); return s; };
const statusMap = {
  ifood: {PLACED:"novo", CONFIRMED:"confirmado", PREPARATION_STARTED:"preparando", READY_TO_PICKUP:"pronto", DISPATCHED:"em_entrega", CONCLUDED:"concluido", CANCELLED:"cancelado"},
  rappi: {READY:"novo", SENT:"novo", TAKEN:"confirmado", READY_FOR_PICKUP:"pronto", REJECTED:"cancelado", TIMEOUT:"cancelado", cancelled:"cancelado", canceled_with_charge:"cancelado", cancel_without_charges:"cancelado", cancel_by_user:"cancelado", cancel_by_support:"cancelado", taken_visible_order:"confirmado", ready_for_pick_up:"pronto", hand_to_domiciliary:"em_entrega", close_order:"concluido"},
  "99food": {CREATED:"novo", CONFIRMED:"confirmado", PREPARING:"preparando", READY:"pronto", IN_DELIVERY:"em_entrega", DELIVERED:"concluido", CANCELLED:"cancelado", CONCLUDED:"concluido"}
};

export function normalizarEvento(provider, body) {
  if (!provs.has(provider) || !body || typeof body !== "object" || Array.isArray(body)) throw Error("provedor ou payload invalido");
  let loja, pedido, evento, estadoBruto, horario, previsto=false, detalhes=false;
  if (provider==="ifood") {
    loja=body.merchantId; pedido=body.orderId; evento=body.id;
    estadoBruto=body.fullCode || body.code; horario=body.createdAt;
    // Webhook iFood é um EVENTO: buscar GET /orders/{id} com retry antes de exibir itens.
  } else if (provider==="rappi") {
    const detail=body.order_detail || {};
    loja=body.store_id ?? detail.store_id ?? body.store?.external_id ?? body.store?.internal_id;
    pedido=body.order_id ?? detail.order_id;
    estadoBruto=body.status ?? body.event;
    previsto=body.action==="scheduled";
    if (body.action==="cancelled") estadoBruto="cancelled";
    else if (previsto) estadoBruto="SCHEDULED";
    else if (!estadoBruto && Array.isArray(detail.items)) estadoBruto="READY";
    evento=body.event_id || [pedido,estadoBruto,body.event_time||detail.place_at||""].join(":");
    horario=body.event_time ?? body.created_at ?? null;
    detalhes=Array.isArray(detail.items) && !previsto;
  } else { // 99Food: contrato Open Delivery; formatos finais serão homologados no sandbox.
    loja=body.merchantId ?? body.merchant?.id;
    pedido=body.orderId ?? body.order?.id;
    evento=body.id ?? body.eventId;
    estadoBruto=body.type ?? body.status ?? body.eventType;
    horario=body.createdAt ?? body.timestamp;
  }
  const sourceStatus=id(estadoBruto);
  const status=previsto?"agendado":(statusMap[provider][sourceStatus] || "revisar");
  return Object.freeze({
    provider, externalStoreId:safeId(loja), externalOrderId:safeId(pedido),
    externalEventId:safeId(evento), sourceStatus:sourceStatus || "desconhecido",
    status, scheduledPreview:previsto, needsOrderFetch: !detalhes,
    occurredAt: typeof horario==="string" && !Number.isNaN(Date.parse(horario)) ? new Date(horario).toISOString() : null
    // Não copiar body / customer / documentos / telefones / endereço para inbox.
  });
}

function constTimeEqualHex(a,b) {
  if(!/^[a-f0-9]{64}$/i.test(a||"") || !/^[a-f0-9]{64}$/i.test(b||"")) return false;
  let diff=0; for(let i=0;i<64;i++) diff |= a.charCodeAt(i)^b.charCodeAt(i);
  return diff===0;
}
async function hmacHex(secret, bytes){
  if(typeof secret!=="string" || !secret) return "";
  const k=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const buf=await crypto.subtle.sign("HMAC",k,bytes);
  return [...new Uint8Array(buf)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
export async function verifyIFood(rawBytes, signature, clientSecret) {
  if(!(rawBytes instanceof Uint8Array)) return false;
  return constTimeEqualHex(await hmacHex(clientSecret,rawBytes), signature);
}
export async function verifyRappi(rawBytes, signature, webhookSecret, nowMs=Date.now(), skewSeconds=600) {
  if(!(rawBytes instanceof Uint8Array) || typeof signature!=="string") return false;
  const m=/^t=(\d{10,13}),sign=([a-f0-9]{64})$/i.exec(signature.replace(/\s+/g,""));
  if(!m || !webhookSecret) return false;
  const t=Number(m[1]); const tMs=t>1e12?t:t*1000;
  if(!Number.isSafeInteger(t) || Math.abs(nowMs-tMs)>skewSeconds*1000) return false;
  const prefix=new TextEncoder().encode(m[1]+".");
  const bytes=new Uint8Array(prefix.length+rawBytes.length);
  bytes.set(prefix); bytes.set(rawBytes,prefix.length);
  return constTimeEqualHex(await hmacHex(webhookSecret,bytes),m[2]);
}
export function dedupeKey(evt) {
  return [evt.provider,evt.externalStoreId,evt.externalOrderId,evt.externalEventId].map(safeId).join("|");
}
const rank={agendado:-1,novo:0,confirmado:1,preparando:2,pronto:3,em_entrega:4,concluido:5,cancelado:6};
export function reconciliarEstado(atual, evento) {
  if(!atual) return evento.status==="revisar" ? "revisar" : evento.status;
  if(evento.status==="revisar" || evento.status==="agendado") return atual;
  if(["concluido","cancelado"].includes(atual)) return atual; // registrar evento, sinalizar revisão manual
  if(evento.status==="cancelado") return "cancelado";
  return (rank[evento.status]??-2)>=(rank[atual]??-2)?evento.status:atual;
}
