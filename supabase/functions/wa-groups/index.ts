// HUB LUH PANDA — wa-groups
//
// Lista os grupos de WhatsApp que a instância LuhPessoal participa, pra ela
// achar o ID certo na hora de ligar um grupo a um cliente/prospect (ficha →
// editar contato → Tipo: Grupo). Sem isto, caçar o ID de um grupo é manual
// e sujeito a erro de dígito na hora de copiar — foi exatamente isso que
// truncou o ID do grupo "The Best" da primeira vez (24/09/2026).
//
// Reaproveita o MESMO secret EVOLUTION_API_KEY da wa-send — não precisa de
// credencial nova em lugar nenhum. Só leitura (GET fetchAllGroups), nunca
// escreve nada.
//
// Deploy: via MCP do Supabase (deploy_edge_function). Este arquivo é a
// fonte da verdade — não editar direto no painel.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const EVOLUTION_URL = Deno.env.get("EVOLUTION_URL") ?? "https://evo.luhpanda.com.br";
const EVOLUTION_INSTANCIA = Deno.env.get("EVOLUTION_INSTANCIA") ?? "LuhPessoal";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function responder(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // verify_jwt=true no deploy já barra quem não tem sessão Supabase válida
  // antes de chegar aqui — não precisa de checagem extra de is_admin, só
  // existe uma conta autenticada neste projeto (a dela).

  if (!EVOLUTION_API_KEY) {
    return responder({
      erro: "Busca de grupos ainda nao ativada — falta configurar a chave da Evolution.",
    }, 503);
  }

  try {
    const r = await fetch(
      `${EVOLUTION_URL}/group/fetchAllGroups/${EVOLUTION_INSTANCIA}?getParticipants=false`,
      { headers: { apikey: EVOLUTION_API_KEY } },
    );
    const texto = await r.text();
    if (!r.ok) throw new Error(`Evolution ${r.status}: ${texto}`);

    const bruto = JSON.parse(texto);
    const grupos = (Array.isArray(bruto) ? bruto : [])
      .map((g: Record<string, unknown>) => ({
        id: String(g.id ?? ""),
        nome: String(g.subject ?? "(sem nome)"),
      }))
      .filter((g: { id: string }) => g.id)
      .sort((a: { nome: string }, b: { nome: string }) => a.nome.localeCompare(b.nome, "pt-BR"));

    return responder({ grupos });
  } catch (e) {
    return responder({ erro: "nao consegui buscar os grupos", detalhe: String(e) }, 502);
  }
});
