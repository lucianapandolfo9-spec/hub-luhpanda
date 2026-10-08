// 08/10/2026 — 502 do docuseal-integrar: leitura das respostas do DocuSeal.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  explicarFalhaDocuseal, concluirDiagnostico, resumirCorpo, ROTA_ENVIO_HTML,
} from '../../supabase/functions/docuseal-integrar/falhas.ts';

test('404 na rota de HTML = edição gratuita sem o recurso', () => {
  const r = explicarFalhaDocuseal(404, ROTA_ENVIO_HTML);
  assert.match(r.causa, /edição gratuita/);
});

test('401/403 = chave recusada, aponta pro /settings/api do self-host', () => {
  for (const s of [401, 403]) {
    assert.match(explicarFalhaDocuseal(s).causa, /chave/);
    assert.match(explicarFalhaDocuseal(s).acao, /assinar\.luhpanda\.com\.br\/settings\/api/);
  }
});

test('sem resposta (null), 422, 500 têm explicação própria', () => {
  assert.match(explicarFalhaDocuseal(null).causa, /não respondeu/);
  assert.match(explicarFalhaDocuseal(422).causa, /conteúdo/);
  assert.match(explicarFalhaDocuseal(503).causa, /interno/);
});

test('diagnóstico: o cenário real de 08/10 (3.2.6, rota 404) não está pronto', () => {
  const d = concluirDiagnostico({ versao: '3.2.6', statusChave: 200, statusRotaHtml: 404 });
  assert.equal(d.chave.valida, true);
  assert.equal(d.envio_por_html.disponivel, false);
  assert.equal(d.pronto_pra_enviar, false);
  assert.equal(d.problemas.length, 1);
});

test('diagnóstico: chave de outra instância + rota ausente = 2 problemas', () => {
  const d = concluirDiagnostico({ versao: '3.2.6', statusChave: 401, statusRotaHtml: 404 });
  assert.equal(d.problemas.length, 2);
});

test('diagnóstico: Pro/nuvem (rota protegida 401 sem token) + chave OK = pronto', () => {
  const d = concluirDiagnostico({ versao: 'x', statusChave: 200, statusRotaHtml: 401 });
  assert.equal(d.pronto_pra_enviar, true);
  assert.deepEqual(d.problemas, []);
});

test('resumirCorpo corta e achata', () => {
  assert.equal(resumirCorpo(null), '');
  assert.equal(resumirCorpo('a\n  b'), 'a b');
  assert.equal(resumirCorpo('x'.repeat(1000)).length, 301);
});

test('diagnóstico nunca manda a chave na sonda da rota de HTML (não pode criar envelope)', () => {
  const src = readFileSync(fileURLToPath(new URL('../../supabase/functions/docuseal-integrar/index.ts', import.meta.url)), 'utf8');
  const fn = src.slice(src.indexOf('async function diagnosticar'), src.indexOf('async function rpc('));
  const sonda = fn.slice(fn.indexOf('ROTA_ENVIO_HTML}'));
  assert.ok(!sonda.slice(0, 200).includes('X-Auth-Token'), 'sonda da rota de HTML não pode levar a chave');
  assert.ok(src.indexOf('acao === "diagnostico"') > src.indexOf('await verificarAdmin('), 'diagnóstico tem que vir depois do portão');
});
