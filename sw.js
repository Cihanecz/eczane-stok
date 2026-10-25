// Sadece uygulama kabuğunu önbelleğe alır; veriler her zaman canlı okunur.
const KABUK = "eczane-stok-v24";
const DOSYALAR = ["./eczane-stok.html", "./manifest.webmanifest", "./ikon.svg", "./ikon-192.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(KABUK).then(c => c.addAll(DOSYALAR))); self.skipWaiting(); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(k => Promise.all(k.filter(x => x !== KABUK).map(x => caches.delete(x))))); self.clients.claim(); });
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(fetch(e.request).then(r => { const k = r.clone(); caches.open(KABUK).then(c => c.put(e.request, k)); return r; })
    .catch(() => caches.match(e.request)));
});
