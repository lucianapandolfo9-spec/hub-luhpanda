// HUB — teste de isolamento multi-empresa (050 → 052) em PGlite.
//
// Roda tudo em memória: imitação do Supabase (auth/storage/roles) + o schema
// `hub` de PRODUÇÃO (só estrutura, lido por catálogo em 07/10/2026) + dados
// FICTÍCIOS + as migrations 050/051/052 + os cenários de ataque entre 2
// workspaces + as 3 voltas (rollback) na ordem inversa.
//
//   cd tests/multi-empresa && npm i @electric-sql/pglite@0.5.8 && node isolamento.test.mjs
//
// Sai com código 1 se qualquer verificação falhar. Não conecta em banco nenhum.
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const RAIZ = path.resolve(AQUI, '../..');
const ler = (p) => fs.readFileSync(path.resolve(RAIZ, p), 'utf8');

const db = new PGlite({ extensions: { pgcrypto } });
let falhas = 0, ok = 0;
const checar = (cond, nome, extra = '') => {
  if (cond) { ok++; console.log('  ✔', nome); }
  else { falhas++; console.log('  ✘', nome, extra); }
};

// Executa SQL "como" alguém, do jeito que o PostgREST faz: papel + claims + headers
async function como(quem, sql, params = [], headers = {}) {
  const claims = quem === 'anon' ? { role: 'anon' }
    : quem === 'service' ? { role: 'service_role' }
    : { role: 'authenticated', sub: quem.id, email: quem.email };
  const role = quem === 'anon' ? 'anon' : quem === 'service' ? 'service_role' : 'authenticated';
  return db.transaction(async (tx) => {
    await tx.query(`select set_config('request.jwt.claims', $1, true), set_config('request.headers', $2, true)`,
      [JSON.stringify(claims), JSON.stringify(headers)]);
    await tx.query(`set local role ${role}`);
    return (await tx.query(sql, params)).rows;
  });
}
async function falha(quem, sql, params = [], headers = {}) {
  try { await como(quem, sql, params, headers); return null; }
  catch (e) { return e.message; }
}

// ---------------------------------------------------------------- base
console.log('\n# carga: stub Supabase + schema hub de produção');
await db.exec(ler('tests/multi-empresa/fixtures/supabase_stub.sql'));
await db.exec(ler('tests/multi-empresa/fixtures/hub_schema_prod_2026-10-07.sql'));

// usuários fictícios (o e-mail dela é o único real, e já está no repo desde a 001)
const LU  = { id: '00000000-0000-4000-8000-00000000000a', email: 'lucianapandolfo9@gmail.com' };
const ISA = { id: '00000000-0000-4000-8000-00000000000b', email: 'isa@exemplo.test' };
const BIA = { id: '00000000-0000-4000-8000-00000000000c', email: 'dona@padaria.test' };   // dono ws2
const OPE = { id: '00000000-0000-4000-8000-00000000000d', email: 'operador@padaria.test' };
const CON = { id: '00000000-0000-4000-8000-00000000000e', email: 'consulta@padaria.test' };
const CTB = { id: '00000000-0000-4000-8000-00000000000f', email: 'contador@escritorio.test' };
const EXT = { id: '00000000-0000-4000-8000-000000000010', email: 'quarto@padaria.test' };
const INT = { id: '00000000-0000-4000-8000-000000000011', email: 'intruso@qualquer.test' };
for (const u of [LU, ISA, BIA, OPE, CON, CTB, EXT, INT]) {
  await db.query('insert into auth.users (id, email) values ($1, $2)', [u.id, u.email]);
}

