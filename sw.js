// Service worker: gör att appen kan läggas på hemskärmen/skrivbordet. Hämtar alltid från nätet först
// (så att nya versioner syns direkt) och använder sparade filer bara när nätet saknas.
// Bara appens egna filer cachas – inte data från Supabase eller kartrutor.
const CACHE = 'hitochdit-v1';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(
  caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
));
self.addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== self.location.origin) return;
  e.respondWith(fetch(e.request).then((svar) => {
    if (svar.ok) { const kopia = svar.clone(); caches.open(CACHE).then((c) => c.put(e.request, kopia)); }
    return svar;
  }).catch(() => caches.match(e.request).then((m) => m || caches.match('./'))));
});
