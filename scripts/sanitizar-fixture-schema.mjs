#!/usr/bin/env node
// HUB LUH PANDA — sanitizar-fixture-schema
//
// Os testes de banco (PGlite) precisam da estrutura REAL do schema `hub`,
// porque algumas tabelas nunca tiveram migration no repo (recebiveis,
// custos_fixos, config, cobranca_envios). Mas o repo é PÚBLICO: o dump de
// produção cru NÃO entra aqui (SEC-HUB-014, 08/10/2026). O que é versionado é a
// versão sanitizada que este script gera:
//
//   - sem comentário SQL (narrativa de negócio, nome de cliente, histórico);
//   - e-mail real da admin trocado por um e-mail de teste (admin@hub.test),
//     que é o mesmo que tests/*/fixture.mjs usa nos claims do JWT.
//
// Uso (o dump cru fica fora do git — ver .gitignore, padrão *_prod_*.sql):
//   node scripts/sanitizar-fixture-schema.mjs <dump_prod.sql> <saida.sql>
//
// O dump cru é schema-only, lido por catálogo (só SELECT) — nunca dado.

import { readFileSync, writeFileSync } from 'node:fs';

const EMAIL_REAL = /lucianapandolfo9@gmail\.com/gi;
export const EMAIL_TESTE = 'admin@hub.test';

// tira o comentário de fim de linha só quando o `--` está FORA de string
// ('...'); se a contagem de aspas antes dele for ímpar, é texto e fica.
function semComentarioFinal(linha) {
  let dentro = false;
  for (let i = 0; i < linha.length; i++) {
    const c = linha[i];
    if (c === "'") dentro = !dentro;
    else if (!dentro && c === '-' && linha[i + 1] === '-') return linha.slice(0, i).trimEnd();
  }
  return linha;
}

export function sanitizar(sql) {
  const saida = [];
  for (const linha of sql.split('\n')) {
    if (/^\s*--/.test(linha)) continue;
    saida.push(semComentarioFinal(linha));
  }
  const corpo = saida.join('\n').replace(EMAIL_REAL, EMAIL_TESTE);
  return '-- Estrutura do schema hub para os testes (PGlite). Gerado por\n' +
    '-- scripts/sanitizar-fixture-schema.mjs: sem dados, sem comentários,\n' +
    '-- e-mail da admin trocado por ' + EMAIL_TESTE + '. Não aplicar em banco nenhum.\n' +
    corpo;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [entrada, destino] = process.argv.slice(2);
  if (!entrada || !destino) {
    console.error('uso: node scripts/sanitizar-fixture-schema.mjs <dump_prod.sql> <saida.sql>');
    process.exit(1);
  }
  const limpo = sanitizar(readFileSync(entrada, 'utf8'));
  if (/lucianapandolfo9|The Best/i.test(limpo)) {
    console.error('sanitização incompleta: ainda há dado identificável na saída');
    process.exit(2);
  }
  writeFileSync(destino, limpo);
  console.log(`ok: ${destino}`);
}
