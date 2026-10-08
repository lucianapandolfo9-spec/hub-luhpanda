// HUB — teste de compatibilidade: chama TODA RPC public.hub_rpc_* como a
// Luciana, com argumento vazio, antes e depois de 050→052, e exige que o
// resultado (ok ou a mesma mensagem de erro) seja idêntico pras RPCs que já
// existiam. Pega grant faltando, posse errada e RLS barrando o uso dela.
//   node compat.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
import path from 'node:path'; import { fileURLToPath } from 'node:url';
const R=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..')+'/'; const L=(p)=>fs.readFileSync(R+p,'utf8');
const db=new PGlite({extensions:{pgcrypto}});
await db.exec(L('tests/multi-empresa/fixtures/supabase_stub.sql')); await db.exec(L('tests/multi-empresa/fixtures/hub_schema_prod_2026-10-08.sql'));
await db.exec(`insert into auth.users(id,email) values ('00000000-0000-4000-8000-00000000000a','lucianapandolfo9@gmail.com');
insert into hub.workspaces(nome,slug) values('Luh Panda','luhpanda'); insert into hub.empresas(nome,cnpj,tipo) values('Luh Panda','11222333000181','mei');
insert into hub.clientes(empresa_id,slug,nome) select id,'acme','Acme' from hub.empresas;`);
const run = async (label) => {
  const fns=(await db.query(`select p.proname, pg_get_function_identity_arguments(p.oid) a, p.pronargs n from pg_proc p where pronamespace='public'::regnamespace and proname like 'hub\\_rpc\\_%' order by 1`)).rows;
  const res={};
  for (const f of fns) {
    const args = f.a ? f.a.split(', ').map(x=>{const t=x.split(' ').slice(1).join(' '); return t==='jsonb'?`'{}'::jsonb`:`null::${t}`}).join(',') : '';
    try { await db.transaction(async tx=>{ await tx.query(`select set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000000a","email":"lucianapandolfo9@gmail.com"}',true)`); await tx.query('set local role authenticated'); await tx.query(`select * from public.${f.proname}(${args})`); throw new Error('__rollback__ok'); }); }
    catch(e){ res[f.proname]= e.message==='__rollback__ok'?'ok':e.message.slice(0,80); }
  }
  return res;
};
const antes = await run();
for (const m of ['050_multiempresa_base','051_multiempresa_workspace_id','052_multiempresa_virada']) await db.exec(L(`migrations/${m}.sql`));
const depois = await run();
let dif=0;
for (const k of Object.keys(depois)) if ((antes[k]??'(nova)')!==depois[k]) { dif++; console.log(k.padEnd(45), '| antes:', antes[k]??'(nova)', '| depois:', depois[k]); }
const quebradas = Object.keys(antes).filter((k) => antes[k] !== depois[k]);
console.log('RPCs:', Object.keys(depois).length, '| novas:', dif - quebradas.length, '| existentes com resultado diferente:', quebradas.length);
process.exit(quebradas.length ? 1 : 0);
