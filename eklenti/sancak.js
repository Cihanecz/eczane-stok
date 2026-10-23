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

  chrome.runtime.onMessage.addListener((m, _s, cevap) => {
    if (m.tip === "ara") { ara(m.barkodlar).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) })); return true; }
    if (m.tip === "giris") { cevap({ tamam: giris(m.giris) }); return false; }
  });
})();
