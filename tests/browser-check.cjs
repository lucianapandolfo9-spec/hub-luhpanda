/* Interface real + RPCs reais no Postgres local; Auth é simulado e nenhuma conexão de produção é feita. */
const http = require("node:http"),
  fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { database, rpc } = require("./fixture.cjs");
const { chromium } = require(process.env.HUB_PLAYWRIGHT_PATH || "playwright");
const root = path.resolve(__dirname, "..");
(async () => {
  console.log("Initializing isolated database");
  const db = await database();
  console.log("Database ready");
  let server, browser;
  const errors = [];
  try {
    server = http.createServer(async (req, res) => {
      try {
        if (req.url === "/mock-sdk.js") {
          res.setHeader("Content-Type", "text/javascript");
          res.end("window.supabase={};");
          return;
        }
        if (req.url === "/config.js") {
          res.setHeader("Content-Type", "text/javascript");
          res.end(
            `const HUB_ADMIN_EMAIL='lucianapandolfo9@gmail.com';const flags=new URLSearchParams(location.search);const hubClient={auth:{getSession:async()=>({data:{session:flags.has('login')?null:{user:{email:flags.has('denied')?'outra@example.invalid':HUB_ADMIN_EMAIL}}}}),onAuthStateChange:()=>{},signOut:async()=>{}},rpc:async(name,params)=>{const r=await fetch('/rpc',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,params})});return r.json();}};`,
          );
          return;
        }
        if (req.url === "/rpc") {
          let body = "";
          for await (const c of req) body += c;
          const { name, params: p = {} } = JSON.parse(body);
          let data;
          if (name === "hub_rpc_modules_snapshot") data = await rpc(db, name);
          else if (name === "hub_rpc_stock_save")
            data = await rpc(db, name, p.p_kind, p.p_data);
          else if (
            name === "hub_rpc_stock_move" ||
            name === "hub_rpc_stock_order"
          )
            data = await rpc(db, name, p.p_data);
          else if (name === "hub_rpc_advisory_save")
            data = await rpc(
              db,
              name,
              p.p_kind,
              p.p_data,
              p.p_id,
              p.p_revision,
            );
          else throw Error("RPC não incluída no teste local: " + name);
          res.setHeader("Content-Type", "application/json");
          res.end(JSON.stringify({ data, error: null }));
          return;
        }
        const pathname = new URL(req.url, "http://local.test").pathname;
        const file = path.resolve(
          root,
          "." + pathname + (pathname.endsWith("/") ? "index.html" : ""),
        );
        if (!file.startsWith(root + path.sep)) throw Error("Caminho inválido");
        let body = fs.readFileSync(file);
        if (file.endsWith(".html"))
          body = body
            .toString()
            .replace(
              "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js",
              "/mock-sdk.js",
            );
        res.setHeader(
          "Content-Type",
          file.endsWith(".js")
            ? "text/javascript"
            : file.endsWith(".css")
              ? "text/css"
              : "text/html",
        );
        res.end(body);
      } catch (error) {
        res.setHeader("Content-Type", "application/json");
        res.end(
          JSON.stringify({ data: null, error: { message: error.message } }),
        );
      }
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    console.log("Launching browser");
    browser = await chromium.launch({
      headless: true,
      executablePath: process.env.HUB_CHROMIUM_PATH || undefined,
      args: ["--no-sandbox", "--disable-dev-shm-usage"],
    });
    console.log("Browser ready");
    const page = await browser.newPage({
      viewport: { width: 1366, height: 900 },
    });
    page.on("pageerror", (e) => {
      errors.push(e.message);
      console.error("Browser error:", e.message);
    });
    page.on("console", (m) => {
      if (m.type() === "error") errors.push(m.text());
    });
    await page.goto(base + "/#/estoque");
    await page
      .getByRole("heading", { name: "Controle de estoque", exact: true })
      .waitFor();
    console.log("Stock page ready");
    const click = (name) =>
      page.getByRole("button", { name, exact: true }).click();
    const fill = (name, value) =>
      page.locator(`[name="${name}"]`).fill(String(value));
    const save = async () => {
      await page.locator("#module-form button[type=submit]").click();
      await page.locator("#module-form").waitFor({ state: "detached" });
    };
    await click("Locais");
    await click("+ Local");
    await fill("name", "Loja teste");
    await fill("capacity_liters", 100);
    await save();
    await click("Itens");
    await click("+ Item");
    await fill("sku", "SKU-TESTE");
    await fill("name", "Produto teste");
    await fill("minimum_quantity", 3);
    await fill("target_quantity", 10);
    await fill("maximum_quantity", 20);
    await fill("volume_liters", 1);
    await fill("supplier", "Fornecedor teste");
    await page
      .locator('[name="preferred_location_id"]')
      .selectOption({ label: "Loja teste" });
    await save();
    await click("Movimentos");
    await click("+ Movimento");
    await page
      .locator('[name="location_id"]')
      .selectOption({ label: "Loja teste" });
    await fill("quantity", 5);
    await fill("cost", 2);
    await fill("reason", "Entrada de teste");
    await save();
    await click("+ Movimento");
    await page.locator('[name="type"]').selectOption("sale");
    await page.locator('[name="position_id"]').selectOption({ index: 1 });
    await fill("quantity", 2);
    await fill("revenue", 10);
    await fill("reason", "Venda de teste");
    await save();
    await click("Visão geral");
    assert.match(await page.locator("#root").innerText(), /R\$\s*6,00/);
    await click("Criar pedido");
    await save();
    await click("Compras");
    await click("Receber");
    await fill("quantity", 2);
    await fill("cost", 2);
    await fill("reason", "Recebimento parcial");
    await save();
    assert.match(await page.locator("#root").innerText(), /7 \/ 2/);
    await page.goto(base + "/#/contador");
    await page
      .getByRole("heading", {
        name: "Contator · assessoria contábil estratégica",
      })
      .waitFor();
    await click("Dados da empresa");
    await fill("name", "Empresa teste");
    await fill("cnpj", "00000000E08G12");
    await save();
    await click("+ Diagnóstico mensal");
    for (const [k, v] of Object.entries({
      revenue_centavos: 10000,
      variable_centavos: 2000,
      fixed_centavos: 1000,
      payroll_centavos: 1000,
      extra_tax_centavos: 0,
      credits_centavos: 0,
      rate_percent: 10,
      source_url: "https://www.gov.br/receitafederal",
      assumptions: "Premissas do teste",
    }))
      await fill(k, v);
    await save();
    assert.match(await page.locator("#root").innerText(), /R\$\s*5\.000,00/);
    await click("Cenários tributários");
    await click("+ Cenário");
    await fill("name", "Simples base");
    for (const [k, v] of Object.entries({
      revenue_centavos: 10000,
      variable_centavos: 2000,
      fixed_centavos: 1000,
      payroll_centavos: 1000,
      extra_tax_centavos: 0,
      credits_centavos: 0,
      rate_percent: 10,
      source_url: "https://www.gov.br/receitafederal",
      assumptions: "Memória do teste",
    }))
      await fill(k, v);
    await save();
    assert.match(
      await page.locator("#root").innerText(),
      /Confirme elegibilidade/,
    );
    await click("Plano de ações");
    await click("+ Ação / obrigação");
    await fill("title", "Revisar CMV");
    await fill("owner", "Contador teste");
    await page.locator('[name="status"]').selectOption("done");
    await fill("amount", 200);
    await page.locator("#module-form button[type=submit]").click();
    await page.locator("#modal-erro:not([hidden])").waitFor();
    assert.match(await page.locator("#modal-erro").innerText(), /evidência/);
    await fill("evidence", "Parecer teste");
    await save();
    await page.evaluate(() => (window.print = () => {}));
    await click("Imprimir dossiê");
    assert.match(
      await page.locator(".module-print").innerText(),
      /Lucro gerencial/,
    );
    await page.evaluate(() => document.querySelector(".module-print").remove());
    const download = page.waitForEvent("download");
    await click("Exportar dossiê JSON");
    const exported = await download;
    assert.equal(exported.suggestedFilename(), "contator-dossie.json");
    const mobile = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    mobile.on("pageerror", (e) => errors.push(e.message));
    await mobile.goto(base + "/#/estoque");
    await mobile
      .getByRole("heading", { name: "Controle de estoque", exact: true })
      .waitFor();
    await mobile.screenshot({
      path: "/tmp/hub-estoque-mobile.png",
      fullPage: true,
    });
    assert.ok(
      await mobile.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      "Layout mobile excede a largura da tela",
    );
    await mobile.goto(base + "/#/contador");
    await mobile
      .getByRole("heading", {
        name: "Contator · assessoria contábil estratégica",
      })
      .waitFor();
    await mobile.screenshot({
      path: "/tmp/hub-contator-mobile.png",
      fullPage: true,
    });
    await page.goto(base + "/?login=1");
    await page.getByRole("heading", { name: "Entrar", exact: true }).waitFor();
    await page.goto(base + "/?denied=1#/estoque");
    await page
      .getByRole("heading", { name: "Acesso negado", exact: true })
      .waitFor();
    assert.deepEqual(errors, []);
    console.log(
      "PASS: interface desktop/mobile, cadastros, entrada/venda, compra parcial, diagnóstico, cenário, plano, evidência, impressão, exportação e login.",
    );
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise((r) => server.close(r));
    await db.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