// "produção" de mentira: workspace 1 com dado fictício
await db.exec(`
  insert into hub.workspaces (nome, slug) values ('Luh Panda', 'luhpanda');
  insert into hub.empresas (nome, cnpj, tipo) values ('Luh Panda', '11.222.333/0001-81', 'mei');
  insert into hub.clientes (empresa_id, slug, nome) select id, 'acme', 'Cliente Acme' from hub.empresas;
  insert into hub.clientes (empresa_id, slug, nome) select id, 'beta', 'Cliente Beta' from hub.empresas;
  insert into hub.contatos (cliente_id, nome, whatsapp_e164) select id, 'Fulano', '+5581999990000' from hub.clientes where slug='acme';
  insert into hub.contratos (cliente_id, status, valor_mensal_centavos, dia_vencimento) select id, 'rascunho', 100000, 10 from hub.clientes where slug='acme';
  insert into hub.recebiveis (cliente_id, competencia, descricao, valor_centavos) select id, '2026-10-01', 'Mensalidade', 100000 from hub.clientes where slug='acme';
  insert into hub.custos_fixos (nome, categoria, valor_centavos) values ('Ferramenta X', 'negocio', 5000);
  insert into hub.prospects (nome, contato_whatsapp) values ('Prospect Um', '+5581999990001');
  insert into hub.conversas (fone_norm, nome_exibicao) values ('558199990000', 'Fulano');
  insert into hub.mensagens (conversa_id, direcao, corpo, evolution_msg_id) select id, 'entrada', 'oi', 'MSG1' from hub.conversas;
  insert into hub.config (chave, valor_hash) values ('bot_secret', encode(extensions.digest('segredo-ws1', 'sha256'), 'hex'));
  insert into storage.objects (bucket_id, name) values ('contratos', 'acme/contrato.pdf');
`);
const contar = async (t) => (await db.query(`select count(*)::int n from hub.${t}`)).rows[0].n;
const antes = {};
for (const t of ['clientes', 'contatos', 'contratos', 'recebiveis', 'custos_fixos', 'prospects', 'conversas', 'mensagens']) antes[t] = await contar(t);

console.log('\n# sanidade do baseline (antes da 050): ela lê, intruso não');
checar((await como(LU, 'select * from public.hub_rpc_carteira()')).length === 2, 'Luciana vê 2 clientes');
checar(!!(await falha(INT, 'select * from public.hub_rpc_carteira()')), 'intruso logado é barrado (e-mail chumbado)');
// ACHADO pré-existente (produção, 07/10): anon sem USAGE no schema hub + wrapper
// public.hub_bot_* SECURITY INVOKER = o bot de cobrança com chave anon falha hoje.
const botAntes = await falha('anon', `select * from public.hub_bot_cobrancas_do_dia('segredo-ws1')`);
checar(!!botAntes && botAntes.includes('schema hub'), 'ACHADO: hoje o bot com chave anon leva "permission denied for schema hub"', botAntes);

// ---------------------------------------------------------------- migrations
console.log('\n# aplicando 050 → 051 → 052');
for (const m of ['050_multiempresa_base', '051_multiempresa_workspace_id', '052_multiempresa_virada']) {
  try { await db.exec(ler(`migrations/${m}.sql`)); checar(true, `${m} aplicou`); }
  catch (e) { checar(false, `${m} aplicou`, e.message); process.exit(1); }
}
const WS1 = (await db.query(`select id from hub.workspaces where slug='luhpanda'`)).rows[0].id;

console.log('\n# backfill: nada sumiu, tudo é do workspace 1');
for (const t of Object.keys(antes)) {
  const r = (await db.query(`select count(*)::int n, count(*) filter (where workspace_id = $1)::int ws1 from hub.${t}`, [WS1])).rows[0];
  checar(r.n === antes[t] && r.ws1 === r.n, `${t}: ${r.n} linha(s), todas no workspace 1`);
}
checar((await db.query(`alter table hub.empresas validate constraint empresas_cnpj_valido`)) && true, 'CNPJ dela (com pontuação) passa na validação nova');

console.log('\n# CNPJ (numérico e alfanumérico IN RFB 2.229/2024)');
const cnpj = async (c) => (await db.query('select hub.cnpj_valido($1) v', [c])).rows[0].v;
checar(await cnpj('00.000.000/0001-91'), 'numérico válido (Banco do Brasil)');
checar(!(await cnpj('00.000.000/0001-92')), 'numérico com DV errado é recusado');
checar(await cnpj('12.ABC.345/01DE-35'), 'alfanumérico do exemplo da Receita é aceito');
checar(!(await cnpj('12.ABC.345/01DE-36')), 'alfanumérico com DV errado é recusado');
checar(!(await cnpj('11.111.111/1111-11')), 'repetido é recusado');

console.log('\n# a Luciana continua igual depois da virada');
checar((await como(LU, 'select * from public.hub_rpc_carteira()')).length === 2, 'carteira dela: 2 clientes, sem header');
checar((await como(LU, `select public.hub_rpc_cliente('acme') c`))[0].c?.cliente?.nome === 'Cliente Acme' ||
       JSON.stringify((await como(LU, `select public.hub_rpc_cliente('acme') c`))[0].c).includes('Cliente Acme'), 'ficha do cliente abre');
