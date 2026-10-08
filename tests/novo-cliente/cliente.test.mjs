import { test } from 'node:test';
import assert from 'node:assert/strict';
import { database, rpc, payload } from './fixture.mjs';

test('Cliente, contrato e parcelas: atomicidade, retry e guardas de acesso', async () => {
  const { db, service } = await database();
  try {
    const p = payload(service);
    await assert.rejects(rpc(db, 'hub_rpc_novo_cliente', p, 'intruso'), /acesso negado/);
    await assert.rejects(rpc(db, 'hub_rpc_novo_cliente', { ...p, contatos: [{ nome: 'X', papeis: ['invalido'] }] }), /contatos_papeis_validos/);
    assert.equal((await db.query('select count(*)::int n from hub.clientes')).rows[0].n, 0, 'erro no contato desfaz toda criação');
    const result = await rpc(db, 'hub_rpc_novo_cliente', p);
    assert.equal((await db.query('select count(*)::int n from hub.recebiveis')).rows[0].n, 0, 'rascunho não cobra');
    assert.equal((await rpc(db, 'hub_rpc_novo_cliente', p)).contrato_id, result.contrato_id);
    assert.equal((await db.query('select count(*)::int n from hub.contratos')).rows[0].n, 1);
    const sameSlug = await rpc(db, 'hub_rpc_novo_cliente', payload(service));
    assert.equal(sameSlug.slug, 'cliente-2');
    await assert.rejects(rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: result.contrato_id, assinado_em: '2026-10-08' }), /exige_porta_saida/);
    assert.equal((await db.query('select status from hub.contratos where id=$1', [result.contrato_id])).rows[0].status, 'rascunho');
    const signed = await rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: result.contrato_id, assinado_em: '2026-10-08', porta_escrita: true });
    assert.equal(signed.parcelas_criadas, 6);
    const rows = (await db.query('select competencia::text,vence_em::text,valor_centavos,descricao from hub.recebiveis order by competencia')).rows;
    assert.equal(rows[0].vence_em, '2026-10-10');
    assert.equal(rows[5].vence_em, '2027-03-10');
    assert.ok(rows.every(r => Number(r.valor_centavos) === 120000 && r.competencia.endsWith('-01')));
    assert.match(rows[5].descricao, /parcela 6\/6/);
    assert.equal((await rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: result.contrato_id })).ja_estava_ativo, true);
    assert.equal((await db.query('select count(*)::int n from hub.recebiveis')).rows[0].n, 6);
    const percent = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { tipo_cobranca: 'percentual', percentual_comissao: 5, valor_mensal_centavos: null }));
    assert.equal((await rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: percent.contrato_id, porta_escrita: true })).parcelas_criadas, 0);
    const contact = (await db.query('select id from hub.contatos where cliente_id=$1', [result.cliente_id])).rows[0].id;
    await assert.rejects(rpc(db, 'hub_rpc_salvar_contato', { id: contact, cliente_id: sameSlug.cliente_id, nome: 'Errado', is_principal: true }), /hub_contato_cliente_divergente/);
    assert.equal((await db.query('select count(*)::int n from hub.contatos where is_principal')).rows[0].n, 3, 'cliente divergente não desmarca principal de outro cliente');
    await rpc(db, 'hub_rpc_salvar_contato', { cliente_id: result.cliente_id, nome: 'Novo principal', is_principal: true });
    assert.equal((await db.query('select count(*)::int n from hub.contatos where cliente_id=$1 and is_principal', [result.cliente_id])).rows[0].n, 1);
  } finally { await db.close(); }
});
