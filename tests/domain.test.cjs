const { test } = require("node:test");
const assert = require("node:assert/strict");
const D = require("../modules/domain.js");
test("Reposição desconta compras, arredonda embalagem e respeita limite físico", () => {
  assert.deepEqual(
    D.replenishment({
      stock: 2,
      minimum: 3,
      target: 10,
      incoming: 2,
      maximum: 12,
      pack: 3,
    }),
    { quantity: 6, unmet: 0, limited: false },
  );
  assert.deepEqual(
    D.replenishment({
      stock: 2,
      minimum: 3,
      target: 10,
      incoming: 0,
      maximum: 10,
      pack: 3,
    }),
    { quantity: 6, unmet: 2, limited: true },
  );
  assert.equal(
    D.replenishment({ stock: 4, minimum: 3, target: 10 }).quantity,
    0,
  );
  assert.equal(
    D.replenishment({
      stock: 0,
      minimum: 3,
      target: 10,
      unitVolume: 2,
      freeVolume: 5,
      pack: 1,
    }).quantity,
    2,
  );
});
test("Dois itens disputam a mesma capacidade sem duplicar espaço nem pedido", () => {
  const items = ["A", "B"].map((id) => ({
    id,
    sku: id,
    active: true,
    minimum_quantity: 2,
    target_quantity: 8,
    maximum_quantity: 20,
    pack_quantity: 1,
    volume_liters: 1,
    preferred_location_id: "L",
  }));
  const r = D.allocatePurchases(
    items,
    [],
    [{ id: "L", active: true, capacity_liters: 10 }],
    [
      {
        product_id: "A",
        location_id: "L",
        quantity: 2,
        received_quantity: 0,
        status: "open",
      },
    ],
  );
  assert.equal(r[0].quantity, 6);
  assert.equal(r[1].quantity, 2);
  assert.equal(r[1].unmet, 6);
  items[0].volume_liters = null;
  const blocked = D.allocatePurchases(
    items,
    [{ product_id: "A", location_id: "L", quantity: 1 }],
    [{ id: "L", active: true, capacity_liters: 10 }],
    [],
  );
  assert.equal(blocked[1].quantity, 0);
  assert.equal(blocked[1].unmet, 8);
});
test("ABC não atribui classe A a item sem giro; perdas não viram demanda de venda", () => {
  const a = D.abc([
    { id: "A", consumption: 85 },
    { id: "B", consumption: 10 },
    { id: "C", consumption: 5 },
    { id: "D", consumption: 0 },
  ]);
  assert.deepEqual(
    a.map((p) => p.classification),
    ["A", "B", "C", "Sem giro"],
  );
  const m = D.stockMetrics(
    [{ product_id: "P", quantity: 10, unit_cost_centavos: 200 }],
    [
      {
        product_id: "P",
        type: "loss",
        quantity: 3,
        cost_total_centavos: 600,
        created_at: "2026-10-01",
      },
    ],
    [{ id: "P" }],
    new Date("2026-10-06"),
  );
  assert.equal(m[0].inventory, 2000);
  assert.equal(m[0].demand, 0);
  assert.equal(m[0].loss, 600);
});
const base = {
  revenue_centavos: 1000000,
  variable_centavos: 200000,
  fixed_centavos: 100000,
  payroll_centavos: 100000,
  rate_percent: 10,
  extra_tax_centavos: 0,
  credits_centavos: 0,
};
test("Lucro, tributos, ponto de equilíbrio e comparação não recomendam inelegível", () => {
  const p = D.projection(base);
  assert.equal(p.tax, 100000);
  assert.equal(p.profit, 500000);
  assert.equal(p.margin, 50);
  assert.equal(p.breakEven, 285714);
  const c = D.compareScenarios([
    { name: "Base", eligibility: "confirmed", inputs: base },
    {
      name: "Impedido",
      eligibility: "blocked",
      inputs: { ...base, rate_percent: 0 },
    },
  ]);
  assert.equal(c.best.name, "Base");
  assert.equal(
    D.compareScenarios([{ eligibility: "pending", inputs: base }]).best,
    null,
  );
  assert.equal(D.projection({ ...base, revenue_centavos: 0 }).breakEven, null);
  assert.equal(D.factorR(0, 100), null);
  assert.equal(D.factorR(100000, 28000), 0.28);
  assert.throws(() => D.projection({ ...base, rate_percent: 101 }));
  assert.throws(() => D.money(NaN));
  assert.throws(() => D.money(1e20));
});
test("Ponto de equilíbrio trata outros tributos e créditos como valores fixos", () => {
  const p = D.projection({ ...base, extra_tax_centavos: 50000 });
  assert.equal(p.breakEven, 357143);
  const c = D.projection({ ...base, credits_centavos: 100000 });
  assert.equal(c.breakEven, 250000);
  assert.equal(
    D.projection({ ...base, variable_centavos: 950000 }).breakEven,
    null,
  );
});
