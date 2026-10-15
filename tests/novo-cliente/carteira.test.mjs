import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database, rpc, payload } from './fixture.mjs';

// 045 — porta de saída opcional + carteira lendo valor dos recebíveis
test('045: cliente novo sem porta de saída vira "nenhuma" e ativa sem trava', async () => {
  const { db, service } = await database();
  try {
    const r = await rpc(db, 'hub_rpc_novo_cliente', payload(service, { porta_saida_tipo: null }));
    const ct = (await db.query('select porta_saida_tipo from hub.contratos where id=$1', [r.contrato_id])).rows[0];
    assert.equal(ct.porta_saida_tipo, 'nenhuma');
    const s = await rpc(db, 'hub_rpc_contrato_assinado', { contrato_id: r.contrato_id, assinado_em: '2026-10-08' });
    assert.equal(s.parcelas_criadas, 6);
    await assert.rejects(rpc(db, 'hub_rpc_novo_cliente', payload(service, { porta_saida_tipo: 'inventada' })), /porta_saida_invalida/);
  } finally { await db.close(); }
});

test('045: carteira mostra valor dos recebíveis de cliente sem contrato', async () => {
  const { db } = await database();
  try {
    const id = randomUUID();
    await db.query(`insert into hub.clientes (id, empresa_id, slug, nome, status) values ($1, hub.default_empresa_id(), 'avulso', 'Avulso', 'ativo')`, [id]);
    const mes = (await db.query(`select date_trunc('month', now() at time zone 'America/Recife')::date::text m`)).rows[0].m;
    await db.query(`insert into hub.recebiveis (cliente_id, competencia, descricao, valor_centavos, entrada_centavos, entrou_em, vence_em, origem)
      values ($1,$2,'Skills',30000,30000,$2,$2,'extra'), ($1,$2,'Extra',50000,10000,null,$2,'extra')`, [id, mes]);
    const linha = await db.transaction(async tx => {
      await tx.query(`select set_config('request.jwt.claims',$1,true)`, [JSON.stringify({ role: 'authenticated', email: 'admin@hub.test' })]);
      await tx.exec('set local role authenticated');
      return (await tx.query(`select * from public.hub_rpc_carteira() where slug='avulso'`)).rows[0];
    });
    assert.equal(linha.valor_mensal_centavos, null);
    assert.equal(Number(linha.receb_valor_centavos), 80000);
    assert.equal(Number(linha.receb_entrou_centavos), 40000);
    assert.equal(Number(linha.receb_falta_centavos), 40000);
    assert.equal(linha.receb_competencia.toISOString().slice(0, 10), mes);
  } finally { await db.close(); }
});
