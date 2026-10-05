/* Hub Luh Panda — service worker do app shell.
 *
 * 🔴 A REGRA QUE NÃO PODE QUEBRAR
 * Este SW só toca em arquivo ESTÁTICO DA PRÓPRIA ORIGEM (HTML, CSS, JS, ícone).
 * Resposta do Supabase (PostgREST/RPC, Auth, Storage, Edge Function) NUNCA
 * entra no cache — nem como fallback de offline. Este painel é o lugar onde
 * ela decide quem já pagou e quem vai ser cobrado: abrir o Hub e ver número
 * financeiro velho sem saber que é velho é o pior erro possível aqui.
 * Como isso é garantido, em três camadas:
 *   1. só `GET` passa por aqui — o Supabase-js fala por `POST` nas RPCs;
 *   2. qualquer `url.origin !== location.origin` sai sem ser interceptado;
 *   3. cinto e suspensório: caminho com cara de API é devolvido pra rede
 *      mesmo que um dia o Supabase passe a ser servido da própria origem.
 *
 * ESTRATÉGIA DO SHELL: NETWORK-FIRST com fallback pro cache.
 * É isso que resolve a invalidação do `index.html` de 263 KB — não existe
 * "HTML velho preso no celular" enquanto houver rede, porque online a resposta
 * usada é sempre a recém-publicada no GitHub Pages; o cache só é consultado
 * quando a rede falha. O `VERSION` abaixo é a trava extra: subir a versão
 * apaga todo cache antigo no `activate`.
 *
 * ⬆️ SUBIR `VERSION` quando mudar a LISTA `SHELL` ou a lógica deste arquivo.
 * Não é preciso subir a cada deploy do `index.html` — network-first já cuida.
 *
 * Chave de cache = origem + pathname, com a query string DESCARTADA. Nenhum
 * token que um dia venha por querystring é persistido no Cache Storage.
 *
 * Fora do shell de propósito: o `supabase.js` do cdn.jsdelivr.net. É outra
 * origem, então não é cacheado — ou seja, 100% offline o app abre a casca e
 * para no "sem conexão". Correto: sem Supabase não há nada pra mostrar, e é
 * melhor do que arriscar servir dado antigo.
 */

const VERSION = 'v1';
const SHELL_CACHE = 'hub-shell-' + VERSION;

const SHELL = [
  './',
  './index.html',
  './style.css',
  './config.js',
  './manifest.webmanifest',
  './favicon.ico',
  './assets/favicon.svg',
  './assets/favicon-32.png',
  './assets/panda.svg',
  './assets/apple-touch-icon.png',
  './assets/icon-192.png',
  './assets/icon-512.png',
  './assets/icon-maskable-192.png',
  './assets/icon-maskable-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // add() individual e tolerante: um 404 num ícone não pode derrubar a
    // instalação inteira do SW (addAll() é tudo-ou-nada).
    await Promise.all(SHELL.map((url) => cache.add(url).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const nomes = await caches.keys();
    await Promise.all(
      nomes.filter((n) => n.startsWith('hub-shell-') && n !== SHELL_CACHE)
           .map((n) => caches.delete(n))
    );
    await self.clients.claim();
  })());
});

function chaveDeCache(url) {
  return url.origin + url.pathname;   // sem query string
}

self.addEventListener('fetch', (event) => {
  const req = event.request;

  // (1) Só GET. POST/PATCH (RPC do Supabase) passa direto, sempre.
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (_) { return; }

  // (2) Outra origem (supabase.co, cdn.jsdelivr.net) → rede pura, sem
  //     interceptar. É esta linha que garante dado fresco.
  if (url.origin !== self.location.origin) return;

  // (3) Cinto e suspensório.
  if (/supabase|\/rest\/|\/auth\/|\/storage\/|\/functions\//.test(url.pathname)) return;

  event.respondWith((async () => {
    const cache = await caches.open(SHELL_CACHE);
    const chave = chaveDeCache(url);
    try {
      const fresca = await fetch(req);
      if (fresca && fresca.ok && fresca.type === 'basic') {
        cache.put(chave, fresca.clone());
      }
      return fresca;
    } catch (erro) {
      const guardada = await cache.match(chave);
      if (guardada) return guardada;
      // Navegação offline num caminho que não está no cache: devolve a casca
      // do próprio app (scope), pra tela abrir e o app avisar que está sem
      // conexão. `registration.scope` funciona tanto em /hub-luhpanda/ quanto
      // num domínio próprio na raiz.
      if (req.mode === 'navigate') {
        const fallback = await cache.match(self.registration.scope) ||
                         await cache.match(self.registration.scope + 'index.html');
        if (fallback) return fallback;
      }
      throw erro;
    }
  })());
});
