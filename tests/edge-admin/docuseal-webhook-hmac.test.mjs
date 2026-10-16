// SEC-HUB-005 — verificação do webhook do DocuSeal contra o algoritmo REAL.
// Vetor gerado com Ruby OpenSSL reproduzindo WebhookUrls::Signatures.sign
// do DocuSeal 3.2.6 (segredo FICTÍCIO, só de teste).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { verificarAssinaturaDocuseal } from '../../supabase/functions/docuseal-webhook/assinatura.ts';

const SEGREDO = 'whsec_dGVzdGUtdGVzdGUtdGVzdGUtdGVzdGUtMTIz'; // fictício
const CORPO = '{"event_type":"submission.completed","timestamp":"2026-10-08T15:00:00Z","data":{"id":42,"name":"Contrato — Teste ção"}}';
const TS = 1791471600;
const HEADER_RUBY = '1791471600.349c0cf23b78d8e9bd35b6dc50c8b299f3068a6a7655a91d6dc2e922a571b844';
const bytes = (s) => new TextEncoder().encode(s);
const assinar = (seg, ts, corpo) => `${ts}.${createHmac('sha256', seg).update(`${ts}.${corpo}`).digest('hex')}`;

test('aceita a assinatura gerada pelo algoritmo do DocuSeal (vetor Ruby, com UTF-8)', async () => {
  assert.deepEqual(await verificarAssinaturaDocuseal(SEGREDO, HEADER_RUBY, bytes(CORPO), TS + 10), { ok: true });
});

test('a chave é o segredo INTEIRO com "whsec_" (não decodifica base64)', async () => {
  const semPrefixo = SEGREDO.slice('whsec_'.length);
  assert.equal((await verificarAssinaturaDocuseal(semPrefixo, HEADER_RUBY, bytes(CORPO), TS)).ok, false);
  const decodificado = Buffer.from(semPrefixo, 'base64').toString('latin1');
  assert.equal((await verificarAssinaturaDocuseal(decodificado, HEADER_RUBY, bytes(CORPO), TS)).ok, false);
});

test('corpo alterado em 1 byte -> recusa', async () => {
  const r = await verificarAssinaturaDocuseal(SEGREDO, HEADER_RUBY, bytes(CORPO.replace('42', '43')), TS);
  assert.deepEqual(r, { ok: false, motivo: 'assinatura nao confere' });
});

test('sem segredo / sem header / header lixo -> recusa', async () => {
  assert.equal((await verificarAssinaturaDocuseal('', HEADER_RUBY, bytes(CORPO), TS)).ok, false);
  assert.equal((await verificarAssinaturaDocuseal(SEGREDO, null, bytes(CORPO), TS)).ok, false);
  for (const h of ['abc', '.abc', 'abc.' + 'a'.repeat(64), `${TS}.xyz`, `${TS}.` + 'a'.repeat(63)]) {
    assert.equal((await verificarAssinaturaDocuseal(SEGREDO, h, bytes(CORPO), TS)).ok, false, h);
  }
});

test('janela de replay: 300 s pra trás e pra frente, como o verify do DocuSeal', async () => {
  assert.equal((await verificarAssinaturaDocuseal(SEGREDO, HEADER_RUBY, bytes(CORPO), TS + 300)).ok, true);
  assert.equal((await verificarAssinaturaDocuseal(SEGREDO, HEADER_RUBY, bytes(CORPO), TS + 301)).motivo, 'timestamp velho');
  assert.equal((await verificarAssinaturaDocuseal(SEGREDO, HEADER_RUBY, bytes(CORPO), TS - 301)).motivo, 'timestamp no futuro');
});

test('assinatura de outro segredo -> recusa; hex maiúsculo é aceito', async () => {
  const outro = assinar('whsec_outro', TS, CORPO);
  assert.equal((await verificarAssinaturaDocuseal(SEGREDO, outro, bytes(CORPO), TS)).ok, false);
  assert.equal((await verificarAssinaturaDocuseal(SEGREDO, HEADER_RUBY.toUpperCase(), bytes(CORPO), TS)).ok, true);
});
