// HUB LUH PANDA — reuniao-analisar
//
// Le a transcricao de uma reuniao ja subida pela ponte `subir-reuniao`, le o
// catalogo de servicos COM PRECO, e devolve: quem e o cliente, a dor real, o
// escopo pedido, prazo/urgencia, o que ficou combinado e uma PROPOSTA montada
// combinando servicos do catalogo. Grava tudo em hub.reunioes.analise.
//
// POR QUE ESTA FUNCAO EXISTE (mesma razao da wa-send): o Hub e uma pagina
// estatica. Se a chave do Gemini ficasse no index.html, qualquer um que
// abrisse o codigo-fonte gastaria a cota dela. A chave vive aqui, no
// servidor, e nunca sai.
//
// IDENTIDADE: esta funcao NAO usa service_role. Ela repassa o JWT do
// navegador da Luciana pro Supabase, entao as RPCs rodam como ela e o guard
// hub.is_admin() continua valendo. (Copiado da wa-send de proposito — e o
// padrao validado do projeto.)
//
// ⚠️ O header `apikey` do PostgREST NAO e o JWT do usuario — e a chave
// publicavel do projeto. Mandar o JWT nos dois lugares devolve
// 401 "Invalid API key".
//
// ⚠️ MODELO FIXADO em `gemini-3.6-flash`. Nunca trocar por `-latest`: alvo
// movel, muda debaixo do pe e quebra em producao sem ninguem mexer em nada.
// (armadilha ja paga no Bloco C)
//
// ⚠️ `thinkingConfig.thinkingBudget: 0`. Os thinking tokens contam DENTRO do
// maxOutputTokens — com thinking ligado a resposta chega cortada no meio,
// JSON invalido. (segunda armadilha ja paga no Bloco C)
//
// ═══════════════════════════════════════════════════════════════════════
// 🔴 A GUARDA DURA — A IA NUNCA INVENTA VALOR
// ═══════════════════════════════════════════════════════════════════════
// Regra do CLAUDE.md dela: tabela de precos homologada, e NUNCA vender hora
// avulsa. Aqui isso esta em DOIS lugares, de proposito:
//
//   1. no prompt — a IA e instruida a so usar servico do catalogo e a
//      escrever "X nao esta no catalogo" (sem preco) pro que nao existe;
//   2. no codigo, depois — todo item volta a ser conferido contra o
//      catalogo. O preco que vai pro banco e SEMPRE o preco do banco, lido
//      pelo `servico_id`. O numero que a IA escreveu e DESCARTADO, mesmo
//      quando esta certo. Item sem servico_id valido perde o preco e vira
//      `fora_do_catalogo`.
//
// Prompt sozinho e promessa. A validacao no codigo e a trava.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")
  ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
  ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-3.6-flash"; // FIXADO. ver cabecalho.
const MAX_TRANSCRICAO = 400_000;         // guarda de sanidade, nao de contexto

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

// ───────────────────────── catalogo ─────────────────────────

type Servico = {
  id: string;
  slug: string;
  nome: string;
  modalidade: string;
  preco_referencia_centavos: number | null;
  unidade: string | null;
  inclui: string | null;
  ativo: boolean;
};

function reais(centavos: number | null): string {
  if (centavos === null || centavos === undefined) return "sem preco de referencia";
  return `R$ ${(centavos / 100).toFixed(2).replace(".", ",")}`;
}

function catalogoEmTexto(servicos: Servico[]): string {
  return servicos.map((s) =>
    [
      `- id: ${s.id}`,
      `  nome: ${s.nome}`,
      `  modalidade: ${s.modalidade}`,
      `  preco: ${reais(s.preco_referencia_centavos)}${s.unidade ? ` por ${s.unidade}` : ""}`,
      s.inclui ? `  inclui: ${String(s.inclui).replace(/\s+/g, " ").slice(0, 400)}` : null,
    ].filter(Boolean).join("\n")
  ).join("\n");
}

// ───────────────────────── prompt ─────────────────────────

