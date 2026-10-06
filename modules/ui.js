/* Módulos usam a sessão, shell, modal e RPC existentes da Hub. */
(function () {
  "use strict";
  let state = null,
    stockTab = "overview",
    adviceTab = "diagnosis";
  const D = HubDomain;
  const types = {
    entry: "Entrada",
    sale: "Venda",
    consumption: "Consumo",
    loss: "Perda",
    customer_return: "Devolução de cliente",
    supplier_return: "Devolução ao fornecedor",
    transfer: "Transferência",
    count: "Contagem física",
  };
  const statuses = {
    open: "Em aberto",
    in_review: "Em revisão",
    done: "Concluído",
    received: "Recebido",
    cancelled: "Cancelado",
  };
  const qty = (n) =>
    Number(n || 0).toLocaleString("pt-BR", { maximumFractionDigits: 3 });
  const cash = (n) => centavosToBRL(n);
  const product = (id) => state.products.find((p) => p.id === id);
  const place = (id) => state.locations.find((l) => l.id === id);
  const record = (id) => state.advisory.find((r) => r.id === id);
  const button = (label, action, primary = false) =>
    `<button class="btn ${primary ? "btn-primary" : "btn-outline"} btn-sm" onclick="${esc(action)}">${label}</button>`;
  const field = (name, label, type = "text", value = "", extra = "") =>
    `<div class="field"><label for="m-${name}">${label}</label><input id="m-${name}" name="${name}" type="${type}" value="${esc(value ?? "")}" ${extra}></div>`;
  const select = (name, label, options, value) =>
    `<div class="field"><label for="m-${name}">${label}</label><select id="m-${name}" name="${name}">${options.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(value) ? "selected" : ""}>${esc(l)}</option>`).join("")}</select></div>`;
  const area = (name, label, value = "", required = true) =>
    `<div class="field module-full"><label for="m-${name}">${label}</label><textarea id="m-${name}" name="${name}" rows="3" ${required ? "required" : ""}>${esc(value)}</textarea></div>`;
  const numberField = (name, label, v, required = true) =>
    field(
      name,
      label,
      "number",
      v ?? (required ? 0 : ""),
      `min="0" max="1000000000000" step="0.001" ${required ? "required" : ""}`,
    );
  const table = (heads, rows, empty = "Nenhum registro ainda.") =>
    rows.length
      ? `<div class="module-table tablewrap"><table><thead><tr>${heads.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((v, i) => `<td data-label="${esc(heads[i])}">${v}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`
      : `<p class="muted">${empty}</p>`;
  const panel = (title, body) =>
    `<section class="card module-panel"><h3>${title}</h3>${body}</section>`;
  const kpis = (items) =>
    `<div class="module-kpis">${items.map(([l, v]) => `<div class="card"><span class="muted">${l}</span><strong>${v}</strong></div>`).join("")}</div>`;
  const tabs = (kind, entries, current) =>
    `<div class="module-tabs">${entries.map(([id, label]) => button(label, `HubModules.tab('${kind}','${id}')`, id === current)).join("")}</div>`;
  function showForm(title, body, save) {
    openModal(
      title,
      `<form id="module-form"><div class="module-fields">${body}</div><p id="module-status" role="status"></p><div class="module-actions">${button("Cancelar", "closeModal()")}<button type="submit" class="btn btn-primary">Salvar</button></div></form>`,
      "wide",
    );
    document
      .getElementById("module-form")
      .addEventListener("submit", async (e) => {
        e.preventDefault();
        const form = e.currentTarget,
          submit = form.querySelector("[type=submit]");
        if (!navigator.onLine) {
          modalErro("Sem conexão. Reconecte para registrar com segurança.");
          return;
        }
        submit.disabled = true;
        let saved = false;
        try {
          await save(Object.fromEntries(new FormData(form)));
          saved = true;
          await refresh();
          closeModal();
          toast("Registro salvo.");
        } catch (error) {
          if (saved) {
            closeModal();
            toast(
              "Registro salvo. Não foi possível atualizar a tela; recarregando dados.",
            );
            await load(currentRoute().page);
          } else modalErro(error.message || "Não foi possível salvar.");
        } finally {
          if (submit.isConnected) submit.disabled = false;
        }
      });
  }
  async function refresh() {
    state = await rpc("hub_rpc_modules_snapshot");
    if (currentRoute().page === "estoque") drawStock();
    else if (currentRoute().page === "contador") drawAdvice();
  }
  async function load(page) {
    root.innerHTML = shell(page, '<p class="muted">Carregando módulo…</p>');
    try {
      await refresh();
    } catch (error) {
      if (currentRoute().page !== page) return;
      root.innerHTML = shell(
        page,
        panel(
          "Módulo indisponível",
          `<p>Não foi possível carregar os dados. Confira a conexão e a instalação da migration deste módulo.</p>${button("Tentar novamente", `HubModules.load('${page}')`)}`,
        ),
      );
    }
  }
  function drawStock() {
    if (!state) return;
    const metrics = D.stockMetrics(
      state.positions,
      state.movements,
      state.products,
    );
    const suggestions = D.allocatePurchases(
      state.products,
      state.positions,
      state.locations,
      state.orders,
    );
    let content = "";
    if (stockTab === "overview") {
      content =
        kpis([
          [
            "Capital em estoque",
            cash(metrics.reduce((a, p) => a + p.inventory, 0)),
          ],
          [
            "CMV / consumo · 30 dias",
            cash(metrics.reduce((a, p) => a + p.consumption, 0)),
          ],
          ["Perdas · 30 dias", cash(metrics.reduce((a, p) => a + p.loss, 0))],
          [
            "Itens no mínimo",
            metrics.filter((p) => p.active && p.stock <= p.minimum_quantity)
              .length,
          ],
        ]) +
        panel(
          "Saúde do estoque · últimos 30 dias",
          table(
            [
              "Item",
              "Saldo",
              "Cobertura",
              "Curva ABC por custo consumido",
              "Validade",
            ],
            metrics.map((p) => [
              esc(p.name),
              `${qty(p.stock)} ${esc(p.unit)}`,
              p.coverage == null
                ? "Sem demanda registrada"
                : `${qty(p.coverage)} dias`,
              esc(p.classification),
              p.expiring.length
                ? `${p.expiring.length} lote(s) vencido(s) ou vencendo em 30 dias`
                : "—",
            ]),
          ),
        ) +
        panel(
          "Lista de reposição automática",
          `<p class="muted">Ao atingir o mínimo, sugere o alvo descontando compras abertas. Arredonda por embalagem, respeita o máximo e distribui o espaço livre por SKU. Revise antes de gerar o pedido.</p>${table(
            [
              "Item / fornecedor",
              "Saldo / a receber",
              "Sugestão",
              "Pendência",
              "",
            ],
            suggestions
              .filter((p) => p.stock <= p.minimum_quantity)
              .map((p) => [
                `${esc(p.name)}<br>${esc(p.supplier || "Fornecedor não informado")}`,
                `${qty(p.stock)} / ${qty(p.incoming)}`,
                `${qty(p.quantity)} ${esc(p.unit)}`,
                esc(
                  p.blocked ||
                    (p.limited
                      ? `Faltam ${qty(p.unmet)} para atingir o alvo.`
                      : ""),
                ),
                p.quantity > 0
                  ? button(
                      "Criar pedido",
                      `HubModules.order('${p.id}',${p.quantity})`,
                    )
                  : "—",
              ]),
            "Nenhum item exige reposição.",
          )}<div class="module-actions">${button("Exportar lista CSV", "HubModules.exportPurchases()")}</div>`,
        );
    }
    if (stockTab === "products")
      content = panel(
        "Itens",
        `<div class="module-actions">${button("+ Item", "HubModules.product()", true)}<input aria-label="Filtrar itens" placeholder="Buscar nome, SKU ou categoria" oninput="HubModules.filter(this.value)"></div>${table(
          [
            "SKU / item",
            "Categoria / unidade",
            "Mínimo / alvo / máximo",
            "Volume por unidade",
            "",
          ],
          state.products.map((p) => [
            `${esc(p.sku)} · ${esc(p.name)}${p.active ? "" : " (inativo)"}`,
            `${esc(p.category)} / ${esc(p.unit)}`,
            `${qty(p.minimum_quantity)} / ${qty(p.target_quantity)} / ${p.maximum_quantity == null ? "—" : qty(p.maximum_quantity)}`,
            p.volume_liters == null
              ? "Não informado"
              : `${qty(p.volume_liters)} L`,
            button("Editar", `HubModules.product('${p.id}')`),
          ]),
        )}`,
      );
    if (stockTab === "movements")
      content =
        panel(
          "Entradas, saídas e inventário",
          `<div class="module-actions">${button("+ Movimento", "HubModules.move()", true)}${button("Exportar histórico (90 dias)", "HubModules.exportMovements()")}</div><p class="muted">Escolha o lote com vencimento mais próximo (FEFO). Contagens geram ajustes auditáveis. Transferências baixam a origem e entram no destino na mesma operação.</p>${table(
            [
              "Data",
              "Item / lote",
              "Movimento",
              "Quantidade",
              "Custo / receita",
              "Motivo",
            ],
            state.movements.map((m) => [
              esc(new Date(m.created_at).toLocaleString("pt-BR")),
              `${esc(product(m.product_id)?.name)} / ${esc(state.positions.find((b) => b.id === m.position_id)?.lot || "Sem lote")}`,
              esc(types[m.type]),
              qty(m.quantity),
              `${cash(m.cost_total_centavos)} / ${cash(m.revenue_centavos)}`,
              esc(m.reason),
            ]),
          )}`,
        ) +
        panel(
          "Saldos por local e lote",
          table(
            ["Item", "Local", "Lote / validade", "Saldo", "Custo médio"],
            state.positions.map((b) => [
              esc(product(b.product_id)?.name),
              esc(place(b.location_id)?.name),
              `${esc(b.lot || "Sem lote")} / ${b.expires_on ? formatDateBR(b.expires_on) : "Sem validade"}`,
              qty(b.quantity),
              cash(b.unit_cost_centavos),
            ]),
          ),
        );
    if (stockTab === "orders")
      content = panel(
        "Compras e recebimentos parciais",
        `${button("+ Pedido", "HubModules.order()", true)}${table(
          [
            "Item / fornecedor",
            "Local / previsão",
            "Pedido / recebido",
            "Status",
            "",
          ],
          state.orders.map((o) => [
            `${esc(product(o.product_id)?.name)} / ${esc(o.supplier)}`,
            `${esc(place(o.location_id)?.name)} / ${formatDateBR(o.expected_on)}`,
            `${qty(o.quantity)} / ${qty(o.received_quantity)}`,
            esc(statuses[o.status]),
            o.status === "open"
              ? `${button("Receber", `HubModules.move('${o.product_id}','${o.id}')`)} ${button("Cancelar", `HubModules.cancelOrder('${o.id}')`)}`
              : "—",
          ]),
        )}`,
      );
    if (stockTab === "locations")
      content = panel(
        "Locais e capacidade",
        `${button("+ Local", "HubModules.location()", true)}<p class="muted">Converta dimensões úteis para litros (1 m³ = 1.000 L). O volume de um item é o espaço ocupado por uma unidade, kg ou litro, conforme sua unidade de controle.</p>${table(
          ["Local", "Usado / limite", "Qualidade da medição", ""],
          state.locations.map((l) => {
            const balances = state.positions.filter(
                (b) => b.location_id === l.id && Number(b.quantity) > 0,
              ),
              unknown = balances.some(
                (b) => !product(b.product_id)?.volume_liters,
              );
            const used = balances.reduce(
              (a, b) =>
                a +
                Number(b.quantity) *
                  Number(product(b.product_id)?.volume_liters || 0),
              0,
            );
            return [
              esc(l.name),
              `${qty(used)} / ${l.capacity_liters == null ? "Não declarado" : qty(l.capacity_liters)} L`,
              unknown
                ? "Parcial: itens sem volume"
                : l.active
                  ? "Ativo"
                  : "Inativo",
              button("Editar", `HubModules.location('${l.id}')`),
            ];
          }),
        )}`,
      );
    root.innerHTML = shell(
      "estoque",
      `<h2 class="section-title">Controle de estoque</h2><p class="muted">Tudo que entra e sai do comércio, com reposição e espaço sob controle.</p>${tabs(
        "stock",
        [
          ["overview", "Visão geral"],
          ["products", "Itens"],
          ["movements", "Movimentos"],
          ["orders", "Compras"],
          ["locations", "Locais"],
        ],
        stockTab,
      )}${content}`,
    );
    document.querySelector(".wrap")?.classList.add("module-wrap");
  }
  function locationForm(id) {
    const l = state.locations.find((x) => x.id === id) || {};
    showForm(
      id ? "Editar local" : "Novo local",
      field("name", "Nome", "text", l.name, 'required maxlength="120"') +
        numberField(
          "capacity_liters",
          "Capacidade útil (L) · vazio = não declarado",
          l.capacity_liters,
          false,
        ) +
        select(
          "active",
          "Status",
          [
            [true, "Ativo"],
            [false, "Inativo"],
          ],
          l.active ?? true,
        ),
      (data) =>
        rpc("hub_rpc_stock_save", {
          p_kind: "location",
          p_data: {
            ...data,
            id: id || null,
            capacity_liters:
              data.capacity_liters === ""
                ? null
                : D.positive(data.capacity_liters, "Capacidade", false),
            active: data.active === "true",
          },
        }),
    );
  }
  function productForm(id) {
    const p = product(id) || {};
    showForm(
      id ? "Editar item" : "Novo item",
      field("sku", "SKU / código", "text", p.sku, 'required maxlength="80"') +
        field("name", "Nome", "text", p.name, 'required maxlength="180"') +
        field("category", "Categoria", "text", p.category) +
        select(
          "unit",
          "Unidade",
          [
            ["un", "Unidade"],
            ["kg", "Quilo"],
            ["l", "Litro"],
          ],
          p.unit || "un",
        ) +
        numberField(
          "minimum_quantity",
          "Quantidade mínima",
          p.minimum_quantity || 0,
        ) +
        numberField(
          "target_quantity",
          "Alvo de reposição",
          p.target_quantity || 0,
        ) +
        numberField(
          "maximum_quantity",
          "Quantidade máxima · opcional",
          p.maximum_quantity,
          false,
        ) +
        numberField(
          "pack_quantity",
          "Embalagem de compra",
          p.pack_quantity || 1,
        ) +
        numberField(
          "volume_liters",
          "Volume ocupado por unidade (L)",
          p.volume_liters,
          false,
        ) +
        field("supplier", "Fornecedor", "text", p.supplier) +
        field(
          "lead_days",
          "Prazo do fornecedor (dias)",
          "number",
          p.lead_days || 0,
          'min="0" max="365" step="1" required',
        ) +
        select(
          "preferred_location_id",
          "Local da reposição",
          [
            ["", "Selecione"],
            ...state.locations
              .filter((l) => l.active)
              .map((l) => [l.id, l.name]),
          ],
          p.preferred_location_id,
        ) +
        select(
          "active",
          "Status",
          [
            [true, "Ativo"],
            [false, "Inativo"],
          ],
          p.active ?? true,
        ),
      (data) => {
        for (const k of [
          "minimum_quantity",
          "target_quantity",
          "maximum_quantity",
          "pack_quantity",
          "volume_liters",
        ])
          data[k] = data[k] === "" ? null : D.positive(data[k], k);
        data.preferred_location_id = data.preferred_location_id || null;
        data.id = id || null;
        data.active = data.active === "true";
        return rpc("hub_rpc_stock_save", { p_kind: "product", p_data: data });
      },
    );
  }
  function moveForm(pid, oid) {
    const o = state.orders.find((o) => o.id === oid);
    const items = state.products.filter((p) => p.active);
    if (!items.length) {
      toast("Cadastre um item primeiro.");
      return;
    }
    const op = crypto.randomUUID(),
      openingPositions = state.positions.map((b) => ({ ...b }));
    showForm(
      "Registrar movimento",
      select(
        "type",
        "Tipo",
        Object.entries(types).filter(([k]) => !o || k === "entry"),
        "entry",
      ) +
        select(
          "product_id",
          "Item",
          items.map((p) => [p.id, `${p.sku} · ${p.name}`]),
          pid || items[0].id,
        ) +
        select(
          "position_id",
          "Lote de origem · saída, transferência e contagem",
          [
            ["", "Selecione um saldo"],
            ...state.positions.map((b) => [
              b.id,
              `${product(b.product_id)?.sku} · ${place(b.location_id)?.name} · ${b.lot || "sem lote"} · validade ${b.expires_on || "não informada"} · saldo ${qty(b.quantity)}`,
            ]),
          ],
          "",
        ) +
        select(
          "location_id",
          "Local de entrada / destino",
          [
            ["", "Selecione"],
            ...state.locations
              .filter((l) => l.active)
              .map((l) => [l.id, l.name]),
          ],
          o?.location_id,
        ) +
        numberField(
          "quantity",
          "Quantidade · na contagem, informe o saldo físico",
          o ? Number(o.quantity) - Number(o.received_quantity) : 1,
        ) +
        field("lot", "Lote da entrada", "text", "", 'maxlength="120"') +
        field("expires_on", "Validade da entrada", "date") +
        field(
          "cost",
          "Custo por unidade da entrada (R$)",
          "number",
          "0",
          'min="0" step="0.01" required',
        ) +
        field(
          "revenue",
          "Valor total da venda (R$)",
          "number",
          "0",
          'min="0" step="0.01" required',
        ) +
        area("reason", "Motivo / documento de referência") +
        `<p class="muted module-full">Entradas e devoluções de cliente exigem o custo de aquisição. Na saída, usa o custo médio do lote. Recebimentos podem ser parciais. Nenhum movimento altera automaticamente os recebíveis.</p>`,
      (data) => {
        const b = openingPositions.find((b) => b.id === data.position_id);
        return rpc("hub_rpc_stock_move", {
          p_data: {
            id: op,
            type: data.type,
            product_id: o?.product_id || data.product_id,
            position_id: data.position_id || null,
            location_id: data.location_id || null,
            quantity: D.positive(data.quantity, "Quantidade"),
            expected_quantity:
              data.type === "count" ? Number(b?.quantity) : null,
            lot: data.lot,
            expires_on: data.expires_on || null,
            unit_cost_centavos: D.money(D.positive(data.cost, "Custo") * 100),
            revenue_centavos: D.money(
              D.positive(data.revenue, "Receita") * 100,
            ),
            reason: data.reason,
            order_id: oid || null,
          },
        });
      },
    );
  }
  function orderForm(pid, quantity = 1) {
    if (!state.products.some((p) => p.active)) {
      toast("Cadastre um item primeiro.");
      return;
    }
    const p = product(pid) || state.products.find((p) => p.active),
      id = crypto.randomUUID();
    showForm(
      "Criar pedido de compra",
      select(
        "product_id",
        "Item",
        state.products.filter((p) => p.active).map((p) => [p.id, p.name]),
        p.id,
      ) +
        select(
          "location_id",
          "Local de recebimento",
          state.locations.filter((l) => l.active).map((l) => [l.id, l.name]),
          p.preferred_location_id,
        ) +
        numberField("quantity", "Quantidade", quantity) +
        field("supplier", "Fornecedor", "text", p.supplier, "required") +
        field("expected_on", "Previsão", "date") +
        `<p class="muted module-full">Registra uma compra planejada. Confira fornecedor, preço e prazo antes de contratar.</p>`,
      (data) =>
        rpc("hub_rpc_stock_order", {
          p_data: {
            ...data,
            id,
            quantity: D.positive(data.quantity, "Quantidade", false),
            expected_on: data.expected_on || null,
          },
        }),
    );
  }
  function cancelOrder(id) {
    showForm(
      "Cancelar pedido",
      area("confirmation", "Motivo do cancelamento"),
      (data) =>
        rpc("hub_rpc_stock_order", {
          p_data: { id, status: "cancelled", reason: data.confirmation },
        }),
    );
  }
  const guides = [
    [
      "Diagnóstico de lucro",
      "Separar receita por competência, CMV, despesas, folha, pró-labore e caixa. Conferir inventário e retiradas pessoais.",
      "https://sebrae.com.br/sites/PortalSebrae/financas",
    ],
    [
      "Regime e elegibilidade",
      "Conferir CNAE, atividade efetiva, receita, vedações, estrutura e prazos antes de comparar regimes.",
      "https://www.gov.br/receitafederal/pt-br/assuntos/orientacao-tributaria/tributos/IRPJ",
    ],
    [
      "Simples e fator R",
      "Consultar a atividade e o manual PGDAS-D. Fator R só se aplica às atividades previstas e exige composição correta da folha e receita.",
      "https://www8.receita.fazenda.gov.br/SimplesNacional/Arquivos/manual/MANUAL_PGDAS-D_2018_V4.pdf",
    ],
    [
      "Estoque, CMV e custo",
      "Reconciliar compras, perdas, devoluções e custo com o contador. O custo médio gerencial por lote não substitui fechamento contábil.",
      "https://www.cpc.org.br/CPC/Documentos-emitidos/Pronunciamentos/Pronunciamento?Id=47",
    ],
    [
      "Tributos, créditos e reforma",
      "Revisar incidências, retenções, créditos, município/estado e regras vigentes para o período. Registrar a memória da carga efetiva utilizada.",
      "https://www.gov.br/receitafederal/pt-br/assuntos/reforma-tributaria",
    ],
    [
      "Agenda fiscal e assinaturas",
      "Cadastrar as obrigações aplicáveis, prazos, documentos e responsável. Anexar referência da evidência na conclusão.",
      "https://www.gov.br/receitafederal/pt-br/assuntos/agenda-tributaria",
    ],
  ];
  function drawAdvice() {
    const records = (k) => state.advisory.filter((r) => r.kind === k),
      profile = records("profile")[0]?.data,
      periods = records("period"),
      scenarios = records("scenario");
    let content = "";
    if (adviceTab === "diagnosis") {
      const current = periods
        .slice()
        .sort((a, b) => b.data.competence.localeCompare(a.data.competence))[0];
      content = panel(
        "Assessoria contábil estratégica",
        `<p>Diagnostique lucro, organize informações, compare premissas tributárias e acompanhe as ações com seu contador.</p><p>${profile ? `${esc(profile.name)} · CNPJ ${esc(profile.cnpj)} · ${esc(profile.regime || "Regime a confirmar")}` : "Cadastre a empresa para montar o dossiê."}</p>${button("Dados da empresa", 'HubModules.adviceForm("profile")')}`,
      );
      if (current) {
        const r = D.projection(current.data.inputs);
        content += kpis([
          ["Competência", esc(current.data.competence)],
          ["Lucro gerencial", cash(r.profit)],
          ["Margem", r.margin == null ? "Sem receita" : `${qty(r.margin)}%`],
          [
            "Ponto de equilíbrio",
            r.breakEven == null
              ? "Sem contribuição positiva"
              : cash(r.breakEven),
          ],
        ]);
      }
      content +=
        panel(
          "Fechamentos por competência",
          `<p class="muted">Informe valores por competência, conciliados com documentos. Custos variáveis incluem CMV; custos fixos excluem folha, tributos e despesas pessoais. Taxa efetiva e créditos são premissas informadas.</p>${button("+ Diagnóstico mensal", 'HubModules.adviceForm("period")', true)}${table(
            ["Competência", "Receita", "Lucro", "Fonte / premissas", ""],
            periods.map((r) => [
              esc(r.data.competence),
              cash(r.data.inputs.revenue_centavos),
              cash(D.projection(r.data.inputs).profit),
              esc(r.data.assumptions),
              button("Revisar", `HubModules.adviceForm('period','${r.id}')`),
            ]),
          )}`,
        ) +
        panel(
          "Fator R · apoio à análise",
          `<form id="factor-r" class="module-fields">${numberField("revenue12", "Receita bruta dos 12 meses (R$)", 0)}${numberField("payroll12", "Folha elegível dos 12 meses (R$)", 0)}<button class="btn btn-outline" type="submit">Calcular relação</button><output id="factor-result"></output></form><p class="muted">A relação não determina sozinha o anexo. Confirme atividade, composição, início de atividade e regras do PGDAS-D com o contador.</p>`,
        );
    }
    if (adviceTab === "scenarios") {
      const compared = D.compareScenarios(
        scenarios.map((r) => ({ ...r.data, id: r.id })),
      );
      const bases = new Set(
        compared.rows.map((s) =>
          JSON.stringify([
            s.inputs.revenue_centavos,
            s.inputs.variable_centavos,
            s.inputs.fixed_centavos,
            s.inputs.payroll_centavos,
          ]),
        ),
      );
      const comparisonNote =
        bases.size > 1
          ? "As bases operacionais diferem entre cenários. Confira receita e custos antes de atribuir a diferença aos tributos."
          : "";
      content = panel(
        "Planejamento tributário e lucro",
        `<p>Compare a mesma receita e operação em regimes distintos. A carga efetiva deve incluir os tributos aplicáveis, com memória de cálculo e fonte para o período. Use créditos apenas quando a elegibilidade estiver comprovada. A projeção anual repete 12 meses iguais; não representa apuração anual nem efeitos de sazonalidade.</p><p class="muted">Não calcula anexos, benefícios ou obrigações automaticamente. O resultado depende das premissas e não aprova uma mudança de regime.</p>${button("+ Cenário", 'HubModules.adviceForm("scenario")', true)}${table(
          [
            "Cenário / regime",
            "Carga / tributos",
            "Lucro mensal / anual projetado",
            "Elegibilidade declarada",
            "",
          ],
          compared.rows.map((s) => [
            `${esc(s.name)} / ${esc(s.regime)}`,
            `${qty(s.inputs.rate_percent)}% / ${cash(s.result.tax)}`,
            `${cash(s.result.profit)} / ${cash(s.result.profit * 12)}<br>Margem: ${s.result.margin == null ? "—" : qty(s.result.margin) + "%"}`,
            esc(
              {
                confirmed: "Confirmada pelo revisor informado",
                pending: "Pendente",
                blocked: "Impedida",
              }[s.eligibility],
            ),
            button("Revisar", `HubModules.adviceForm('scenario','${s.id}')`),
          ]),
        )}<p>${compared.best ? `${esc(compared.best.name)}: ` : ""}${esc(compared.message)}</p><p class="muted">${esc(comparisonNote)}</p>`,
      );
    }
    if (adviceTab === "actions")
      content = panel(
        "Plano de ações e obrigações",
        `${button("+ Ação / obrigação", 'HubModules.adviceForm("action")', true)}${table(
          [
            "Ação / valor previsto",
            "Prazo / responsável",
            "Status",
            "Como fazer / evidência",
            "",
          ],
          records("action").map((r) => [
            `${esc(r.data.title)}${r.data.amount_centavos != null ? "<br>" + cash(r.data.amount_centavos) : ""}`,
            `${formatDateBR(r.data.due_on)} / ${esc(r.data.owner)}`,
            `${esc(statuses[r.data.status])}${r.data.status !== "done" && r.data.due_on < todayISO() ? " · Atrasada" : ""}`,
            `${esc(r.data.instructions)}<br>${esc(r.data.evidence || "")}`,
            button("Atualizar", `HubModules.adviceForm('action','${r.id}')`),
          ]),
        )}`,
      );
    if (adviceTab === "guides")
      content = guides
        .map(([title, instructions, url]) =>
          panel(
            esc(title),
            `<p>${esc(instructions)}</p><a href="${esc(url)}" target="_blank" rel="noopener noreferrer">Consultar fonte oficial</a> · ${button("Criar ação", `HubModules.guideAction(${guides.findIndex((g) => g[0] === title)})`)}`,
          ),
        )
        .join("");
    root.innerHTML = shell(
      "contador",
      `<h2 class="section-title">Contator · assessoria contábil estratégica</h2><p class="muted">Diagnóstico → premissas → comparação → revisão → ações → acompanhamento.</p><div class="module-actions">${button("Exportar dossiê JSON", "HubModules.exportAdvice()")}${button("Imprimir dossiê", "HubModules.printAdvice()")}</div>${tabs(
        "advice",
        [
          ["diagnosis", "Diagnóstico"],
          ["scenarios", "Cenários tributários"],
          ["actions", "Plano de ações"],
          ["guides", "Orientações"],
        ],
        adviceTab,
      )}${content}`,
    );
    document.querySelector(".wrap")?.classList.add("module-wrap");
    document.getElementById("factor-r")?.addEventListener("submit", (e) => {
      e.preventDefault();
      const f = new FormData(e.currentTarget),
        r = D.factorR(f.get("revenue12"), f.get("payroll12"));
      document.getElementById("factor-result").textContent =
        r == null
          ? "Receita zero: confira as regras especiais."
          : `Relação informada: ${qty(r * 100)}% · validar aplicação com contador.`;
    });
  }
  function adviceForm(kind, id, defaults = {}) {
    const saved =
        record(id) ||
        (kind === "profile"
          ? state.advisory.find((r) => r.kind === "profile")
          : null),
      data = saved?.data || defaults;
    let body = "";
    if (kind === "profile")
      body =
        field("name", "Razão social", "text", data.name, "required") +
        field(
          "cnpj",
          "CNPJ · 14 posições, sem pontuação",
          "text",
          data.cnpj,
          'required pattern="[A-Za-z0-9]{12}[0-9]{2}" maxlength="14"',
        ) +
        field("cnae", "CNAE / atividade efetiva", "text", data.cnae) +
        select(
          "regime",
          "Regime atual",
          [
            ["", "A confirmar"],
            ...["MEI", "Simples Nacional", "Lucro Presumido", "Lucro Real"].map(
              (r) => [r, r],
            ),
          ],
          data.regime,
        ) +
        field("city", "Município / UF", "text", data.city) +
        field(
          "accountant",
          "Contador responsável / CRC",
          "text",
          data.accountant,
        ) +
        area(
          "strategy",
          "Objetivo e diagnóstico inicial",
          data.strategy,
          false,
        );
    if (kind === "period" || kind === "scenario") {
      body =
        kind === "period"
          ? field(
              "competence",
              "Competência",
              "month",
              data.competence || todayISO().slice(0, 7),
              "required",
            )
          : field("name", "Nome do cenário", "text", data.name, "required") +
            select(
              "regime",
              "Regime",
              ["MEI", "Simples Nacional", "Lucro Presumido", "Lucro Real"].map(
                (r) => [r, r],
              ),
              data.regime,
            ) +
            select(
              "eligibility",
              "Elegibilidade",
              [
                ["pending", "A verificar"],
                ["confirmed", "Confirmada com evidência"],
                ["blocked", "Impedida"],
              ],
              data.eligibility || "pending",
            ) +
            field(
              "reviewed_by",
              "Revisor / contador / CRC",
              "text",
              data.reviewed_by,
            ) +
            area(
              "review_note",
              "Evidência de elegibilidade",
              data.review_note,
              false,
            );
      const labels = {
        revenue_centavos: "Receita (R$)",
        variable_centavos: "Custos variáveis / CMV (R$)",
        fixed_centavos: "Custos fixos sem folha (R$)",
        payroll_centavos: "Folha / pró-labore e encargos (R$)",
        extra_tax_centavos: "Outros tributos fora da taxa (R$)",
        credits_centavos: "Créditos elegíveis (R$)",
      };
      body +=
        Object.entries(labels)
          .map(([k, l]) =>
            field(
              k,
              l,
              "number",
              data.inputs?.[k] == null ? "" : (data.inputs[k] / 100).toFixed(2),
              'required min="0" step="0.01" max="10000000000"',
            ),
          )
          .join("") +
        field(
          "rate_percent",
          "Carga efetiva sobre receita (%)",
          "number",
          data.inputs?.rate_percent ?? "",
          'required min="0" max="100" step="0.0001"',
        ) +
        field(
          "source_url",
          "Fonte / memória da carga (HTTPS)",
          "url",
          data.source_url,
          'required pattern="https://.*"',
        ) +
        field(
          "valid_on",
          "Data-base das premissas",
          "date",
          data.valid_on || todayISO(),
          "required",
        ) +
        area(
          "assumptions",
          "Premissas, cálculo da carga, tributos, restrições e documentos",
          data.assumptions,
        );
    }
    if (kind === "action")
      body =
        field("title", "Ação / obrigação", "text", data.title, "required") +
        field("owner", "Responsável", "text", data.owner, "required") +
        field(
          "due_on",
          "Prazo",
          "date",
          data.due_on || todayISO(),
          "required",
        ) +
        field(
          "amount",
          "Valor previsto a pagar (R$) · opcional",
          "number",
          data.amount_centavos == null
            ? ""
            : (data.amount_centavos / 100).toFixed(2),
          'min="0" step="0.01"',
        ) +
        select(
          "status",
          "Status",
          Object.entries(statuses).filter(([k]) =>
            ["open", "in_review", "done"].includes(k),
          ),
          data.status || "open",
        ) +
        area(
          "instructions",
          "Como fazer / documentos / fonte",
          data.instructions,
          false,
        ) +
        area(
          "evidence",
          "Evidência / protocolo / parecer para conclusão",
          data.evidence,
          false,
        );
    showForm(
      "Contator · " +
        {
          profile: "Dados da empresa",
          period: "Diagnóstico mensal",
          scenario: "Cenário tributário",
          action: "Plano de ação",
        }[kind],
      body,
      (form) => {
        if (kind === "period" || kind === "scenario") {
          form.inputs = {};
          for (const k of [
            "revenue_centavos",
            "variable_centavos",
            "fixed_centavos",
            "payroll_centavos",
            "extra_tax_centavos",
            "credits_centavos",
          ]) {
            form.inputs[k] = D.money(D.positive(form[k], k) * 100);
            delete form[k];
          }
          form.inputs.rate_percent = D.positive(form.rate_percent, "Carga");
          delete form.rate_percent;
          D.projection(form.inputs);
        }
        if (kind === "profile") form.cnpj = form.cnpj.toUpperCase();
        if (kind === "action") {
          form.amount_centavos =
            form.amount === ""
              ? null
              : D.money(D.positive(form.amount, "Valor previsto") * 100);
          delete form.amount;
        }
        return rpc("hub_rpc_advisory_save", {
          p_kind: kind,
          p_data: form,
          p_id: saved?.id || null,
          p_revision: saved?.revision || null,
        });
      },
    );
  }
  function download(name, body, type) {
    const url = URL.createObjectURL(new Blob([body], { type }));
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function csv(rows) {
    return (
      "\uFEFF" +
      rows
        .map((row) =>
          row
            .map((value) => {
              let v = String(value ?? "");
              if (/^(?:\s*[=+\-@]|[\t\r\n])/.test(v)) v = "'" + v;
              return '"' + v.replace(/"/g, '""') + '"';
            })
            .join(";"),
        )
        .join("\r\n")
    );
  }
  function dossier() {
    return {
      generated_at: new Date().toISOString(),
      scope:
        "Assessoria gerencial; premissas informadas; revisão profissional necessária",
      records: state.advisory,
      comparison: D.compareScenarios(
        state.advisory.filter((r) => r.kind === "scenario").map((r) => r.data),
      ),
      stock_summary: D.stockMetrics(
        state.positions,
        state.movements,
        state.products,
      ),
    };
  }
  function printAdvice() {
    const node = document.createElement("article");
    node.className = "module-print";
    const labels = {
      name: "Nome",
      cnpj: "CNPJ",
      cnae: "CNAE / atividade",
      regime: "Regime",
      city: "Município / UF",
      accountant: "Contador / CRC",
      strategy: "Objetivo estratégico",
      competence: "Competência",
      eligibility: "Elegibilidade declarada",
      reviewed_by: "Revisor",
      review_note: "Evidência de elegibilidade",
      source_url: "Fonte / memória",
      valid_on: "Data-base",
      assumptions: "Premissas",
      title: "Ação",
      owner: "Responsável",
      due_on: "Prazo",
      status: "Status",
      instructions: "Como fazer",
      evidence: "Evidência",
      amount_centavos: "Valor previsto",
    };
    const inputsLabels = {
      revenue_centavos: "Receita",
      variable_centavos: "Custos variáveis / CMV",
      fixed_centavos: "Custos fixos sem folha",
      payroll_centavos: "Folha / pró-labore",
      extra_tax_centavos: "Outros tributos",
      credits_centavos: "Créditos elegíveis",
      rate_percent: "Carga efetiva (%)",
    };
    const translate = (v) =>
      statuses[v] ||
      {
        pending: "Pendente",
        confirmed: "Confirmada pelo revisor informado",
        blocked: "Impedida",
      }[v] ||
      v;
    node.innerHTML =
      `<h1>Contator · dossiê de assessoria</h1><p>${esc(new Date().toLocaleString("pt-BR"))}</p><p>Premissas informadas para revisão profissional. Comparações não autorizam mudança de regime.</p>` +
      state.advisory
        .map((r) => {
          const details = Object.entries(r.data)
            .filter(([k, v]) => labels[k] && v != null && v !== "")
            .map(
              ([k, v]) =>
                `<p><strong>${labels[k]}:</strong> ${esc(k === "amount_centavos" ? cash(v) : translate(v))}</p>`,
            )
            .join("");
          let analysis = "";
          if (r.data.inputs) {
            const result = D.projection(r.data.inputs);
            analysis = `<h3>Premissas e resultado mensal</h3>${table(
              ["Premissa", "Valor"],
              Object.entries(r.data.inputs).map(([k, v]) => [
                esc(inputsLabels[k] || k),
                k === "rate_percent" ? qty(v) + "%" : cash(v),
              ]),
            )}<p>Tributos estimados: ${cash(result.tax)} · Lucro gerencial: ${cash(result.profit)} · Margem: ${result.margin == null ? "Sem receita" : qty(result.margin) + "%"}</p><p>Ponto de equilíbrio: ${result.breakEven == null ? "Não calculável com estas premissas" : cash(result.breakEven)}</p>${r.kind === "scenario" ? `<p>Projeção de lucro de 12 meses iguais: ${cash(result.profit * 12)}. Não considera sazonalidade ou apuração anual.</p>` : ""}`;
          }
          return `<section><h2>${esc({ profile: "Empresa", period: "Diagnóstico", scenario: "Cenário", action: "Plano de ação" }[r.kind])}</h2>${details}${analysis}</section>`;
        })
        .join("");
    document.body.appendChild(node);
    window.addEventListener("afterprint", () => node.remove(), { once: true });
    window.print();
  }
  window.renderEstoque = () => load("estoque");
  window.renderContator = () => load("contador");
  window.HubModules = {
    load,
    tab: (kind, tab) => {
      if (kind === "stock") {
        stockTab = tab;
        drawStock();
      } else {
        adviceTab = tab;
        drawAdvice();
      }
    },
    location: locationForm,
    product: productForm,
    move: moveForm,
    order: orderForm,
    cancelOrder,
    adviceForm,
    guideAction: (i) =>
      adviceForm("action", null, {
        title: guides[i][0],
        instructions: guides[i][1] + "\n" + guides[i][2],
      }),
    filter: (value) =>
      document
        .querySelectorAll(".module-table tbody tr")
        .forEach(
          (row) =>
            (row.hidden = !row.textContent
              .toLowerCase()
              .includes(value.toLowerCase())),
        ),
    exportAdvice: () =>
      download(
        "contator-dossie.json",
        JSON.stringify(dossier(), null, 2),
        "application/json",
      ),
    printAdvice,
    exportPurchases: () =>
      download(
        "estoque-reposicao.csv",
        csv([
          [
            "SKU",
            "Item",
            "Fornecedor",
            "Local",
            "Saldo",
            "A receber",
            "Quantidade sugerida",
            "Pendência",
          ],
          ...D.allocatePurchases(
            state.products,
            state.positions,
            state.locations,
            state.orders,
          )
            .filter((p) => p.stock <= p.minimum_quantity)
            .map((p) => [
              p.sku,
              p.name,
              p.supplier,
              p.location?.name,
              p.stock,
              p.incoming,
              p.quantity,
              p.blocked || p.unmet,
            ]),
        ]),
        "text/csv;charset=utf-8",
      ),
    exportMovements: () =>
      download(
        "estoque-movimentos-90-dias.csv",
        csv([
          [
            "Data",
            "Item",
            "Tipo",
            "Quantidade",
            "Custo centavos",
            "Receita centavos",
            "Motivo",
          ],
          ...state.movements.map((m) => [
            m.created_at,
            product(m.product_id)?.name,
            types[m.type],
            m.quantity,
            m.cost_total_centavos,
            m.revenue_centavos,
            m.reason,
          ]),
        ]),
        "text/csv;charset=utf-8",
      ),
  };
})();
