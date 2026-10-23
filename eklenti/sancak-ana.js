// Eczane Stok - Depo Köprüsü: Sancak sayfasının "sepete ekle" isteğinin sonucunu okur (yalnızca not alır, istek göndermez).
(() => {
  if (window.__ezSnAna) return; window.__ezSnAna = true;
  const ac = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, url) {
    try { if (/AddItemToBasket/i.test(String(url))) this.addEventListener("loadend", () => { try { document.documentElement.setAttribute("data-ez-sn-ab", this.status + "|" + Date.now() + "|" + String(this.responseText || "").slice(0, 400)); } catch { } }); } catch { }
    return ac.apply(this, arguments);
  };
})();
