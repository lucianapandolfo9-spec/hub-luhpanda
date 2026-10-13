import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database, rpc, payload } from './fixture.mjs';

const MIG = 'migrations/045_recebivel_cadastro_integridade.sql';

// chama qualquer função pública como o admin (ou intruso) logado
async function call(db, sql, params = [], who = 'admin') {
  const claims = { role: 'authenticated', sub: '00000000-0000-4000-8000-00000000000a',
    email: who === 'admin' ? 'admin@hub.test' : 'intruso@exemplo.test' };
  return db.transaction(async tx => {
    await tx.query(`select set_config('request.jwt.claims',$1,true)`, [JSON.stringify(claims)]);
    await tx.exec('set local role authenticated');
    return (await tx.query(sql, params)).rows;
  });
}
const salvar = (db, p, who) => call(db, 'select public.hub_rpc_salvar_recebivel($1::jsonb) r', [JSON.stringify(p)], who);

test('045: cadastro manual — validações, id idempotente, valor travado e troca de cliente', async () => {
  const { db, service } = await database([MIG]);
  try {
    const a = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { slug: 'a', nome: 'A' }));
    const b = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { slug: 'b', nome: 'B' }));
    const base = { cliente_id: a.cliente_id, competencia: '2026-10-07', descricao: 'Freela', valor_centavos: 50000 };

    await assert.rejects(salvar(db, base, 'intruso'), /acesso negado/);
    await assert.rejects(salvar(db, { ...base, cliente_id: null }), /hub_recebivel_sem_cliente/);
    await assert.rejects(salvar(db, { ...base, cliente_id: randomUUID() }), /hub_recebivel_cliente_inexistente/);
    await assert.rejects(salvar(db, { ...base, descricao: '   ' }), /hub_recebivel_sem_descricao/);
    await assert.rejects(salvar(db, { ...base, valor_centavos: null }), /hub_recebivel_valor_invalido/);
    await assert.rejects(salvar(db, { ...base, valor_centavos: -1 }), /hub_recebivel_valor_invalido/);
    assert.equal((await db.query('select count(*)::int n from hub.recebiveis')).rows[0].n, 0, 'rejeição não deixa linha');

    // duplo envio com o mesmo id (o front agora gera o id) = 1 linha só
    const id = randomUUID();
    await salvar(db, { ...base, id });
    await salvar(db, { ...base, id });
    const rows = (await db.query('select competencia::text c, valor_travado t, origem from hub.recebiveis')).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].c, '2026-10-01', 'competência vira dia 1');
    assert.equal(rows[0].t, true, 'lançamento manual nasce travado');
    assert.equal(rows[0].origem, 'contrato', 'default do banco continua; o front manda "extra"');

    // payload explícito destrava
    const id2 = randomUUID();
    await salvar(db, { ...base, id: id2, valor_travado: false });
    assert.equal((await db.query('select valor_travado t from hub.recebiveis where id=$1', [id2])).rows[0].t, false);

    // recebível de contrato não muda de cliente
    const signed = await rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: a.contrato_id, assinado_em: '2026-10-08', porta_escrita: true });
    assert.ok(signed.parcelas_criadas > 0);
    const parcela = (await db.query('select id from hub.recebiveis where contrato_id=$1 limit 1', [a.contrato_id])).rows[0].id;
    await assert.rejects(salvar(db, { ...base, id: parcela, cliente_id: b.cliente_id, descricao: 'x' }), /hub_recebivel_contrato_outro_cliente/);
  } finally { await db.close(); }
});

test('045: valor digitado à mão sobrevive à adoção pelo gerador (causa do "valor errado")', async () => {
  const { db, service } = await database([MIG]);
  try {
    const c = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { slug: 'c', nome: 'C', parcelas_total: null, inicio_em: '2026-10-01' }));
    // lançou à mão, origem contrato, ANTES do contrato existir ativo
    await salvar(db, { cliente_id: c.cliente_id, competencia: '2026-10-01', descricao: 'Criação de APP', valor_centavos: 720000, origem: 'contrato' });
    await rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: c.contrato_id, assinado_em: '2026-10-08', porta_escrita: true });
    await call(db, `select public.hub_rpc_garantir_recebiveis_mes('2026-10-01')`);
    const r = (await db.query(`select valor_centavos::int v from hub.recebiveis where cliente_id=$1 and competencia='2026-10-01' and descricao='Criação de APP'`, [c.cliente_id])).rows;
    assert.equal(r.length, 1);
    assert.equal(r[0].v, 720000, 'o gerador não reescreve o valor manual');
  } finally { await db.close(); }
});

test('045: marcar pago — guardas e soma de parciais', async () => {
  const { db, service } = await database([MIG]);
  try {
    const a = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { slug: 'a', nome: 'A' }));
    const id = (await salvar(db, { cliente_id: a.cliente_id, competencia: '2026-10-01', descricao: 'X', valor_centavos: 10000 }))[0].r;
    const pagar = (v, d = '2026-10-10', i = id) => call(db, 'select public.hub_rpc_marcar_pago($1::uuid,$2::bigint,$3::date) r', [i, v, d]);
    await assert.rejects(pagar(null), /hub_pagamento_valor_invalido/);
    await assert.rejects(pagar(0), /hub_pagamento_valor_invalido/);
    await assert.rejects(pagar(-5), /hub_pagamento_valor_invalido/);
    await assert.rejects(pagar(100, null), /hub_pagamento_sem_data/);
    await assert.rejects(pagar(100, '2026-10-10', randomUUID()), /hub_recebivel_nao_encontrado/);
    await assert.rejects(pagar(10001), /hub_pagamento_maior_que_falta/);
    await pagar(4000);
    await pagar(6000);
    const r = (await db.query('select entrada_centavos::int e, falta_centavos::int f from hub.recebiveis where id=$1', [id])).rows[0];
    assert.deepEqual(r, { e: 10000, f: 0 });
    await assert.rejects(pagar(1), /hub_pagamento_maior_que_falta/, 'pago não recebe de novo');
  } finally { await db.close(); }
});

test('045: Dash por período conta recebível sem vencimento pela competência', async () => {
  const { db, service } = await database([MIG]);
  try {
    const a = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { slug: 'a', nome: 'A' }));
    await salvar(db, { cliente_id: a.cliente_id, competencia: '2026-10-01', descricao: 'sem data', valor_centavos: 30000 });
    await salvar(db, { cliente_id: a.cliente_id, competencia: '2026-10-01', descricao: 'com data', valor_centavos: 20000, vence_em: '2026-10-15' });
    const d = (await call(db, `select public.hub_rpc_dash_periodo('2026-10-01','2026-10-31') r`))[0].r;
    assert.equal(Number(d.previsto_centavos), 50000);
    assert.equal(d.granularidade, 'dia');
    assert.equal(d.serie.length, 31);
    assert.equal(Number(d.serie[0].previsto_centavos), 30000, 'sem vencimento cai no dia 1');
    const ano = (await call(db, `select public.hub_rpc_dash_periodo('2026-01-01','2026-12-31') r`))[0].r;
    assert.equal(ano.granularidade, 'mes');
    assert.equal(Number(ano.previsto_centavos), 50000);
    assert.equal(Number(ano.vencidos_count), 0, 'sem data não é vencido');
  } finally { await db.close(); }
});
