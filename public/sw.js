/* Offline support. Navigations go network-first so a deploy is never served
   stale; hashed assets are cached forever; everything else is
   stale-while-revalidate. Bump VERSION to drop every cache. */

const VERSION = 'v1';
const RUNTIME = `runtime-${VERSION}`;
const OFFLINE_URL = '/offline/';

/* the film's frame sequences are big and only useful online; leave them to
   the HTTP cache instead of doubling them into cache storage */
const SKIP = /^\/film\/(lg|sm|xl|portrait)\//;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(RUNTIME)
      .then((cache) => cache.addAll([OFFLINE_URL]))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== RUNTIME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;
  if (SKIP.test(url.pathname)) return;

  const putCopy = (res) => {
    if (res && res.ok) {
      const copy = res.clone();
      caches.open(RUNTIME).then((cache) => cache.put(req, copy));
    }
    return res;
  };

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then(putCopy)
        .catch(() => caches.match(req).then((hit) => hit || caches.match(OFFLINE_URL))),
    );
    return;
  }

  if (url.pathname.startsWith('/_astro/')) {
    event.respondWith(caches.match(req).then((hit) => hit || fetch(req).then(putCopy)));
    return;
  }

  event.respondWith(
    caches.match(req).then((hit) => {
      const net = fetch(req).then(putCopy).catch(() => hit);
      return hit || net;
    }),
  );
});
