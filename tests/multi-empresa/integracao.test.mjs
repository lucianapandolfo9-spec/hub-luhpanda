import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const LU = { id: '00000000-0000-4000-8000-00000000000a', email: 'lucianapandolfo9@gmail.com' };
const BIA = { id: '00000000-0000-4000-8000-00000000000b', email: 'dona@exemplo.test' };
const CON = { id: '00000000-0000-4000-8000-00000000000c', email: 'consulta@exemplo.test' };

test('Integração real: Estoque, Contator, Novo cliente e DocuSeal isolados por workspace', async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  const call = async (who, name, ...args) => db.transaction(async tx => {
    const claims = who === 'service' ? { role: 'service_role' } : { role: 'authenticated', sub: who.id, email: who.email };
    await tx.query(`select set_config('request.jwt.claims',$1,true)`, [JSON.stringify(claims)]);
    await tx.exec(`set local role ${who === 'service' ? 'service_role' : 'authenticated'}`);
    return (await tx.query(`select public.${name}(${args.map((_, i) => '$' + (i + 1)).join(',')}) r`, args.map(a => a && typeof a === 'object' ? JSON.stringify(a) : a))).rows[0].r;
  });
  try {
    await db.exec(read('tests/multi-empresa/fixtures/supabase_stub.sql'));
    await db.exec(read('tests/multi-empresa/fixtures/hub_schema_prod_2026-10-08.sql'));
    for (const f of ['041_novo_cliente_tela_unica', '20261008112314_novo_cliente_integridade',
      '042_docuseal_ativa_contrato', '20261008112347_docuseal_preserva_encerramento',
      '20261006052445_estoque_contator_estrategico', '20261007204101_estoque_unidade_historico']) {
      await db.exec(read(`tests/multi-empresa/fixtures/prs/${f}.sql`));
    }
    for (const u of [LU, BIA, CON]) await db.query('insert into auth.users(id,email) values($1,$2)', [u.id,u.email]);
    await db.exec(`insert into hub.workspaces(nome,slug) values('Luh Panda','luhpanda');
      insert into hub.empresas(nome,cnpj,tipo) values('Luh Panda','11222333000181','mei');
      insert into hub.servicos(slug,nome,modalidade) values('servico','Serviço','recorrente');`);
    const makeStock = async (who, name) => {
      const loc = await call(who,'hub_rpc_stock_save','location',{name,capacity_liters:100});
      const prod = await call(who,'hub_rpc_stock_save','product',{name,sku:'ITEM',unit:'un',minimum_quantity:1,target_quantity:10,pack_quantity:1,volume_liters:1,preferred_location_id:loc});
      await call(who,'hub_rpc_stock_move',{id:randomUUID(),type:'entry',product_id:prod,location_id:loc,quantity:5,unit_cost_centavos:100,reason:'Entrada de teste'});
      return {loc,prod};
    };
    const stockA = await makeStock(LU,'Item privado da Luh');
    const sidA = (await db.query('select id from hub.servicos limit 1')).rows[0].id;
    const newPayload = sid => ({id:randomUUID(),nome:'Novo',slug:'novo',tipo_cobranca:'percentual',percentual_comissao:5,
      porta_saida_tipo:'manutencao_mensal',servicos:[{servico_id:sid}],contatos:[{nome:'Contato',is_principal:true}]});
    const clientA = await call(LU,'hub_rpc_novo_cliente',newPayload(sidA));
    await db.query(`insert into hub.advisory_records(workspace_id,kind,data) select id,'action','{"private":"Contator da Luh"}'::jsonb from hub.workspaces`);
    for (const f of ['050_multiempresa_base','051_multiempresa_workspace_id','052_multiempresa_virada']) await db.exec(read(`migrations/${f}.sql`));
    if (!process.env.SKIP_INTEGRATION_FIX) {
      await db.exec(read('migrations/20261008112355_multiempresa_integracao_modulos.sql'));
    }
    const WS1 = (await db.query(`select id from hub.workspaces where slug='luhpanda'`)).rows[0].id;
    const WS2 = randomUUID();
    await db.query(`insert into hub.workspaces(id,nome,slug,status) values($1,'Outra empresa','outra','ativo')`,[WS2]);
    await db.query(`insert into hub.workspace_membros(workspace_id,user_id,papel) values($1,$2,'dono'),($1,$3,'consulta')`,[WS2,BIA.id,CON.id]);
    await call(BIA,'hub_rpc_onboarding_salvar_empresa',{cnpj:'12.ABC.345/01DE-35',razao_social:'Outra empresa'});
    const snapBefore = await call(BIA,'hub_rpc_modules_snapshot');
    assert.equal(snapBefore.products.length,0,'ws2 não lê estoque do ws1');
    assert.equal(snapBefore.advisory.length,0,'ws2 não lê Contator do ws1');
    // P5 (grill 08/10): vários CNPJs por workspace
    assert.ok(await call(BIA,'hub_rpc_onboarding_salvar_empresa',{cnpj:'00.000.000/0001-91',razao_social:'Segundo CNPJ'}));
    const stockB = await makeStock(BIA,'Item da outra empresa');
    assert.equal((await db.query('select workspace_id from hub.stock_products where id=$1',[stockB.prod])).rows[0].workspace_id,WS2);
    await assert.rejects(call(BIA,'hub_rpc_stock_save','product',{id:stockA.prod,name:'Roubo',sku:'ITEM',unit:'un',minimum_quantity:1,target_quantity:10,pack_quantity:1}), /workspace|row-level security/);
    await assert.rejects(call(CON,'hub_rpc_stock_save','location',{name:'Proibido'}), /row-level security/);
    assert.equal((await call(CON,'hub_rpc_modules_snapshot')).products[0].id,stockB.prod,'Consulta só lê o próprio estoque');
    assert.equal((await call(LU,'hub_rpc_modules_snapshot')).products[0].id,stockA.prod,'estoque da Luh permanece intacto');
    assert.equal((await call(LU,'hub_rpc_modules_snapshot')).advisory.length,1);
    await db.query(`insert into hub.servicos(workspace_id,slug,nome,modalidade) values($1,'servico','Serviço B','recorrente')`,[WS2]);
    const sidB = (await db.query('select id from hub.servicos where workspace_id=$1',[WS2])).rows[0].id;
    await assert.rejects(call(BIA,'hub_rpc_contrato_assinado',{contrato_id:clientA.contrato_id,porta_escrita:true}), /não encontrado/);
    assert.equal((await db.query('select status from hub.contratos where id=$1',[clientA.contrato_id])).rows[0].status,'rascunho');
    const clientB = await call(BIA,'hub_rpc_novo_cliente',newPayload(sidB));
    assert.equal((await db.query('select workspace_id from hub.clientes where id=$1',[clientB.cliente_id])).rows[0].workspace_id,WS2);
    assert.equal(clientB.slug,'novo','slug pode se repetir em outro workspace');
    await db.query(`update hub.contratos set docuseal_submission_id=700,porta_saida_escrita_em=now() where id=$1`,[clientB.contrato_id]);
    const event={docuseal_submission_id:700,status:'assinado',assinado_em:'2026-10-08'};
    await call('service','hub_rpc_docuseal_registrar_evento',event);
    assert.equal((await db.query('select status from hub.contratos where id=$1',[clientB.contrato_id])).rows[0].status,'ativo','webhook resolve ws2 pelo submission ID');
    assert.equal((await call('service','hub_rpc_docuseal_registrar_evento',event)).ativacao.ja_estava_ativo,true);
    assert.equal((await db.query('select workspace_id from hub.clientes where id=$1',[clientA.cliente_id])).rows[0].workspace_id,WS1);
  } finally { await db.close(); }
});
