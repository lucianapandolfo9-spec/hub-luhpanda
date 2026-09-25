// HUB LUH PANDA — agenda-google
//
// Ponte entre o Hub e o Google Agenda (Fase 3, Bloco F). SEIS AÇÕES:
//
//   "calendarios" — lista os calendários da conta (calendarList.list) —
//                usada pra descobrir IDs; não é chamada pelo front hoje.
//   "listar"   — eventos dos DOIS calendários que ela usa (CALENDARIOS
//                abaixo: "Gestão PDK" = primary, e "Luh Panda"), buscados
//                em paralelo, juntados e ordenados por horário de início
//                (pra tela #/agenda, visão semana/mês). Cada evento
//                devolvido leva `calendario_id`/`calendario_nome` pra o
//                front saber de onde veio. 5º ajuste pedido por ela em
//                25/09/2026: só esses dois, não os outros calendários da
//                conta (Certo Agro, Pandoka, The Best, etc.).
//   "obter"    — detalhe ao vivo de uma lista de google_event_id (pra
//                ficha do cliente/prospect mostrar os eventos vinculados —
//                o Hub nunca guarda título/horário, só o vínculo em
//                hub.eventos_agenda; aqui é onde ele pergunta pro Google
//                de novo, toda vez). Aceita `calendario_id` opcional
//                (default 'primary' — vínculos criados antes do 5º ajuste
//                não têm essa informação salva, e sempre foram criados no
//                calendário principal).
//   "criar"    — cria o evento no calendário PRINCIPAL dela (não muda com
//                o 5º ajuste — ela só pediu pra LER os dois calendários,
//                não pra escolher onde criar), convida o cliente/prospect
//                (attendees + sendUpdates=all — convite formal de
//                verdade, não aviso por fora), Google Meet se marcado, e
//                grava o vínculo (hub.eventos_agenda) + o rascunho em
//                hub.reunioes.
//   "cancelar" — apaga o evento no Google (DELETE, sendUpdates=all —
//                avisa quem foi convidado da cancelação) e SÓ DEPOIS
//                apaga o vínculo em hub.eventos_agenda (RPC
//                rpc_eventos_agenda_desvincular, migration 030). Pedido
//                dela em 25/09/2026, ao ver o Bloco F ao vivo: "apagar
//                reunião clicando nela, igual ao Google Agenda". Aceita
//                `calendario_id` opcional (default 'primary').
//   "editar"   — troca título/data/hora/duração/convidado/Meet de um
//                evento já existente (PATCH, sendUpdates=all — avisa o
//                convidado da mudança). NÃO mexe em hub.eventos_agenda
//                nem em hub.reunioes — o vínculo continua o mesmo, só o
//                conteúdo do evento no Google muda (fonte da verdade
//                nunca duplicada no Hub, mesma regra desde o desenho
//                original do Bloco F). 3º ajuste pedido por ela em
//                25/09/2026, no mesmo modal de detalhe do "Apagar". Aceita
//                `calendario_id` opcional (default 'primary').
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

// Os DOIS calendários que ela pediu pra ler (5º ajuste, 25/09/2026) — IDs
// confirmados via ação "calendarios" (calendarList.list). Hardcoded de
// propósito: ela pediu só esses dois, não uma tela de configuração pra
// escolher entre todos os calendários da conta (tem mais: Certo Agro,
// Calendario Pandoka, The Best, Alma Pipa, Preserve Pipa, Lume Social,
// Feriados no Brasil — nenhum desses entra aqui).
const CALENDARIOS = [
  { id: "primary", nome: "Gestão PDK" },
  { id: "1dc36bf3a86b75744f57a1cb848425f46ae36465989daec54a4f7d5c011c48a8@group.calendar.google.com", nome: "Luh Panda" },
];

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

