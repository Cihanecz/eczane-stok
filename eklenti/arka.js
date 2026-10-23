// Eczane Stok - Depo Köprüsü (arka plan)
// Toplayıcı (toplayici.ps1 -Asama depo) bilgisayarda 127.0.0.1:47811'de iş açar.
// Eklenti 30 sn'de bir sorar; iş varsa açık Sancak sekmesinde arama yaptırıp sonucu geri verir.
// Toplayıcı çalışmıyorsa hiçbir şey yapmaz. Hata olursa sessizce bir sonraki turu bekler.
const KOK = "http://127.0.0.1:47811";
const SANCAK = "https://eticaret.sancakecza.com.tr/";
let calisiyor = false;

function alarmKur() { chrome.alarms.create("yokla", { periodInMinutes: 0.5 }); }
chrome.runtime.onInstalled.addListener(alarmKur);
chrome.runtime.onStartup.addListener(alarmKur);
chrome.alarms.onAlarm.addListener(a => { if (a.name === "yokla") yokla(); });

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

async function sancakSekmesi(adres) {
  let t = await chrome.tabs.query({ url: "https://eticaret.sancakecza.com.tr/*" });
  if (t.length) return t[0];
  const yeni = await chrome.tabs.create({ url: adres || SANCAK, active: false, pinned: true });
  await yuklenmesiniBekle(yeni.id);
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
    await chrome.scripting.executeScript({ target: { tabId: id }, files: ["sancak.js"] });
    await bekle(300);
    return await chrome.tabs.sendMessage(id, mesaj);
  }
}

async function yokla() {
  if (calisiyor) return;
  calisiyor = true;
  try {
    let girisDenendi = false;
    for (let tur = 0; tur < 60; tur++) {
      const is = await isAl();
      if (!is || !is.barkodlar || !is.barkodlar.length) return;
      let sekme, c;
      try {
        sekme = await sancakSekmesi(is.adres);
        c = await sekmeyeSor(sekme.id, { tip: "ara", barkodlar: is.barkodlar });
      } catch (e) { await bildir({ durum: "hata", mesaj: "sekme: " + (e.message || e) }); return; }
      if (!c) { await bildir({ durum: "hata", mesaj: "sekmeden cevap yok" }); return; }
      if (c.durum === "giris") {
        // oturum düşmüş: kayıtlı bilgiyle bir kez giriş dene
        if (is.giris && !girisDenendi) {
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
