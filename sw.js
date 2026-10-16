/* Hub — cache apenas da casca estática, separado por escopo.
 * APIs, outras origens e URLs com query nunca entram no handler.
 * O CDN do Supabase fica fora do cache; o boot mostra conexão indisponível
 * sem depender da biblioteca externa. Não há dados financeiros offline.
 * Network-first revalida o HTTP cache; a escrita permanece ligada ao evento.
 */
const VERSION = 'v2';
const CACHE_PREFIX = 'hub-shell-' + encodeURIComponent(self.registration.scope) + '-';
const SHELL_CACHE = CACHE_PREFIX + VERSION;

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

const CORE_SHELL = SHELL.slice(0, 5);
// Arquivos opcionais permitem coexistir com o PR de Estoque/Contator.
const MODULES = ['./modules/domain.js', './modules/ui.js', './modules/modules.css'];
const STATIC_URLS = new Set([...SHELL, ...MODULES].map(path => new URL(path, self.registration.scope).href));

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // Falha no HTML/CSS/config impede ativar uma casca incompleta.
    await cache.addAll(CORE_SHELL);
    await Promise.all(SHELL.slice(5).map(url => cache.add(url).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name => name.startsWith(CACHE_PREFIX) && name !== SHELL_CACHE)
      .map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  // Lista explícita: não basta ter a mesma origem ou parecer arquivo estático.
  if (url.origin !== self.location.origin || url.search || !STATIC_URLS.has(url.href)) return;
  event.respondWith((async () => {
    const cache = await caches.open(SHELL_CACHE);
    try {
      const response = await fetch(req, { cache: 'no-cache' });
      if (response.ok && response.type === 'basic') {
        event.waitUntil(cache.put(url.href, response.clone()).catch(() => {}));
      }
      return response;
    } catch (error) {
      const cached = await cache.match(url.href);
      if (cached) return cached;
      if (req.mode === 'navigate') {
        const fallback = await cache.match(self.registration.scope + 'index.html');
        if (fallback) return fallback;
      }
      throw error;
    }
  })());
});
