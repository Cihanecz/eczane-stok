/* ====================================================================
   TO DO LIST — ortak çekirdek (çalışan + yönetici sayfaları)
   Veri: Supabase 'ayar' tablosu, satır-başına:
     - todo_cfg            : { pin, calisanlar:[{id,ad}], sablonlar:[...] }
     - todo_t_<id>         : tek görev { ... }
   Satır başına yazıldığı için eşzamanlı işaretlemeler birbirini ezmez.
   Yapılandırma: window.TODO_CFG = { rol:'calisan'|'yonetici', kisiId, scURL, scKEY, eczaneAd }
==================================================================== */
(function(){
"use strict";
const CFG = window.TODO_CFG || {};
const sc = supabase.createClient(CFG.scURL, CFG.scKEY);
const $ = s=>document.querySelector(s);
const kacis = s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const bugun0 = ()=>{ const d=new Date(); d.setHours(0,0,0,0); return d; };
function uuid(){ try{return crypto.randomUUID();}catch(e){return "t"+Date.now()+Math.random().toString(36).slice(2,8);} }

/* ---------- tema (renk + açık/koyu, cihazda) ---------- */
const ACCENTLER={yesil:{ad:"Yeşil",renk:"#0F8A5F"},pembe:{ad:"Pembe",renk:"#E0518A"},kirmizi:{ad:"Kırmızı",renk:"#D3433B"},mavi:{ad:"Mavi",renk:"#2B78C8"},mor:{ad:"Mor",renk:"#7A52C4"},turuncu:{ad:"Turuncu",renk:"#D97A1A"}};
const TKEY="todo_tema_"+(CFG.rol||"x")+"_"+(CFG.kisiId||"");
function temaOku(){ try{ return JSON.parse(localStorage.getItem(TKEY))||{}; }catch(e){ return {}; } }
function temaYaz(t){ try{ localStorage.setItem(TKEY, JSON.stringify(t)); }catch(e){} }
function temaUygula(){
  const t=temaOku();
  const acc=ACCENTLER[t.accent]? t.accent : (CFG.rol==="yonetici"?"yesil":"pembe");
  const koyu=!!t.koyu;
  const r=document.documentElement;
  r.dataset.koyu = koyu? "1":"";
  r.style.setProperty("--ana", ACCENTLER[acc].renk);
  r.style.setProperty("--ana-soft", ACCENTLER[acc].renk+"22");
}
function renkSecici(){
  const t=temaOku();
  const acc=ACCENTLER[t.accent]? t.accent : (CFG.rol==="yonetici"?"yesil":"pembe");
  const noktalar=Object.keys(ACCENTLER).map(k=>`<button class="renk-nokta ${acc===k?'sec':''}" title="${ACCENTLER[k].ad}" style="background:${ACCENTLER[k].renk}" onclick="TODO.renkSec('${k}')"></button>`).join("");
  return `<div class="renk-bar">${noktalar}<button class="renk-nokta koyu" title="Açık/Koyu" onclick="TODO.koyuDegis()">${t.koyu?"☀️":"🌙"}</button></div>`;
}

/* ---------- ses (trink) ---------- */
let _ac;
function trink(){
  try{
    _ac=_ac||new (window.AudioContext||window.webkitAudioContext)();
    const o=_ac.createOscillator(), g=_ac.createGain();
    o.type="sine"; o.frequency.value=880;
    g.gain.setValueAtTime(0.0001,_ac.currentTime);
    g.gain.exponentialRampToValueAtTime(0.25,_ac.currentTime+0.01);
    g.gain.exponentialRampToValueAtTime(0.0001,_ac.currentTime+0.35);
    o.connect(g); g.connect(_ac.destination); o.start(); o.stop(_ac.currentTime+0.36);
  }catch(e){}
}
function bildirimGoster(baslik, govde){
  try{ if("Notification" in window && Notification.permission==="granted") new Notification(baslik,{body:govde,icon:"ikon-192.png"}); }catch(e){}
}
/* ---------- push ---------- */
function b64ToU8(s){ const pad="=".repeat((4-s.length%4)%4); const b=(s+pad).replace(/-/g,"+").replace(/_/g,"/"); const raw=atob(b); return Uint8Array.from([...raw].map(c=>c.charCodeAt(0))); }
async function pushAbone(){
  if(!("serviceWorker" in navigator) || !("PushManager" in window)) throw new Error("push-yok");
  const p=await Notification.requestPermission();
  if(p!=="granted") throw new Error("izin-yok");
  const reg=await navigator.serviceWorker.register("todo-sw.js");
  await navigator.serviceWorker.ready;
  let sub=await reg.pushManager.getSubscription();
  if(!sub) sub=await reg.pushManager.subscribe({userVisibleOnly:true, applicationServerKey:b64ToU8(CFG.vapid)});
  const sid="todo_sub_"+kimlik()+"_"+(await sha(JSON.stringify(sub.endpoint))).slice(0,14);
  await sc.from("ayar").upsert({anahtar:sid, deger:JSON.stringify({owner:kimlik(), rol:CFG.rol, sub:sub.toJSON()}), guncelleme:new Date().toISOString()});
}
function pushGonder(hedef, baslik, govde){
  try{ fetch(CFG.scURL+"/functions/v1/todo-push",{method:"POST",headers:{"Content-Type":"application/json","Authorization":"Bearer "+CFG.scKEY,"apikey":CFG.scKEY},body:JSON.stringify({hedef,baslik,govde})}); }catch(e){}
}

/* ---------- veri ---------- */
let CFGV={pin:null,sifreler:{},calisanlar:[],sablonlar:[]};
let GOREVLER=[];
let sonGoruldu = (()=>{ try{ return Number(localStorage.getItem("todo_songor_"+(CFG.kisiId||"x")))||0; }catch(e){ return 0; } })();

async function veriOku(){
  const [c,t]=await Promise.all([
    sc.from("ayar").select("deger").eq("anahtar","todo_cfg").maybeSingle(),
    sc.from("ayar").select("anahtar,deger").like("anahtar","todo_t_%")
  ]);
  if(c && c.data && c.data.deger){ try{ CFGV=Object.assign({pin:null,sifreler:{},calisanlar:[],sablonlar:[]}, JSON.parse(c.data.deger)); }catch(e){} }
  GOREVLER = ((t&&t.data)||[]).map(r=>{ try{ return JSON.parse(r.deger); }catch(e){ return null; } }).filter(Boolean);
}
async function cfgYaz(){ await sc.from("ayar").upsert({anahtar:"todo_cfg",deger:JSON.stringify(CFGV),guncelleme:new Date().toISOString()}); }
async function gorevYaz(g){ await sc.from("ayar").upsert({anahtar:"todo_t_"+g.id,deger:JSON.stringify(g),guncelleme:new Date().toISOString()}); }
async function gorevSilDb(id){ await sc.from("ayar").delete().eq("anahtar","todo_t_"+id); }

/* ---------- tekrar üretimi + oto-arşiv (açılışta) ---------- */
function haftaAnahtar(d){ const t=new Date(d); const gun=(t.getDay()+6)%7; t.setDate(t.getDate()-gun); return t.getFullYear()+"-H"+Math.ceil(((t-new Date(t.getFullYear(),0,1))/864e5+1)/7); }
async function bakimYap(){
  const now=Date.now(); const yazilacak=[];
  // oto-arşiv: yapıldı + 24 saat geçmiş
  for(const g of GOREVLER){ if(g.durum==="yapildi" && g.yapilmaZamani && (now-new Date(g.yapilmaZamani).getTime())>864e5){ g.durum="arsiv"; g.arsivZamani=new Date().toISOString(); yazilacak.push(g); } }
  // tekrar: aktif şablonlar için bu periyodun görevi yoksa üret
  const bg=bugun0();
  for(const s of (CFGV.sablonlar||[])){
    if(!s.aktif) continue;
    let periyot, tarih;
    if(s.tekrar==="gunluk"){ periyot=bg.toISOString().slice(0,10); tarih=periyot; }
    else if(s.tekrar==="haftalik"){ periyot=haftaAnahtar(bg); const t=new Date(bg); const hed=Number(s.gun||1); const fark=((hed-1)-((t.getDay()+6)%7)); t.setDate(t.getDate()+fark); tarih=t.toISOString().slice(0,10); }
    else if(s.tekrar==="aylik"){ periyot=bg.getFullYear()+"-"+(bg.getMonth()+1); const g2=Math.min(Number(s.gun||1),28); tarih=new Date(bg.getFullYear(),bg.getMonth(),g2).toISOString().slice(0,10); }
    else continue;
    const varmi=GOREVLER.some(g=>g.sablonId===s.id && g.periyot===periyot);
    if(!varmi){ const g={id:uuid(),sablonId:s.id,periyot,baslik:s.baslik,aciklama:s.aciklama||"",kime:s.kime,tarih,saat:s.saat||"",durum:"bekliyor",olusturan:"sablon",yapan:null,yapilmaZamani:null,olusturmaZamani:new Date().toISOString()}; GOREVLER.push(g); yazilacak.push(g); }
  }
  for(const g of yazilacak){ try{ await gorevYaz(g); }catch(e){} }
}

/* ---------- yardımcılar ---------- */
function kisiAd(id){ if(id==="genel") return "Genel"; const k=(CFGV.calisanlar||[]).find(x=>x.id===id); return k?k.ad:id; }
function banaAit(g){ if(CFG.rol==="yonetici") return true; return g.kime==="genel" || g.kime===CFG.kisiId; }
function tarihMetin(g){ if(!g.tarih) return ""; const d=new Date(g.tarih+"T"+(g.saat||"00:00")); const bg=bugun0(); const gd=new Date(g.tarih); gd.setHours(0,0,0,0); const fark=Math.round((gd-bg)/864e5); let s= fark===0?"Bugün":fark===1?"Yarın":fark===-1?"Dün":fark<0?(-fark)+" gün gecikti":fark+" gün sonra"; if(g.saat) s+=" "+g.saat; return s; }
function gecikti(g){ if(g.durum!=="bekliyor"||!g.tarih) return false; const d=new Date(g.tarih+"T"+(g.saat||"23:59")); return d.getTime()<Date.now(); }

/* ---------- işlemler ---------- */
async function gorevEkle(o){ const g=Object.assign({id:uuid(),sablonId:null,periyot:null,durum:"bekliyor",yapan:null,yapilmaZamani:null,olusturmaZamani:new Date().toISOString()},o); GOREVLER.push(g); await gorevYaz(g); return g; }
async function gorevYapildi(id, yapan){ const g=GOREVLER.find(x=>x.id===id); if(!g) return; g.durum="yapildi"; g.yapan=yapan; g.yapilmaZamani=new Date().toISOString(); await gorevYaz(g); }
async function gorevGeriAl(id){ const g=GOREVLER.find(x=>x.id===id); if(!g) return; g.durum="bekliyor"; g.yapan=null; g.yapilmaZamani=null; await gorevYaz(g); }
async function gorevArsivle(id){ const g=GOREVLER.find(x=>x.id===id); if(!g) return; g.durum="arsiv"; g.arsivZamani=new Date().toISOString(); await gorevYaz(g); }
async function gorevSil(id){ GOREVLER=GOREVLER.filter(x=>x.id!==id); await gorevSilDb(id); }

function bildirimBanner(){
  let g=false; try{ g=("Notification" in window)&&Notification.permission==="granted"; }catch(e){ g=false; }
  if(g) return "";
  return `<div class="bil-banner" onclick="TODO.bildirimIzin()">🔔 Bildirimleri aç <small>— görev gelince telefonuna haber düşsün</small></div>`;
}

/* ===================== ÇALIŞAN GÖRÜNÜMÜ ===================== */
function calisanEkran(){
  const benim=GOREVLER.filter(g=>banaAit(g));
  const aktif=benim.filter(g=>g.durum==="bekliyor").sort((a,b)=>(a.tarih+(a.saat||"")).localeCompare(b.tarih+(b.saat||"")));
  const yapilan=benim.filter(g=>g.durum==="yapildi").sort((a,b)=>new Date(b.yapilmaZamani)-new Date(a.yapilmaZamani));
  const ad = kisiAd(CFG.kisiId);
  const kart=g=>`<div class="g-kart ${gecikti(g)?'gec':''}">
    <button class="g-check" onclick="TODO.yap('${g.id}')" aria-label="Yapıldı">○</button>
    <div class="g-orta"><div class="g-bas">${kacis(g.baslik)}</div>
      ${g.aciklama?`<div class="g-ack">${kacis(g.aciklama)}</div>`:""}
      <div class="g-alt">${g.kime==="genel"?'<span class="rozet genel">Genel</span>':'<span class="rozet">Bana</span>'}${g.tarih?` · ${kacis(tarihMetin(g))}`:""}${g.sablonId?' · 🔁':""}</div>
    </div></div>`;
  const yKart=g=>`<div class="g-kart yapildi">
    <span class="g-check ok">✓</span>
    <div class="g-orta"><div class="g-bas" style="text-decoration:line-through;opacity:.7">${kacis(g.baslik)}</div>
      <div class="g-alt">${kacis(kisiAd(g.yapan)||"")} yaptı · onay bekliyor</div></div>
    <button class="mini" onclick="TODO.geri('${g.id}')">geri al</button></div>`;
  $("#app").innerHTML=`
  <header class="tbar"><div class="tbar-ic"><div class="tbar-ad">👋 ${kacis(ad)}</div>${renkSecici()}</div>
    <div class="tbar-alt">${kacis(CFG.eczaneAd||"")} · Görevlerim</div></header>
  <main class="twrap">
    ${bildirimBanner()}
    ${aktif.length?`<section><h2>Yapılacaklar <span class="say">${aktif.length}</span></h2>${aktif.map(kart).join("")}</section>`:`<div class="bos">🎉 Bekleyen görevin yok!</div>`}
    <section class="kendi"><button class="ekle-btn" onclick="TODO.kendineEkle()">+ Kendime hatırlatma ekle</button></section>
    ${yapilan.length?`<section><h2 class="sol">Yaptıklarım</h2>${yapilan.map(yKart).join("")}</section>`:""}
    <div class="dip"><button class="mini" onclick="TODO.bildirimIzin()">🔔 Bildirimleri aç</button> <button class="mini" onclick="TODO.sifreDegistir()">🔒 Şifremi değiştir</button></div>
  </main>`;
}

/* ===================== YÖNETİCİ GÖRÜNÜMÜ ===================== */
let yTab="ver";
function yoneticiEkran(){
  const say=k=>`<button class="y-tab ${yTab===k?'sec':''}" onclick="TODO.yTab('${k}')">`;
  const onayBekleyen=GOREVLER.filter(g=>g.durum==="yapildi");
  const bekleyen=GOREVLER.filter(g=>g.durum==="bekliyor");
  let govde="";
  if(yTab==="ver") govde=yVerGovde();
  else if(yTab==="takip") govde=yTakipGovde(bekleyen);
  else if(yTab==="onay") govde=yOnayGovde(onayBekleyen);
  else if(yTab==="calisan") govde=yCalisanGovde();
  else if(yTab==="arsiv") govde=yArsivGovde();
  $("#app").innerHTML=`
  <header class="tbar"><div class="tbar-ic"><div class="tbar-ad">🗂️ Yönetici</div>${renkSecici()}</div>
    <div class="tbar-alt">${kacis(CFG.eczaneAd||"")} · To Do List</div></header>
  <nav class="y-nav">
    ${say("ver")}➕ Görev ver</button>
    ${say("takip")}📋 Takip <span class="say">${bekleyen.length}</span></button>
    ${say("onay")}✅ Onay <span class="say ${onayBekleyen.length?'kirmizi':''}">${onayBekleyen.length}</span></button>
    ${say("calisan")}👥 Çalışanlar</button>
    ${say("arsiv")}🗄️ Arşiv</button>
  </nav>
  <main class="twrap">${bildirimBanner()}${govde}</main>`;
  if(yTab==="ver") yVerBagla();
}
function yVerGovde(){
  const ks=(CFGV.calisanlar||[]).map(k=>`<option value="${k.id}">${kacis(k.ad)}</option>`).join("");
  const bg=new Date().toISOString().slice(0,10);
  return `<section class="form-kutu">
    <label>Başlık<input id="vBas" placeholder="Örn. Buzdolabı ısısını kontrol et"></label>
    <label>Açıklama (ops.)<input id="vAck" placeholder="Detay"></label>
    <div class="ikili">
      <label>Kime<select id="vKime"><option value="genel">Genel (herkes)</option>${ks}</select></label>
      <label>Tekrar<select id="vTekrar" onchange="TODO.tekrarDegis()"><option value="yok">Tekrar yok</option><option value="gunluk">Her gün</option><option value="haftalik">Her hafta</option><option value="aylik">Her ay</option></select></label>
    </div>
    <div class="ikili" id="vGunSatir" style="display:none"><label id="vGunLbl">Gün</label><div id="vGunKutu"></div></div>
    <div class="ikili">
      <label id="vTarihLbl">Tarih<input id="vTarih" type="date" value="${bg}"></label>
      <label>Saat<input id="vSaat" type="time"></label>
    </div>
    <button class="ana-dugme" onclick="TODO.gorevVer()">Görevi ver</button>
    <div id="vDurum" class="durum"></div>
  </section>`;
}
function yVerBagla(){ /* tekrar alanı başlangıç */ }
function yTakipGovde(list){
  list=list.slice().sort((a,b)=>(a.tarih+(a.saat||"")).localeCompare(b.tarih+(b.saat||"")));
  if(!list.length) return `<div class="bos">Bekleyen görev yok.</div>`;
  return list.map(g=>`<div class="g-kart ${gecikti(g)?'gec':''}">
    <div class="g-orta"><div class="g-bas">${kacis(g.baslik)}</div>
      <div class="g-alt"><span class="rozet ${g.kime==='genel'?'genel':''}">${kacis(kisiAd(g.kime))}</span>${g.tarih?` · ${kacis(tarihMetin(g))}`:""}${g.sablonId?' · 🔁':""}</div></div>
    <button class="mini" onclick="TODO.sil('${g.id}')">sil</button></div>`).join("");
}
function yOnayGovde(list){
  list=list.slice().sort((a,b)=>new Date(a.yapilmaZamani)-new Date(b.yapilmaZamani));
  if(!list.length) return `<div class="bos">Onay bekleyen görev yok.</div>`;
  return list.map(g=>`<div class="g-kart onay">
    <div class="g-orta"><div class="g-bas">${kacis(g.baslik)}</div>
      <div class="g-alt"><b>${kacis(kisiAd(g.yapan)||"?")}</b> yaptı · ${kacis(new Date(g.yapilmaZamani).toLocaleString("tr-TR"))}</div></div>
    <div class="onay-btn"><button class="mini yesil" onclick="TODO.arsivle('${g.id}')">✓ Arşivle</button><button class="mini kirmizi" onclick="TODO.geri('${g.id}')">↩ Geri çevir</button></div></div>`).join("");
}
function calisanLink(id){ const taban=location.href.split("?")[0].replace(/[^/]*$/,""); return taban+"todo-calisan.html?k="+encodeURIComponent(id); }
function yCalisanGovde(){
  const ks=(CFGV.calisanlar||[]).map(k=>{ const l=calisanLink(k.id); return `<div class="g-kart" style="flex-direction:column;align-items:stretch;gap:8px">
    <div style="display:flex;justify-content:space-between;align-items:center;gap:10px"><div class="g-bas">${kacis(k.ad)}</div><button class="mini kirmizi" onclick="TODO.calisanSil('${k.id}')">sil</button></div>
    <a href="${kacis(l)}" target="_blank" style="font-size:12px;color:var(--ana);word-break:break-all;background:var(--bg);border:1px solid var(--cizgi);border-radius:8px;padding:9px;text-decoration:none">${kacis(l)}</a>
    <div style="display:flex;gap:6px;flex-wrap:wrap"><button class="mini yesil" onclick="TODO.linkWa('${k.id}')">🟢 WhatsApp ile gönder</button><button class="mini" onclick="TODO.linkKopyala('${k.id}')">📋 Kopyala</button></div>
  </div>`; }).join("");
  return `<section class="form-kutu"><label>Yeni çalışan adı<input id="cAd" placeholder="Örn. Ayşe"></label><button class="ana-dugme" onclick="TODO.calisanEkle()">+ Ekle</button></section>${ks||'<div class="bos">Çalışan yok.</div>'}
  <div class="dip"><button class="mini" onclick="TODO.sifreDegistir()">🔒 Şifremi değiştir</button></div>`;
}
function yArsivGovde(){
  const list=GOREVLER.filter(g=>g.durum==="arsiv").sort((a,b)=>new Date(b.arsivZamani||0)-new Date(a.arsivZamani||0)).slice(0,100);
  if(!list.length) return `<div class="bos">Arşiv boş.</div>`;
  return list.map(g=>`<div class="g-kart yapildi"><div class="g-orta"><div class="g-bas" style="opacity:.75">${kacis(g.baslik)}</div><div class="g-alt">${kacis(kisiAd(g.yapan)||"")} · ${g.arsivZamani?kacis(new Date(g.arsivZamani).toLocaleDateString("tr-TR")):""}</div></div><button class="mini" onclick="TODO.sil('${g.id}')">kalıcı sil</button></div>`).join("");
}

/* ---------- şifre kapısı ---------- */
async function sha(s){ const b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(String(s))); return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join(""); }
function kimlik(){ return CFG.kisiId || "cihan"; }
function kapiAcikMi(){ try{ return localStorage.getItem("todo_kapi_"+kimlik())==="1"; }catch(e){ return false; } }
function kapiAc(){ try{ localStorage.setItem("todo_kapi_"+kimlik(),"1"); }catch(e){} }
function sifreVar(){ return !!(CFGV.sifreler && CFGV.sifreler[kimlik()]); }
function kapiCiz(){
  const olustur=!sifreVar();
  const ad = CFG.rol==="yonetici" ? "Yönetici" : kisiAd(kimlik());
  $("#app").innerHTML=`<div class="pin-kutu"><h2>🔒 ${kacis(ad)}</h2><p>${kacis(CFG.eczaneAd||"")}</p>
    ${olustur?`<p style="font-size:13px;color:var(--soluk)">İlk giriş: kendine bir şifre oluştur.</p>
      <input id="s1" type="password" class="pin-in" placeholder="Yeni şifre">
      <input id="s2" type="password" class="pin-in" placeholder="Şifre (tekrar)">
      <button class="ana-dugme" onclick="TODO.kapiOlustur()">Oluştur ve gir</button>`
    :`<input id="s1" type="password" class="pin-in" placeholder="Şifre" onkeydown="if(event.key==='Enter')TODO.kapiGir()">
      <button class="ana-dugme" onclick="TODO.kapiGir()">Gir</button>`}
    <div id="sHata" class="pin-hata"></div></div>`;
}
function calisanChooser(){
  const ks=(CFGV.calisanlar||[]).filter(k=>k.id!=="cihan").map(k=>`<button class="ana-dugme" style="width:100%;margin-bottom:8px" onclick="location.search='?k=${encodeURIComponent(k.id)}'">${kacis(k.ad)}</button>`).join("");
  $("#app").innerHTML=`<header class="tbar"><div class="tbar-ic"><div class="tbar-ad">👋 Hoş geldin</div></div><div class="tbar-alt">${kacis(CFG.eczaneAd||"")} · To Do List</div></header><main class="twrap"><h2>Sen kimsin?</h2>${ks||'<div class="bos">Çalışan tanımlı değil.</div>'}</main>`;
}

/* ---------- render seçici ---------- */
function ciz(){
  temaUygula();
  if(CFG.rol!=="yonetici" && !CFG.kisiId){ return calisanChooser(); }
  if(!kapiAcikMi()){ return kapiCiz(); }
  if(CFG.rol==="yonetici") yoneticiEkran(); else calisanEkran();
}

/* ---------- canlı yenileme + bildirim ---------- */
async function tazele(sesli){
  const oncekiIds=new Set(GOREVLER.map(g=>g.id));
  await veriOku();
  if(sesli){
    const yeni=GOREVLER.filter(g=>banaAit(g) && g.durum==="bekliyor" && !oncekiIds.has(g.id) && new Date(g.olusturmaZamani).getTime()>sonGoruldu);
    if(yeni.length){ trink(); bildirimGoster("Yeni görev", yeni[0].baslik + (yeni.length>1?` (+${yeni.length-1})`:"")); }
  }
  const el=document.activeElement, tag=el&&el.tagName;
  const yaziyor = (tag==="INPUT"||tag==="TEXTAREA"||tag==="SELECT");
  const formda = (CFG.rol==="yonetici" && yTab==="ver");
  if(yaziyor || formda) return;   // kullanıcı girdi yaparken ekran yenilenmesin (yazdıkları silinmesin)
  ciz();
}

/* ---------- genel API ---------- */
window.TODO={
  renkSec(k){ const t=temaOku(); t.accent=k; temaYaz(t); temaUygula(); ciz(); },
  koyuDegis(){ const t=temaOku(); t.koyu=!t.koyu; temaYaz(t); temaUygula(); ciz(); },
  async yap(id){ await gorevYapildi(id, CFG.kisiId); ciz(); },
  async geri(id){ await gorevGeriAl(id); ciz(); },
  async arsivle(id){ await gorevArsivle(id); ciz(); },
  async sil(id){ if(confirm("Görev silinsin mi?")){ await gorevSil(id); ciz(); } },
  kendineEkle(){
    const b=prompt("Hatırlatma (başlık):"); if(!b) return;
    gorevEkle({baslik:b.trim(),aciklama:"",kime:CFG.kisiId,tarih:new Date().toISOString().slice(0,10),saat:"",olusturan:CFG.kisiId}).then(ciz);
  },
  tekrarDegis(){
    const v=$("#vTekrar").value, sat=$("#vGunSatir"), kutu=$("#vGunKutu"), lbl=$("#vGunLbl"), tl=$("#vTarihLbl");
    if(v==="haftalik"){ sat.style.display=""; lbl.textContent="Haftanın günü"; kutu.innerHTML=`<select id="vGun">${["Pzt","Sal","Çar","Per","Cum","Cmt","Paz"].map((g,i)=>`<option value="${i+1}">${g}</option>`).join("")}</select>`; tl.style.display="none"; }
    else if(v==="aylik"){ sat.style.display=""; lbl.textContent="Ayın günü"; kutu.innerHTML=`<select id="vGun">${Array.from({length:28},(_,i)=>`<option value="${i+1}">${i+1}</option>`).join("")}</select>`; tl.style.display="none"; }
    else { sat.style.display="none"; tl.style.display=""; }
  },
  async gorevVer(){
    const bas=$("#vBas").value.trim(); if(!bas){ $("#vDurum").textContent="Başlık gir."; return; }
    const kime=$("#vKime").value, tekrar=$("#vTekrar").value, ack=$("#vAck").value.trim(), saat=$("#vSaat").value;
    const d=$("#vDurum"); d.textContent="Kaydediliyor…";
    if(tekrar==="yok"){ await gorevEkle({baslik:bas,aciklama:ack,kime,tarih:$("#vTarih").value||new Date().toISOString().slice(0,10),saat,olusturan:"yonetici"}); }
    else { const gun=$("#vGun")?Number($("#vGun").value):1; const s={id:uuid(),baslik:bas,aciklama:ack,kime,tekrar,gun,saat,aktif:true,olusturan:"yonetici",olusturmaZamani:new Date().toISOString()}; CFGV.sablonlar.push(s); await cfgYaz(); await bakimYap(); }
    pushGonder(kime, "Yeni görev", bas);
    d.textContent="Verildi ✓"; $("#vBas").value=""; $("#vAck").value="";
    setTimeout(()=>{ yTab="takip"; ciz(); },700);
  },
  yTab(k){ yTab=k; ciz(); },
  async kapiOlustur(){ const a=$("#s1").value, b=$("#s2").value; const h=$("#sHata"); if(!a||a.length<3){ h.textContent="En az 3 karakter."; return; } if(a!==b){ h.textContent="Şifreler aynı değil."; return; } CFGV.sifreler=CFGV.sifreler||{}; CFGV.sifreler[kimlik()]=await sha(a); try{ await cfgYaz(); }catch(e){ h.textContent="Kaydedilemedi, tekrar dene."; return; } kapiAc(); ciz(); },
  async kapiGir(){ const a=$("#s1").value; const h=await sha(a); if(CFGV.sifreler && CFGV.sifreler[kimlik()]===h){ kapiAc(); ciz(); } else { $("#sHata").textContent="Hatalı şifre."; } },
  async sifreDegistir(){ const eski=prompt("Mevcut şifre:"); if(eski===null) return; if(!CFGV.sifreler||CFGV.sifreler[kimlik()]!==await sha(eski)){ alert("Mevcut şifre hatalı."); return; } const yeni=prompt("Yeni şifre (en az 3 karakter):"); if(yeni===null) return; if(yeni.trim().length<3){ alert("En az 3 karakter."); return; } CFGV.sifreler[kimlik()]=await sha(yeni.trim()); try{ await cfgYaz(); alert("Şifre değiştirildi."); }catch(e){ alert("Kaydedilemedi."); } },
  linkKopyala(id){ const l=calisanLink(id); try{ navigator.clipboard.writeText(l); alert("Link kopyalandı:\n"+l); }catch(e){ prompt("Linki kopyala:", l); } },
  linkWa(id){ const k=(CFGV.calisanlar||[]).find(x=>x.id===id); const l=calisanLink(id); const msg=encodeURIComponent((k?k.ad:"")+" için görev takip (To Do List) linkin:\n"+l+"\n\nAç → Paylaş → Ana Ekrana Ekle, sonra Bildirimleri aç."); window.open("https://wa.me/?text="+msg,"_blank"); },
  async calisanEkle(){ const ad=$("#cAd").value.trim(); if(!ad) return; const id=ad.toLocaleLowerCase("tr").replace(/[^a-z0-9ğüşıöç]/g,"").slice(0,12)+Math.random().toString(36).slice(2,5); CFGV.calisanlar.push({id,ad}); await cfgYaz(); ciz(); },
  async calisanSil(id){ if(!confirm("Çalışan silinsin mi? (görevleri kalır)")) return; CFGV.calisanlar=CFGV.calisanlar.filter(k=>k.id!==id); await cfgYaz(); ciz(); },
  async bildirimIzin(){ try{ await pushAbone(); alert("Bildirimler açıldı ✓ Artık sana görev gelince telefonuna bildirim düşer (uygulama kapalı olsa bile)."); }catch(e){ const m=String(e&&e.message||e); alert(m==="izin-yok"?"Bildirim izni verilmedi.":m==="push-yok"?"Bu tarayıcı push desteklemiyor. iPhone'da önce linki 'Ana Ekrana Ekle' yapıp o ikondan açman gerekiyor.":"Bildirim açılamadı. iPhone'da önce 'Ana Ekrana Ekle' yapıp uygulamadan aç, sonra tekrar dene."); } }
};

/* ---------- başlat ---------- */
(async function(){
  try{ if("serviceWorker" in navigator) navigator.serviceWorker.register("todo-sw.js").catch(()=>{}); }catch(e){}
  try{
    await veriOku();
    // ilk kurulum: çalışan listesi boşsa ve yöneticiysek çekirdek kadro
    if(CFG.rol==="yonetici" && (!CFGV.calisanlar||!CFGV.calisanlar.length) && CFG.ilkKadro){ CFGV.calisanlar=CFG.ilkKadro; await cfgYaz(); }
    await bakimYap();
    ciz();
    try{ sonGoruldu=Date.now(); localStorage.setItem("todo_songor_"+(CFG.kisiId||"x"), String(sonGoruldu)); }catch(e){}
    setInterval(()=>tazele(true), 20000);
    document.addEventListener("visibilitychange",()=>{ if(!document.hidden) tazele(false); });
  }catch(e){ $("#app").innerHTML=`<div class="bos">Bağlantı hatası: ${kacis(e.message||e)}<br><button class="mini" onclick="location.reload()">Tekrar dene</button></div>`; }
})();
})();
