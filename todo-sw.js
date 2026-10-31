/* To Do push service worker */
self.addEventListener("install", ()=>self.skipWaiting());
self.addEventListener("activate", e=>e.waitUntil(self.clients.claim()));
self.addEventListener("push", e=>{
  let d={}; try{ d=e.data.json(); }catch(_){ try{ d={baslik:"Yeni görev", govde:e.data&&e.data.text()||""}; }catch(e2){ d={baslik:"Yeni görev"}; } }
  e.waitUntil(self.registration.showNotification(d.baslik||"Yeni görev",{
    body:d.govde||"", icon:"ikon-192.png", badge:"ikon-192.png", vibrate:[80,40,80], tag:"todo", renotify:true, data:{url:d.url||"./"}
  }));
});
self.addEventListener("notificationclick", e=>{
  e.notification.close();
  e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(cs=>{
    for(const c of cs){ if("focus" in c){ return c.focus(); } }
    if(self.clients.openWindow) return self.clients.openWindow((e.notification.data&&e.notification.data.url)||"./");
  }));
});
