// HUB LUH PANDA — _shared/admin.ts
//
// PORTÃO ÚNICO das Edge Functions do Hub (SEC-HUB-001, 08/10/2026).
//
// O DEFEITO QUE ISTO FECHA: `verify_jwt=true` no deploy só prova que o
// token é um JWT assinado pelo projeto — e a chave ANON (pública, está no
// config.js de um repo público) É um JWT assinado pelo projeto. Ou seja,
// verify_jwt sozinho deixava passar: (1) qualquer pessoa da internet com a
// anon key e (2) qualquer usuário logado no MESMO projeto (clientes do
// aprovi.ai, schema posta_ai). As functions que repassam o JWT pra uma RPC
// `hub.is_admin()` ANTES do efeito externo estavam protegidas por tabela;
// as que falavam com Google/Evolution/DocuSeal antes (ou sem) RPC, não.
//
// A REGRA AGORA: toda function do Hub chama `exigirAdmin()` na primeira
// linha útil, ANTES de ler corpo, checar secret ou tocar serviço externo.
//
// COMO DECIDE (mesma regra de hub.is_admin(), sem migration nova):
//   1) pergunta ao Supabase Auth quem é o dono do token (GET /auth/v1/user).
//      A anon key não tem `sub` → o Auth recusa → 401. Token expirado,
//      revogado ou forjado → 401. Isso é validação no servidor, não só
//      decodificar o JWT.
//   2) compara o e-mail do usuário com HUB_ADMIN_EMAIL — o MESMO e-mail
//      fixo de hub.is_admin() (migration 001) e do config.js. Outro usuário
//      do projeto → 403.
//   Qualquer falha de rede/config → fecha (503), nunca abre.

export const HUB_ADMIN_EMAIL = "lucianapandolfo9@gmail.com";

export type ResultadoPortao =
  | { ok: true; jwt: string; email: string }
  | { ok: false; status: number; erro: string };

export async function verificarAdmin(
  req: Request,
  cfg: { supabaseUrl: string; anonKey: string; adminEmail?: string; fetchFn?: typeof fetch },
): Promise<ResultadoPortao> {
  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return { ok: false, status: 401, erro: "sem sessao" };
  if (!cfg.supabaseUrl || !cfg.anonKey) {
    return { ok: false, status: 503, erro: "configuracao incompleta (SUPABASE_URL/ANON_KEY)" };
  }
  if (jwt === cfg.anonKey) return { ok: false, status: 401, erro: "sem sessao" };

  const f = cfg.fetchFn ?? fetch;
  let r: Response;
  try {
    r = await f(`${cfg.supabaseUrl}/auth/v1/user`, {
      headers: { apikey: cfg.anonKey, Authorization: `Bearer ${jwt}` },
    });
  } catch {
    return { ok: false, status: 503, erro: "nao consegui validar a sessao" };
  }
  if (r.status === 401 || r.status === 403) {
    await r.body?.cancel();
    return { ok: false, status: 401, erro: "sessao invalida" };
  }
  if (!r.ok) {
    await r.body?.cancel();
    return { ok: false, status: 503, erro: "nao consegui validar a sessao" };
  }

  let email = "";
  try {
    const u = await r.json();
    email = String(u?.email ?? "").trim().toLowerCase();
  } catch {
    return { ok: false, status: 503, erro: "nao consegui validar a sessao" };
  }
  const admin = (cfg.adminEmail ?? HUB_ADMIN_EMAIL).toLowerCase();
  if (!email || email !== admin) return { ok: false, status: 403, erro: "acesso negado" };
  return { ok: true, jwt, email };
}
