// Eczane Stok - Depo Köprüsü (arka plan)
// Toplayıcı (toplayici.ps1 -Asama depo) bilgisayarda 127.0.0.1:47811'de iş açar.
// Eklenti 30 sn'de bir sorar; iş varsa ilgili depo sekmesinde (Sancak / BEK) arama yaptırıp sonucu geri verir.
// Toplayıcı çalışmıyorsa hiçbir şey yapmaz. Hata olursa sessizce bir sonraki turu bekler.
const KOK = "http://127.0.0.1:47811";
const SANCAK = "https://eticaret.sancakecza.com.tr/";
let calisiyor = false;

function alarmKur() { chrome.alarms.create("yokla", { periodInMinutes: 0.5 }); }
chrome.runtime.onInstalled.addListener(alarmKur);
chrome.runtime.onStartup.addListener(alarmKur);
chrome.alarms.onAlarm.addListener(a => { if (a.name === "yokla") { yokla(); sepetYokla(); araYokla(); } });
// Açık depo sekmesi 1,5 sn'de bir "nabız" gönderir: sepet ve arama işlerine 30 sn beklemeden hemen bakılır
let sonNabiz = 0;
chrome.runtime.onMessage.addListener(m => { if (m && m.tip === "nabiz") { const s = Date.now(); if (s - sonNabiz < 1200) return; sonNabiz = s; sepetYokla(); araYokla(); } });

const bekle = ms => new Promise(r => setTimeout(r, ms));

async function isAl() {
  try {
    const r = await fetch(KOK + "/is", { cache: "no-store" });
    if (!r.ok) return null;
    return await r.json();
  } catch { return null; }            // toplayıcı çalışmıyor: normal durum
}
async function bildir(govde) {
  try { await fetch(KOK + "/sonuc", { method: "POST", body: JSON.stringify(govde) }); } catch { }
}

const DEPO = {
  sn:  { desen: "https://eticaret.sancakecza.com.tr/*", adres: "https://eticaret.sancakecza.com.tr/" },
  bek: { desen: "https://esube.bek.org.tr/*",           adres: "https://esube.bek.org.tr/irj/portal/" },
};
async function depoSekmesi(depo, adres) {
  const d = DEPO[depo] || DEPO.sn;
  let t = await chrome.tabs.query({ url: d.desen });
  if (t.length) return t[0];
  const yeni = await chrome.tabs.create({ url: adres || d.adres, active: false, pinned: true });
  await yuklenmesiniBekle(yeni.id);
  if (depo === "bek") await bekle(6000);           // BEK uygulaması çerçevede geç açılır
  return await chrome.tabs.get(yeni.id);
}
async function yuklenmesiniBekle(id, sn = 40) {
  for (let i = 0; i < sn * 2; i++) {
    await bekle(500);
    try { const t = await chrome.tabs.get(id); if (t.status === "complete") { await bekle(2500); return; } } catch { return; }
  }
}
async function sekmeyeSor(id, mesaj) {
  try { return await chrome.tabs.sendMessage(id, mesaj); }
  catch {
    // sekme eklentiden önce açılmışsa içerik betiği yoktur: ekle ve tekrar dene
    await chrome.scripting.executeScript({ target: { tabId: id, allFrames: mesaj.depo === "bek" }, files: [mesaj.depo === "bek" ? "bek.js" : "sancak.js"] });
    await bekle(300);
    return await chrome.tabs.sendMessage(id, mesaj);
  }
}

