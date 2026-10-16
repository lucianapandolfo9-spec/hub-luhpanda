// HUB LUH PANDA — docuseal-webhook/assinatura.ts  (SEC-HUB-005, revisão 08/10/2026)
//
// Verificação da assinatura do webhook do DocuSeal, isolada pra ser testada
// em Node (tests/edge-admin/docuseal-webhook-hmac.test.mjs) contra o MESMO
// algoritmo do servidor.
//
// FORMATO REAL, conferido no código-fonte do DocuSeal (docusealco/docuseal,
// tag 3.2.6 = versão do self-host assinar.luhpanda.com.br, e master 3.3.1):
//   lib/send_webhook_request.rb
//     body = { event_type:, timestamp:, data: }.to_json
//     header "X-Docuseal-Signature" = WebhookUrls::Signatures.sign(hmac_secret, body:)
//   lib/webhook_urls/signatures.rb
//     sign:   "#{ts}.#{OpenSSL::HMAC.hexdigest('sha256', secret, "#{ts}.#{body}")}"
//     verify: ts, sig = header.split('.', 2); ts inteiro; |agora - ts| <= 300 s;
//             secure_compare(hex esperado, sig)
//     generate_secret: "whsec_" + Base64(24 bytes)
// ⚠️ A CHAVE do HMAC é a string INTEIRA, com o prefixo "whsec_" — o DocuSeal
// NÃO decodifica o base64 (diferente do Svix/Stripe). Colar o valor completo
// no secret DOCUSEAL_WEBHOOK_SECRET.
// O DocuSeal reassina a cada tentativa (timestamp novo), então a janela de
// 5 min não derruba retentativa legítima.

export const JANELA_SEGUNDOS = 300;

export type Veredito = { ok: true } | { ok: false; motivo: string };

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function iguaisTempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// `corpo` são os BYTES crus da requisição — assinar exatamente o que chegou,
// sem decodificar/re-codificar texto no meio.
export async function verificarAssinaturaDocuseal(
  segredo: string | null | undefined,
  header: string | null | undefined,
  corpo: Uint8Array,
  agoraSegundos: number = Math.floor(Date.now() / 1000),
): Promise<Veredito> {
  if (!segredo) return { ok: false, motivo: "segredo nao configurado" };
  if (!header) return { ok: false, motivo: "sem header X-Docuseal-Signature" };

  const ponto = header.indexOf(".");
  if (ponto <= 0) return { ok: false, motivo: "header mal formado" };
  const tsTexto = header.slice(0, ponto);
  const assinatura = header.slice(ponto + 1).trim().toLowerCase();

  // Number("abc") = NaN e NaN > 300 é false — sem esta checagem um timestamp
  // lixo passaria pela janela de replay (a comparação do HMAC ainda barraria,
  // mas a janela tem que se defender sozinha).
  if (!/^\d{1,12}$/.test(tsTexto)) return { ok: false, motivo: "timestamp invalido" };
  if (!/^[0-9a-f]{64}$/.test(assinatura)) return { ok: false, motivo: "assinatura nao e sha256 hex" };
  const ts = Number(tsTexto);
  if (ts < agoraSegundos - JANELA_SEGUNDOS) return { ok: false, motivo: "timestamp velho" };
  if (ts > agoraSegundos + JANELA_SEGUNDOS) return { ok: false, motivo: "timestamp no futuro" };

  const prefixo = new TextEncoder().encode(`${tsTexto}.`);
  const mensagem = new Uint8Array(prefixo.length + corpo.length);
  mensagem.set(prefixo, 0);
  mensagem.set(corpo, prefixo.length);

  const chave = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(segredo),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const esperado = hex(await crypto.subtle.sign("HMAC", chave, mensagem));
  return iguaisTempoConstante(esperado, assinatura) ? { ok: true } : { ok: false, motivo: "assinatura nao confere" };
}
