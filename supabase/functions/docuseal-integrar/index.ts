// HUB LUH PANDA — docuseal-integrar
//
// Cria o envelope de assinatura no DocuSeal auto-hospedado
// (assinar.luhpanda.com.br) a partir do contrato já montado no Hub, e grava
// o docuseal_submission_id de volta no contrato.
//
// POR QUE ESTA FUNCAO EXISTE (mesma razao de wa-send/reuniao-analisar): o
// Hub e uma pagina estatica no GitHub Pages. Se a API key do DocuSeal
// ficasse no index.html, qualquer um que abrisse o codigo-fonte poderia
// criar envelope de assinatura em nome dela. A chave vive aqui, no
// servidor, e nunca sai.
//
// IDENTIDADE: esta funcao NAO usa service_role. Ela repassa o JWT do
// navegador da Luciana pro Supabase, entao a RPC roda como ela e o guard
// hub.is_admin() continua valendo. (Copiado da wa-send/reuniao-analisar de
// proposito — e o padrao validado do projeto.)
//
// FLUXO: o Hub monta o HTML do contrato NO NAVEGADOR, ja com os marcadores
// de campo do DocuSeal embutidos como texto — {{Assinatura Contratada;
// role=Contratada;type=signature}} etc, ver montarContratoHtmlDocuseal() em
// index.html. Esta funcao so ENCAMINHA esse HTML pronto pro DocuSeal via
// POST /api/submissions/html — quem renderiza HTML -> PDF e detecta os
// campos e o proprio DocuSeal (guia oficial "embedded text field tags").
//
// ⚠️ Por que /submissions/html e nao /submissions/pdf: o Hub NUNCA gerou um
// PDF-blob no navegador nesta versao — o pipeline existente
// (gerarContratoPDF/emitirContrato) sempre abriu window.print() pra ELA
// salvar manualmente. Pedir um PDF pronto aqui exigiria uma biblioteca nova
// no front so pra isso. HTML resolve sem dependencia nenhuma.
//
// ORDEM DE ASSINATURA: "order": "preserved" + submitters na ordem
// [Contratada (ela), Contratante (cliente)] -> o DocuSeal so libera o
// segundo depois que o primeiro assina (comportamento documentado do
// SubmittersOrder = preserved). E-mail sai automatico pros dois, na hora
// certa — nao precisa nada mais desta funcao depois de criar a submission.
//
// QUEM FECHA O CIRCULO: a Edge Function docuseal-webhook (outra, sem JWT,
// autenticada por HMAC) — quando os dois terminam de assinar, ela marca o
// contrato como 'assinado' sozinha.
//
// ⚠️ NAO TESTADO PONTA A PONTA (25/09/2026): ela ainda nao criou a conta em
// /setup do DocuSeal nem gerou a API key. O formato de request abaixo vem
// da OpenAPI publica do DocuSeal (console.docuseal.com/openapi.yml,
// schema CreateSubmissionFromHtmlRequest) — nao de uma chamada real. A
// resposta do POST /api/submissions/html tem DUAS formas possiveis
// documentadas em exemplos DocuSeal (um objeto {id,...} OU uma lista de
// submitters, cada um com submission_id) — o parse abaixo cobre as duas.
// Se vier um terceiro formato na primeira chamada real, é so aqui que
// ajusta.
//
// 🔴 08/10/2026 — CAUSA DO 502: o self-host (DocuSeal 3.2.6, edição
// gratuita) NÃO TEM a rota POST /api/submissions/html (só nuvem/Pro) e
// devolve 404. Detalhe em ./falhas.ts. Desde então esta função:
//   - LOGA status + corpo (cortado) de toda falha do DocuSeal, sem token;
//   - devolve `docuseal_status`, `causa` e `acao` no erro;
//   - aceita { "acao": "diagnostico" } (só ela, depois do portão), que NÃO
//     cria envelope nem manda e-mail: lê a versão, testa a chave em
//     GET /api/user e verifica se a rota de HTML existe nesta edição.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { verificarAdmin } from "../_shared/admin.ts";
import { concluirDiagnostico, explicarFalhaDocuseal, resumirCorpo, ROTA_ENVIO_HTML } from "./falhas.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")
  ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
  ?? "";