const novoRec = await como(LU, `select public.hub_rpc_salvar_recebivel($1::jsonb) id`,
  [JSON.stringify({ cliente_id: (await db.query(`select id from hub.clientes where slug='beta'`)).rows[0].id, competencia: '2026-11-05', descricao: 'Extra', valor_centavos: 5000, origem: 'extra' })]);
checar((await db.query('select workspace_id from hub.recebiveis where id=$1', [novoRec[0].id])).rows[0].workspace_id === WS1, 'recebível novo dela nasce no workspace 1 (default)');
checar((await como(LU, 'select * from public.hub_rpc_meus_workspaces()')).length === 1, 'ela é membro de 1 workspace');

console.log('\n# convite: Luciana (admin da plataforma) cria o workspace 2 e convida a dona');
const criado = (await como(LU, `select public.hub_rpc_plataforma_criar_workspace($1::jsonb) r`,
  [JSON.stringify({ nome: 'Padaria Fictícia', email_dono: BIA.email, modulos: ['financeiro', 'clientes_cobranca'] })]))[0].r;
const WS2 = criado.workspace_id;
checar(!!WS2 && !!criado.token, 'workspace 2 criado + token de convite');
checar(!!(await falha(INT, `select public.hub_rpc_plataforma_criar_workspace('{"nome":"x","email_dono":"a@b.c"}'::jsonb)`)), 'não-admin não cria workspace');
checar(!!(await falha(INT, `select public.hub_rpc_aceitar_convite($1)`, [criado.token])), 'convite não serve pra outro e-mail');
checar((await como(BIA, `select public.hub_rpc_aceitar_convite($1) w`, [criado.token]))[0].w === WS2, 'dona aceita e entra no workspace 2');
checar(!!(await falha(BIA, `select public.hub_rpc_aceitar_convite($1)`, [criado.token])), 'convite não reaproveita');
checar((await db.query(`select count(*)::int n from hub.convites where token_hash = $1`, [criado.token])).rows[0].n === 0, 'token em claro não fica no banco');

console.log('\n# vagas: 3 usuários + contador não ocupa vaga');
const convidar = async (email, papel, eh_contador = false) =>
  (await como(BIA, `select public.hub_rpc_criar_convite($1::jsonb) r`, [JSON.stringify({ email, papel, eh_contador })]))[0].r.token;
const tOpe = await convidar(OPE.email, 'operador');
const tCon = await convidar(CON.email, 'consulta');
const tCtb = await convidar(CTB.email, 'consulta', true);
const tExt = await convidar(EXT.email, 'operador');
await como(OPE, 'select public.hub_rpc_aceitar_convite($1)', [tOpe]);
await como(CON, 'select public.hub_rpc_aceitar_convite($1)', [tCon]);
checar(!(await falha(CTB, 'select public.hub_rpc_aceitar_convite($1)', [tCtb])), 'contador entra com 3 vagas já ocupadas');
const semVaga = await falha(EXT, 'select public.hub_rpc_aceitar_convite($1)', [tExt]);
checar(!!semVaga && semVaga.includes('sem vaga'), '4º usuário (não contador) é recusado', semVaga);
checar(!!(await falha(OPE, `select public.hub_rpc_criar_convite('{"email":"x@y.z","papel":"dono"}'::jsonb)`)), 'operador não convida');
checar(!!(await falha(BIA, `select public.hub_rpc_alterar_membro($1::jsonb)`, [JSON.stringify({ id: (await db.query('select id from hub.workspace_membros where user_id=$1', [BIA.id])).rows[0].id, ativo: false })])), 'último dono não se remove');

console.log('\n# onboarding fiscal do workspace 2');
const empId = (await como(BIA, `select public.hub_rpc_onboarding_salvar_empresa($1::jsonb) id`, [JSON.stringify({
  cnpj: '12.ABC.345/01DE-35', razao_social: 'Padaria Fictícia Ltda', simples_optante: true, simei_optante: false,
  regime_sugerido: 'simples', regime_sugerido_fonte: 'brasilapi', receita_fonte: 'brasilapi',
  socios: [{ nome: 'Dona Fictícia', qualificacao: 'Sócio-Administrador', cpf: '***123***' }] })]))[0].id;
