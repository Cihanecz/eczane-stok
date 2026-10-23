// Eczane Stok - Depo Köprüsü: BEK sekmesinde çalışır. Sadece ürün arar ve ürün kartını okur. Sepet/sipariş yok.
(() => {
  if (window.__ezBekKopru) return; window.__ezBekKopru = true;
  const bekle = ms => new Promise(r => setTimeout(r, ms));
  const anahtar = () => ({ token: document.documentElement.getAttribute("data-ez-bek-token"), sln: document.documentElement.getAttribute("data-ez-bek-sln") });

  async function istek(yol, govde) {
    const a = anahtar();
    const bas = { "Accept": "application/json;charset=utf-8", "Token": a.token };
    if (a.sln) bas["Sln"] = a.sln;
    if (govde !== undefined) bas["Content-Type"] = "application/json;charset=UTF-8";
    const r = await fetch(yol, { method: govde !== undefined ? "POST" : "GET", credentials: "include", headers: bas, body: govde !== undefined ? JSON.stringify(govde) : undefined });
    if (r.status === 401 || r.status === 403) throw { giris: true };
    const ct = r.headers.get("content-type") || "";
    if (!ct.includes("json")) { if (/login|logon/i.test(r.url)) throw { giris: true }; throw new Error("beklenmeyen cevap " + r.status); }
    return r.json();
  }

  async function ara(barkodlar) {
    const sonuc = {}; let hata = 0, sonHata = "";
    for (const b of barkodlar) {
      try {
        const s = await istek("/MainService/api/rfc/mat/sm?ST=" + encodeURIComponent(b) + "&TYP=3");
        const x = (s && s.ET_MAKTX || [])[0];
        if (!x || !x.MATNR) { sonuc[b] = []; }
        else {
          await bekle(250);
          const d = await istek("/MainService/api/rfc/mat/ms?MATNR=" + encodeURIComponent(x.MATNR), {});
          sonuc[b] = [{ sm: { MATNR: x.MATNR, MAKTX: x.MAKTX, PSF: x.PSF, STOK_MEVCUT: x.STOK_MEVCUT }, ms: d }];
        }
        hata = 0;
      } catch (e) {
        if (e && e.giris) return { durum: "giris", sonuc };
        hata++; sonHata = String((e && e.message) || e);
        if (hata >= 5) return { durum: "hata", mesaj: sonHata, sonuc };
      }
      await bekle(400);
    }
    return { durum: "ok", sonuc };
  }

  chrome.runtime.onMessage.addListener((m, _s, cevap) => {
    if (m.tip !== "ara" || m.depo !== "bek") return false;
    if (!anahtar().token) return false;            // bu çerçevede oturum anahtarı yok: başka çerçeve cevaplasın
    ara(m.barkodlar).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) }));
    return true;
  });
})();
