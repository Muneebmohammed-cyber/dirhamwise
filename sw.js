const V = 'dirhamwise-2026-11-15b';
const CORE = ['./', './index.html', './manifest.webmanifest', './lib/chart.umd.js', './lib/xlsx.full.min.js', './lib/jspdf.umd.min.js', './lib/jspdf.plugin.autotable.min.js', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(V).then(c => c.addAll(CORE.map(u => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const req = e.request; if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (req.mode === 'navigate' || url.pathname.endsWith('/index.html') || url.pathname.endsWith('/manifest.webmanifest')) {
    // always fetch the newest app (skip the browser's HTTP cache), fall back to the saved copy offline
    e.respondWith(fetch(req, { cache: 'no-store' }).then(r => { if (r.ok && req.mode === 'navigate') { const cp = r.clone(); caches.open(V).then(c => c.put('./index.html', cp)); } return r; }).catch(() => caches.match(req.mode === 'navigate' ? './index.html' : req)));
    return;
  }
  e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => { if (r.ok && (url.origin === location.origin || url.hostname.includes('fonts.g'))) { const cp = r.clone(); caches.open(V).then(c => c.put(req, cp)); } return r; })));
});
