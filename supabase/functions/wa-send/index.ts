// HUB LUH PANDA — wa-send
//
// Envia uma mensagem de WhatsApp pela Evolution API a partir da ficha do Hub.
//
// POR QUE ESTA FUNÇÃO EXISTE: o Hub é uma página estática no GitHub Pages.
// Se a chave da Evolution ficasse no index.html, qualquer pessoa que abrisse
// o código-fonte poderia disparar WhatsApp pelo número pessoal da Luciana.
// A chave vive aqui, no servidor, e nunca sai.
//
// IDENTIDADE: esta função NÃO usa service_role. Ela repassa o JWT do
// navegador da Luciana pro Supabase, então as RPCs rodam como ela e o guard
// hub.is_admin() continua valendo. Se alguém chamar esta função com outro
// login, as RPCs recusam sozinhas.
//
// SECRETS (Supabase → Project Settings → Edge Functions → Secrets):
//   EVOLUTION_API_KEY    obrigatório — Global API Key da Evolution
//   EVOLUTION_URL        opcional, default https://evo.luhpanda.com.br
//   EVOLUTION_INSTANCIA  opcional, default LuhPessoal
//
// Deploy: via MCP do Supabase (deploy_edge_function) ou `supabase functions
// deploy wa-send`. Este arquivo é a fonte da verdade — não editar direto no
// painel.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const EVOLUTION_URL = Deno.env.get("EVOLUTION_URL") ?? "https://evo.luhpanda.com.br";
const EVOLUTION_INSTANCIA = Deno.env.get("EVOLUTION_INSTANCIA") ?? "LuhPessoal";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY");

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

// Chama uma RPC do Hub repassando o JWT de quem chamou a função.
async function rpc(nome: string, corpo: unknown, jwt: string) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: jwt,
      Authorization: `Bearer ${jwt}`,
    },
    body: JSON.stringify(corpo),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${texto}`);
  try {
    return texto ? JSON.parse(texto) : null;
  } catch {
    return texto; // RPC escalar devolve o valor cru, sem aspas
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return responder({ erro: "metodo nao permitido" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return responder({ erro: "sem sessao" }, 401);

  if (!EVOLUTION_API_KEY) {
    // Estado honesto: a função está no ar mas ainda não foi configurada.
    return responder({
      erro: "Envio ainda nao ativado — falta configurar a chave da Evolution.",
      detalhe: "Definir o secret EVOLUTION_API_KEY no projeto Supabase.",
    }, 503);
  }

  let entrada: { fone?: string; corpo?: string; prospect_id?: string; cliente_id?: string };
  try {
    entrada = await req.json();
  } catch {
    return responder({ erro: "corpo invalido" }, 400);
  }

  const texto = (entrada.corpo ?? "").trim();
  if (!entrada.fone || !texto) return responder({ erro: "fone e corpo sao obrigatorios" }, 400);

  // 1) enfileira no banco. Roda como a Luciana: se não for ela, a RPC recusa.
  //    Devolve o telefone já canonicalizado — nunca montar o JID a partir do
  //    cadastro, por causa da regra do nono dígito (DDD >= 31 não leva o 9).
  let msgId: string;
  let foneNorm: string;
  try {
    const preparado = await rpc("hub_rpc_preparar_envio", {
      p: {
        fone: entrada.fone,
        corpo: texto,
        prospect_id: entrada.prospect_id ?? null,
        cliente_id: entrada.cliente_id ?? null,
      },
    }, jwt);
    msgId = preparado.msg_id;
    foneNorm = preparado.fone_norm;
  } catch (e) {
    return responder({ erro: "nao consegui registrar a mensagem", detalhe: String(e) }, 403);
  }

  // 2) manda pela Evolution
  try {
    const r = await fetch(`${EVOLUTION_URL}/message/sendText/${EVOLUTION_INSTANCIA}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_API_KEY },
      body: JSON.stringify({
        number: `${foneNorm}@s.whatsapp.net`,
        text: texto,
        delay: 1200,
        linkPreview: false,
      }),
    });
    const resposta = await r.text();
    if (!r.ok) throw new Error(`Evolution ${r.status}: ${resposta}`);

    await rpc("hub_rpc_marcar_envio", { p: { msg_id: msgId, status: "enviado" } }, jwt);
    return responder({ ok: true, msg_id: msgId });
  } catch (e) {
    // A mensagem fica no banco marcada como erro, com o motivo. Melhor um
    // registro honesto de falha do que uma linha 'enviando' pendurada pra
    // sempre, que a tela mostraria como se ainda estivesse a caminho.
    await rpc("hub_rpc_marcar_envio", {
      p: { msg_id: msgId, status: "erro", erro: String(e) },
    }, jwt).catch(() => {});
    return responder({ erro: "a mensagem NAO foi enviada", detalhe: String(e) }, 502);
  }
});
