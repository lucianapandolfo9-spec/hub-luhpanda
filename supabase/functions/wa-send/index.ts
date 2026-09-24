// HUB LUH PANDA — wa-send
//
// Envia uma mensagem de WhatsApp pela Evolution API a partir da ficha do Hub.
//
// POR QUE ESTA FUNCAO EXISTE: o Hub e uma pagina estatica no GitHub Pages.
// Se a chave da Evolution ficasse no index.html, qualquer pessoa que abrisse
// o codigo-fonte poderia disparar WhatsApp pelo numero pessoal da Luciana.
// A chave vive aqui, no servidor, e nunca sai.
//
// IDENTIDADE: esta funcao NAO usa service_role. Ela repassa o JWT do
// navegador da Luciana pro Supabase, entao as RPCs rodam como ela e o guard
// hub.is_admin() continua valendo.
//
// ⚠️ O header `apikey` do PostgREST NAO e o JWT do usuario — e a chave
// publicavel do projeto. Mandar o JWT nos dois lugares devolve
// 401 "Invalid API key".
//
// ⚠️ DUPLICACAO: a Evolution ecoa de volta, pelo MESSAGES_UPSERT, toda
// mensagem que ela mesma envia (fromMe=true). Sem gravar o key.id na linha
// original, o webhook de ingestao inseria uma SEGUNDA copia. Por isso o
// marcar_envio leva o evolution_msg_id — ai o eco bate no unique e e
// descartado pelo `on conflict do nothing`.
//
// ⏱️ LATENCIA: o `delay` do payload da Evolution e um atraso DELIBERADO que
// simula digitacao (anti-ban pra bot). Aqui quem escreve e a Luciana, no
// ritmo dela. Mantido em 0. A resposta devolve `ms` por trecho.
//
// 👥 GRUPO (24/09/2026): destino de grupo usa sufixo @g.us, não
// @s.whatsapp.net. Mandar pro sufixo errado dá "jid ... exists:false" na
// Evolution — foi exatamente o que quebrou o primeiro teste com o grupo
// "The Best", 23/09/2026. hub_rpc_preparar_envio devolve `eh_grupo` (lido
// da própria hub.conversas) pra esta função saber qual sufixo montar.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")
  ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
  ?? "";
const EVOLUTION_URL = Deno.env.get("EVOLUTION_URL") ?? "https://evo.luhpanda.com.br";
const EVOLUTION_INSTANCIA = Deno.env.get("EVOLUTION_INSTANCIA") ?? "LuhPessoal";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY");
const EVOLUTION_DELAY = Number(Deno.env.get("EVOLUTION_DELAY") ?? "0");

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

  const tInicio = Date.now();

  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return responder({ erro: "sem sessao" }, 401);

  if (!EVOLUTION_API_KEY) {
    return responder({
      erro: "Envio ainda nao ativado — falta configurar a chave da Evolution.",
      detalhe: "Definir o secret EVOLUTION_API_KEY no projeto Supabase.",
    }, 503);
  }
  if (!ANON_KEY) {
    return responder({ erro: "configuracao incompleta", detalhe: "SUPABASE_ANON_KEY ausente." }, 500);
  }

  let entrada: { fone?: string; corpo?: string; prospect_id?: string; cliente_id?: string; eh_grupo?: boolean };
  try {
    entrada = await req.json();
  } catch {
    return responder({ erro: "corpo invalido" }, 400);
  }

  const texto = (entrada.corpo ?? "").trim();
  if (!entrada.fone || !texto) return responder({ erro: "fone e corpo sao obrigatorios" }, 400);

  let msgId: string;
  let foneNorm: string;
  let ehGrupo: boolean;
  const tAntesPreparar = Date.now();
  try {
    const preparado = await rpc("hub_rpc_preparar_envio", {
      p: {
        fone: entrada.fone,
        corpo: texto,
        prospect_id: entrada.prospect_id ?? null,
        cliente_id: entrada.cliente_id ?? null,
        eh_grupo: entrada.eh_grupo ?? false,
      },
    }, jwt);
    msgId = preparado.msg_id;
    foneNorm = preparado.fone_norm;
    ehGrupo = !!preparado.eh_grupo;
  } catch (e) {
    return responder({ erro: "nao consegui registrar a mensagem", detalhe: String(e) }, 403);
  }
  const msPreparar = Date.now() - tAntesPreparar;

  const tAntesEvo = Date.now();
  try {
    const r = await fetch(`${EVOLUTION_URL}/message/sendText/${EVOLUTION_INSTANCIA}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_API_KEY },
      body: JSON.stringify({
        number: `${foneNorm}@${ehGrupo ? "g.us" : "s.whatsapp.net"}`,
        text: texto,
        delay: EVOLUTION_DELAY,
        linkPreview: false,
      }),
    });
    const resposta = await r.text();
    if (!r.ok) throw new Error(`Evolution ${r.status}: ${resposta}`);
    const msEvolution = Date.now() - tAntesEvo;

    // id da Evolution: sem ele, o eco do MESSAGES_UPSERT vira linha duplicada
    let evoId: string | null = null;
    try {
      const j = JSON.parse(resposta);
      evoId = (j && j.key && j.key.id) ? String(j.key.id) : null;
    } catch { /* resposta sem JSON: segue sem o id */ }

    const tAntesMarcar = Date.now();
    await rpc("hub_rpc_marcar_envio", {
      p: { msg_id: msgId, status: "enviado", evolution_msg_id: evoId },
    }, jwt);
    const msMarcar = Date.now() - tAntesMarcar;

    return responder({
      ok: true,
      msg_id: msgId,
      evolution_msg_id: evoId,
      ms: {
        preparar: msPreparar,
        evolution: msEvolution,
        marcar: msMarcar,
        total: Date.now() - tInicio,
      },
    });
  } catch (e) {
    await rpc("hub_rpc_marcar_envio", {
      p: { msg_id: msgId, status: "erro", erro: String(e) },
    }, jwt).catch(() => {});
    return responder({ erro: "a mensagem NAO foi enviada", detalhe: String(e) }, 502);
  }
});