checar(!!empId, 'empresa criada a partir da consulta');
checar(!JSON.stringify((await db.query('select socios from hub.empresas where id=$1', [empId])).rows[0].socios).includes('cpf'), 'CPF de sócio não é gravado');
checar(!!(await falha(BIA, `select public.hub_rpc_onboarding_salvar_empresa('{"cnpj":"12.ABC.345/01DE-99"}'::jsonb)`)), 'CNPJ inválido é recusado');
checar(!!(await falha(OPE, `select public.hub_rpc_onboarding_confirmar_regime($1::jsonb)`, [JSON.stringify({ empresa_id: empId, regime: 'simples' })])), 'operador não confirma regime');
await como(BIA, `select public.hub_rpc_onboarding_confirmar_regime($1::jsonb)`, [JSON.stringify({ empresa_id: empId, regime: 'simples', faixa_faturamento: '81k_360k' })]);
checar((await db.query('select regime, regime_confirmado_por from hub.empresas where id=$1', [empId])).rows[0].regime_confirmado_por === BIA.id, 'regime confirmado pela dona, com autor');
await como(CON, 'select * from public.hub_rpc_perfil_fiscal()');
checar((await db.query(`select count(*)::int n from hub.acessos_sensiveis where workspace_id=$1 and user_id=$2`, [WS2, CON.id])).rows[0].n === 1, 'leitura do perfil fiscal deixa rastro (LGPD)');
checar(!(await falha(BIA, `select public.hub_rpc_aceitar_termos('{"documento":"termos_de_uso","versao":"2026-10"}'::jsonb)`)), 'aceite de termos registrado');

console.log('\n# ISOLAMENTO — o workspace 2 não enxerga nem mexe no 1');
await como(BIA, `select public.hub_rpc_salvar_cliente($1::jsonb)`, [JSON.stringify({ empresa_id: empId, slug: 'acme', nome: 'Acme da Padaria' })]);
checar(true, 'slug "acme" pode existir nos 2 workspaces');
const cartB = await como(BIA, 'select * from public.hub_rpc_carteira()');
checar(cartB.length === 1 && cartB[0].nome === 'Acme da Padaria', 'carteira do ws2 mostra só o cliente dele');
checar((await como(LU, 'select * from public.hub_rpc_carteira()')).length === 2, 'carteira do ws1 continua com 2');
checar(!JSON.stringify(await como(BIA, `select public.hub_rpc_cliente('beta') c`)).includes('Cliente Beta'), 'ws2 não abre a ficha de cliente do ws1 por slug');
checar((await como(BIA, `select * from public.hub_rpc_recebiveis('2026-10-01')`)).length === 0, 'ws2 não vê recebíveis do ws1');
const dashB = JSON.stringify(await como(BIA, 'select public.hub_rpc_dash() d'));
checar(!dashB.includes('Cliente Acme') && !dashB.includes('100000'), 'dash do ws2 não soma dinheiro do ws1');
checar((await como(BIA, 'select * from public.hub_rpc_custos()')).length === 0, 'custos do ws1 invisíveis pro ws2');
checar((await como(BIA, 'select * from public.hub_rpc_prospects()')).length === 0, 'CRM do ws1 invisível pro ws2');
checar((await como(BIA, 'select * from public.hub_rpc_conversas_resumo()')).length === 0, 'conversas do ws1 invisíveis pro ws2');

const idAcmeWs1 = (await db.query(`select id from hub.clientes where slug='acme' and workspace_id=$1`, [WS1])).rows[0].id;
const idRecWs1 = (await db.query(`select id from hub.recebiveis where workspace_id=$1 limit 1`, [WS1])).rows[0].id;
checar(!!(await falha(BIA, `select public.hub_rpc_salvar_cliente($1::jsonb)`, [JSON.stringify({ id: idAcmeWs1, empresa_id: empId, slug: 'roubado', nome: 'Sobrescrito' })])), 'ws2 não sobrescreve cliente do ws1 pelo id');
checar((await db.query('select nome from hub.clientes where id=$1', [idAcmeWs1])).rows[0].nome === 'Cliente Acme', '…e o cliente do ws1 ficou intacto');
checar(!!(await falha(BIA, `select public.hub_rpc_salvar_recebivel($1::jsonb)`, [JSON.stringify({ cliente_id: idAcmeWs1, competencia: '2026-10-01', descricao: 'x', valor_centavos: 1 })])), 'ws2 não cria recebível pendurado em cliente do ws1 (FK composta)');
checar(!!(await falha(BIA, 'select public.hub_rpc_apagar_recebivel($1)', [idRecWs1])), 'ws2 não apaga recebível do ws1');
checar(!!(await falha(BIA, 'select public.hub_rpc_marcar_pago($1, 1, current_date)', [idRecWs1])) ||
       (await db.query('select entrada_centavos from hub.recebiveis where id=$1', [idRecWs1])).rows[0].entrada_centavos === '0' ||
       Number((await db.query('select entrada_centavos from hub.recebiveis where id=$1', [idRecWs1])).rows[0].entrada_centavos) === 0, 'ws2 não marca pago recebível do ws1');
