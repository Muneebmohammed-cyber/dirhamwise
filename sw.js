const V = 'dirhamwise-v1';
const CORE = ['./', './index.html', './manifest.webmanifest', './lib/chart.umd.js', './lib/xlsx.full.min.js', './lib/jspdf.umd.min.js', './lib/jspdf.plugin.autotable.min.js', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(V).then(c => c.addAll(CORE)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const req = e.request; if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (req.mode === 'navigate' || url.pathname.endsWith('/index.html')) { // network first so updates arrive, cache fallback offline
    e.respondWith(fetch(req).then(r => { const cp = r.clone(); caches.open(V).then(c => c.put('./index.html', cp)); return r; }).catch(() => caches.match('./index.html')));
    return;
  }
  e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => { if (r.ok && (url.origin === location.origin || url.hostname.includes('fonts.g'))) { const cp = r.clone(); caches.open(V).then(c => c.put(req, cp)); } return r; })));
});