// molde enxuto que o front consome — nunca devolve o objeto cru do Google.
// `calendarioId` marca de qual dos CALENDARIOS o evento veio (pro front
// guardar e repassar de volta em "obter"/"cancelar"/"editar" — sem isso
// editar/apagar um evento do calendário "Luh Panda" tentaria mexer no
// "primary" e devolveria 404).
function resumirEvento(ev: Record<string, unknown>, calendarioId: string) {
  const start = (ev.start ?? {}) as Record<string, unknown>;
  const end = (ev.end ?? {}) as Record<string, unknown>;
  const conf = (ev.conferenceData ?? {}) as Record<string, unknown>;
  const entryPoints = (conf.entryPoints ?? []) as Array<Record<string, unknown>>;
  const meet = entryPoints.find((p) => p.entryPointType === "video");
  const cal = CALENDARIOS.find((c) => c.id === calendarioId);
  return {
    id: ev.id,
    calendario_id: calendarioId,
    calendario_nome: cal ? cal.nome : calendarioId,
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
    // ---------------- calendarios (lista os calendários da conta dela) ----------------
    // Exige escopo `calendar` (full) — ampliado em 25/09/2026 pra suportar
    // ler calendários específicos além do principal (pedido dela: "Gestão
    // Pandoka" e "Luh Panda"). Usada hoje pelo coordenador pra descobrir os
    // IDs; fica no ar pra uma futura tela de configuração escolher quais
    // calendários o Hub lê, sem precisar redeployar.
    if (acao === "calendarios") {
      const dados = await chamarGoogleCalendar(`/users/me/calendarList`);
      const calendarios = ((dados?.items ?? []) as Array<Record<string, unknown>>).map((c) => ({
        id: c.id, nome: c.summary, principal: !!c.primary, acesso: c.accessRole,
      }));
      return responder({ ok: true, calendarios });
    }

    // ---------------- listar (mini-calendário) ----------------
    // Consulta os DOIS calendários de CALENDARIOS em paralelo, junta e
    // ordena por horário de início — 5º ajuste (25/09/2026).
    if (acao === "listar") {
      const desde = String(entrada.desde_iso ?? "");
      const ate = String(entrada.ate_iso ?? "");
      if (!desde || !ate) return responder({ erro: "desde_iso e ate_iso são obrigatórios" }, 400);
      const qs = new URLSearchParams({
        timeMin: desde, timeMax: ate, singleEvents: "true", orderBy: "startTime", maxResults: "250",
      });
      const listasPorCalendario = await Promise.all(CALENDARIOS.map(async (cal) => {
        const dados = await chamarGoogleCalendar(`/calendars/${encodeURIComponent(cal.id)}/events?${qs}`);
        return ((dados?.items ?? []) as Array<Record<string, unknown>>)
          .filter((ev) => ev.status !== "cancelled")
          .map((ev) => resumirEvento(ev, cal.id));
      }));
      const eventos = listasPorCalendario.flat()
        .sort((a, b) => new Date(String(a.inicio)).getTime() - new Date(String(b.inicio)).getTime());
      return responder({ ok: true, eventos });
    }

    // ---------------- obter (detalhe ao vivo, pra ficha) ----------------
    if (acao === "obter") {
      const ids = Array.isArray(entrada.google_event_ids) ? entrada.google_event_ids as string[] : [];
      const calendarioId = String(entrada.calendario_id ?? "primary").trim() || "primary";
      const eventos = [];
      for (const id of ids) {
        try {
          const ev = await chamarGoogleCalendar(`/calendars/${encodeURIComponent(calendarioId)}/events/${encodeURIComponent(id)}`);
          eventos.push(resumirEvento(ev, calendarioId));
        } catch (e) {
          // evento pode ter sido apagado direto no Google — não derruba os outros
          eventos.push({ id, calendario_id: calendarioId, erro: String(e).includes("404") ? "apagado no Google" : String(e) });
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

      return responder({ ok: true, evento: resumirEvento(criado, "primary") });
    }

    // ---------------- cancelar (apagar reunião, clicando nela) ----------------
    if (acao === "cancelar") {
      const googleEventId = String(entrada.google_event_id ?? "").trim();
      const calendarioId = String(entrada.calendario_id ?? "primary").trim() || "primary";
      if (!googleEventId) return responder({ erro: "google_event_id é obrigatório" }, 400);

      const qs = new URLSearchParams({ sendUpdates: "all" });
      try {
        await chamarGoogleCalendar(`/calendars/${encodeURIComponent(calendarioId)}/events/${encodeURIComponent(googleEventId)}?${qs}`, {
          method: "DELETE",
        });
      } catch (e) {
        // 404/410: já não existe mais no Google (apagado por fora, duplo-clique
        // dela, etc.) — segue pra limpar o vínculo do Hub mesmo assim, de forma
        // idempotente, em vez de deixar um vínculo órfão preso.
        if (!/\b(404|410)\b/.test(String(e))) throw e;
      }

      // só chega aqui depois do Google confirmar (ou já não ter o evento) —
      // nunca o contrário, senão um erro no Google deixaria o vínculo apagado
      // apontando pra um evento que ainda existe na agenda dela.
      const resultado = await rpc("hub_rpc_eventos_agenda_desvincular", {
        p: { google_event_id: googleEventId },
      }, jwt).catch((e) => { throw new Error(`vínculo não removido: ${e}`); });

      return responder({ ok: true, ...(resultado && typeof resultado === "object" ? resultado : {}) });
    }

    // ---------------- editar (trocar dados de uma reunião já marcada) ----------------
    if (acao === "editar") {
      const googleEventId = String(entrada.google_event_id ?? "").trim();
      const calendarioId = String(entrada.calendario_id ?? "primary").trim() || "primary";
      const titulo = String(entrada.titulo ?? "").trim();
      const inicioIso = String(entrada.inicio_iso ?? "");
      const duracaoMin = Number(entrada.duracao_min ?? 60);
      const attendeeEmail = entrada.attendee_email ? String(entrada.attendee_email).trim() : null;
      const comMeet = !!entrada.com_meet;

      if (!googleEventId) return responder({ erro: "google_event_id é obrigatório" }, 400);
      if (!titulo || !inicioIso) return responder({ erro: "titulo e inicio_iso são obrigatórios" }, 400);

      const inicio = new Date(inicioIso);
      if (isNaN(inicio.getTime())) return responder({ erro: "inicio_iso inválido" }, 400);
      const fim = new Date(inicio.getTime() + duracaoMin * 60000);

      // busca o evento atual só pra decidir se mexe no Google Meet — não
      // recriar uma sala que já existe, e só remover se ela desmarcou o
      // checkbox de verdade.
      const atual = await chamarGoogleCalendar(`/calendars/${encodeURIComponent(calendarioId)}/events/${encodeURIComponent(googleEventId)}`);
      const jaTemMeet = !!(((atual?.conferenceData as Record<string, unknown> | undefined)?.entryPoints ?? []) as Array<Record<string, unknown>>)
        .find((p) => p.entryPointType === "video");

      const body: Record<string, unknown> = {
        summary: titulo,
        description: entrada.descricao !== undefined ? (entrada.descricao ? String(entrada.descricao) : null) : undefined,
        start: { dateTime: inicio.toISOString(), timeZone: TIMEZONE },
        end: { dateTime: fim.toISOString(), timeZone: TIMEZONE },
        attendees: attendeeEmail ? [{ email: attendeeEmail }] : [],
      };

      let precisaConferenceVersion = false;
      if (comMeet && !jaTemMeet) {
        body.conferenceData = {
          createRequest: { requestId: crypto.randomUUID(), conferenceSolutionKey: { type: "hangoutsMeet" } },
        };
        precisaConferenceVersion = true;
      } else if (!comMeet && jaTemMeet) {
        body.conferenceData = null;
        precisaConferenceVersion = true;
      }

      const qs = new URLSearchParams({ sendUpdates: "all" });
      if (precisaConferenceVersion) qs.set("conferenceDataVersion", "1");

      const atualizado = await chamarGoogleCalendar(`/calendars/${encodeURIComponent(calendarioId)}/events/${encodeURIComponent(googleEventId)}?${qs}`, {
        method: "PATCH",
        body: JSON.stringify(body),
      });

      return responder({ ok: true, evento: resumirEvento(atualizado, calendarioId) });
    }

    return responder({ erro: `ação desconhecida: "${acao}"` }, 400);
  } catch (e) {
    return responder({ erro: "Google Agenda recusou a chamada", detalhe: String(e) }, 502);
  }
});
