const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function boot({ online = false, authError = false, library = false } = {}) {
  const root = { innerHTML: 'Carregando...' }, listeners = {}, calls = { reload: 0, auth: 0 };
  const context = vm.createContext({
    document: { getElementById: id => id === 'root' ? root : { addEventListener() {} } },
    window: { addEventListener: (name, fn) => listeners[name] = fn,
      location: { reload: () => calls.reload++ } },
    location: { hash: '' }, navigator: { onLine: online }, console, setTimeout, clearTimeout, URL,
  });
  if (library) context.supabase = { createClient: () => ({ auth: {
    getSession: async () => { calls.auth++; if(authError) throw Error('Network failure'); return {data: {session: null}}; },
    onAuthStateChange: () => {},
  } }) };
  vm.runInContext(fs.readFileSync('config.js', 'utf8'), context);
  const html = fs.readFileSync('index.html', 'utf8');
  const main = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)]
    .map(m => m[1]).find(s => s.includes('async function init()'));
  vm.runInContext(main.replace(/^init\(\);$/m, 'globalThis.bootPromise = init();'), context);
  return { context, root, listeners, calls };
}
function worker({ networkFailure = false, delayedPut = false, writeFailure = false, coreFailure = false } = {}) {
  const handlers = {}, saved = new Map(), waits = [], removed = [], fetched = [];
  const scope = 'https://example.test/hub/';
  const prefix = 'hub-shell-' + encodeURIComponent(scope) + '-';
  let finishPut;
  const response = { ok: true, type: 'basic', clone() { return this; } };
  const cache = {
    addAll: async () => { if(coreFailure) throw Error('core unavailable'); },
    add: async () => { throw Error('optional icon unavailable'); },
    put: (key, value) => {
      if(writeFailure) return Promise.reject(Error('quota exceeded'));
      if(delayedPut) return new Promise(resolve => { finishPut = () => {saved.set(key, value);resolve();}; });
      saved.set(key, value); return Promise.resolve();
    }, match: async key => saved.get(key),
  };
  const context = vm.createContext({ URL, encodeURIComponent,
    self: { location: { origin: 'https://example.test' }, registration: {scope},
      addEventListener: (event, fn) => handlers[event] = fn,
      skipWaiting: async () => {}, clients: { claim: async () => {} } },
    caches: { open: async () => cache,
      keys: async () => [prefix+'v1', prefix+'v2', 'another-app-v1'],
      delete: async key => {removed.push(key);return true;} },
    fetch: async (req, options) => { fetched.push({req, options}); if(networkFailure) throw Error('offline');return response; },
  });
  vm.runInContext(fs.readFileSync('sw.js', 'utf8'), context);
  function request(url, method = 'GET', mode = 'cors') {
    let result;
    handlers.fetch({ request: {url, method, mode}, respondWith: p => result = p,
      waitUntil: p => waits.push(p) });
    return result;
  }
  return {scope, handlers, request, waits, removed, fetched, saved, response, finishPut: () => finishPut()};
}

test('Boot offline sem CDN mostra aviso, mantém rota protegida e recupera ao reconectar', async () => {
  const b = boot(); await b.context.bootPromise;
  assert.match(b.root.innerHTML, /Sem conexão/);
  assert.match(b.root.innerHTML, /Tentar novamente/);
  await b.context.render(); assert.match(b.root.innerHTML, /Sem conexão/);
  b.context.navigator.onLine = true; b.listeners.online(); assert.equal(b.calls.reload, 1);
});
test('Boot online trata biblioteca ausente e falha de Auth; sessão normal abre login', async () => {
  for(const options of [{online: true}, {online: true, library: true, authError: true}]) {
    const b = boot(options); await b.context.bootPromise;
    assert.match(b.root.innerHTML, /Conexão indisponível/);
  }
  const b = boot({online: true, library: true}); await b.context.bootPromise;
  assert.match(b.root.innerHTML, /Link mágico/); assert.equal(b.calls.auth, 1);
  b.listeners.online(); assert.equal(b.calls.reload, 0);
});
test('SW limita cache a arquivos estáticos, excluindo APIs, query, outra origem e POST', async () => {
  const w = worker({delayedPut: true});
  for(const url of [w.scope+'?code=example', w.scope+'index.html?token=example', w.scope+'data',
    'https://example.test/other/config.js', w.scope+'rest/v1/data', 'https://cdn.example.test/lib.js'])
    assert.equal(w.request(url), undefined);
  assert.equal(w.request(w.scope+'index.html', 'POST'), undefined);
  assert.equal(await w.request(w.scope+'index.html'), w.response);
  assert.equal(w.saved.size, 0); assert.equal(w.waits.length, 1);
  assert.equal(w.fetched[0].options.cache, 'no-cache');
  w.finishPut(); await Promise.all(w.waits); assert.equal(w.saved.size, 1);
});
test('SW mantém resposta online mesmo se cache falha e abre casca estática offline', async () => {
  const online = worker({writeFailure: true});
  assert.equal(await online.request(online.scope+'style.css'), online.response);
  await Promise.all(online.waits);
  const offline = worker({networkFailure: true});
  const html = {body: 'cached shell'}; offline.saved.set(offline.scope+'index.html', html);
  assert.equal(await offline.request(offline.scope, 'GET', 'navigate'), html);
  assert.equal(offline.request(offline.scope+'private', 'GET', 'navigate'), undefined);
});
test('SW remove apenas versões antigas do cache do próprio escopo', async () => {
  const w = worker(); let done;
  w.handlers.activate({waitUntil: p => done = p}); await done;
  assert.equal(w.removed.length, 1); assert.match(w.removed[0], /-v1$/);
  assert.ok(!w.removed.includes('another-app-v1'));
});
test('SW não ativa sem arquivos essenciais; ícone opcional ausente não impede instalação', async () => {
  for(const failing of [true, false]) {
    const w = worker({coreFailure: failing}); let done;
    w.handlers.install({waitUntil: p => done = p});
    if(failing) await assert.rejects(done, /core unavailable/); else await done;
  }
});
