// Eczane Stok - Depo Köprüsü: Sancak sekmesinde çalışır. Sadece ürün arar (okuma). Sepet/sipariş yok.
(() => {
  if (window.__ezDepoKopru) return;
  window.__ezDepoKopru = true;
  const bekle = ms => new Promise(r => setTimeout(r, ms));

  function dogrulamaVar(doc, metin) {
    if (doc && doc.querySelector('#challenge-form, .cf-turnstile, iframe[src*="challenges.cloudflare.com"], #cf-challenge-running')) return true;
    return /Just a moment|cf-chl|challenge-platform|Checking your browser/i.test(metin || "");
  }
  const girisSayfasi = () => !!document.querySelector('input[type="password"]');

  async function ara(barkodlar) {
    if (dogrulamaVar(document, document.title)) return { durum: "dogrulama" };
    if (girisSayfasi()) return { durum: "giris" };
    const jt = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
    const bas = { "Content-Type": "application/json; charset=utf-8", "X-Requested-With": "XMLHttpRequest" };
    if (jt) { bas["RequestVerificationToken"] = jt; bas["__RequestVerificationToken"] = jt; }
    const sonuc = {}; let hata = 0, sonHata = "";
    for (const b of barkodlar) {
      try {
        const r = await fetch("/Sales/QuickSearchItems", {
          method: "POST", credentials: "include", headers: bas,
          body: JSON.stringify({ Key: b, SearchType: 0, StockType: 0, Page: 1, CacheForCampaign: false, ItemScope: "0" })
        });
        const ct = r.headers.get("content-type") || "";
        if (!ct.includes("json")) {
          const t = await r.text();
          if (dogrulamaVar(null, t)) return { durum: "dogrulama", sonuc };
          if (/type=["']?password/i.test(t) || /login|giris|account/i.test(r.url)) return { durum: "giris", sonuc };
          throw new Error("beklenmeyen cevap " + r.status);
        }
        if (r.status === 401 || r.status === 403) return { durum: "giris", sonuc };
        const j = await r.json();
        const v = j.Value || j.value || j.Items || j.items || (Array.isArray(j) ? j : []);
        sonuc[b] = (Array.isArray(v) ? v : []).slice(0, 3);
        hata = 0;
      } catch (e) {
        hata++; sonHata = String(e.message || e);
        if (hata >= 5) return { durum: "hata", mesaj: sonHata, sonuc };
      }
      await bekle(450);
    }
    return { durum: "ok", sonuc };
  }

  function giris(g) {
    // g: { alanAdi: deger } — toplayıcının şifreli kayıtlı bilgisi (depo.dat). Sadece giriş formunu doldurur.
    const sifre = document.querySelector('input[type="password"]');
    if (!sifre || !g) return false;
    const form = sifre.form || document;
    const yaz = (el, v) => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
      setter.call(el, v); el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true }));
    };
    for (const [ad, v] of Object.entries(g)) {
      const el = form.querySelector(`[name="${CSS.escape(ad)}"]`);
      if (el && el.type !== "hidden") yaz(el, String(v));
    }
    const dugme = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    if (dugme) dugme.click(); else if (form.requestSubmit) form.requestSubmit();
    return true;
  }

  // ---- SEPETE EKLE: ekranda elle yapılanın aynısı (barkodu ara → açılan üründe adet yaz → "Sepete Ekle"). Siparişi tamamlamaz.
  async function bekleKadar(f, sn) { for (let i = 0; i < sn * 4; i++) { const v = f(); if (v) return v; await bekle(250); } return null; }
  const gorunur = e => !!(e && e.offsetParent);
  function yaz(el, v) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    el.focus(); setter.call(el, String(v));
    for (const t of ["input", "keyup", "change"]) el.dispatchEvent(t === "keyup" ? new KeyboardEvent("keyup", { bubbles: true, key: "0" }) : new Event(t, { bubbles: true }));
  }
  async function sepeteEkle(k) {
    const barkod = String(k.barkod).replace(/^0(\d{13})$/, "$1");
    const ara = [...document.querySelectorAll("input")].find(i => /barkod/i.test(i.placeholder || "") && gorunur(i));
    if (!ara) return { tamam: false, mesaj: "Sancak arama kutusu bulunamadı" };
    yaz(ara, barkod);
    const M = await bekleKadar(() => { const x = document.querySelector(".siparis-detay-modal.active"); return x && x.innerText.includes(barkod) ? x : null; }, 15);
    if (!M) return { tamam: false, mesaj: "Sancak'ta ürün açılamadı" };
    const ekle = M.querySelector("button.addtobasket");
    if (!gorunur(ekle)) return { tamam: false, mesaj: "ürün zaten sepette ya da şu an eklenemiyor" };
    const adet = M.querySelector('input[name="ManuelAdet"]');
    if (!adet) return { tamam: false, mesaj: "adet kutusu bulunamadı" };
    yaz(adet, k.adet); await bekle(1800);
    const once = document.documentElement.getAttribute("data-ez-sn-ab") || "";
    ekle.click();
    const son = await bekleKadar(() => { const v = document.documentElement.getAttribute("data-ez-sn-ab") || ""; return v && v !== once ? v : null; }, 15);
    if (!son) return { tamam: false, mesaj: "Sancak cevap vermedi, sepeti kontrol edin" };
    const p = son.split("|"); let j = null; try { j = JSON.parse(p.slice(2).join("|")); } catch { }
    if (j && j.Result) return { tamam: true, mesaj: "" };
    return { tamam: false, mesaj: (j && j.Message) || ("Sancak hata " + p[0]) };
  }
  async function sepet(kalemler) {
    const sonuc = {};
    if (dogrulamaVar(document, document.title)) return { durum: "dogrulama", sonuc };
    if (girisSayfasi()) return { durum: "giris", sonuc };
    for (const k of kalemler) {
      try { sonuc[k.id] = await sepeteEkle(k); } catch (e) { sonuc[k.id] = { tamam: false, mesaj: String((e && e.message) || e) }; }
      const kapat = document.querySelector(".siparis-detay-modal.active .close, .siparis-detay-modal.active [data-dismiss]"); if (kapat) kapat.click();
      await bekle(800);
    }
    return { durum: "ok", sonuc };
  }

  chrome.runtime.onMessage.addListener((m, _s, cevap) => {
    if (m.tip === "sepet" && m.depo === "sn") { sepet(m.kalemler).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) })); return true; }
    if (m.tip === "ara" && (m.depo || "sn") === "sn") { ara(m.barkodlar).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) })); return true; }
    if (m.tip === "giris") { cevap({ tamam: giris(m.giris) }); return false; }
  });
})();