checar((await db.query('select count(*)::int n from hub.recebiveis where workspace_id=$1', [WS1])).rows[0].n === antes.recebiveis + 1, 'recebíveis do ws1 intactos');

console.log('\n# header x-workspace-id não fura');
checar(!!(await falha(BIA, 'select * from public.hub_rpc_carteira()', [], { 'x-workspace-id': WS1 })), 'dona do ws2 mandando header do ws1 é barrada');
checar(!!(await falha(INT, 'select * from public.hub_rpc_carteira()', [], { 'x-workspace-id': WS1 })), 'intruso sem workspace mandando header do ws1 é barrado');
checar(!!(await falha(INT, 'select * from public.hub_rpc_carteira()')), 'intruso sem header é barrado');
checar(!!(await falha('anon', 'select * from public.hub_rpc_carteira()')), 'anon é barrado');
checar(!!(await falha(BIA, 'select * from public.hub_rpc_carteira()', [], { 'x-workspace-id': 'lixo' })), 'header inválido é barrado');

console.log('\n# papéis dentro do ws2');
checar((await como(CON, 'select * from public.hub_rpc_carteira()')).length === 1, 'Consulta lê');
checar(!!(await falha(CON, `select public.hub_rpc_salvar_cliente($1::jsonb)`, [JSON.stringify({ empresa_id: empId, slug: 'novo', nome: 'Novo' })])), 'Consulta não cria');
const idAcmeWs2 = (await db.query(`select id from hub.clientes where slug='acme' and workspace_id=$1`, [WS2])).rows[0].id;
await falha(CON, `select public.hub_rpc_salvar_cliente($1::jsonb)`, [JSON.stringify({ id: idAcmeWs2, empresa_id: empId, slug: 'acme', nome: 'Alterado pela consulta' })]);
checar((await db.query('select nome from hub.clientes where id=$1', [idAcmeWs2])).rows[0].nome === 'Acme da Padaria', 'Consulta não altera');
checar((await como(CTB, 'select * from public.hub_rpc_carteira()')).length === 1, 'contador (Consulta) lê');
checar(!(await falha(OPE, `select public.hub_rpc_salvar_cliente($1::jsonb)`, [JSON.stringify({ empresa_id: empId, slug: 'op', nome: 'Do operador' })])), 'Operador cria');
const membros = await como(BIA, 'select * from public.hub_rpc_membros()');
checar(membros.length === 4, 'dona vê os 4 membros', JSON.stringify(membros));
checar((await como(CON, 'select * from public.hub_rpc_membros()')).length === 0, 'Consulta não lista membros');
checar(!!(await falha(CON, 'select count(*) from hub.eventos_auditoria')), 'auditoria não é exposta direto (RPC-only)');

