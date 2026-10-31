/* To Do service worker — ağ öncelikli (hep en güncel) + push */
const V = "todo-v2";
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil((async () => {
  const ks = await caches.keys();
  await Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)));
  await self.clients.claim();
})()));
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(
    fetch(e.request).then(r => { const c = r.clone(); caches.open(V).then(cc => cc.put(e.request, c)); return r; })
      .catch(() => caches.match(e.request))
  );
});
self.addEventListener("push", e => {
  let d = {}; try { d = e.data.json(); } catch (_) { try { d = { baslik: "Yeni görev", govde: e.data && e.data.text() || "" }; } catch (e2) { d = { baslik: "Yeni görev" }; } }
  e.waitUntil(self.registration.showNotification(d.baslik || "Yeni görev", {
    body: d.govde || "", icon: "todo-ikon-calisan.png", badge: "todo-ikon-calisan.png", vibrate: [80, 40, 80], tag: "todo", renotify: true, data: { url: d.url || "./" }
  }));
});
self.addEventListener("notificationclick", e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(cs => {
    for (const c of cs) { if ("focus" in c) return c.focus(); }
    if (self.clients.openWindow) return self.clients.openWindow((e.notification.data && e.notification.data.url) || "./");
  }));
});
