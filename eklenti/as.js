// Eczane Stok - Depo Köprüsü: AS / Selçuk (webdepo) sekmesinde çalışır. SADECE OKUR.
// Sitenin kendi akışıyla (GetUrunler -> GetIlacDetay) tarayıcı oturumundan sorgular;
// toplayıcı artık doğrudan sunucudan istek atmaz, bu yüzden "robot değilim" (captcha) çıkmaz.
// Sepete ekleme / sipariş YOK. Host'a göre (asecza / selcuk) göreli adres kullanır.
(() => {
  if (window.__ezAsKopru) return;
  window.__ezAsKopru = true;
  const bekle = ms => new Promise(r => setTimeout(r, ms));
  const temizle = b => String(b).replace(/^0(\d{13})$/, "$1");

  function dogrulamaVar(txt) {
    if (document.querySelector('.cf-turnstile, iframe[src*="challenges.cloudflare.com"], #cf-challenge-running, iframe[src*="recaptcha"], .g-recaptcha')) return true;
    return /robot de[ğg]ilim|reCAPTCHA|g-recaptcha|hCaptcha|Just a moment|Checking your browser|challenge-platform/i.test(txt || "");
  }
  const girisSayfasi = () => !!document.querySelector('input[type="password"]');

  let sayfaIsindi = false;
  async function isit() {
    if (sayfaIsindi) return;
    try { await fetch("/Siparis/hizlisiparis.aspx", { credentials: "include", cache: "no-store" }); } catch { }
    sayfaIsindi = true;   // detay isteği bu sayfa oturumda açılmadan "Hata oluştu" döner
  }
  async function post(url, govde) {
    return await fetch(url, {
      method: "POST", credentials: "include",
      headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "X-Requested-With": "XMLHttpRequest" },
      body: new URLSearchParams(govde).toString()
    });
  }
  // JSON cevabı ayıkla; captcha / giriş sayfası gelirse durumu bildir.
  // webdepo ajax ucu JSON'u text/html content-type ile döndürebiliyor → content-type'a bakmadan önce JSON dene (PS tarafı gibi).
  async function jsonAl(r) {
    if (r.status === 401 || r.status === 403) return { durum: "giris" };
    const t = await r.text();
    try { return { durum: "ok", j: JSON.parse(t) }; } catch { }
    if (dogrulamaVar(t)) return { durum: "dogrulama" };
    if (/type=["']?password/i.test(t) || /login|giris|account/i.test(r.url)) return { durum: "giris" };
    return { durum: "hata", mesaj: "beklenmeyen cevap " + r.status };
  }

  async function urunAra(barkod) {
    const r = await post("/Siparis/hizlisiparis-ajax.aspx", { action: "GetUrunler", searchText: temizle(barkod), isInculude: "true", isStoktakiler: "false", siralama: "ilacASC", marka: "", baslangicSayfasi: "0", topRowNum: "0", sayfaMaxRowAdet: "10", s: "s" });
    const a = await jsonAl(r); if (a.durum !== "ok") return a;
    let liste = (a.j && a.j.obj && a.j.obj.urunler) ? a.j.obj.urunler : [];
    // PS tarafı gibi düzleştir (dizi içinde dizi gelebilir)
    const duz = []; for (const x of liste) { if (Array.isArray(x)) { for (const y of x) if (y) duz.push(y); } else if (x) duz.push(x); }
    return { durum: "ok", liste: duz };
  }
  async function urunDetay(e) {
    const r = await post("/Ilac/IlacGetir-ajax.aspx", { action: "GetIlacDetay", kod: e.kodu, isEsdeger: "false", esdeger: "", isJenerik: "false", jenerikId: "", tip: "null", ILACTIP: e.ILACTIP, kampKodu: "" });
    const a = await jsonAl(r); if (a.durum !== "ok") return a;
    return { durum: "ok", obj: (a.j ? a.j.obj : null) };
  }

  // ---- FİYAT TOPLAMA: barkod başına ilk ürünün ham detayını döndürür (PS AsCoz ayıklar)
  async function ara(barkodlar) {
    if (dogrulamaVar(document.title)) return { durum: "dogrulama" };
    if (girisSayfasi()) return { durum: "giris" };
    await isit();
    const sonuc = {}; let hata = 0, sonHata = "";
    for (const b of barkodlar) {
      try {
        const u = await urunAra(b);
        if (u.durum === "dogrulama" || u.durum === "giris") return { durum: u.durum, sonuc };
        if (u.durum === "hata") { hata++; sonHata = u.mesaj; if (hata >= 5) return { durum: "hata", mesaj: sonHata, sonuc }; await bekle(500); continue; }
        const e = (u.liste || [])[0];
        if (e) {
          const d = await urunDetay(e);
          if (d.durum === "dogrulama" || d.durum === "giris") return { durum: d.durum, sonuc };
          if (d.durum === "ok" && d.obj) sonuc[temizle(b)] = [{ s: e.stokDurumu, obj: d.obj }];
        }
        hata = 0;
      } catch (e) { hata++; sonHata = String((e && e.message) || e); if (hata >= 5) return { durum: "hata", mesaj: sonHata, sonuc }; }
      await bekle(500);
    }
    return { durum: "ok", sonuc };
  }

  // ---- DEPOLARDA ARA: ad/barkodla; ilk 8 ürünü fiyat+MF ile hazır döndürür (PS'de pass-through)
  async function araQ(q) {
    if (dogrulamaVar(document.title)) return { durum: "dogrulama" };
    if (girisSayfasi()) return { durum: "giris" };
    await isit();
    const u = await urunAra(q);
    if (u.durum !== "ok") return { durum: u.durum, mesaj: u.mesaj };
    const out = [];
    for (const e of (u.liste || []).slice(0, 8)) {
      let d = null;
      try { const dd = await urunDetay(e); if (dd.durum === "ok") d = dd.obj; } catch { }
      const mf = []; let vade = null;
      if (d) for (const k of (d.kampanyalar || [])) {
        if (vade == null) vade = k.vadeGun;
        const mik = k.miktar || [];
        for (let i = 0; i < mik.length; i++) if (mik[i] > 0) mf.push({ a: mik[i], m: (k.mf || [])[i], n: Math.round((+(k.netFiyati || [])[i]) * 100) / 100, v: k.vadeGun });
      }
      out.push({
        ad: (d && (d.ilacAdi || d.ilacAdı || d.adi)) || e.ilacAdi || e.ilacAdı || e.adi || e.ad || "",
        b: (d && d.barkod) ? String(d.barkod) : (e.barkod || e.barcode || ""),
        d: d ? (+d.depocuFiyati || 0) : 0,
        s: (/^[1-9]/.test(String(e.stokDurumu)) ? 1 : 0),
        v: vade, mf
      });
      await bekle(300);
    }
    return { durum: "ok", u: out };
  }

  // ---- GİRİŞ: oturum düşmüşse kayıtlı bilgiyle giriş formunu doldurur (yalnızca form doldurma)
  function giris(g) {
    const sifre = document.querySelector('input[type="password"]');
    if (!sifre || !g) return false;
    const form = sifre.form || document;
    const yaz = (el, v) => { const s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; s.call(el, v); el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true })); };
    if (g.__sifre !== undefined) {
      const metin = [...form.querySelectorAll('input')].filter(e => e.offsetParent && !["hidden", "password", "checkbox", "radio", "submit", "button"].includes(e.type));
      if (metin[0]) yaz(metin[0], String(g.__kullanici || ""));
      if (metin[1] && g.__ek) yaz(metin[1], String(g.__ek));
      yaz(sifre, String(g.__sifre));
    } else for (const [ad, v] of Object.entries(g)) {
      const el = form.querySelector(`[name="${CSS.escape(ad)}"]`);
      if (el && el.type !== "hidden") yaz(el, String(v));
    }
    const dugme = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    if (dugme) dugme.click(); else if (form.requestSubmit) form.requestSubmit();
    return true;
  }

  chrome.runtime.onMessage.addListener((m, _s, cevap) => {
    if (m.tip === "araq" && m.depo === "as") { araQ(m.q).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) })); return true; }
    if (m.tip === "ara" && m.depo === "as") { ara(m.barkodlar).then(cevap, e => cevap({ durum: "hata", mesaj: String(e) })); return true; }
    if (m.tip === "giris") { cevap({ tamam: giris(m.giris) }); return false; }
  });
})();

// Nabız: arka plana 1,5 sn'de bir haber verir (arama işi beklemesin). Sadece en üst çerçeveden.
(() => {
  if (window.top !== window || window.__ezAsNabiz) return; window.__ezAsNabiz = true;
  const t = setInterval(() => { try { chrome.runtime.sendMessage({ tip: "nabiz" }).catch(() => { }); } catch (e) { clearInterval(t); } }, 1500);
})();
