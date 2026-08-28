/* Offline support. Navigations go network-first so a deploy is never served
   stale; hashed assets are cached forever; everything else is
   stale-while-revalidate. Bump VERSION to drop every cache. */

const VERSION = 'v2';
const RUNTIME = `runtime-${VERSION}`;
const OFFLINE_URL = '/offline/';

/* the film's frame sequences, the 3D models and the mesh decoder are big and
   only useful online; leave them to the HTTP cache instead of doubling them
   into cache storage */
const SKIP = /^\/film\/(lg|sm|xl|portrait)\/|\.glb$|^\/draco\//;

/* every page worth reading in a basement with no signal, plus the posters
   the homepage falls back to. the frame sequences stay online-only. */
const CORE = [
  OFFLINE_URL,
  '/',
  '/work/',
  '/work/datum/',
  '/work/photography/',
  '/lab/',
  '/lab/keepsake/',
  '/lab/field/',
  '/film/poster.webp',
  '/film/poster-end.webp',
  '/film/poster-portrait.webp',
  '/film/poster-end-portrait.webp',
  '/site.webmanifest',
  '/favicon.svg',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(RUNTIME)
      .then((cache) => cache.addAll(CORE))
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
