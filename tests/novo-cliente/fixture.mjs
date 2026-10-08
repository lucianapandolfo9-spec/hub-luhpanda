import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
export const root = fileURLToPath(new URL('../../', import.meta.url));
export const read = p => readFileSync(root + p, 'utf8');
export async function database(extra = []) {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(read('tests/novo-cliente/fixtures/supabase_stub.sql'));
  await db.exec(read('tests/novo-cliente/fixtures/hub_schema.sql'));
  await db.exec(`insert into hub.workspaces(nome,slug) values('Luh Panda','luhpanda');
    insert into hub.empresas(nome,tipo) values('Luh Panda','mei');
    insert into hub.servicos(slug,nome,modalidade) values('servico','Serviço','recorrente');`);
  await db.exec(read('migrations/041_novo_cliente_tela_unica.sql'));
  await db.exec(read('migrations/20261008112314_novo_cliente_integridade.sql'));
  for (const file of extra) await db.exec(read(file));
  const service = (await db.query('select id from hub.servicos limit 1')).rows[0].id;
  return { db, service };
}
export async function rpc(db, name, p, who = 'admin') {
  const claims = who === 'service' ? { role: 'service_role' } :
    { role: 'authenticated', sub: '00000000-0000-4000-8000-00000000000a',
      email: who === 'admin' ? 'admin@hub.test' : 'intruso@exemplo.test' };
  return db.transaction(async tx => {
    await tx.query(`select set_config('request.jwt.claims',$1,true)`, [JSON.stringify(claims)]);
    await tx.exec(`set local role ${who === 'service' ? 'service_role' : 'authenticated'}`);
    return (await tx.query(`select public.${name}($1::jsonb) r`, [JSON.stringify(p)])).rows[0].r;
  });
}
export function payload(service, extra = {}) {
  return { id: randomUUID(), nome: 'Cliente de teste', slug: 'cliente', recorrente: true,
    tipo_cobranca: 'fixo', valor_mensal_centavos: 120000, parcelas_total: 6,
    dia_vencimento: 10, inicio_em: '2026-10-01', porta_saida_tipo: 'manutencao_mensal',
    servicos: [{ servico_id: service }], contatos: [{ nome: 'Contato', is_principal: true,
      papeis: ['financeiro', 'decisor'], email: 'contato@exemplo.test' }], ...extra };
}