async function yokla() {
  if (calisiyor) return;
  calisiyor = true;
  try {
    let girisDenendi = false, yenilendi = false;
    for (let tur = 0; tur < 80; tur++) {
      const is = await isAl();
      if (!is || !is.barkodlar || !is.barkodlar.length) return;
      const depo = is.depo || "sn";
      let sekme, c;
      try {
        sekme = await depoSekmesi(depo, is.adres);
        c = await sekmeyeSor(sekme.id, { tip: "ara", depo, barkodlar: is.barkodlar });
      } catch (e) {
        // BEK: oturum anahtarı henüz yakalanmadı (sekme eklentiden önce açılmış) → sekmeyi bir kez yenile
        if (depo === "bek" && !yenilendi && sekme) { yenilendi = true; await chrome.tabs.reload(sekme.id); await yuklenmesiniBekle(sekme.id); await bekle(8000); continue; }
        await bildir({ durum: depo === "bek" ? "giris" : "hata", mesaj: "sekme: " + (e.message || e) }); return;
      }
      if (!c && depo === "bek" && !yenilendi) { yenilendi = true; await chrome.tabs.reload(sekme.id); await yuklenmesiniBekle(sekme.id); await bekle(8000); continue; }
      if (!c) { await bildir({ durum: depo === "bek" ? "giris" : "hata", mesaj: "sekmeden cevap yok" }); return; }
      if (c.durum === "giris") {
        if (depo === "bek" && !yenilendi) { yenilendi = true; await chrome.tabs.reload(sekme.id); await yuklenmesiniBekle(sekme.id); await bekle(8000); continue; }
        // Sancak oturumu düşmüş: kayıtlı bilgiyle bir kez giriş dene
        if (depo === "sn" && is.giris && !girisDenendi) {
          girisDenendi = true;
          try { await sekmeyeSor(sekme.id, { tip: "giris", giris: is.giris }); } catch { }
          await bekle(1500); await yuklenmesiniBekle(sekme.id);
          continue;
        }
        await bildir({ durum: "giris", sonuc: c.sonuc || {} }); return;
      }
      await bildir({ durum: c.durum, mesaj: c.mesaj || "", sonuc: c.sonuc || {} });
      if (c.durum !== "ok") return;
    }
  } finally { calisiyor = false; }
}

// ---- Sepete ekle işleri (toplayıcı 127.0.0.1:47812'de açar). Sadece sepete ekler, siparişi tamamlamaz.
const SEPET = "http://127.0.0.1:47812";
let sepetCalisiyor = false;
async function sepetYokla() {
  if (sepetCalisiyor) return;
  sepetCalisiyor = true;
  try {
    for (let tur = 0; tur < 10; tur++) {
      let is = null;
      try { const r = await fetch(SEPET + "/is", { cache: "no-store" }); if (r.ok) is = await r.json(); } catch { }
      if (!is || !is.kalemler || !is.kalemler.length) return;
      const depo = is.depo; let c = null, sekme = null, yenilendi = false;
      for (let deneme = 0; deneme < 2; deneme++) {
        try {
          sekme = await depoSekmesi(depo);
          c = await sekmeyeSor(sekme.id, { tip: "sepet", depo, kalemler: is.kalemler });
        } catch (e) { c = null; }
        if (c || depo !== "bek" || yenilendi) break;
        yenilendi = true; await chrome.tabs.reload(sekme.id); await yuklenmesiniBekle(sekme.id); await bekle(8000);
      }
      try { await fetch(SEPET + "/sonuc", { method: "POST", body: JSON.stringify(c || { durum: "hata", mesaj: "depo sekmesi cevap vermedi" }) }); } catch { }
    }
  } finally { sepetCalisiyor = false; }
}

// ---- "Depolarda ara" işleri (sitedeki arama; toplayıcı 127.0.0.1:47813'te açar). Sadece arar ve okur.
const ARA = "http://127.0.0.1:47813";
let araCalisiyor = false;
async function araYokla() {
  if (araCalisiyor) return;
  araCalisiyor = true;
  try {
    for (let tur = 0; tur < 6; tur++) {
      let is = null;
      try { const r = await fetch(ARA + "/ara", { cache: "no-store" }); if (r.ok) is = await r.json(); } catch { }
      if (!is || !is.depo) return;
      let c = null, sekme = null, yenilendi = false, girisDenendi = false;
      for (let deneme = 0; deneme < 3; deneme++) {
        try { sekme = await depoSekmesi(is.depo, is.adres); c = await sekmeyeSor(sekme.id, { tip: "araq", depo: is.depo, q: is.q }); } catch (e) { c = null; }
        if (c && c.durum === "giris" && is.depo === "sn" && is.giris && !girisDenendi) {
          girisDenendi = true; try { await sekmeyeSor(sekme.id, { tip: "giris", giris: is.giris }); } catch { }
          await bekle(1500); await yuklenmesiniBekle(sekme.id); continue;
        }
        if ((!c || c.durum === "giris") && is.depo === "bek" && !yenilendi && sekme) { yenilendi = true; await chrome.tabs.reload(sekme.id); await yuklenmesiniBekle(sekme.id); await bekle(8000); continue; }
        break;
      }
      const govde = c ? { depo: is.depo, durum: c.durum, mesaj: c.mesaj || "", u: c.u || [] } : { depo: is.depo, durum: is.depo === "bek" ? "giris" : "hata", mesaj: "depo sekmesi cevap vermedi", u: [] };
      try { await fetch(ARA + "/sonuc", { method: "POST", body: JSON.stringify(govde) }); } catch { }
    }
  } finally { araCalisiyor = false; }
}
