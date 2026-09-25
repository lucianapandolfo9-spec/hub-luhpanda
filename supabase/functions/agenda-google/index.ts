// HUB LUH PANDA — agenda-google
//
// Ponte entre o Hub e o Google Agenda (Fase 3, Bloco F). TRÊS AÇÕES:
//
//   "listar" — eventos do calendário PRINCIPAL da conta dela num intervalo
//              (pra tela #/agenda, visão semana/mês).
//   "obter"  — detalhe ao vivo de uma lista de google_event_id (pra ficha
//              do cliente/prospect mostrar os eventos vinculados — o Hub
//              nunca guarda título/horário, só o vínculo em
//              hub.eventos_agenda; aqui é onde ele pergunta pro Google de
//              novo, toda vez).
//   "criar"  — cria o evento no calendário dela, convida o cliente/prospect
//              (attendees + sendUpdates=all — convite formal de verdade,
//              não aviso por fora), Google Meet se marcado, e grava o
//              vínculo (hub.eventos_agenda) + o rascunho em hub.reunioes.
//
// POR QUE ESTA FUNÇÃO EXISTE (mesma razão de wa-send/reuniao-analisar): o
// Hub é uma página estática. Se o client_secret/refresh_token do Google
// ficassem no index.html, qualquer um que abrisse o código-fonte poderia
// mexer na agenda pessoal dela. As chaves vivem aqui, no servidor.
//
// IDENTIDADE — dois caminhos DIFERENTES na mesma função, de propósito:
//   • Supabase (RPCs hub_rpc_eventos_agenda_vincular /
//     hub_rpc_criar_rascunho_reuniao_agenda): repassa o JWT do navegador
//     dela, então hub.is_admin() continua valendo — mesmo padrão de sempre.
//   • Google Calendar API: usa GOOGLE_CALENDAR_REFRESH_TOKEN (secret do
//     servidor) pra pegar um access_token — a mesma lógica de
//     EVOLUTION_API_KEY: um segredo do sistema, não por usuário, porque só
//     existe UMA conta Google (a dela) e UM calendário (o principal).
//
// ⚠️ NÃO TESTADO PONTA A PONTA (25/09/2026) — ela ainda não fez a
// autorização OAuth (falta criar o Client ID no Google Cloud e rodar
// google-oauth-callback). Até lá, toda chamada cai no guard de "Google
// Agenda ainda não conectada" abaixo, igual ao padrão já usado em
// wa-send (EVOLUTION_API_KEY) e reuniao-analisar (GEMINI_API_KEY).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")
  ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
  ?? "";
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CALENDAR_CLIENT_ID");
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CALENDAR_CLIENT_SECRET");
const GOOGLE_REFRESH_TOKEN = Deno.env.get("GOOGLE_CALENDAR_REFRESH_TOKEN");
const TIMEZONE = "America/Recife";

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
    headers: { "Content-Type": "application/json", apikey: ANON_KEY, Authorization: `Bearer ${jwt}` },
    body: JSON.stringify(corpo),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${texto}`);
  try { return texto ? JSON.parse(texto) : null; } catch { return texto; }
}

// ---------- access_token do Google, a partir do refresh_token ----------
// Cache simples em memória do processo (edge functions ficam "quentes" por
// um tempo entre chamadas) — evita bater no endpoint de token do Google a
// cada ação. Token de acesso do Google dura ~1h; damos folga de 2 min.
let _accessTokenCache: { token: string; expiraEm: number } | null = null;

async function obterAccessToken(): Promise<string> {
  if (_accessTokenCache && Date.now() < _accessTokenCache.expiraEm) {
    return _accessTokenCache.token;
  }
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID!,
      client_secret: GOOGLE_CLIENT_SECRET!,
      refresh_token: GOOGLE_REFRESH_TOKEN!,
      grant_type: "refresh_token",
    }),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`Google token: ${r.status} ${texto}`);
  const j = JSON.parse(texto);
  _accessTokenCache = { token: j.access_token, expiraEm: Date.now() + (Number(j.expires_in ?? 3000) - 120) * 1000 };
  return j.access_token;
}

async function chamarGoogleCalendar(caminho: string, init: RequestInit = {}) {
  const token = await obterAccessToken();
  const r = await fetch(`https://www.googleapis.com/calendar/v3${caminho}`, {
    ...init,
    headers: { ...(init.headers || {}), Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`Google Calendar ${r.status}: ${texto}`);
  return texto ? JSON.parse(texto) : null;
}

