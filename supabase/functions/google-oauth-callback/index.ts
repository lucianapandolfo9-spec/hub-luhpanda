// HUB LUH PANDA — google-oauth-callback
//
// Autorização OAuth do Google Agenda, FEITA UMA VEZ (item 7 do Bloco F). Ela
// abre esta própria URL no navegador — sem código nenhum — e a função faz
// as duas pontas:
//
//   1) SEM ?code na querystring: redireciona (302) pra tela de consentimento
//      do Google (access_type=offline + prompt=consent, pra garantir que o
//      Google devolva um refresh_token — sem os dois juntos ele só manda
//      refresh_token na PRIMEIRA autorização, e nunca mais).
//   2) COM ?code (o Google voltou pra cá depois dela aceitar): troca o code
//      por token em oauth2.googleapis.com/token e mostra o refresh_token
//      numa página HTML simples, pra ela copiar e colar como secret no
//      Supabase.
//
// ⚠️ ESTA FUNÇÃO NUNCA GRAVA O REFRESH_TOKEN EM LUGAR NENHUM — nem banco,
// nem log, nem Storage. Ele só aparece nesta resposta HTML, uma vez, na tela
// dela. É o mesmo princípio de segredo do EVOLUTION_API_KEY/GEMINI_API_KEY:
// nunca no cliente, nunca automatizado — ela sempre cola manualmente. Depois
// de colar o secret, fechar esta aba já é suficiente (nada fica pendurado).
//
// PRÉ-REQUISITO (ação dela, fora daqui): criar um OAuth Client ID no Google
// Cloud Console e registrar a URL desta própria função como Redirect URI
// autorizado. Ver o passo a passo completo no relatório desta sessão / no
// Hub Dev.md — não dá pra fazer essa parte por ela, precisa da conta Google
// Cloud dela.
//
// Escopo pedido: calendar.events — cria/lê/edita evento, NÃO dá acesso pra
// apagar o calendário inteiro nem pra outros dados do Google (Gmail, Drive
// etc.). Mínimo necessário pro que o Bloco F promete.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const CLIENT_ID = Deno.env.get("GOOGLE_CALENDAR_CLIENT_ID");
const CLIENT_SECRET = Deno.env.get("GOOGLE_CALENDAR_CLIENT_SECRET");
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/google-oauth-callback`;
const SCOPE = "https://www.googleapis.com/auth/calendar";
// ⚠️ Ampliado de `calendar.events` pra `calendar` (full) em 25/09/2026 — ela
// pediu pra ler múltiplos calendários específicos (não só o principal), e
// listar quais calendários existem (`calendarList.list`) exige esse escopo
// mais amplo; `calendar.events` sozinho dava 403 insufficientPermissions.
// Continua sem acesso a Gmail/Drive/etc — é só o produto Calendar inteiro.

function paginaHtml(titulo: string, corpoHtml: string, cor = "#FF6B35") {
  return new Response(
    `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>${titulo} — Hub Luh Panda</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body{background:#12081A;color:#EDE7F6;font-family:-apple-system,Inter,sans-serif;
       max-width:640px;margin:60px auto;padding:0 20px;line-height:1.55;}
  h1{color:${cor};font-size:22px;}
  code,textarea{font-family:ui-monospace,Menlo,monospace;}
  textarea{width:100%;min-height:70px;background:#1B0F26;color:#EDE7F6;
           border:1px solid rgba(255,255,255,.15);border-radius:10px;padding:12px;font-size:13px;}
  .ok{color:#8BE28B;} .warn{color:#FFC24B;}
  a{color:${cor};}
</style></head><body>
<h1>🐼 Hub Luh Panda</h1>
${corpoHtml}
</body></html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  if (!CLIENT_ID || !CLIENT_SECRET) {
    return paginaHtml("Falta configurar", `
      <p class="warn">Ainda não dá pra autorizar — faltam os secrets
      <code>GOOGLE_CALENDAR_CLIENT_ID</code> e <code>GOOGLE_CALENDAR_CLIENT_SECRET</code>
      no projeto Supabase.</p>
      <p>Esses dois vêm do OAuth Client criado no Google Cloud Console
      (tipo "Web application", com esta URL como Redirect URI autorizado):</p>
      <textarea readonly>${REDIRECT_URI}</textarea>
      <p>Depois de criar o client e colar os dois secrets, recarregue esta página.</p>
    `);
  }

  const erro = url.searchParams.get("error");
  if (erro) {
    return paginaHtml("Autorização recusada", `
      <p class="warn">O Google devolveu: <code>${erro}</code>. Nada foi salvo.
      Pode tentar de novo recarregando esta página.</p>
    `);
  }

  const code = url.searchParams.get("code");

  // Passo 1: sem código ainda — manda ela pro consentimento do Google.
  if (!code) {
    const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    authUrl.searchParams.set("client_id", CLIENT_ID);
    authUrl.searchParams.set("redirect_uri", REDIRECT_URI);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", SCOPE);
    authUrl.searchParams.set("access_type", "offline"); // pede refresh_token
    authUrl.searchParams.set("prompt", "consent");       // garante que ele venha SEMPRE, não só na 1ª vez
    return Response.redirect(authUrl.toString(), 302);
  }

  // Passo 2: trocar o código pelos tokens.
  try {
    const r = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        redirect_uri: REDIRECT_URI,
        grant_type: "authorization_code",
      }),
    });
    const texto = await r.text();
    if (!r.ok) {
      return paginaHtml("Erro na troca do código", `
        <p class="warn">O Google recusou a troca: ${r.status}</p>
        <textarea readonly>${texto.replace(/</g, "&lt;")}</textarea>
        <p>Recarregue esta página pra tentar autorizar de novo.</p>
      `, "#FF5C7A");
    }
    const j = JSON.parse(texto);
    if (!j.refresh_token) {
      // Acontece quando ela já tinha autorizado antes SEM revogar o acesso
      // — o Google só manda refresh_token de novo se o acesso anterior for
      // revogado primeiro (myaccount.google.com/permissions).
      return paginaHtml("Sem refresh_token desta vez", `
        <p class="warn">O Google confirmou o acesso, mas não mandou um <code>refresh_token</code>
        novo — ele só manda isso na primeira autorização de um app.</p>
        <p><b>Como resolver:</b> abra
        <a href="https://myaccount.google.com/permissions" target="_blank">myaccount.google.com/permissions</a>,
        remova o acesso do app "Hub Luh Panda" (ou o nome que você deu ao OAuth Client),
        e recarregue esta página pra autorizar de novo do zero.</p>
      `);
    }

    return paginaHtml("Autorizado!", `
      <p class="ok">Conectado com a Google Agenda. Copie o valor abaixo e cole como secret
      <code>GOOGLE_CALENDAR_REFRESH_TOKEN</code> no projeto Supabase
      (Project Settings → Edge Functions → Secrets), do mesmo jeito que
      <code>EVOLUTION_API_KEY</code> e <code>GEMINI_API_KEY</code> já estão lá.</p>
      <textarea readonly onclick="this.select()">${j.refresh_token}</textarea>
      <p style="margin-top:18px;">Depois de colar o secret, pode fechar esta aba — este token
      não fica guardado em nenhum outro lugar. Se precisar gerar de novo no futuro, é só
      voltar nesta mesma URL.</p>
    `);
  } catch (e) {
    return paginaHtml("Erro inesperado", `<p class="warn">${String(e).replace(/</g, "&lt;")}</p>`, "#FF5C7A");
  }
});
