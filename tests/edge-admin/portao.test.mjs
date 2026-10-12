// SEC-HUB-012 — prova do portão de admin das Edge Functions do Hub.
// Roda em Node (>= 22.18, que lê .ts direto): `node --test` nesta pasta.
//
// 1) unidade: verificarAdmin() recusa sem token, com anon key, com sessão
//    inválida e com usuário que não é ela; aceita só o e-mail admin.
// 2) estrutura: toda function com JWT do Hub importa o portão e o chama
//    ANTES de qualquer fetch a serviço externo. Se alguém escrever uma
//    function nova sem portão, ou reordenar, este teste quebra.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { verificarAdmin, HUB_ADMIN_EMAIL } from '../../supabase/functions/_shared/admin.ts';

const URL_SB = 'https://exemplo.supabase.co';
const ANON = 'anon.jwt.publico';
const req = (token) => new Request('https://x/fn', {
  method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {},
});
// Auth falso: token -> resposta de /auth/v1/user
function authFalso(mapa) {
  const chamadas = [];
  const fetchFn = async (url, init) => {
    chamadas.push(url);
    assert.equal(url, `${URL_SB}/auth/v1/user`);
    const t = init.headers.Authorization.replace('Bearer ', '');
    const r = mapa[t];
    if (r instanceof Error) throw r;
    if (!r) return new Response('{"msg":"invalid JWT"}', { status: 401 });
    return new Response(JSON.stringify(r.corpo), { status: r.status ?? 200 });
  };
  return { fetchFn, chamadas };
}
const cfg = (fetchFn) => ({ supabaseUrl: URL_SB, anonKey: ANON, fetchFn });

test('sem token -> 401, sem nem chamar o Auth', async () => {
  const { fetchFn, chamadas } = authFalso({});
  const r = await verificarAdmin(req(null), cfg(fetchFn));
  assert.deepEqual([r.ok, r.status], [false, 401]);
  assert.equal(chamadas.length, 0);
});

test('anon key (pública) -> 401', async () => {
  const { fetchFn } = authFalso({});
  const r = await verificarAdmin(req(ANON), cfg(fetchFn));
  assert.deepEqual([r.ok, r.status], [false, 401]);
});

test('token que o Auth recusa (expirado/forjado/anon sem sub) -> 401', async () => {
  const { fetchFn } = authFalso({ 'tok.ruim': { status: 403, corpo: { msg: 'missing sub claim' } } });
  assert.equal((await verificarAdmin(req('tok.ruim'), cfg(fetchFn))).status, 401);
  assert.equal((await verificarAdmin(req('tok.desconhecido'), cfg(fetchFn))).status, 401);
});

test('usuário logado que NÃO é ela (ex.: cliente do aprovi.ai) -> 403', async () => {
  const { fetchFn } = authFalso({ 'tok.cliente': { corpo: { id: 'u2', email: 'cliente@aprovi.test' } } });
  const r = await verificarAdmin(req('tok.cliente'), cfg(fetchFn));
  assert.deepEqual([r.ok, r.status], [false, 403]);
});

test('usuário sem e-mail (ex.: login por telefone) -> 403', async () => {
  const { fetchFn } = authFalso({ 'tok.fone': { corpo: { id: 'u3', email: '' } } });
  assert.equal((await verificarAdmin(req('tok.fone'), cfg(fetchFn))).status, 403);
});

test('Auth fora do ar / resposta estranha -> fecha (503), nunca abre', async () => {
  const { fetchFn } = authFalso({ 'tok.x': new Error('rede'), 'tok.y': { status: 500, corpo: {} } });
  assert.deepEqual(await verificarAdmin(req('tok.x'), cfg(fetchFn)).then((r) => [r.ok, r.status]), [false, 503]);
  assert.deepEqual(await verificarAdmin(req('tok.y'), cfg(fetchFn)).then((r) => [r.ok, r.status]), [false, 503]);
  const semCfg = await verificarAdmin(req('tok.x'), { supabaseUrl: '', anonKey: '', fetchFn });
  assert.deepEqual([semCfg.ok, semCfg.status], [false, 503]);
});

test('ela -> passa e devolve o JWT pra repassar às RPCs', async () => {
  const { fetchFn } = authFalso({ 'tok.ela': { corpo: { id: 'u1', email: HUB_ADMIN_EMAIL.toUpperCase() } } });
  const r = await verificarAdmin(req('tok.ela'), cfg(fetchFn));
  assert.equal(r.ok, true);
  assert.equal(r.jwt, 'tok.ela');
});

// ---------- estrutura ----------
const FUNCS = fileURLToPath(new URL('../../supabase/functions/', import.meta.url));
// públicas por desenho, cada uma com a própria autenticação:
const PUBLICAS = {
  'docuseal-webhook': 'HMAC do DocuSeal',
  'google-oauth-callback': 'redirect do Google (sem JWT por natureza)',
};

test('toda function com JWT do Hub passa pelo portão antes de qualquer fetch', () => {
  const nomes = readdirSync(FUNCS).filter((n) => !n.startsWith('_') && statSync(FUNCS + n).isDirectory());
  assert.ok(nomes.length >= 7, 'achei menos functions do que o esperado');
  for (const n of nomes) {
    if (PUBLICAS[n]) continue;
    const src = readFileSync(`${FUNCS}${n}/index.ts`, 'utf8');
    assert.match(src, /from "\.\.\/_shared\/admin\.ts"/, `${n}: não importa o portão`);
    const corpo = src.slice(src.indexOf('Deno.serve('));
    const iPortao = corpo.indexOf('await verificarAdmin(');
    assert.ok(iPortao > 0, `${n}: não chama verificarAdmin no handler`);
    const antes = corpo.slice(0, iPortao);
    for (const proibido of ['fetch(', 'req.json(', 'rpc(', 'chamarGoogleCalendar(']) {
      assert.ok(!antes.includes(proibido), `${n}: "${proibido}" antes do portão`);
    }
  }
});
