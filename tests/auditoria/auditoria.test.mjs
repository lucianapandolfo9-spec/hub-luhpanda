import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
const read = name => readFileSync(new URL('../../migrations/' + name, import.meta.url), 'utf8');

test('037 mantém triggers existentes e grava antes/depois de INSERT, UPDATE e DELETE', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create schema hub; create schema auth;
      create function auth.email() returns text language sql as $$ select 'teste@exemplo.test'::text $$;
      create function hub.is_admin() returns boolean language sql as $$ select true $$;`);
    const initial = read('001_schema_seguranca_auditoria.sql');
    await db.exec(initial.slice(initial.indexOf('-- ---------- auditoria ----------')));
    await db.exec(`create table hub.teste(id uuid primary key default gen_random_uuid(),valor bigint);
      create trigger auditar after insert or update or delete on hub.teste for each row execute function hub.registrar_auditoria();
      insert into hub.teste(valor) values(100);`);
    const old = (await db.query('select dados_antes,dados_depois from hub.eventos_auditoria')).rows[0];
    assert.deepEqual(old, { dados_antes: null, dados_depois: null }, 'reproduz bug original');
    await db.exec(read('037_auditoria_tg_op.sql'));
    await db.exec(`delete from hub.eventos_auditoria;
      insert into hub.teste(valor) values(200);
      update hub.teste set valor=250 where valor=200;
      delete from hub.teste where valor=250;`);
    const events = (await db.query('select acao,dados_antes,dados_depois,ator_email from hub.eventos_auditoria')).rows;
    assert.equal(events.length,3,'exatamente um evento por alteração');
    const insert = events.find(e=>e.acao==='insert');
    const update = events.find(e=>e.acao==='update');
    const deleted = events.find(e=>e.acao==='delete');
    assert.equal(insert.dados_antes,null);
    assert.equal(insert.dados_depois.valor,200);
    assert.equal(update.dados_antes.valor,200);
    assert.equal(update.dados_depois.valor,250);
    assert.equal(deleted.dados_antes.valor,250);
    assert.equal(deleted.dados_depois,null);
    assert.ok(events.every(e=>e.ator_email==='teste@exemplo.test'));
  } finally { await db.close(); }
});