function montarPrompt(titulo: string, realizadaEm: string, transcricao: string, resumo: string, servicos: Servico[]) {
  return `Voce e o analista comercial da Luh Panda (automacao e IA para negocios).
Recebeu a transcricao de uma reuniao e precisa transformar isso em briefing + proposta.

REGRA MAIS IMPORTANTE, ACIMA DE QUALQUER OUTRA:
Voce NUNCA inventa, estima, arredonda ou sugere um valor em dinheiro.
O unico lugar de onde preco pode sair e o CATALOGO abaixo, lido pelo campo "id".
- Todo item de proposta precisa citar um "servico_id" que exista literalmente no catalogo.
- Se o cliente pediu algo que NAO esta no catalogo, voce inclui o item com
  "servico_id": null, "preco_centavos": null, "fora_do_catalogo": true e
  "observacao": "<o que ele pediu> nao esta no catalogo".
- Nunca proponha "hora avulsa", "valor por hora" ou "a combinar com valor".
  Trabalho por hora avulsa nao e vendido aqui.
- Nao escreva numero de dinheiro em NENHUM campo de texto (dor, combinados,
  justificativa). Valor so existe no campo numerico preco_centavos.

CATALOGO DE SERVICOS (unica fonte de preco que existe):
${catalogoEmTexto(servicos)}

REUNIAO
titulo: ${titulo || "(sem titulo)"}
realizada em: ${realizadaEm || "(sem data)"}

${resumo ? `RESUMO QUE O MEETILY JA GEROU (use como apoio, a transcricao manda):\n${resumo}\n` : ""}
TRANSCRICAO (formato "[mm:ss] fala"; a transcricao e automatica e erra nome
proprio o tempo todo — na duvida escreva "a confirmar" em vez de chutar nome):
${transcricao}

RESPONDA SO COM JSON, neste formato exato:
{
  "cliente": {
    "nome": "quem e o cliente/prospect, ou 'a confirmar'",
    "quem_e": "1-2 frases: que negocio e esse, tamanho, momento",
    "confianca": "alta" | "media" | "baixa"
  },
  "dor": "a dor REAL, nao o que ele pediu. o problema que faz ele perder dinheiro ou tempo hoje",
  "escopo_pedido": ["o que ele pediu, um item por linha, nas palavras dele"],
  "prazo": {
    "urgencia": "alta" | "media" | "baixa",
    "prazo_citado": "o prazo que apareceu na conversa, ou null",
    "por_que": "o que na conversa indica essa urgencia"
  },
  "combinados": ["o que ficou combinado/prometido na reuniao, um por linha"],
  "proximos_passos": ["acao concreta que depende da Luh, uma por linha"],
  "proposta": {
    "itens": [
      {
        "servico_id": "id copiado LITERALMENTE do catalogo, ou null",
        "servico_nome": "nome do servico (ou o que o cliente pediu, se for fora do catalogo)",
        "quantidade": 1,
        "fora_do_catalogo": false,
        "justificativa": "por que este servico resolve a dor dele",
        "observacao": null
      }
    ],
    "raciocinio": "2-3 frases ligando a dor aos servicos escolhidos"
  },
  "alertas": ["qualquer coisa que a Luh precise olhar com cuidado antes de propor"]
}

Nao escreva nada fora do JSON. Nao use markdown, nem crase, nem \`\`\`json.`;
}

// ───────────────────────── Gemini, com retry em 503 ─────────────────────────

async function chamarGemini(prompt: string): Promise<string> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
  const corpo = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 8192,
      responseMimeType: "application/json",
      // ⚠️ ver cabecalho: thinking token conta dentro do maxOutputTokens e
      // corta a resposta no meio. Zero, sempre.
      thinkingConfig: { thinkingBudget: 0 },
    },
  };

  // 503 (modelo sobrecarregado) e 429 (cota do minuto) sao transitorios no
  // Gemini e resolvem sozinhos. 4xx de verdade nao adianta repetir.
  const esperas = [0, 1500, 4000];
  let ultimoErro = "";

  for (const espera of esperas) {
    if (espera) await new Promise((r) => setTimeout(r, espera));

    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY! },
      body: JSON.stringify(corpo),
    });
    const texto = await r.text();

    if (r.ok) {
      const j = JSON.parse(texto);
      const saida = j?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? "").join("") ?? "";
      const motivo = j?.candidates?.[0]?.finishReason;
      if (!saida) throw new Error(`Gemini devolveu resposta vazia (finishReason=${motivo})`);
      if (motivo === "MAX_TOKENS") {
        throw new Error("Gemini cortou a resposta no limite de tokens — transcricao grande demais pra uma passada so");
      }
      return saida;
    }

    ultimoErro = `Gemini ${r.status}: ${texto.slice(0, 500)}`;
    if (r.status !== 503 && r.status !== 429 && r.status < 500) break;
  }

  throw new Error(ultimoErro || "Gemini nao respondeu");
}

