const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { PGlite } = require("@electric-sql/pglite");
const { randomUUID } = require("node:crypto");
const files = [
  "migrations/20261006052445_estoque_contator_estrategico.sql",
  "migrations/20261007204101_estoque_unidade_historico.sql",
];
const W = "10000000-0000-0000-0000-000000000001",
  OTHER = "10000000-0000-0000-0000-000000000002";
async function database({ install = true } = {}) {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create schema auth; create schema hub;
 create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
 create function auth.email() returns text language sql as $$ select current_setting('test.email',true) $$;
 grant usage on schema auth,hub to authenticated,anon;
 create function hub.is_admin() returns boolean language sql as $$ select coalesce(auth.email(),'')='lucianapandolfo9@gmail.com' $$;
 create table hub.workspaces(id uuid primary key,slug text);
 insert into hub.workspaces values('${W}','luhpanda'),('${OTHER}','other');
 create function hub.default_workspace_id() returns uuid language sql as $$ select '${W}'::uuid $$;`);
  // Usa o trigger de auditoria real da base, sem copiar dados de produção.
  const security = fs.readFileSync(
    "migrations/001_schema_seguranca_auditoria.sql",
    "utf8",
  );
  await db.exec(
    security.slice(security.indexOf("-- ---------- auditoria ----------")),
  );
  if (install) for (const file of files) await db.exec(fs.readFileSync(file, "utf8"));
  await db.exec(
    `select set_config('test.uid','${randomUUID()}',false),set_config('test.email','lucianapandolfo9@gmail.com',false);set role authenticated;`,
  );
  return db;
}
async function rpc(db, name, ...args) {
  const binds = args.map((a, i) => `$${i + 1}`).join(",");
  return (
    await db.query(
      `select public.${name}(${binds}) as result`,
      args.map((a) =>
        typeof a === "object" && a !== null ? JSON.stringify(a) : a,
      ),
    )
  ).rows[0].result;
}
const snapshot = (db) => rpc(db, "hub_rpc_modules_snapshot");
const move = (db, data) =>
  rpc(db, "hub_rpc_stock_move", {
    id: randomUUID(),
    type: "entry",
    quantity: 1,
    unit_cost_centavos: 100,
    revenue_centavos: 0,
    reason: "Teste",
    ...data,
  });
async function setup(db, cap = 100, max = 100) {
  const location = await rpc(db, "hub_rpc_stock_save", "location", {
    name: "Loja",
    capacity_liters: cap,
  });
  const product = await rpc(db, "hub_rpc_stock_save", "product", {
    sku: "SKU1",
    name: "Mercadoria",
    unit: "un",
    minimum_quantity: 3,
    target_quantity: 10,
    maximum_quantity: max,
    pack_quantity: 1,
    volume_liters: 1,
    preferred_location_id: location,
  });
  return { product, location };
}

module.exports = { database, rpc, snapshot, setup, move };
