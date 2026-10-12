import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { verificarAssinaturaDocuseal } from '../../supabase/functions/docuseal-webhook/assinatura.ts';

const SECRET = 'whsec_ficticio_somente_teste_http';
function webhook({ secret = SECRET, serviceKey = 'service.ficticio' } = {}) {
  let handler;
  const calls = [], logs = [];
  const source = readFileSync(new URL('../../supabase/functions/docuseal-webhook/index.ts', import.meta.url), 'utf8')
    .replace(/^import .*;\r?\n/gm, '');
  const env = { SUPABASE_URL: 'https://hub.supabase.test', SUPABASE_SERVICE_ROLE_KEY: serviceKey, DOCUSEAL_WEBHOOK_SECRET: secret };
  runInNewContext(stripTypeScriptTypes(source), {
    Deno: { env: { get: name => env[name] }, serve: fn => { handler = fn; } },
    verificarAssinaturaDocuseal, Request, Response, TextDecoder, TextEncoder, Uint8Array, URL, crypto,
    console: { error: value => logs.push(value), warn: value => logs.push(value), log() {} },
    fetch: async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body) });
      return Response.json({ contrato_id: 'contrato-teste', cliente_slug: null, ativacao: { ja_estava_ativo: true } });
    },
  });
  const send = async (body, { signature = true, method = 'POST', age = 0 } = {}) => {
    const ts = Math.floor(Date.now() / 1000) - age;
    const bytes = typeof body === 'string' ? Buffer.from(body) : body;
    const headers = signature ? { 'X-Docuseal-Signature': `${ts}.${createHmac('sha256', SECRET).update(`${ts}.`).update(bytes).digest('hex')}` } : {};
    return handler(new Request('https://hub.test/docuseal-webhook', { method, headers, ...(method === 'POST' ? { body: bytes } : {}) }));
  };
  return { send, calls, logs };
}

test('HTTP: assinatura ausente, segredo ausente, replay e método incorreto não chamam serviços', async () => {
  const body = '{"event_type":"submission.completed","data":{"id":42}}';
  const w = webhook();
  assert.equal((await w.send(body, { signature: false })).status, 401);
  assert.equal((await w.send(body, { age: 301 })).status, 401);
  assert.equal((await w.send(body, { method: 'GET' })).status, 405);
  assert.equal((await w.send(body, { method: 'OPTIONS' })).status, 200);
  assert.equal(w.calls.length, 0);
  const noSecret = webhook({ secret: '' });
  assert.equal((await noSecret.send(body)).status, 401);
  assert.equal(noSecret.calls.length, 0);
  assert.ok(w.logs.every(log => !log.includes(SECRET) && !log.includes(body)));
});

test('HTTP: JSON/UTF-8/estrutura/ID inválidos retornam 400 sem RPC nem eco do payload', async () => {
  const w = webhook();
  for (const body of ['{', 'null', '[]', 'true',
    '{"event_type":"submission.completed","data":[]}',
    '{"event_type":"submission.completed","data":{"id":42.5}}',
    '{"event_type":"submission.completed","data":{"id":"9007199254740993"}}',
    '{"event_type":"submission.completed","data":{"email":"privado@teste.invalid"}}',
    Buffer.from([0x7b,0x22,0x78,0x22,0x3a,0x22,0xff,0x22,0x7d])]) {
    const response = await w.send(body);
    assert.equal(response.status, 400);
    assert.ok(!(await response.text()).includes('privado@teste.invalid'));
  }
  assert.equal(w.calls.length, 0);
});

test('HTTP: evento válido chega à RPC e form.completed é ignorado', async () => {
  const w = webhook();
  assert.equal((await w.send('{"event_type":"form.completed","data":{"id":42}}')).status, 200);
  assert.equal(w.calls.length, 0);
  const response = await w.send('{"event_type":"submission.completed","data":{"id":42,"completed_at":"2026-10-08T01:00:00Z"}}');
  assert.equal(response.status, 200);
  assert.equal(w.calls.length, 1);
  assert.equal(w.calls[0].url, 'https://hub.supabase.test/rest/v1/rpc/hub_rpc_docuseal_registrar_evento');
  assert.equal(w.calls[0].body.p.docuseal_submission_id, 42);
  assert.equal(w.calls[0].body.p.assinado_em, '2026-10-07');
});