function extrairJson(bruto: string): Record<string, unknown> {
  const limpo = bruto.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  try {
    return JSON.parse(limpo);
  } catch {
    const i = limpo.indexOf("{");
    const f = limpo.lastIndexOf("}");
    if (i >= 0 && f > i) return JSON.parse(limpo.slice(i, f + 1));
    throw new Error("a resposta do Gemini nao era JSON");
  }
}

// ───────────────────── a trava: preco so vem do banco ─────────────────────

type ItemBruto = {
  servico_id?: string | null;
  servico_nome?: string | null;
  quantidade?: number | null;
  fora_do_catalogo?: boolean;
  justificativa?: string | null;
  observacao?: string | null;
  // se a IA mandar preco (nao devia), ele e IGNORADO — ver abaixo.
  preco_centavos?: number | null;
  valor?: unknown;
  preco?: unknown;
};

function validarProposta(propostaBruta: unknown, servicos: Servico[]) {
  const porId = new Map(servicos.map((s) => [String(s.id), s]));
  const p = (propostaBruta ?? {}) as { itens?: unknown; raciocinio?: unknown };
  const brutos: ItemBruto[] = Array.isArray(p.itens) ? p.itens as ItemBruto[] : [];

  const itens: Record<string, unknown>[] = [];
  const foraDoCatalogo: string[] = [];
  let total = 0;
  let totalConfiavel = true;

  for (const b of brutos) {
    const qtd = Math.max(1, Math.round(Number(b.quantidade ?? 1) || 1));
    const servico = b.servico_id ? porId.get(String(b.servico_id)) : undefined;
    const nomePedido = (b.servico_nome ?? "item sem nome").toString().trim();

    if (!servico) {
      // Nao achou no catalogo. O preco que a IA escreveu (se escreveu) morre
      // AQUI — e exatamente o caso que a regra existe pra cobrir.
      const frase = `${nomePedido} nao esta no catalogo`;
      foraDoCatalogo.push(frase);
      totalConfiavel = false;
      itens.push({
        servico_id: null,
        servico_nome: nomePedido,
        modalidade: null,
        quantidade: qtd,
        preco_centavos: null,
        subtotal_centavos: null,
        fora_do_catalogo: true,
        justificativa: b.justificativa ?? null,
        observacao: frase,
      });
      continue;
    }

    // Achou. O preco vem do BANCO, nunca do modelo — mesmo que o modelo
    // tenha acertado. Um caminho so pra preco.
    const preco = servico.preco_referencia_centavos;
    if (preco === null || preco === undefined) totalConfiavel = false;
    else total += preco * qtd;

    itens.push({
      servico_id: servico.id,
      servico_slug: servico.slug,
      servico_nome: servico.nome,          // nome do catalogo, nao o que a IA escreveu
      modalidade: servico.modalidade,
      unidade: servico.unidade,
      quantidade: qtd,
      preco_centavos: preco ?? null,       // do banco
      subtotal_centavos: preco === null || preco === undefined ? null : preco * qtd,
      fora_do_catalogo: false,
      justificativa: b.justificativa ?? null,
      observacao: preco === null || preco === undefined
        ? `${servico.nome} nao tem preco de referencia no catalogo`
        : (b.observacao ?? null),
    });
  }

  return {
    itens,
    itens_fora_do_catalogo: foraDoCatalogo,
    total_centavos: itens.length && totalConfiavel ? total : null,
    total_parcial: !totalConfiavel,
    raciocinio: typeof p.raciocinio === "string" ? p.raciocinio : null,
    // rastro pra auditoria: quem conferiu o preco foi o codigo, nao o prompt
    precos_conferidos_contra_catalogo: true,
  };
}

