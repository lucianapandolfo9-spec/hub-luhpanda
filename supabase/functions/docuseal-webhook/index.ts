// HUB LUH PANDA — docuseal-webhook
//
// Recebe o callback do DocuSeal (assinar.luhpanda.com.br) quando um
// envelope de assinatura muda de estado, e atualiza hub.contratos sozinho.
// É a metade que fecha o círculo aberto por docuseal-integrar.
//
// SEM JWT: quem chama esta função é o próprio servidor do DocuSeal, não o
// navegador dela — não existe sessão de usuário pra repassar. A
// autenticação é OUTRA: a assinatura HMAC-SHA256 no header
// X-Docuseal-Signature (formato "timestamp.hex"), verificada contra o
// segredo DOCUSEAL_WEBHOOK_SECRET (aba HMAC de Configurações de Segurança
// do DocuSeal — o valor começa com "whsec_").
//
// Por não ter JWT de usuário, esta função usa a SUPABASE_SERVICE_ROLE_KEY —
// injetada AUTOMATICAMENTE pelo runtime de Edge Functions em todo projeto
// Supabase, nunca precisa configurar como secret manual — só pra chamar as
// duas RPCs de escrita, que por sua vez estão fechadas por
// hub.is_ingestor() (auth.role() = 'service_role'), a MESMA porta que a
// ponte do Meetily usa (027_reunioes.sql). Nunca escreve direto numa
// tabela — sempre por RPC, igual a todo o resto do projeto.
//
// ⚠️ NÃO TESTADO PONTA A PONTA (25/09/2026) — ela ainda não criou a conta
// nem gerou a API key/segredo do webhook no DocuSeal. Os nomes de evento
// (submission.completed) e a forma do payload (event_type/data ou
// event/submission) vêm da OpenAPI pública do DocuSeal
// (console.docuseal.com/openapi.yml, enum EventType) e da documentação de
// webhooks — não de um payload real capturado. `extrairEvento()` e
// `extrairDocumentoAssinado()` estão isolados de propósito: se o formato
// real vier diferente na primeira assinatura de teste, é só ali que ajusta,
// sem mexer na verificação de assinatura nem nas RPCs.
//
// Registrar esta URL em Configurações → Webhooks do DocuSeal, evento
// "Submission Completed" (ou equivalente): apontar pra
// https://<projeto>.supabase.co/functions/v1/docuseal-webhook

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DOCUSEAL_WEBHOOK_SECRET = Deno.env.get("DOCUSEAL_WEBHOOK_SECRET");
const DOCUSEAL_API_KEY = Deno.env.get("DOCUSEAL_API_KEY"); // reaproveitado só pra baixar o PDF final, se precisar de auth
const CONTRATO_BUCKET = "contratos";
const JANELA_REPLAY_SEGUNDOS = 300; // 5 min, mesma tolerância do exemplo oficial

function responder(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
}