// molde enxuto que o front consome — nunca devolve o objeto cru do Google
function resumirEvento(ev: Record<string, unknown>) {
  const start = (ev.start ?? {}) as Record<string, unknown>;
  const end = (ev.end ?? {}) as Record<string, unknown>;
  const conf = (ev.conferenceData ?? {}) as Record<string, unknown>;
  const entryPoints = (conf.entryPoints ?? []) as Array<Record<string, unknown>>;
  const meet = entryPoints.find((p) => p.entryPointType === "video");
  return {
    id: ev.id,
    titulo: ev.summary ?? "(sem título)",
    descricao: ev.description ?? null,
    inicio: start.dateTime ?? start.date ?? null,
    fim: end.dateTime ?? end.date ?? null,
    dia_inteiro: !start.dateTime,
    status: ev.status ?? null, // 'confirmed' | 'cancelled' | 'tentative'
    html_link: ev.htmlLink ?? null,
    meet_link: meet ? meet.uri : null,
    attendees: ((ev.attendees ?? []) as Array<Record<string, unknown>>).map((a) => ({
      email: a.email, resposta: a.responseStatus,
    })),
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return responder({ erro: "método não permitido" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return responder({ erro: "sem sessão" }, 401);

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REFRESH_TOKEN) {
    return responder({
      erro: "Google Agenda ainda não conectada.",
      detalhe: "Falta autorizar em /functions/v1/google-oauth-callback e colar o refresh_token como secret GOOGLE_CALENDAR_REFRESH_TOKEN.",
    }, 503);
  }
  if (!ANON_KEY) return responder({ erro: "configuração incompleta", detalhe: "SUPABASE_ANON_KEY ausente." }, 500);

  let entrada: Record<string, unknown>;
  try { entrada = await req.json(); } catch { return responder({ erro: "corpo inválido" }, 400); }

  const acao = String(entrada.acao ?? "");

  try {
    // ---------------- listar (mini-calendário) ----------------
    if (acao === "listar") {
      const desde = String(entrada.desde_iso ?? "");
      const ate = String(entrada.ate_iso ?? "");
      if (!desde || !ate) return responder({ erro: "desde_iso e ate_iso são obrigatórios" }, 400);
      const qs = new URLSearchParams({
        timeMin: desde, timeMax: ate, singleEvents: "true", orderBy: "startTime", maxResults: "250",
      });
      const dados = await chamarGoogleCalendar(`/calendars/primary/events?${qs}`);
      const eventos = ((dados?.items ?? []) as Array<Record<string, unknown>>)
        .filter((ev) => ev.status !== "cancelled")
        .map(resumirEvento);
      return responder({ ok: true, eventos });
    }

    // ---------------- obter (detalhe ao vivo, pra ficha) ----------------
    if (acao === "obter") {
      const ids = Array.isArray(entrada.google_event_ids) ? entrada.google_event_ids as string[] : [];
      const eventos = [];
      for (const id of ids) {
        try {
          const ev = await chamarGoogleCalendar(`/calendars/primary/events/${encodeURIComponent(id)}`);
          eventos.push(resumirEvento(ev));
        } catch (e) {
          // evento pode ter sido apagado direto no Google — não derruba os outros
          eventos.push({ id, erro: String(e).includes("404") ? "apagado no Google" : String(e) });
        }
      }
      return responder({ ok: true, eventos });
    }

    // ---------------- criar ----------------
    if (acao === "criar") {
      const titulo = String(entrada.titulo ?? "").trim();
      const inicioIso = String(entrada.inicio_iso ?? "");
      const duracaoMin = Number(entrada.duracao_min ?? 60);
      const attendeeEmail = entrada.attendee_email ? String(entrada.attendee_email).trim() : null;
      const comMeet = !!entrada.com_meet;
      const clienteId = entrada.cliente_id ? String(entrada.cliente_id) : null;
      const prospectId = entrada.prospect_id ? String(entrada.prospect_id) : null;

      if (!titulo || !inicioIso) return responder({ erro: "titulo e inicio_iso são obrigatórios" }, 400);
      if (!clienteId && !prospectId) return responder({ erro: "informe cliente_id ou prospect_id" }, 400);

      const inicio = new Date(inicioIso);
      if (isNaN(inicio.getTime())) return responder({ erro: "inicio_iso inválido" }, 400);
      const fim = new Date(inicio.getTime() + duracaoMin * 60000);

      const body: Record<string, unknown> = {
        summary: titulo,
        description: entrada.descricao ? String(entrada.descricao) : undefined,
        start: { dateTime: inicio.toISOString(), timeZone: TIMEZONE },
        end: { dateTime: fim.toISOString(), timeZone: TIMEZONE },
      };
      if (attendeeEmail) body.attendees = [{ email: attendeeEmail }];
      if (comMeet) {
        body.conferenceData = {
          createRequest: {
            requestId: crypto.randomUUID(),
            conferenceSolutionKey: { type: "hangoutsMeet" },
          },
        };
      }

      const qs = new URLSearchParams({ sendUpdates: "all" });
      if (comMeet) qs.set("conferenceDataVersion", "1");
      const criado = await chamarGoogleCalendar(`/calendars/primary/events?${qs}`, {
        method: "POST",
        body: JSON.stringify(body),
      });

      const googleEventId = String(criado.id);

      // vínculo + rascunho de reunião — como ELA (JWT repassado)
      await rpc("hub_rpc_eventos_agenda_vincular", {
        p: { google_event_id: googleEventId, cliente_id: clienteId, prospect_id: prospectId, criado_por: "hub" },
      }, jwt).catch((e) => { throw new Error(`vínculo não salvo: ${e}`); });

      await rpc("hub_rpc_criar_rascunho_reuniao_agenda", {
        p: {
          google_event_id: googleEventId, cliente_id: clienteId, prospect_id: prospectId,
          titulo, realizada_em: inicio.toISOString(),
        },
      }, jwt).catch((e) => { throw new Error(`rascunho de reunião não criado: ${e}`); });

      return responder({ ok: true, evento: resumirEvento(criado) });
    }

    return responder({ erro: `ação desconhecida: "${acao}"` }, 400);
  } catch (e) {
    return responder({ erro: "Google Agenda recusou a chamada", detalhe: String(e) }, 502);
  }
});
