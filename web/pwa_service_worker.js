'use strict';

const CACHE_NAME = 'abu3meer-pwa-v4';
const APP_SHELL = [
  '/manifest.json',
  '/icons/Abu3meer-64.png',
  '/icons/Abu3meer-192.png',
  '/icons/Abu3meer-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) => Promise.all(
        names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name)),
      )),
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;

  const mustStayFresh = request.mode === 'navigate' ||
    url.pathname === '/index.html' ||
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.wasm') ||
    url.pathname.endsWith('.json') ||
    url.pathname.includes('AssetManifest') ||
    url.pathname.includes('FontManifest');

  if (mustStayFresh) {
    event.respondWith(
      fetch(request, { cache: 'no-store' })
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || caches.match('/index.html'))),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      const refresh = fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
        }
        return response;
      });
      return cached || refresh;
    }),
  );
});