async function rpcServiceRole(nome: string, corpo: unknown) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(corpo),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${texto}`);
  try {
    return texto ? JSON.parse(texto) : null;
  } catch {
    return texto;
  }
}

// ---------- verificação HMAC (Web Crypto — Deno não tem node:crypto aqui) ----------
async function hmacHex(segredo: string, mensagem: string): Promise<string> {
  const chave = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(segredo),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const assinatura = await crypto.subtle.sign("HMAC", chave, new TextEncoder().encode(mensagem));
  return [...new Uint8Array(assinatura)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// comparação em tempo constante — não é `===` de propósito (timing attack
// num endpoint de webhook de documento legal não é hipotético demais pra
// ignorar, e custa três linhas a mais).
function compararConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function assinaturaValida(header: string | null, corpoBruto: string): Promise<boolean> {
  // sem segredo configurado = recusa por padrão. Um webhook de assinatura de
  // CONTRATO sem verificação é pior que não ter o webhook — qualquer um que
  // descobrisse a URL poderia forjar "contrato assinado".
  if (!DOCUSEAL_WEBHOOK_SECRET) return false;
  if (!header) return false;
  const [timestamp, assinatura] = header.split(".", 2);
  if (!timestamp || !assinatura) return false;
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > JANELA_REPLAY_SEGUNDOS) return false;
  const esperado = await hmacHex(DOCUSEAL_WEBHOOK_SECRET, `${timestamp}.${corpoBruto}`);
  return compararConstante(esperado, assinatura);
}

// ---------- forma do payload — isolado de propósito, ver cabeçalho ----------
function extrairEvento(bruto: Record<string, unknown>): { tipo: string; dados: Record<string, unknown> } {
  const tipo = String(bruto.event_type ?? bruto.event ?? "");
  const dados = (bruto.data ?? bruto.submission ?? bruto) as Record<string, unknown>;
  return { tipo, dados };
}

function extrairSubmissionId(dados: Record<string, unknown>): number | null {
  const bruto = dados.id ?? dados.submission_id
    ?? (dados.submission as Record<string, unknown> | undefined)?.id
    ?? null;
  const n = Number(bruto);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function extrairUrlDocumentoAssinado(dados: Record<string, unknown>): string | null {
  const docs = dados.documents;
  if (Array.isArray(docs) && docs.length) {
    const primeiro = docs[0] as Record<string, unknown>;
    if (typeof primeiro.url === "string") return primeiro.url;
  }
  if (typeof dados.combined_document_url === "string") return dados.combined_document_url;
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return responder({ erro: "metodo nao permitido" }, 405);

  const corpoBruto = await req.text();
  const assinaturaHeader = req.headers.get("X-Docuseal-Signature") ?? req.headers.get("x-docuseal-signature");

  if (!(await assinaturaValida(assinaturaHeader, corpoBruto))) {
    return responder({ erro: "assinatura invalida (ou DOCUSEAL_WEBHOOK_SECRET nao configurado)" }, 401);
  }
  if (!SERVICE_ROLE_KEY) {
    return responder({ erro: "configuracao incompleta", detalhe: "SUPABASE_SERVICE_ROLE_KEY ausente." }, 500);
  }

  let bruto: Record<string, unknown>;
  try {
    bruto = JSON.parse(corpoBruto);
  } catch {
    return responder({ erro: "corpo nao e JSON" }, 400);
  }

  const { tipo, dados } = extrairEvento(bruto);

  // só o evento de "TODO MUNDO assinou" avança o status. form.completed
  // dispara por SUBMITTER — ela assinar sozinha não pode virar 'assinado'
  // (o cliente ainda nem recebeu o e-mail dele nesse ponto).
  if (tipo !== "submission.completed") {
    return responder({ ok: true, ignorado: tipo || "evento sem event_type reconhecível" });
  }

  const submissionId = extrairSubmissionId(dados);
  if (submissionId === null) {
    // 200 de propósito: não queremos que o DocuSeal fique reenviando pra
    // sempre um payload que a gente simplesmente não sabe interpretar ainda
    // — isso é bug de leitura nosso, não algo que retry resolve.
    return responder({ ok: true, aviso: "nao achei o id da submission no payload", payload_recebido: bruto });
  }
  const auditLogUrl = typeof dados.audit_log_url === "string" ? dados.audit_log_url : null;

  // 1) o que IMPORTA: marcar o contrato como assinado.
  let contratoId: string | null = null;
  let clienteSlug: string | null = null;
  try {
    const resultado = await rpcServiceRole("hub_rpc_docuseal_registrar_evento", {
      p: { docuseal_submission_id: submissionId, status: "assinado", audit_log_url: auditLogUrl },
    });
    contratoId = resultado?.contrato_id ?? null;
    clienteSlug = resultado?.cliente_slug ?? null;
  } catch (e) {
    return responder({ erro: "evento recebido mas NAO gravado", detalhe: String(e) }, 502);
  }

  // 2) melhor esforço: baixar o PDF final assinado e guardar no MESMO
  // bucket/caminho que o upload manual já usa (<cliente_slug>/<contrato_id>.pdf,
  // 026_bucket_contratos.sql) — assim "Ver PDF" na tela de Contratos
  // funciona sem nenhuma mudança no front. Nunca falha o webhook por causa
  // disso: o status já foi gravado no passo 1, que é o que importa de
  // verdade pro pipeline dela.
  try {
    const urlDoc = extrairUrlDocumentoAssinado(dados);
    if (urlDoc && contratoId && clienteSlug) {
      const respPdf = await fetch(
        urlDoc,
        DOCUSEAL_API_KEY ? { headers: { "X-Auth-Token": DOCUSEAL_API_KEY } } : undefined,
      );
      if (respPdf.ok) {
        const bytes = new Uint8Array(await respPdf.arrayBuffer());
        const caminho = `${clienteSlug}/${contratoId}.pdf`;
        const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${CONTRATO_BUCKET}/${caminho}`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            apikey: SERVICE_ROLE_KEY,
            "Content-Type": "application/pdf",
            "x-upsert": "true",
          },
          body: bytes,
        });
        if (up.ok) {
          await rpcServiceRole("hub_rpc_arquivo_contrato_ingestor", {
            p: { contrato_id: contratoId, arquivo_path: caminho, arquivo_nome: "contrato-assinado.pdf", arquivo_tipo: "application/pdf" },
          });
        }
      }
    }
  } catch (_e) {
    // best-effort de propósito — ver comentário acima. Se isto falhar, ela
    // ainda pode subir o PDF manualmente pela tela, como já fazia antes.
  }

  return responder({ ok: true, contrato_id: contratoId });
});
