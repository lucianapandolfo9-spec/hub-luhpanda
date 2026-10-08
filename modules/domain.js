/* Regras gerenciais puras; sem alíquotas legais presumidas ou chamadas de rede. */
(function (scope) {
  "use strict";
  const number = (value, label = "Valor") => {
    if (value === "" || value == null || !Number.isFinite(Number(value)))
      throw Error(`${label} precisa ser informado.`);
    return Number(value);
  };
  const positive = (v, label, zero = true) => {
    const n = number(v, label);
    if (n < 0 || (!zero && n === 0))
      throw Error(
        `${label} deve ser ${zero ? "zero ou positivo" : "positivo"}.`,
      );
    return n;
  };
  const money = (value) => {
    const n = Math.round(number(value));
    if (!Number.isSafeInteger(n) || Math.abs(n) > 1000000000000)
      throw Error("Valor monetário fora do limite.");
    return n;
  };
  function replenishment({
    stock,
    minimum,
    target,
    incoming = 0,
    maximum = null,
    unitVolume = null,
    freeVolume = null,
    pack = 1,
  }) {
    [stock, minimum, target, incoming].forEach((x) =>
      positive(x, "Quantidade"),
    );
    positive(pack, "Embalagem", false);
    if (target < minimum)
      throw Error("O alvo deve ser maior ou igual ao mínimo.");
    if (stock > minimum) return { quantity: 0, unmet: 0, limited: false };
    const need = Math.max(0, target - stock - incoming);
    let cap =
      maximum == null ? Infinity : Math.max(0, maximum - stock - incoming);
    if (freeVolume != null && unitVolume > 0)
      cap = Math.min(cap, Math.max(0, freeVolume) / unitVolume);
    const roundedNeed = Math.ceil((need - 1e-9) / pack) * pack;
    const quantity = Math.max(
      0,
      Math.min(roundedNeed, Math.floor((cap + 1e-9) / pack) * pack),
    );
    return {
      quantity,
      unmet: Math.max(0, need - quantity),
      limited: quantity < need,
    };
  }
  function abc(products) {
    const sorted = products
      .map((p) => ({
        ...p,
        consumption: Math.max(0, Number(p.consumption || 0)),
      }))
      .sort(
        (a, b) =>
          b.consumption - a.consumption ||
          String(a.id).localeCompare(String(b.id)),
      );
    const total = sorted.reduce((a, p) => a + p.consumption, 0);
    let before = 0;
    return sorted.map((p) => {
      const classification =
        !total || !p.consumption
          ? "Sem giro"
          : before / total < 0.8
            ? "A"
            : before / total < 0.95
              ? "B"
              : "C";
      before += p.consumption;
      return { ...p, classification, share: total ? p.consumption / total : 0 };
    });
  }
  function stockMetrics(positions, movements, products, now = new Date()) {
    const from = now.getTime() - 30 * 86400000;
    return abc(
      products.map((p) => {
        const balances = positions.filter((b) => b.product_id === p.id);
        const recent = movements.filter(
          (m) =>
            m.product_id === p.id &&
            new Date(m.created_at).getTime() >= from &&
            new Date(m.created_at).getTime() <= now.getTime(),
        );
        const demand = recent
          .filter((m) => ["sale", "consumption"].includes(m.type))
          .reduce((a, m) => a + Number(m.quantity), 0);
        const consumption = recent
          .filter((m) => ["sale", "consumption"].includes(m.type))
          .reduce((a, m) => a + Number(m.cost_total_centavos), 0);
        const stock = balances.reduce((a, b) => a + Number(b.quantity), 0);
        const inventory = balances.reduce(
          (a, b) => a + Number(b.quantity) * Number(b.unit_cost_centavos),
          0,
        );
        const sales = recent
          .filter((m) => m.type === "sale")
          .reduce((a, m) => a + Number(m.revenue_centavos), 0);
        const loss = recent
          .filter((m) => m.type === "loss")
          .reduce((a, m) => a + Number(m.cost_total_centavos), 0);
        return {
          ...p,
          stock,
          inventory: Math.round(inventory),
          demand,
          consumption,
          sales,
          loss,
          coverage: demand ? stock / (demand / 30) : null,
          expiring: balances.filter(
            (b) =>
              b.expires_on &&
              Number(b.quantity) > 0 &&
              new Date(b.expires_on + "T23:59:59Z").getTime() <=
                now.getTime() + 30 * 86400000,
          ),
        };
      }),
    );
  }
  function projection(input) {
    const revenue = positive(input.revenue_centavos, "Receita");
    const variable = positive(input.variable_centavos, "Custos variáveis");
    const fixed = positive(input.fixed_centavos, "Custos fixos");
    const payroll = positive(input.payroll_centavos, "Folha");
    const rate = positive(input.rate_percent, "Carga tributária");
    if (rate > 100) throw Error("A carga deve estar entre 0 e 100%.");
    const extra = positive(input.extra_tax_centavos || 0, "Outros tributos");
    const credits = positive(input.credits_centavos || 0, "Créditos");
    const tax = Math.max(
      0,
      Math.round((revenue * rate) / 100) + extra - credits,
    );
    const costs = variable + fixed + payroll + tax;
    const grossRate = revenue ? 1 - variable / revenue : 0;
    const noTaxBreakEven = grossRate > 0 ? (fixed + payroll) / grossRate : null;
    const taxableRate = grossRate - rate / 100;
    const breakEven =
      noTaxBreakEven == null
        ? null
        : (noTaxBreakEven * rate) / 100 + extra - credits <= 0
          ? noTaxBreakEven
          : taxableRate > 0
            ? (fixed + payroll + extra - credits) / taxableRate
            : null;
    return {
      revenue,
      tax,
      costs,
      profit: revenue - costs,
      margin: revenue ? ((revenue - costs) / revenue) * 100 : null,
      breakEven: revenue && breakEven != null ? Math.round(breakEven) : null,
    };
  }
  function compareScenarios(scenarios) {
    const rows = scenarios.map((s) => ({ ...s, result: projection(s.inputs) }));
    const eligible = rows.filter((s) => s.eligibility === "confirmed");
    const best = eligible
      .slice()
      .sort((a, b) => b.result.profit - a.result.profit)[0];
    return {
      rows,
      best: best || null,
      message: best
        ? "Melhor resultado entre as premissas e elegibilidades confirmadas."
        : "Confirme elegibilidade e premissas antes de decidir.",
    };
  }
  function factorR(revenue12, payroll12) {
    const revenue = positive(revenue12, "Receita 12 meses");
    const payroll = positive(payroll12, "Folha 12 meses");
    return revenue > 0 ? payroll / revenue : null;
  }
  function allocatePurchases(products, positions, locations, orders) {
    const free = new Map(
      locations.map((l) => [
        l.id,
        l.capacity_liters == null
          ? null
          : Math.max(
              0,
              Number(l.capacity_liters) -
                positions
                  .filter((b) => b.location_id === l.id)
                  .reduce(
                    (a, b) =>
                      a +
                      Number(b.quantity) *
                        Number(
                          products.find((p) => p.id === b.product_id)
                            ?.volume_liters || 0,
                        ),
                    0,
                  ),
            ),
      ]),
    );
    // Todos os pedidos em aberto reservam capacidade antes de novas sugestões.
    for (const order of orders.filter((o) => o.status === "open")) {
      const p = products.find((p) => p.id === order.product_id);
      if (free.get(order.location_id) != null)
        free.set(
          order.location_id,
          Math.max(
            0,
            free.get(order.location_id) -
              Number(order.quantity - order.received_quantity) *
                Number(p?.volume_liters || 0),
          ),
        );
    }
    return products
      .filter((p) => p.active)
      .sort((a, b) => String(a.sku).localeCompare(String(b.sku)))
      .map((p) => {
        const location = locations.find(
          (l) => l.id === p.preferred_location_id && l.active,
        );
        const stock = positions
          .filter((b) => b.product_id === p.id)
          .reduce((a, b) => a + Number(b.quantity), 0);
        const incoming = orders
          .filter((o) => o.product_id === p.id && o.status === "open")
          .reduce((a, o) => a + Number(o.quantity - o.received_quantity), 0);
        const unknownCapacity =
          location?.capacity_liters != null &&
          (!p.volume_liters ||
            positions.some(
              (b) =>
                b.location_id === location.id &&
                Number(b.quantity) > 0 &&
                !products.find((x) => x.id === b.product_id)?.volume_liters,
            ));
        const suggestion = replenishment({
          stock,
          incoming,
          minimum: Number(p.minimum_quantity),
          target: Number(p.target_quantity),
          maximum:
            p.maximum_quantity == null ? null : Number(p.maximum_quantity),
          unitVolume: Number(p.volume_liters),
          freeVolume: location ? free.get(location.id) : null,
          pack: Number(p.pack_quantity),
        });
        if (!location || unknownCapacity) {
          suggestion.quantity = 0;
          suggestion.unmet = Math.max(
            0,
            Number(p.target_quantity) - stock - incoming,
          );
          suggestion.limited = suggestion.unmet > 0;
        }
        if (location && free.get(location.id) != null)
          free.set(
            location.id,
            Math.max(
              0,
              free.get(location.id) -
                suggestion.quantity * Number(p.volume_liters || 0),
            ),
          );
        return {
          ...p,
          ...suggestion,
          stock,
          incoming,
          location,
          blocked: !location
            ? "Defina um local de reposição."
            : unknownCapacity
              ? "Informe volume de todos os itens armazenados nesse local."
              : "",
        };
      });
  }
  const api = {
    number,
    positive,
    money,
    replenishment,
    abc,
    stockMetrics,
    projection,
    compareScenarios,
    factorR,
    allocatePurchases,
  };
  scope.HubDomain = api;
  if (typeof module !== "undefined") module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
