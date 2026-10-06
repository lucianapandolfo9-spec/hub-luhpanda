const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { database } = require("./fixture.cjs");
const preflight = fs.readFileSync(
  "migrations/_preflight_estoque_contator.sql",
  "utf8",
);
const verify = fs.readFileSync(
  "migrations/_verificacao_estoque_contator.sql",
  "utf8",
);
const migration = fs.readFileSync(
  "migrations/20261006052445_estoque_contator_estrategico.sql",
  "utf8",
);
test("Pacote de implantação detecta dependência ausente e instalação completa", async () => {
  const db = await database({ install: false });
  try {
    await db.exec("reset role;");
    let rows = (await db.query(preflight)).rows;
    assert.equal(rows.length, 28);
    assert.ok(rows.every((r) => r.ok));
    await db.exec("begin;drop function hub.default_workspace_id();");
    rows = (await db.query(preflight)).rows;
    assert.equal(
      rows.find((r) => r.verificacao === "hub.default_workspace_id()").ok,
      false,
    );
    await db.exec("rollback;");
    rows = (await db.query(verify)).rows;
    assert.equal(rows.length, 19);
    assert.ok(rows.every((r) => !r.ok));
    await db.exec(migration);
    rows = (await db.query(verify)).rows;
    assert.equal(rows.length, 19);
    assert.ok(rows.every((r) => r.ok));
    rows = (await db.query(preflight)).rows;
    assert.ok(
      rows.filter((r) => r.etapa === "objeto_novo_ausente").every((r) => !r.ok),
    );
    await db.exec(
      "begin;alter table hub.stock_products disable row level security;grant select on hub.stock_locations to authenticated;drop function public.hub_rpc_stock_order(jsonb);",
    );
    rows = (await db.query(verify)).rows;
    for (const name of [
      "hub.stock_products",
      "hub.stock_locations",
      "public.hub_rpc_stock_order(jsonb)",
    ])
      assert.equal(rows.find((r) => r.objeto === name).ok, false);
    await db.exec("rollback;");
    assert.ok((await db.query(verify)).rows.every((r) => r.ok));
  } finally {
    await db.close();
  }
});
