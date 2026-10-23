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

  // ---- SEPETE EKLE: depo ekranında elle yapılanın aynısı (ürün sayfası → adet → "Siparişe Ekle"). Siparişi tamamlamaz.
  const dugmeBul = () => [...document.querySelectorAll("button")].find(x => /Sipari/i.test(x.textContent) && /Ekle/i.test(x.textContent));
  const adetKutusu = d => [...document.querySelectorAll("input")].filter(i => d && (i.compareDocumentPosition(d) & 4) && /^\d+$/.test(i.value)).pop();
  async function bekleKadar(f, sn) { for (let i = 0; i < sn * 4; i++) { const v = f(); if (v) return v; await bekle(250); } return null; }
  function yaz(el, v) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    el.focus(); setter.call(el, String(v));
    el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key: "0" })); el.blur();
  }
  async function urunSayfasi(matnr, barkod) {
    for (const yol of ["/FrameWorkT1/medicine-detail/", "/FrameWorkT1/non-medicine-detail/"]) {
      history.pushState({}, "", yol + matnr); window.dispatchEvent(new PopStateEvent("popstate", { state: {} }));
      await bekle(1500);
      const d = await bekleKadar(() => { const x = dugmeBul(); return x && document.body.innerText.includes(barkod) ? x : null; }, 10);
      if (d) return d;
    }
    return null;
  }
  async function sepeteEkle(k) {
    const s = await istek("/MainService/api/rfc/mat/sm?ST=" + encodeURIComponent(k.barkod) + "&TYP=3");
    const x = (s && s.ET_MAKTX || [])[0];
    if (!x || !x.MATNR) return { tamam: false, mesaj: "BEK'te ürün bulunamadı" };
    let d = await urunSayfasi(x.MATNR, String(k.barkod).replace(/^0(\d{13})$/, "$1"));
    if (!d) return { tamam: false, mesaj: "ürün sayfası açılamadı" };
    const kutu = adetKutusu(d);
    if (!kutu) return { tamam: false, mesaj: "adet kutusu bulunamadı" };
    yaz(kutu, k.adet); await bekle(1200);
    d = dugmeBul();
    if (!d || d.disabled) return { tamam: false, mesaj: "ürün zaten sepette ya da şu an eklenemiyor" };
    const once = document.documentElement.getAttribute("data-ez-bek-ab") || "";
    d.click();
    const son = await bekleKadar(() => { const v = document.documentElement.getAttribute("data-ez-bek-ab") || ""; return v && v !== once ? v : null; }, 15);
    if (!son) return { tamam: false, mesaj: "BEK cevap vermedi, sepeti kontrol edin" };
    const kod = parseInt(son.split("|")[0], 10);
    return kod >= 200 && kod < 300 ? { tamam: true, mesaj: (d.textContent || "").replace(/\s+/g, " ").trim() } : { tamam: false, mesaj: "BEK hata " + kod };
  }
  async function sepet(kalemler) {
    const sonuc = {};
    for (const k of kalemler) {
      try { sonuc[k.id] = await sepeteEkle(k); } catch (e) { if (e && e.giris) return { durum: "giris", sonuc }; sonuc[k.id] = { tamam: false, mesaj: String((e && e.message) || e) }; }
      await bekle(800);
    }
    return { durum: "ok", sonuc };
  }

  chrome.runtime.onMessage.addListener((m, _s, cevap) => {
    if (m.tip === "sepet" && m.depo === "bek") {
      if (!anahtar().token) return false;
      sepet(m.kalemler).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) }));
      return true;
    }
    if (m.tip !== "ara" || m.depo !== "bek") return false;
    if (!anahtar().token) return false;            // bu çerçevede oturum anahtarı yok: başka çerçeve cevaplasın
    ara(m.barkodlar).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) }));
    return true;
  });
})();
