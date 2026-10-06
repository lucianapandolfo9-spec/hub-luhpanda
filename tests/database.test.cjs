const { test } = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { database, rpc, snapshot, setup, move } = require("./fixture.cjs");
const W = "10000000-0000-0000-0000-000000000001",
  OTHER = "10000000-0000-0000-0000-000000000002";
test("Estoque: transações, custo, lotes, idempotência, compra parcial e inventário", async () => {
  const db = await database();
  try {
    const { product, location } = await setup(db);
    const payload = {
      id: randomUUID(),
      product_id: product,
      location_id: location,
      quantity: 10,
      type: "entry",
      unit_cost_centavos: 100,
      reason: "NF 1",
    };
    await rpc(db, "hub_rpc_stock_move", payload);
    await rpc(db, "hub_rpc_stock_move", payload);
    await assert.rejects(
      rpc(db, "hub_rpc_stock_move", { ...payload, quantity: 11 }),
      /outros dados/,
    );
    await move(db, {
      product_id: product,
      location_id: location,
      quantity: 10,
      unit_cost_centavos: 300,
    });
    let s = await snapshot(db);
    let b = s.positions[0];
    assert.equal(Number(b.quantity), 20);
    assert.equal(b.unit_cost_centavos, 200);
    assert.equal(s.movements.length, 2);
    await assert.rejects(
      move(db, {
        type: "sale",
        product_id: product,
        position_id: b.id,
        quantity: 21,
      }),
      /insuficiente/,
    );
    await move(db, {
      type: "sale",
      product_id: product,
      position_id: b.id,
      quantity: 5,
      revenue_centavos: 2000,
    });
    await assert.rejects(
      move(db, {
        type: "count",
        product_id: product,
        position_id: b.id,
        quantity: 10,
        expected_quantity: 20,
      }),
      /Saldo mudou/,
    );
    await move(db, {
      type: "count",
      product_id: product,
      position_id: b.id,
      quantity: 0,
      expected_quantity: 15,
    });
    const dest = await rpc(db, "hub_rpc_stock_save", "location", {
      name: "Depósito",
      capacity_liters: 50,
    });
    await move(db, { product_id: product, location_id: location, quantity: 8 });
    await move(db, {
      type: "transfer",
      product_id: product,
      position_id: b.id,
      location_id: dest,
      quantity: 3,
    });
    s = await snapshot(db);
    assert.equal(Number(s.positions.find((x) => x.id === b.id).quantity), 5);
    assert.equal(
      Number(s.positions.find((x) => x.location_id === dest).quantity),
      3,
    );
    const order = await rpc(db, "hub_rpc_stock_order", {
      id: randomUUID(),
      product_id: product,
      location_id: dest,
      quantity: 10,
      supplier: "Fornecedor",
    });
    await move(db, { product_id: product, order_id: order, quantity: 4 });
    s = await snapshot(db);
    assert.equal(s.orders[0].status, "open");
    assert.equal(Number(s.orders[0].received_quantity), 4);
    await assert.rejects(
      move(db, { product_id: product, order_id: order, quantity: 7 }),
      /incompatível/,
    );
    await move(db, { product_id: product, order_id: order, quantity: 6 });
    s = await snapshot(db);
    assert.equal(s.orders[0].status, "received");
    await move(db, {
      product_id: product,
      location_id: location,
      lot: "Vencido",
      expires_on: "2020-01-01",
      quantity: 1,
    });
    s = await snapshot(db);
    const expired = s.positions.find((p) => p.lot === "Vencido");
    await assert.rejects(
      move(db, {
        type: "sale",
        product_id: product,
        position_id: expired.id,
        quantity: 1,
      }),
      /vencido/,
    );
    await move(db, {
      type: "loss",
      product_id: product,
      position_id: expired.id,
      quantity: 1,
    });
    await assert.rejects(
      move(db, {
        product_id: product,
        location_id: location,
        lot: "Vencido",
        expires_on: "2030-01-01",
        quantity: 1,
      }),
      /outra validade/,
    );
    await db.exec("reset role;");
    assert.ok(
      (await db.query("select count(*)::int n from hub.eventos_auditoria"))
        .rows[0].n > 20,
    );
  } finally {
    await db.close();
  }
});
test("Estoque: capacidade compartilhada, reservas, limites e acesso", async () => {
  const db = await database();
  try {
    const { product, location } = await setup(db, 10, 20);
    await move(db, { product_id: product, location_id: location, quantity: 8 });
    await assert.rejects(
      move(db, { product_id: product, location_id: location, quantity: 3 }),
      /Capacidade/,
    );
    const order = await rpc(db, "hub_rpc_stock_order", {
      product_id: product,
      location_id: location,
      quantity: 2,
      supplier: "F",
    });
    await assert.rejects(
      rpc(db, "hub_rpc_stock_order", {
        product_id: product,
        location_id: location,
        quantity: 1,
        supplier: "F",
      }),
      /reservada/,
    );
    await rpc(db, "hub_rpc_stock_order", { id: order, status: "cancelled" });
    await assert.rejects(
      rpc(db, "hub_rpc_stock_save", "location", {
        id: location,
        name: "Loja",
        capacity_liters: 7,
      }),
      /Capacidade/,
    );
    await assert.rejects(
      rpc(db, "hub_rpc_stock_save", "location", {
        name: "Inválido",
        capacity_liters: "NaN",
      }),
    );
    await assert.rejects(
      rpc(db, "hub_rpc_stock_save", "product", {
        sku: "FORA",
        name: "Fora",
        unit: "un",
        minimum_quantity: 0,
        target_quantity: 1,
        pack_quantity: 1,
        preferred_location_id: OTHER,
      }),
    );
    await db.exec(
      `select set_config('test.email','outra@example.invalid',false);`,
    );
    await assert.rejects(snapshot(db), /Acesso negado/);
    await db.exec(
      `select set_config('test.email','lucianapandolfo9@gmail.com',false),set_config('test.uid','',false);`,
    );
    await assert.rejects(snapshot(db), /Acesso negado/);
    await db.exec(`reset role;set role anon;`);
    await assert.rejects(snapshot(db), /permission denied/);
    await db.exec(`reset role;set role authenticated;`);
    await assert.rejects(
      db.query("select * from hub.stock_positions"),
      /permission denied/,
    );
    await assert.rejects(
      db.query(`select hub.stock_capacity('${W}','${location}',0,1)`),
      /permission denied/,
    );
  } finally {
    await db.close();
  }
});
const inputs = {
  revenue_centavos: 1000000,
  variable_centavos: 200000,
  fixed_centavos: 100000,
  payroll_centavos: 100000,
  rate_percent: 10,
  extra_tax_centavos: 0,
  credits_centavos: 0,
};
test("Contator: premissas, elegibilidade, competência, revisão e evidência", async () => {
  const db = await database();
  try {
    const data = {
      name: "Base",
      regime: "Simples Nacional",
      eligibility: "pending",
      inputs,
      assumptions: "Memória revisável",
      source_url: "https://www.gov.br/receitafederal",
      valid_on: "2026-10-01",
    };
    const id = await rpc(
      db,
      "hub_rpc_advisory_save",
      "scenario",
      data,
      null,
      null,
    );
    await assert.rejects(
      rpc(
        db,
        "hub_rpc_advisory_save",
        "scenario",
        { ...data, eligibility: "confirmed" },
        id,
        1,
      ),
      /revisor/,
    );
    await rpc(
      db,
      "hub_rpc_advisory_save",
      "scenario",
      {
        ...data,
        eligibility: "confirmed",
        reviewed_by: "Contador teste",
        review_note: "CNAE e limites conferidos",
      },
      id,
      1,
    );
    await assert.rejects(
      rpc(db, "hub_rpc_advisory_save", "scenario", data, id, 1),
      /Registro mudou/,
    );
    await assert.rejects(
      rpc(
        db,
        "hub_rpc_advisory_save",
        "scenario",
        { ...data, inputs: { ...inputs, rate_percent: 101 } },
        null,
        null,
      ),
      /Premissa inválida/,
    );
    await assert.rejects(
      rpc(
        db,
        "hub_rpc_advisory_save",
        "scenario",
        { ...data, source_url: "javascript:alert(1)" },
        null,
        null,
      ),
      /HTTPS/,
    );
    await rpc(
      db,
      "hub_rpc_advisory_save",
      "period",
      { ...data, competence: "2026-10" },
      null,
      null,
    );
    await assert.rejects(
      rpc(
        db,
        "hub_rpc_advisory_save",
        "period",
        { ...data, competence: "2026-10" },
        null,
        null,
      ),
      /já cadastrada/,
    );
    await assert.rejects(
      rpc(
        db,
        "hub_rpc_advisory_save",
        "action",
        {
          title: "DAS",
          owner: "Contador",
          due_on: "2026-10-20",
          status: "done",
        },
        null,
        null,
      ),
      /evidência/,
    );
    await rpc(
      db,
      "hub_rpc_advisory_save",
      "action",
      {
        title: "DAS",
        owner: "Contador",
        due_on: "2026-10-20",
        status: "done",
        evidence: "Protocolo teste",
      },
      null,
      null,
    );
    assert.equal((await snapshot(db)).advisory.length, 3);
  } finally {
    await db.close();
  }
});
test("Transferência e edição com erro fazem rollback; saídas simultâneas não excedem saldo", async () => {
  const db = await database();
  try {
    const { product, location } = await setup(db, 100, 10);
    await move(db, { product_id: product, location_id: location, quantity: 5 });
    const dest = await rpc(db, "hub_rpc_stock_save", "location", {
      name: "Pequeno",
      capacity_liters: 1,
    });
    let before = await snapshot(db),
      b = before.positions[0];
    await assert.rejects(
      move(db, {
        type: "transfer",
        product_id: product,
        position_id: b.id,
        location_id: dest,
        quantity: 2,
      }),
      /Capacidade/,
    );
    let after = await snapshot(db);
    assert.deepEqual(after.positions, before.positions);
    assert.equal(after.movements.length, before.movements.length);
    const p = before.products[0];
    await assert.rejects(
      rpc(db, "hub_rpc_stock_save", "product", { ...p, active: false }),
      /possui saldo/,
    );
    after = await snapshot(db);
    assert.equal(after.products[0].active, true);
    const results = await Promise.allSettled([
      move(db, {
        type: "sale",
        product_id: product,
        position_id: b.id,
        quantity: 4,
      }),
      move(db, {
        type: "sale",
        product_id: product,
        position_id: b.id,
        quantity: 4,
      }),
    ]);
    assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
    assert.equal(Number((await snapshot(db)).positions[0].quantity), 1);
    // PGlite serializa a conexão; lock transacional deve também ser validado em homologação com duas sessões.
  } finally {
    await db.close();
  }
});
test("Contator aceita CNPJ numérico e alfanumérico, preservando revisão do cadastro", async () => {
  const db = await database();
  try {
    const id = await rpc(
      db,
      "hub_rpc_advisory_save",
      "profile",
      { name: "Empresa teste", cnpj: "00000000E08G12" },
      null,
      null,
    );
    await rpc(
      db,
      "hub_rpc_advisory_save",
      "profile",
      { name: "Empresa teste", cnpj: "00000000000191" },
      id,
      1,
    );
    await assert.rejects(
      rpc(
        db,
        "hub_rpc_advisory_save",
        "profile",
        { name: "Erro", cnpj: "00000000E08GAA" },
        id,
        2,
      ),
      /CNPJ/,
    );
  } finally {
    await db.close();
  }
});
