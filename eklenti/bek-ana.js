// Eczane Stok - Depo Köprüsü: BEK sayfasının kendi isteklerindeki oturum anahtarını (Token/Sln başlıkları) yakalar.
// Hiçbir istek göndermez, sadece sayfanın gönderdiği başlıkları okur ve sayfaya not eder.
(() => {
  if (window.__ezBekAna) return; window.__ezBekAna = true;
  const not = (ad, deger) => {
    if (!/^(token|sln)$/i.test(ad) || !deger) return;
    try { document.documentElement.setAttribute("data-ez-bek-" + ad.toLowerCase(), String(deger)); } catch { }
  };
  // sepete ekleme isteğinin sonucunu not et (sepet işlemi doğrulaması için)
  const ac = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, url) {
    try { if (/order\/ab\b/.test(String(url))) this.addEventListener("loadend", () => { try { document.documentElement.setAttribute("data-ez-bek-ab", this.status + "|" + Date.now() + "|" + String(this.responseText || "").slice(0, 300)); } catch { } }); } catch { }
    return ac.apply(this, arguments);
  };
  const asil = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function (ad, deger) { not(ad, deger); return asil.apply(this, arguments); };
  const f = window.fetch;
  window.fetch = function (girdi, ayar) {
    try { const h = new Headers((ayar && ayar.headers) || (girdi && girdi.headers) || {}); h.forEach((v, k) => not(k, v)); } catch { }
    return f.apply(this, arguments);
  };
})();