console.log('\n# automações (service_role / segredo do bot)');
await db.query(`insert into hub.workspace_canais (workspace_id, tipo, identificador) values ($1, 'evolution_instancia', 'PadariaZap')`, [WS2]);
await db.query(`insert into hub.contatos (cliente_id, nome, whatsapp_e164, workspace_id) values ($1, 'Mesmo fone', '+5581999990000', $2)`, [idAcmeWs2, WS2]);
const msg = (inst, id) => JSON.stringify({ fone: '+5581999990000', corpo: 'olá ' + inst, evolution_msg_id: id, instancia: inst });
const c1 = (await como('service', `select public.hub_rpc_registrar_mensagem($1::jsonb) c`, [msg('LuhPessoal', 'A1')]))[0].c;
const c2 = (await como('service', `select public.hub_rpc_registrar_mensagem($1::jsonb) c`, [msg('PadariaZap', 'B1')]))[0].c;
const wsDe = async (id) => (await db.query('select workspace_id from hub.conversas where id=$1', [id])).rows[0]?.workspace_id;
checar(await wsDe(c1) === WS1 && await wsDe(c2) === WS2, 'mesmo telefone vira 2 conversas, uma em cada workspace, pela instância');
checar(!!(await falha('service', `select public.hub_rpc_registrar_mensagem($1::jsonb)`, [msg('InstanciaDesconhecida', 'X1')])), 'instância desconhecida é recusada (não cai em workspace errado)');
const semInst = (await como('service', `select public.hub_rpc_registrar_mensagem($1::jsonb) c`, [JSON.stringify({ fone: '+5581999990000', corpo: 'legado', evolution_msg_id: 'L1' })]))[0].c;
checar(await wsDe(semInst) === WS1, 'n8n de hoje (sem instância) continua caindo no ws1 — compat da etapa 3');
// (antes da chamada do service_role: o plano em cache da função SQL pularia a checagem de schema)
checar(!!(await falha('anon', `select * from public.hub_bot_cobrancas_do_dia('segredo-ws1')`)), 'anon continua sem USAGE no schema hub (guarda mantida)');
const botOk = await falha('service', `select * from public.hub_bot_cobrancas_do_dia('segredo-ws1')`);
checar(!botOk, 'bot com segredo do ws1 roda (porta service_role)', botOk);
checar(!!(await falha('service', `select * from public.hub_bot_cobrancas_do_dia('segredo-errado')`)), 'bot com segredo errado é barrado');

console.log('\n# Storage (bucket contratos)');
await db.query(`insert into storage.objects (bucket_id, name) values ('contratos', $1)`, [`${WS2}/acme/contrato.pdf`]);
const objs = async (u) => (await como(u, `select name from storage.objects where bucket_id='contratos' order by name`)).map((r) => r.name);
checar(JSON.stringify(await objs(LU)) === JSON.stringify(['acme/contrato.pdf']), 'ws1 vê só o PDF legado dele');
checar(JSON.stringify(await objs(BIA)) === JSON.stringify([`${WS2}/acme/contrato.pdf`]), 'ws2 vê só o PDF dele');
checar(!!(await falha(BIA, `insert into storage.objects (bucket_id, name) values ('contratos', $1)`, [`${WS1}/x.pdf`])), 'ws2 não sobe arquivo na pasta do ws1');
checar(!!(await falha(CON, `insert into storage.objects (bucket_id, name) values ('contratos', $1)`, [`${WS2}/y.pdf`])), 'Consulta não sobe arquivo');

console.log('\n# acesso direto às tabelas (sem RPC) continua fechado');
checar(!!(await falha(BIA, 'select * from hub.clientes')), 'authenticated não lê hub.clientes direto');
checar(!!(await falha('anon', 'select * from hub.workspace_membros')), 'anon não lê membros');

console.log('\n# rollback 052 → 051 → 050 (na volta, o Hub dela tem que funcionar)');
checar(!!(await db.exec(ler('migrations/rollback/052_down.sql')).catch((e) => e.message)), '052_down recusa enquanto existe dado do ws2');
await db.query(`delete from storage.objects where name like $1`, [`${WS2}/%`]);
for (const t of ['clientes', 'conversas', 'prospects', 'empresas']) await db.query(`delete from hub.${t} where workspace_id = $1`, [WS2]);
for (const m of ['052_down', '051_down', '050_down']) {
  try { await db.exec(ler(`migrations/rollback/${m}.sql`)); checar(true, `${m} aplicou`); }
  catch (e) { checar(false, `${m} aplicou`, e.message); }
}
checar((await como(LU, 'select * from public.hub_rpc_carteira()')).length === 2, 'depois do rollback ela vê a carteira dela');
checar(!!(await falha(INT, 'select * from public.hub_rpc_carteira()')), 'depois do rollback intruso continua barrado');
checar((await db.query(`select count(*)::int n from hub.workspaces`)).rows[0].n === 1, 'rollback remove workspaces de teste');
checar(await contar('recebiveis') === antes.recebiveis + 1, 'rollback não perde dado do ws1');

console.log(`\n${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