const DOCUSEAL_URL = (Deno.env.get("DOCUSEAL_URL") ?? "https://assinar.luhpanda.com.br").replace(/\/+$/, "");
const DOCUSEAL_API_KEY = Deno.env.get("DOCUSEAL_API_KEY");

// e-mail dela como CONTRATADA no envelope — mesmo valor de HUB_ADMIN_EMAIL
// em config.js. Hardcoded aqui de proposito, no mesmo espirito de
// MODELO_BASE_HTML ja hardcodar CNPJ/endereco/chave Pix dela: e dado fixo
// da empresa, nao configuracao de ambiente.
const EMAIL_CONTRATADA = "lucianapandolfo9@gmail.com";
const NOME_CONTRATADA = "Luciana Cristina Goveia Pandolfo";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function responder(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function logar(etapa: string, dados: Record<string, unknown>) {
  // nunca loga header nem a chave — só o que o DocuSeal respondeu.
  console.error(JSON.stringify({ fn: "docuseal-integrar", etapa, ...dados }));
}

async function statusDe(url: string, init?: RequestInit): Promise<{ status: number | null; corpo: string }> {
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(15000) });
    return { status: r.status, corpo: resumirCorpo(await r.text()) };
  } catch (e) {
    return { status: null, corpo: resumirCorpo(String(e)) };
  }
}

