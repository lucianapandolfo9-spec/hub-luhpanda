import { test } from 'node:test';
import assert from 'node:assert/strict';
import { database, rpc, payload } from './fixture.mjs';

test('DocuSeal: ativa uma vez, registra assinatura pendente e não reabre encerrado', async () => {
  const { db, service } = await database([
    'migrations/042_docuseal_ativa_contrato.sql',
    'migrations/20261008112347_docuseal_preserva_encerramento.sql',
  ]);
  try {
    let submission = 100;
    for (const status of ['rascunho', 'encerrado', 'arquivado']) {
      const r = await rpc(db, 'hub_rpc_novo_cliente', payload(service));
      await db.query(`update hub.contratos set status=$1,docuseal_submission_id=$2 where id=$3`, [status, ++submission, r.contrato_id]);
      const p = { docuseal_submission_id: submission, status: 'assinado', assinado_em: '2026-10-08', audit_log_url: 'https://exemplo.test/audit' };
      await assert.rejects(rpc(db, 'hub_rpc_docuseal_registrar_evento', p, 'intruso'), /acesso negado|permission denied/);
      const result = await rpc(db, 'hub_rpc_docuseal_registrar_evento', p, 'service');
      assert.ok(result.ativacao.erro);
      const ct = (await db.query('select status,assinado_em::text,docuseal_audit_log_url from hub.contratos where id=$1', [r.contrato_id])).rows[0];
      assert.equal(ct.status, status === 'rascunho' ? 'assinado' : status);
      if (status === 'rascunho') assert.equal(ct.assinado_em, '2026-10-08', 'data real permanece mesmo quando a ativação exige ajuste');
      assert.equal(ct.docuseal_audit_log_url, p.audit_log_url);
    }
    assert.equal((await db.query('select count(*)::int n from hub.recebiveis')).rows[0].n, 0);
    const r = await rpc(db, 'hub_rpc_novo_cliente', payload(service));
    await db.query(`update hub.contratos set docuseal_submission_id=999,porta_saida_escrita_em=now() where id=$1`, [r.contrato_id]);
    const p = { docuseal_submission_id: 999, status: 'assinado', assinado_em: '2026-10-08' };
    assert.equal((await rpc(db, 'hub_rpc_docuseal_registrar_evento', p, 'service')).ativacao.parcelas_criadas, 6);
    assert.equal((await rpc(db, 'hub_rpc_docuseal_registrar_evento', p, 'service')).ativacao.ja_estava_ativo, true);
    assert.equal((await db.query('select count(*)::int n from hub.recebiveis')).rows[0].n, 6);
  } finally { await db.close(); }
});