// ───────────────────────── handler ─────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return responder({ erro: "metodo nao permitido" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return responder({ erro: "sem sessao" }, 401);

  if (!GEMINI_API_KEY) {
    return responder({
      erro: "Analise de reuniao ainda nao ativada — falta configurar a chave do Gemini.",
      detalhe: "Definir o secret GEMINI_API_KEY no projeto Supabase.",
    }, 503);
  }
  if (!ANON_KEY) {
    return responder({ erro: "configuracao incompleta", detalhe: "SUPABASE_ANON_KEY ausente." }, 500);
  }

  let entrada: { reuniao_id?: string; salvar?: boolean };
  try {
    entrada = await req.json();
  } catch {
    return responder({ erro: "corpo invalido" }, 400);
  }
  if (!entrada.reuniao_id) return responder({ erro: "reuniao_id e obrigatorio" }, 400);

  // 1) reuniao + 2) catalogo, as duas rodando COMO ELA (is_admin vale)
  let detalhe: { reuniao?: Record<string, unknown> } | null;
  let servicos: Servico[];
  try {
    const [d, cat] = await Promise.all([
      rpc("hub_rpc_reuniao", { p_id: entrada.reuniao_id }, jwt),
      rpc("hub_rpc_catalogo", {}, jwt),
    ]);
    detalhe = d;
    servicos = (Array.isArray(cat) ? cat : []).filter((s: Servico) => s.ativo !== false);
  } catch (e) {
    return responder({ erro: "nao consegui ler a reuniao ou o catalogo", detalhe: String(e) }, 403);
  }

  const r = detalhe?.reuniao;
  if (!r) return responder({ erro: "reuniao nao encontrada" }, 404);
  if (!servicos.length) {
    return responder({ erro: "catalogo de servicos vazio — sem catalogo nao existe proposta com preco" }, 409);
  }

  const transcricao = String(r.transcricao ?? "").slice(0, MAX_TRANSCRICAO);
  const resumo = String(r.resumo ?? "");
  if (!transcricao && !resumo) {
    return responder({ erro: "essa reuniao nao tem transcricao nem resumo pra analisar" }, 409);
  }

  // 3) Gemini
  let bruto: Record<string, unknown>;
  try {
    const saida = await chamarGemini(
      montarPrompt(String(r.titulo ?? ""), String(r.realizada_em ?? ""), transcricao, resumo, servicos),
    );
    bruto = extrairJson(saida);
  } catch (e) {
    return responder({ erro: "a analise nao foi gerada", detalhe: String(e) }, 502);
  }

  // 4) A TRAVA. Preco do banco, sempre.
  const analise = {
    cliente: bruto.cliente ?? null,
    dor: bruto.dor ?? null,
    escopo_pedido: bruto.escopo_pedido ?? [],
    prazo: bruto.prazo ?? null,
    combinados: bruto.combinados ?? [],
    proximos_passos: bruto.proximos_passos ?? [],
    proposta: validarProposta(bruto.proposta, servicos),
    alertas: bruto.alertas ?? [],
    meta: {
      modelo: GEMINI_MODEL,
      gerado_em: new Date().toISOString(),
      transcricao_chars: transcricao.length,
      servicos_no_catalogo: servicos.length,
      // nunca virar true sem a validacao acima ter rodado
      preco_so_do_catalogo: true,
    },
  };

  // 5) grava (a menos que ela tenha pedido so a previa)
  if (entrada.salvar !== false) {
    try {
      await rpc("hub_rpc_salvar_analise", { p: { id: entrada.reuniao_id, analise } }, jwt);
    } catch (e) {
      return responder({ erro: "analise gerada mas NAO salva", detalhe: String(e), analise }, 502);
    }
  }

  return responder({ ok: true, reuniao_id: entrada.reuniao_id, salvo: entrada.salvar !== false, analise });
});
