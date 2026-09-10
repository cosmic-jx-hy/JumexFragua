const CACHE_NAME = 'jumex-fragua-v4-offline-1';
const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './jf-icon-192.png',
  './jf-icon-512.png'
];
const SUPABASE_JS = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    for (const url of APP_SHELL) {
      try { await cache.add(url); } catch (_) {}
    }
    try {
      const response = await fetch(SUPABASE_JS, { mode: 'no-cors' });
      await cache.put(SUPABASE_JS, response);
    } catch (_) {}
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const req = event.request;
  const url = new URL(req.url);

  // Nunca cachear API/Auth de Supabase. Offline se resuelve con IndexedDB.
  if (url.hostname.endsWith('.supabase.co')) return;

  // CDN de Supabase JS: cache first para que la app abra offline.
  if (req.url === SUPABASE_JS || url.hostname === 'cdn.jsdelivr.net') {
    event.respondWith((async () => {
      const cached = await caches.match(req);
      if (cached) return cached;
      try {
        const response = await fetch(req);
        const cache = await caches.open(CACHE_NAME);
        await cache.put(req, response.clone());
        return response;
      } catch (_) {
        return cached || Response.error();
      }
    })());
    return;
  }

  // Navegación: network first; si falla, usar index cacheado.
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const response = await fetch(req);
        const cache = await caches.open(CACHE_NAME);
        await cache.put(req, response.clone());
        return response;
      } catch (_) {
        return (await caches.match(req)) || (await caches.match('./index.html')) || (await caches.match('./'));
      }
    })());
    return;
  }

  // Assets locales: stale-while-revalidate.
  if (url.origin === self.location.origin) {
    event.respondWith((async () => {
      const cached = await caches.match(req);
      const network = fetch(req).then(async response => {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(req, response.clone());
        return response;
      }).catch(() => null);
      return cached || await network || Response.error();
    })());
  }
});