async function diagnosticar(): Promise<Response> {
  const versao = await statusDe(`${DOCUSEAL_URL}/version`);
  const chave = await statusDe(`${DOCUSEAL_URL}/api/user`, {
    headers: { "X-Auth-Token": DOCUSEAL_API_KEY! },
  });
  // SEM a chave de propósito: sem token o DocuSeal nunca cria nada. Só
  // distingue rota inexistente (404) de rota protegida (401).
  const rotaHtml = await statusDe(`${DOCUSEAL_URL}${ROTA_ENVIO_HTML}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });
  const resultado = concluirDiagnostico({
    versao: versao.status === 200 ? versao.corpo.slice(0, 20) : null,
    statusChave: chave.status,
    statusRotaHtml: rotaHtml.status,
  });
  logar("diagnostico", resultado);
  return responder({ ok: true, diagnostico: resultado });
}

async function rpc(nome: string, corpo: unknown, jwt: string) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${jwt}`,
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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return responder({ erro: "metodo nao permitido" }, 405);

  // SEC-HUB-012: portão de admin ANTES de qualquer secret/serviço externo
  // (ver _shared/admin.ts — verify_jwt sozinho deixa passar a anon key).
  const portao = await verificarAdmin(req, { supabaseUrl: SUPABASE_URL, anonKey: ANON_KEY });
  if (!portao.ok) return responder({ erro: portao.erro }, portao.status);
  const jwt = portao.jwt;

  if (!DOCUSEAL_API_KEY) {
    return responder({
      erro: "Assinatura por e-mail ainda nao ativada — falta configurar a chave do DocuSeal.",
      detalhe: "Gerar a API key em " + DOCUSEAL_URL + "/settings/api e definir o secret DOCUSEAL_API_KEY no projeto Supabase.",
    }, 503);
  }
  if (!ANON_KEY) {
    return responder({ erro: "configuracao incompleta", detalhe: "SUPABASE_ANON_KEY ausente." }, 500);
  }

  let entrada: {
    acao?: string;
    contrato_id?: string;
    numero?: string | null;
    cliente_nome?: string;
    cliente_email?: string;
    html?: string;
  };
  try {
    entrada = await req.json();
  } catch {
    return responder({ erro: "corpo invalido" }, 400);
  }

  if (entrada.acao === "diagnostico") return await diagnosticar();

  const { contrato_id, cliente_nome, cliente_email, html } = entrada;
  if (!contrato_id || !cliente_nome || !cliente_email || !html) {
    return responder({ erro: "contrato_id, cliente_nome, cliente_email e html sao obrigatorios" }, 400);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cliente_email)) {
    return responder({ erro: "e-mail do cliente parece invalido: " + cliente_email }, 400);
  }

  const nomeSubmissao = `Contrato${entrada.numero ? " nº " + entrada.numero : ""} — ${cliente_nome}`.slice(0, 250);

  // 1) cria o envelope no DocuSeal
  let submissionId: number | null = null;
  let r: Response;
  try {
    r = await fetch(`${DOCUSEAL_URL}${ROTA_ENVIO_HTML}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Auth-Token": DOCUSEAL_API_KEY },
      body: JSON.stringify({
        name: nomeSubmissao,
        order: "preserved", // sequencial: Contratada assina, SÓ DEPOIS o Contratante é liberado
        send_email: true,
        documents: [{ name: nomeSubmissao, html }],
        submitters: [
          { role: "Contratada", name: NOME_CONTRATADA, email: EMAIL_CONTRATADA },
          { role: "Contratante", name: cliente_nome, email: cliente_email },
        ],
      }),
      signal: AbortSignal.timeout(60000),
    });
  } catch (e) {
    const { causa, acao } = explicarFalhaDocuseal(null);
    logar("criar_envelope", { contrato_id, rota: ROTA_ENVIO_HTML, docuseal_status: null, erro: resumirCorpo(String(e)) });
    return responder({
      erro: "nao consegui criar o envelope no DocuSeal",
      docuseal_status: null, causa, acao,
      detalhe: `DocuSeal sem resposta: ${causa}`,
    }, 502);
  }

  const texto = await r.text();
  if (!r.ok) {
    const { causa, acao } = explicarFalhaDocuseal(r.status, ROTA_ENVIO_HTML);
    logar("criar_envelope", { contrato_id, rota: ROTA_ENVIO_HTML, docuseal_status: r.status, corpo: resumirCorpo(texto) });
    return responder({
      erro: "nao consegui criar o envelope no DocuSeal",
      docuseal_status: r.status, causa, acao,
      detalhe: `DocuSeal ${r.status}: ${causa}`,
    }, 502);
  }

  try {
    const corpo = JSON.parse(texto);
    // a resposta documentada do DocuSeal para criação a partir de HTML/PDF
    // varia por versão: às vezes um objeto {id,...}, às vezes uma lista de
    // submitters (cada um trazendo submission_id). Cobre as duas.
    if (Array.isArray(corpo)) {
      submissionId = corpo[0]?.submission_id ?? corpo[0]?.id ?? null;
    } else {
      submissionId = corpo?.id ?? corpo?.submission_id ?? null;
    }
  } catch { /* cai no if abaixo */ }
  if (!submissionId) {
    logar("ler_resposta", { contrato_id, docuseal_status: r.status, corpo: resumirCorpo(texto) });
    return responder({
      erro: "nao consegui criar o envelope no DocuSeal",
      docuseal_status: r.status,
      detalhe: "resposta do DocuSeal sem id de submission reconhecível (o envelope PODE ter sido criado — conferir no painel do DocuSeal antes de reenviar): " + resumirCorpo(texto),
    }, 502);
  }

  // 2) grava o vínculo no contrato — roda COMO ELA (JWT repassado)
  try {
    await rpc("hub_rpc_docuseal_marcar_enviado", {
      p: { contrato_id, docuseal_submission_id: submissionId },
    }, jwt);
  } catch (e) {
    logar("vincular_contrato", { contrato_id, docuseal_submission_id: submissionId, erro: resumirCorpo(String(e)) });
    // o envelope JÁ foi criado do lado do DocuSeal — não perder esse id por
    // causa de um erro de banco. Ela consegue religar manualmente com o id
    // devolvido aqui (via SQL, até existir tela pra isso).
    return responder({
      erro: "envelope criado no DocuSeal mas NAO vinculado ao contrato",
      detalhe: String(e),
      docuseal_submission_id: submissionId,
    }, 502);
  }

  return responder({ ok: true, docuseal_submission_id: submissionId });
});
