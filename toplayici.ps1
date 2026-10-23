# =====================================================================
#  ECZANE STOK — Rx toplayıcı
#  Rx'te SADECE rapor ekranlarını açar, Sorgula / Yazdır önizleme /
#  Dışa Aktar kullanır. Kayıt değiştiren hiçbir düğmeye basmaz.
# =====================================================================
param(
  [string]$Asama = "hepsi",          # envanter | stokdokum | satis | alis | hepsi
  [string]$Bas = "",                 # satış/alış başlangıç tarihi gg.aa.yyyy
  [string]$Bit = "",                 # bitiş tarihi
  [switch]$Kesif,                    # yeni açılan pencerelerin yapısını kaydet
  [switch]$Kur                       # bir kerelik: bulut giriş bilgisini kaydet
  ,[switch]$HastaKur                 # bir kerelik: hasta şifresini bu bilgisayara kaydet
  ,[switch]$DepoKur                  # bir kerelik: depo kullanıcı adı/şifresini bu bilgisayara kaydet
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class W2 {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static void MesajTik(IntPtr h, int x, int y) { IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF)); PostMessage(h, 0x201, (IntPtr)1, lp); System.Threading.Thread.Sleep(60); PostMessage(h, 0x202, IntPtr.Zero, lp); }
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static void Tik(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(80); mouse_event(2,0,0,0,IntPtr.Zero); mouse_event(4,0,0,0,IntPtr.Zero); }
  public static void SagTik(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(80); mouse_event(8,0,0,0,IntPtr.Zero); mouse_event(16,0,0,0,IntPtr.Zero); }
}
"@

$KOK   = "C:\EczaneStok"
$SB_URL = "https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY = "sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS  = Join-Path $KOK "giris.dat"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$VERI  = Join-Path $KOK "veri"
$GUNLUK = Join-Path $KOK "gunluk.txt"
New-Item -ItemType Directory -Force -Path $VERI | Out-Null
$DURDUR = Join-Path $KOK "durdur.flag"
function Log($m) { $s = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $m; Add-Content -Path $GUNLUK -Value $s -Encoding UTF8; Write-Host $s
  if ((Test-Path $DURDUR) -and $m -notlike "HATA*") { Remove-Item $DURDUR -Force -ErrorAction SilentlyContinue; throw "Kullanıcı Durdur'a bastı." } }

$A  = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]

# ---------- konumlar (Rx ekranı tam ekran açıkken, ekran pikseli) ----------
$K = @{
  RaporlarSekme   = @(1245, 56)
  SatisRaporlari  = @(49, 127);   UrunBazliSatis = @(128, 200)
  UrunHareket     = @(156, 127);  UrunBazliAlis  = @(205, 202)
  AlisTarihBas    = @(356, 274);  AlisTarihBit   = @(514, 274);  AlisSorgula = @(1212, 360)
  SatisTarihBas   = @(356, 280);  SatisTarihBit  = @(514, 280);  SatisSorgula = @(1059, 348)
  HastaRap        = @(758, 119);  RaporuBiten    = @(854, 170);  IlaciBiten = @(854, 202)
  IlacBitBas      = @(463, 300);  IlacTurOk      = @(1282, 305); IlacRaporlu = @(908, 347);  IlacRaporsuz = @(908, 369);  IlacSorgula = @(790, 422)
  IlacTumu        = @(251, 468);  IlacSag        = @(1436, 600);  RaporTumu = @(252, 402);  RaporSag = @(1050, 600)
  RaporSorgula    = @(1166, 362)
  EnvanterRap     = @(258, 127);  GenelEnvanter  = @(332, 174);  UrunDokum = @(332, 203);  StokDokum = @(332, 233);  GenelKarekod = @(332, 352)
}

# Ekran ölçeği: konumlar %125 (120 DPI) ekranda alındı; başka ölçekte orantılı kaydırılır. C:\EczaneStok\olcek.txt varsa o kullanılır.
$EO = 1.0
try { $dpi = [int](Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction Stop).AppliedDPI; if ($dpi -gt 0) { $EO = $dpi / 120.0 } } catch { }
$OLCEK = Join-Path $KOK "olcek.txt"; if (Test-Path $OLCEK) { $EO = [double]::Parse((Get-Content $OLCEK -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture) }

# ---------- pencere yardımcıları ----------
function RxSureci { $p = Get-Process -Name "RxMediaPharmaEYS" -ErrorAction SilentlyContinue | Select-Object -First 1; if (-not $p) { throw "Rx açık değil." }; $p }
function Pencereler([int]$procId) {
  $liste = New-Object System.Collections.ArrayList
  $cb = [W2+EnumProc]{ param($h,$l) $p=0; [void][W2]::GetWindowThreadProcessId($h,[ref]$p)
        if ($p -eq $procId -and [W2]::IsWindowVisible($h)) { $sb = New-Object System.Text.StringBuilder 256; [void][W2]::GetWindowText($h,$sb,256); [void]$liste.Add([pscustomobject]@{H=$h;Ad=$sb.ToString()}) }; $true }.GetNewClosure()
  [void][W2]::EnumWindows($cb, [IntPtr]::Zero); $liste
}
function PencereBekle([int]$procId, [scriptblock]$kosul, [int]$sn = 30, [string]$ne = "pencere") {
  $son = (Get-Date).AddSeconds($sn)
  while ((Get-Date) -lt $son) { $w = Pencereler $procId | Where-Object $kosul | Select-Object -First 1; if ($w) { return $w }; Start-Sleep -Milliseconds 300 }
  throw "$ne açılmadı ($sn sn)."
}
function Dikdortgen($h) { $r = New-Object W2+RECT; [void][W2]::GetWindowRect($h,[ref]$r); $r }
function Kesfet($h, $etiket) {
  if (-not $Kesif) { return }
  $el = $A::FromHandle($h); $sb = New-Object System.Text.StringBuilder
  $yur = [System.Windows.Automation.TreeWalker]::ControlViewWalker; $n = 0
  function Y($e,$d) { if ($script:n -gt 3000 -or $d -gt 12) {return}; $script:n++
    $c=$e.Current; $t=$c.ControlType.ProgrammaticName -replace "ControlType\.",""; $r=$c.BoundingRectangle
    $ad=$c.Name; if($t -in @("DataGrid","Table","DataItem","Document")){$ad="(içerik yazılmadı)"}
    $kon = if ($r.IsEmpty -or [double]::IsInfinity($r.X)) { "-" } else { "$([int]$r.X),$([int]$r.Y),$([int]$r.Width)x$([int]$r.Height)" }
    [void]$sb.AppendLine(("  "*$d)+"[$t] '$ad' id='$($c.AutomationId)' konum=$kon")
    if($t -in @("DataGrid","Table","DataItem","Document")){return}
    $k=$yur.GetFirstChild($e); while($k -ne $null){ Y $k ($d+1); $k=$yur.GetNextSibling($k) } }
  Y $el 0
  $sb.ToString() | Out-File (Join-Path $KOK ("kesif-" + $etiket + ".txt")) -Encoding utf8
}
# Ada göre ekranda GÖRÜNEN öğeyi bulur; tabloların içine girmez (hem hızlı hem hasta verisine dokunmaz)
$script:ATLA = @("DataGrid","Table","DataItem","Tree","List","Document")
function AgacAra($el, [string]$ad, [int]$derin) {
  if ($derin -gt 16) { return $null }
  $yur = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $k = $yur.GetFirstChild($el)
  while ($k -ne $null) {
    try {
      $c = $k.Current
      if ($c.Name -eq $ad -and -not $c.IsOffscreen -and $c.BoundingRectangle.Width -gt 0) { return $k }
      $tip = $c.ControlType.ProgrammaticName -replace "ControlType\.",""
      if ($script:ATLA -notcontains $tip -and -not $c.IsOffscreen) { $s = AgacAra $k $ad ($derin + 1); if ($s) { return $s } }
    } catch { }
    $k = $yur.GetNextSibling($k)
  }
  return $null
}
function Bul($kokEl, [string]$ad, [int]$sn = 15) {
  $son = (Get-Date).AddSeconds($sn); $t0 = Get-Date
  while ((Get-Date) -lt $son) { $e = AgacAra $kokEl $ad 0; if ($e) { Log ("  '{0}' {1:N1} sn'de bulundu" -f $ad, ((Get-Date)-$t0).TotalSeconds); return $e }; Start-Sleep -Milliseconds 500 }
  throw "'$ad' bulunamadı."
}
$script:ON = [IntPtr]::Zero   # tıklamadan önce öne alınacak pencere
function OneAl { if ($script:ON -ne [IntPtr]::Zero) { [void][W2]::SetForegroundWindow($script:ON); Start-Sleep -Milliseconds 250 } }
# Düğmeye doğrudan pencere mesajıyla tıklar (üstte başka pencere/bildirim olsa da doğru düğmeye gider)
function ElTikla($e) {
  $c = $e.Current; $r = $c.BoundingRectangle; $h = [IntPtr]$c.NativeWindowHandle
  if ($h -ne [IntPtr]::Zero) { [W2]::MesajTik($h, [int]($r.Width/2), [int]($r.Height/2)) }
  else { OneAl; [W2]::Tik([int]($r.X + $r.Width/2), [int]($r.Y + $r.Height/2)) }
}
function K($ad) { OneAl; [W2]::Tik([int]($K[$ad][0]*$EO), [int]($K[$ad][1]*$EO)); Start-Sleep -Milliseconds 900 }
function Tus($t) { [System.Windows.Forms.SendKeys]::SendWait($t); Start-Sleep -Milliseconds 250 }

function RxOne($p) {
  foreach ($w in (Pencereler $p.Id | Where-Object { $_.Ad -in @("Duyuru","Veritabanı Yedekleme") })) { [void][W2]::SendMessage($w.H, 0x10, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Milliseconds 800; Log "Rx duyurusu kapatıldı" }
  $h = AnaPencere $p
  [void][W2]::ShowWindow($h, 3)          # tam ekran
  [void][W2]::SetForegroundWindow($h); Start-Sleep -Milliseconds 600
  $script:ON = $h
  $A::FromHandle($h)
}

# Sorgu sonrası Rx'in rahatlamasını bekler (Filtreleme kapanır, Rx yanıt verir hâle gelir)
function YuklemeBekle($p, [int]$sn = 600) {
  $son = (Get-Date).AddSeconds($sn); Start-Sleep 3; $sakin = 0
  while ((Get-Date) -lt $son) {
    $p.Refresh()
    $acik = Pencereler $p.Id | Where-Object { $_.Ad -in @("Filtreleme","Lütfen Bekleyiniz") -or $_.Ad -like "*Bekley*" }
    if ($p.Responding -and -not $acik) { $sakin++ } else { $sakin = 0 }
    if ($sakin -ge 4) { Log "Rapor yüklendi"; return $A::FromHandle((AnaPencere $p)) }
    Start-Sleep -Milliseconds 700
  }
  throw "Rapor $sn saniyede yüklenmedi."
}
function AnaPencere($p) { (Pencereler $p.Id | Where-Object { $_.Ad -eq "RxMediaPharma Eczane Yönetim Sistemi" } | Select-Object -First 1).H }

# ---------- rapor açma ----------
function MenuYuk($p) { $en = 99999; foreach ($w in (Pencereler $p.Id | Where-Object { $_.Ad -eq "" })) { $r = Dikdortgen $w.H; $y = $r.B - $r.T; if ($r.T -lt 400 -and $r.L -lt 1000 -and $y -gt 10 -and $y -lt $en) { $en = $y } }; $en }
function MenuAc($p, $grup) { $h0 = MenuYuk $p; for ($j = 0; $j -lt 2 -and $h0 -ge 99999; $j++) { Log "  menü açılmadı, tekrar deneniyor"; K "RaporlarSekme"; K $grup; $h0 = MenuYuk $p }; if ($h0 -ge 99999) { throw "Rapor menüsü açılmadı." }; for ($i = 0; $i -lt 4; $i++) { Tus "^{DOWN}"; Start-Sleep -Milliseconds 400; $h1 = MenuYuk $p; if ($h1 -ge 99999) { K $grup; $h0 = MenuYuk $p; continue }; if ($h1 -gt $h0) { break }; if ($h1 -lt $h0) { $h0 = $h1 } } }   # kısaltılmış (son kullanılanlar) menüyü tam listeye açar
function RaporAc($p, [string]$grup, [string]$oge, [string]$baslik) {
  $rx = RxOne $p
  K "RaporlarSekme"; K $grup; MenuAc $p $grup; K $oge
  Log "Rapor açılıyor: $baslik"
}

# Yazdır önizlemesinden CSV'ye aktar
function OnizlemedenCsv($p, $rx, [string]$dosya, [scriptblock]$ac = $null) {
  if (Test-Path $dosya) { Remove-Item $dosya -Force }
  $once = @(Pencereler $p.Id | ForEach-Object { $_.H })
  if (-not $ac) {
  Log "Yazdır düğmesi aranıyor"
  $yz = Bul $rx "Yazdır" 20
  $rr = $yz.Current.BoundingRectangle
  Log ("Yazdır bulundu: {0},{1} {2}x{3} — tıklanıyor" -f [int]$rr.X,[int]$rr.Y,[int]$rr.Width,[int]$rr.Height)
  }
  # Gerçek fare tıklaması: arkadaki sekmelerde aynı yerde duran gizli "Yazdır" düğmelerine değil, görünene basılır
  $yeni = { Pencereler $p.Id | Where-Object { $_.Ad -in @("Yazdır","Preview","Önizleme") -and $once -notcontains $_.H } | Select-Object -First 1 }
  $on = $null
  for ($deneme = 1; $deneme -le 3 -and -not $on; $deneme++) {
    if ($ac) { if ($deneme -le 2) { [void][W2]::ShowWindow($script:ON, 3); OneAl; & $ac } else { break } }
    elseif ($deneme -le 2) { [void][W2]::ShowWindow($script:ON, 3); OneAl; [W2]::Tik([int]($rr.X + $rr.Width/2), [int]($rr.Y + $rr.Height/2)) }
    else { Log "  fareyle açılmadı, doğrudan düğmeye basılıyor"; ElTikla $yz }
    Log "Önizleme bekleniyor (deneme $deneme)"
    $son = (Get-Date).AddSeconds($(if ($deneme -lt 3) { 25 } else { 300 }))
    while (-not $on -and (Get-Date) -lt $son) {
      $on = & $yeni
      # önizleme hazırlanırken Rx meşgulse beklemeye devam et
      if (-not $on) { $p.Refresh(); if (-not $p.Responding) { $son = $son.AddSeconds(1) }; Start-Sleep -Milliseconds 500 }
    }
  }
  if (-not $on) { throw "Yazdır önizlemesi açılmadı." }
  # Önizlemeyi ekranı kaplayacak şekilde yerleştir (tam ekran komutu her zaman çalışmıyor)
  for ($i = 0; $i -lt 5; $i++) {
    [void][W2]::ShowWindow($on.H, 9); Start-Sleep -Milliseconds 400
    [void][W2]::MoveWindow($on.H, 0, 0, 1920, 1040, $true); Start-Sleep -Milliseconds 400
    [void][W2]::SetForegroundWindow($on.H); Start-Sleep -Milliseconds 600
    $r = Dikdortgen $on.H
    if ($r.L -le 0 -and $r.R -ge 1900) { break }
  }
  Start-Sleep 2
  Kesfet $on.H "onizleme"
  $r = Dikdortgen $on.H
  Log ("Önizleme penceresi: {0},{1} - {2},{3}" -f $r.L,$r.T,$r.R,$r.B)

  # --- Dışa Aktar oku → CSV (konumlar pencerenin sağ-üst köşesine göre) ---
  $script:ON = $on.H
  if ($on.Ad -ne "Yazdır") { $okX = $r.R - 316; $okY = [Math]::Max($r.T, 0) + 92; $csvX = 60; $csvY = 346 }   # DevExpress "Preview" (ızgaradan dışa aktar)
  elseif ($EO -lt 0.9) { $okX = $r.R - 225; $okY = [Math]::Max($r.T, 0) + 113; $csvX = 32; $csvY = 342 } else { $okX = $r.R - 183; $okY = [Math]::Max($r.T, 0) + 97; $csvX = 52; $csvY = 420 }
  $KN = Join-Path $KOK $(if ($on.Ad -ne "Yazdır") { "disaaktar-izgara.txt" } else { "disaaktar.txt" }); if (Test-Path $KN) { $v = (Get-Content $KN -Raw).Trim().Split(","); $okX = $r.R - [int]$v[0]; $okY = [Math]::Max($r.T, 0) + [int]$v[1]; $csvX = [int]$v[2]; $csvY = [int]$v[3] }
  Log "Dışa aktar oku: $okX,$okY"
  OneAl; [W2]::Tik($okX, $okY); Start-Sleep -Milliseconds 1200
  [void][W2]::SetCursorPos($okX + $csvX, $okY + $csvY); Start-Sleep -Milliseconds 500
  OneAl; [W2]::Tik($okX + $csvX, $okY + $csvY); Start-Sleep -Milliseconds 1500
  $ayar = PencereBekle $p.Id { $_.Ad -like "*Dışa Aktarma Ayarları*" } 15 "Dışa aktarma ayarları"
  Log ("Açılan pencere: " + $ayar.Ad)
  if ($ayar.Ad -notlike "CSV*") { [void][W2]::SendMessage($ayar.H, 0x10, [IntPtr]::Zero, [IntPtr]::Zero); throw ("CSV yerine '" + $ayar.Ad + "' açıldı, iptal edildi.") }
  Kesfet $ayar.H "csv-ayar"
  [void][W2]::SetForegroundWindow($ayar.H); Start-Sleep -Milliseconds 400; Tus "{ENTER}"
  $kay = PencereBekle $p.Id { $_.Ad -in @("Save As","Farklı Kaydet","Kaydet") } 20 "Kaydet penceresi"
  Kesfet $kay.H "kaydet"
  Remove-Item $dosya -ErrorAction SilentlyContinue
  $ke = $A::FromHandle($kay.H)
  $kos = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, "1001")),
    (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)))
  $ad = $ke.FindFirst($TS::Descendants, $kos)
  $yazildi = $false
  if ($ad) { try { $ad.SetFocus(); $vp = $ad.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); $vp.SetValue($dosya); $yazildi = $true } catch { Log ("  değer yazılamadı: " + $_.Exception.Message) } }
  if (-not $yazildi) { [void][W2]::SetForegroundWindow($kay.H); Start-Sleep -Milliseconds 300; Tus "^a"; try { [System.Windows.Forms.Clipboard]::SetText($dosya); Tus "^v" } catch { Tus $dosya } }   # panodan: Caps Lock açık olsa da doğru yazılır
  Log "Dosya adı yazıldı: $dosya"
  Start-Sleep -Milliseconds 400; [void][W2]::SetForegroundWindow($kay.H); Start-Sleep -Milliseconds 300; Tus "{ENTER}"
  Log "Kaydediliyor: $dosya"
  $son = (Get-Date).AddSeconds(600)
  while ((Get-Date) -lt $son) {
    $soru = Pencereler $p.Id | Where-Object { $_.Ad -like "*Aktar*" -and $_.Ad -notlike "*Ayarları*" } | Select-Object -First 1
    if ($soru) { Kesfet $soru.H "acsoru"; $se = $A::FromHandle($soru.H); try { ElTikla (Bul $se "Hayır" 5) } catch { [void][W2]::SetForegroundWindow($soru.H); Tus "{ESC}" }; break }
    if ((Test-Path $dosya) -and ((Get-Item $dosya).Length -gt 0) -and ((Get-Date) - (Get-Item $dosya).LastWriteTime).TotalSeconds -gt 5) { break }
    Start-Sleep -Milliseconds 700
  }
  if (-not (Test-Path $dosya)) { throw "CSV dosyası oluşmadı." }
  $onceki = -1; for ($i = 0; $i -lt 60; $i++) { $b = (Get-Item $dosya).Length; if ($b -gt 0 -and $b -eq $onceki) { break }; $onceki = $b; Start-Sleep 1 }
  Log ("CSV hazır: {0:N0} bayt" -f (Get-Item $dosya).Length)
  # önizlemeyi kapat
  try { $oe = $A::FromHandle($on.H); ElTikla (Bul $oe "Vazgeç" 5) } catch { [void][W2]::SendMessage($on.H, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) }
  Start-Sleep 1
  return $dosya
}

# Raporu aldıktan sonra Rx'te açtığımız sekmeyi kapatır (sekme başlığındaki çarpıya basar; kayıt değiştirmez)
function SekmeKapat($p) {
  try {
    $h = AnaPencere $p; $rx = $A::FromHandle($h)
    $kos = New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, "Raporlar")
    $pn = @($rx.FindAll($TS::Descendants, $kos) | Where-Object { -not $_.Current.IsOffscreen -and $_.Current.BoundingRectangle.Width -gt 500 }) | Select-Object -First 1
    if (-not $pn) { Log "  kapatılacak rapor sekmesi bulunamadı"; return }
    $ust = [int]$pn.Current.BoundingRectangle.Y
    [void][W2]::ShowWindow($h, 3); [void][W2]::SetForegroundWindow($h); Start-Sleep -Milliseconds 700
    $bm = New-Object System.Drawing.Bitmap 1920, ([int](24*$EO))
    $g = [System.Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen(0, $ust - [int](24*$EO), 0, 0, $bm.Size); $g.Dispose()
    # satırı mavi (etkin sekme) / beyaz / diğer diye sınıflandır; mavinin içindeki 10-26 px beyaz kutu = çarpı düğmesi
    $kutu = $null
    foreach ($sat in @(3, 19, 6, 16 | ForEach-Object { [int]($_*$EO) })) {
      $tip = for ($x = 0; $x -lt 1920; $x++) { $c = $bm.GetPixel($x, $sat); if ($c.B -gt $c.R + 50) { 'B' } elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { 'W' } else { '.' } }
      $x = 2
      while ($x -lt 1916) {
        if ($tip[$x] -eq 'W' -and ($tip[$x - 1] -eq 'B' -or $tip[$x - 2] -eq 'B')) {
          $b = $x; while ($x -lt 1916 -and $tip[$x] -eq 'W') { $x++ }; $gen = $x - $b
          if (($tip[$x] -eq 'B' -or $tip[$x + 1] -eq 'B') -and $gen -ge [int](10*$EO) -and $gen -le 26) { $kutu = [int]($b + $gen / 2) } }
        $x++
      }
      if ($null -ne $kutu) { break }
    }
    $bm.Dispose()
    if ($null -eq $kutu) { Log "  sekmenin çarpısı bulunamadı, açık kaldı"; return }
    [W2]::Tik($kutu, $ust - [int](13*$EO)); Start-Sleep -Milliseconds 1500
    Log "Rapor sekmesi kapatıldı"
  } catch { if ($_.Exception.Message -like "*Durdur*") { throw }; Log ("  sekme kapatılamadı: " + $_.Exception.Message) }
}

# Ürün Bazlı Satış: tarih aralığı yazılır, Sorgula, Yazdır → CSV. Hasta sütunu dosyadan okunurken atılır.
# Rx tarih kutusu noktayı ayraç saymıyor: sadece rakamlar yazılır (01.02.2026 -> 01022026)
function TarihYaz($ad, [string]$t) { K $ad; Tus "^a"; Tus ($t -replace '\D', ''); Tus "{TAB}"; Start-Sleep -Milliseconds 500 }
function AsamaSatis($p, [string]$bas, [string]$bit, [string]$dosyaAdi, [switch]$AyniSekme) {
  if (-not $AyniSekme) { RaporAc $p "SatisRaporlari" "UrunBazliSatis" "Ürün Bazlı Satış"; Start-Sleep 3 }
  Log "Satış tarihleri: $bas - $bit"; $script:ARALIK = @($bas, $bit)
  $script:ON = AnaPencere $p
  TarihYaz "SatisTarihBas" $bas
  TarihYaz "SatisTarihBit" $bit
  K "SatisSorgula"
  Log "Satış sorgulandı ($bas - $bit), yüklenmesi bekleniyor"
  $rx = YuklemeBekle $p 900
  OnizlemedenCsv $p $rx (Join-Path $VERI $dosyaAdi) | Out-Null
  SekmeKapat $p
}

# ---------- aşamalar ----------
# Filtreleme penceresinde: Temizle → "Sadece Stoktakiler" işaretle → Filtrele → yüklenince Yazdır → CSV
function StoktakilerRaporu($p, [string]$oge, [string]$baslik, [string]$dosyaAdi) {
  RaporAc $p "EnvanterRap" $oge $baslik
  $f = PencereBekle $p.Id { $_.Ad -eq "Filtreleme" } 20 "Filtreleme penceresi"
  Kesfet $f.H ("filtre-" + $oge)
  $script:ON = $f.H
  $fe = $A::FromHandle($f.H)
  ElTikla (Bul $fe "Temizle"); Start-Sleep 1                       # önceki filtreleri sıfırla
  $etiket = (Bul $fe "Sadece Stoktakiler").Current.BoundingRectangle
  [W2]::Tik([int]($etiket.X + 260*$EO), [int]($etiket.Y + $etiket.Height/2)); Start-Sleep 1   # kutucuğu işaretle
  ElTikla (Bul $fe "Filtrele")
  Log "$baslik sorgulandı, yüklenmesi bekleniyor"
  $rx = YuklemeBekle $p 600
  $script:ON = AnaPencere $p
  if ($oge -eq "GenelEnvanter") { try { $sm = Bul $rx "Son Alım Maliyetleri Göster" 10; $sr = $sm.Current.BoundingRectangle; OneAl; [W2]::Tik([int]($sr.X + 7), [int]($sr.Y + $sr.Height/2)); Log "Son alım maliyetleri gösterildi"; $rx = YuklemeBekle $p 600; $script:ON = AnaPencere $p } catch { if ($_.Exception.Message -like "*Durdur*") { throw }; Log ("  UYARI: maliyet kutusu işaretlenemedi: " + $_.Exception.Message) } }
  OnizlemedenCsv $p $rx (Join-Path $VERI $dosyaAdi) | Out-Null
  SekmeKapat $p
}
function AsamaEnvanter($p) { StoktakilerRaporu $p "GenelEnvanter" "Genel Envanter" "envanter.csv" }
function AsamaUrunDokum($p) { StoktakilerRaporu $p "UrunDokum" "Ürün Döküm" "urundokum.csv" }
function AsamaKarekod($p) { StoktakilerRaporu $p "StokDokum" "Stok Döküm (karekod)" "karekod.csv" }

# ---------- ALIŞ (Ürün Hareket Raporları → Ürün Bazlı Alış) ----------
# Satış ekranı gibi: Tarih aralığı yazılır, Sorgula, Yazdır → CSV. Depo satırda var.
function AsamaAlis($p, [string]$bas, [string]$bit, [string]$dosyaAdi, [switch]$AyniSekme) {
  if (-not $AyniSekme) { RaporAc $p "UrunHareket" "UrunBazliAlis" "Ürün Bazlı Alış"; Start-Sleep 3 } else { [void](RxOne $p) }
  Log "Alış tarihleri: $bas - $bit"; $script:ARALIK = @($bas, $bit)
  $script:ON = AnaPencere $p
  TarihYaz "AlisTarihBas" $bas
  TarihYaz "AlisTarihBit" $bit
  K "AlisSorgula"
  Log "Alış sorgulandı ($bas - $bit), yüklenmesi bekleniyor"
  $rx = YuklemeBekle $p 900
  OnizlemedenCsv $p $rx (Join-Path $VERI $dosyaAdi) | Out-Null
  SekmeKapat $p
}
# Dışa aktarılan dosya istenen tarih aralığının mı? (Rx bazen önceki sorgunun sonucunu aktarıyor)
function AralikKontrol($tarihler) {
  if (-not $script:ARALIK) { return }
  $b = [datetime]::ParseExact($script:ARALIK[0], "dd.MM.yyyy", $null).ToString("yyyy-MM-dd")
  $e = [datetime]::ParseExact($script:ARALIK[1], "dd.MM.yyyy", $null).ToString("yyyy-MM-dd")
  $t = @($tarihler); if ($t.Count -eq 0) { return }
  $ic = @($t | Where-Object { $_ -ge $b -and $_ -le $e }).Count
  if ($ic -lt $t.Count * 0.9) { throw ("Aktarılan dosya istenen tarihlerde değil ({0}/{1} satır aralıkta) — yüklenmedi." -f $ic, $t.Count) }
}
# Ürün Bazlı Alış CSV → alis tablosu. Sütunlar başlık adından bulunur (sıra değişse de çalışır).
function AlisYukle([string]$dosyaAdi) {
  $dosya = Join-Path $VERI $dosyaAdi
  $m = [IO.File]::ReadAllText($dosya, [Text.Encoding]::GetEncoding(1254))
  if ($m.StartsWith("#;")) { $i = 0 } else { $i = $m.IndexOf("`n#;"); if ($i -lt 0) { throw "$dosya içinde başlık satırı bulunamadı." }; $i++ }
  $j = $m.IndexOf("`n", $i)
  $bas = $m.Substring($i, $j - $i).TrimEnd("`r").Split(";") | ForEach-Object { $_.Trim() }
  $adlar = @(); for ($k = 0; $k -lt $bas.Count; $k++) { $adlar += "c$k" }
  function Sutun([string]$desen) { for ($k = 0; $k -lt $bas.Count; $k++) { if ($bas[$k] -match $desen) { return "c$k" } }; return $null }
  $S = @{ barkod = Sutun '^Barkod$'; urun = Sutun '^Ürün'; depo = Sutun '^Depo$'; tarih = Sutun 'Fat.*Tarih'; fatno = Sutun 'Fat.*No'
          adet = Sutun '^Adet$'; mf = Sutun '(?i)^mf$'; depocu = Sutun '^Depocu'; net = Sutun 'Net'; kdv = Sutun 'KDV'; brut = Sutun 'Brüt' }
  foreach ($a in @("barkod","tarih","adet","net")) { if (-not $S[$a]) { throw "Alış dosyasında '$a' sütunu bulunamadı. Başlık: $($bas -join ' | ')" } }
  $govde = $m.Substring($j + 1)
  $satirlar = ($govde -split "`r?`n") | Where-Object { $_ -ne "" } | ConvertFrom-Csv -Delimiter ";" -Header $adlar
  $sayac = @{}; $liste = New-Object System.Collections.ArrayList; $beklenen = 1
  foreach ($r in $satirlar) {
    if (-not ($r.c0 -match '^\d+$' -and [int]$r.c0 -eq $beklenen)) { continue }; $beklenen++
    $tarih = TarihIso ([string]$r.($S.tarih)); $barkod = ([string]$r.($S.barkod)).Trim()
    if (-not $tarih -or $barkod -eq "") { continue }
    $fn = if ($S.fatno) { ([string]$r.($S.fatno)).Trim() } else { "" }
    $dp = if ($S.depo) { ([string]$r.($S.depo)).Trim() } else { "" }
    $k = "$tarih|$dp|$fn|$barkod"; if ($sayac.ContainsKey($k)) { $sayac[$k]++ } else { $sayac[$k] = 1 }
    $depocu = if ($S.depocu) { Sayi $r.($S.depocu) } else { $null }; $net = Sayi $r.($S.net)
    [void]$liste.Add([ordered]@{
      satir_kodu = "$k|$($sayac[$k])"; fat_tarih = $tarih; fat_no = $fn; depo = $dp; barkod = $barkod
      urun_ad = if ($S.urun) { ([string]$r.($S.urun)).Trim() } else { $null }
      adet = [double](Sayi $r.($S.adet)); mf = if ($S.mf) { [double](Sayi $r.($S.mf)) } else { 0 }
      depocu = $depocu; top_iskonto = if ($null -ne $depocu -and $null -ne $net) { [Math]::Round($depocu - $net, 2) } else { $null }
      top_net = $net; top_kdv = if ($S.kdv) { Sayi $r.($S.kdv) } else { $null }; top_brut = if ($S.brut) { Sayi $r.($S.brut) } else { $null } })
  }
  AralikKontrol ($liste | ForEach-Object { $_.fat_tarih })
  $tut = ($liste | ForEach-Object { [double]$_.top_brut } | Measure-Object -Sum).Sum
  Log ("Alış: {0} satır, {1:N2} TL (KDV dahil)" -f $liste.Count, $tut)
  $jt = Jeton
  for ($i = 0; $i -lt $liste.Count; $i += 1000) { BulutEkle "alis" $liste.GetRange($i, [Math]::Min(1000, $liste.Count - $i)).ToArray() $jt "satir_kodu" }
  $un = @{}; foreach ($r in $liste) { if (-not $un.ContainsKey($r.barkod) -and $r.urun_ad) { $un[$r.barkod] = $r.urun_ad } }
  $urunler = @($un.Keys | ForEach-Object { [ordered]@{ barkod = $_; ad = $un[$_] } })
  for ($i = 0; $i -lt $urunler.Count; $i += 1000) { BulutEkle "urun" $urunler[$i..([Math]::Min($i + 999, $urunler.Count - 1))] $jt "barkod" }
  Kayit "alis" "tamam" $liste.Count ("{0:N0} TL alış" -f $tut) $jt
  Remove-Item $dosya -Force -ErrorAction SilentlyContinue
}
function AlisGecmis([string]$basAy) {
  $p = RxSureci
  $ay = [datetime]::ParseExact($basAy, "MM.yyyy", $null); $ilk = $true
  while ($ay -le (Get-Date)) {
    $son = $ay.AddMonths(1).AddDays(-1); if ($son -gt (Get-Date)) { $son = (Get-Date).Date }
    AsamaAlis $p $ay.ToString("dd.MM.yyyy") $son.ToString("dd.MM.yyyy") "alis.csv" ; $ilk = $false
    try { AlisYukle "alis.csv" } catch { if ($_.Exception.Message -like "*istenen tarihlerde*") { Log "  bu ay boş, geçiliyor"; Remove-Item (Join-Path $VERI "alis.csv") -Force -ErrorAction SilentlyContinue } else { throw } }
    $ay = $ay.AddMonths(1)
  }
}
function CsvBas([string]$dosya, [int]$n = 4) {
  $m = [IO.File]::ReadAllText($dosya, [Text.Encoding]::GetEncoding(1254))
  $i = $m.IndexOf("`n#;"); if ($i -lt 0) { $i = 0 }
  Write-Host "----- $dosya -----"
  $l = ($m.Substring($i + 1) -split "`r?`n") | Select-Object -First $n
  $h = $l[0].Split(";"); $d = $l[1].Split(";")
  for ($k = 0; $k -lt $h.Count; $k++) { Write-Host ("{0,2} {1,-22} {2}" -f $k, $h[$k], $(if ($k -lt $d.Count) { $d[$k] })) }
}


# ---------- CSV okuma (Rx Windows-1254, ; ayraçlı, 1.234,56 sayılar) ----------
function Sayi($t) {
  if ($null -eq $t) { return $null }
  $t = ([string]$t).Trim(); if ($t -eq "") { return $null }
  $t = ($t -replace '\(.*\)', '') -replace '[^0-9,.\-]', ''
  if ($t -eq "" -or $t -eq "-") { return $null }
  $t = $t.Replace(".", "").Replace(",", ".")
  $d = 0.0; if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }; return $null
}
function CsvOku([string]$dosya, [string[]]$basliklar) {
  $metin = [IO.File]::ReadAllText($dosya, [Text.Encoding]::GetEncoding(1254))
  $i = $metin.IndexOf("`n#;"); if ($i -lt 0) { throw "$dosya içinde başlık satırı bulunamadı." }
  $j = $metin.IndexOf("`n", $i + 1)
  $govde = $metin.Substring($j + 1)
  $satirlar = ($govde -split "`r?`n") | Where-Object { $_ -ne "" } | ConvertFrom-Csv -Delimiter ";" -Header $basliklar
  # sıra numarası 1,2,3… gider; en alttaki toplam satırı (kalem sayısıyla başlar) atlanır
  $liste = New-Object System.Collections.ArrayList; $beklenen = 1
  foreach ($r in $satirlar) { if ($r.no -match '^\d+$' -and [int]$r.no -eq $beklenen) { [void]$liste.Add($r); $beklenen++ } }
  @($liste)
}
function AdAnahtar($ad) { (([string]$ad).Trim().ToUpperInvariant().Replace([string][char]0x130, "I")) -replace '\s+', ' ' }

# ---------- bulut ----------
function GirisKur {
  Write-Host ""
  Write-Host "Eczane Stok programına girişte kullandığın e-posta ve şifreyi yaz."
  $ep = Read-Host "E-posta"
  $sf = Read-Host "Şifre" -AsSecureString
  $duz = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
  $null = BulutGiris $ep $duz
  ($ep + "`n" + (ConvertFrom-SecureString $sf)) | Out-File $GIRIS -Encoding utf8
  Log "Giriş bilgisi kaydedildi (şifreli) — $ep"
}
function BulutGiris([string]$ep, [string]$sf) {
  $govde = @{ email = $ep; password = $sf } | ConvertTo-Json
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{ apikey = $SB_KEY } -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($govde))
  } catch { throw "Buluta giriş yapılamadı: " + $_.Exception.Message }
  $r.access_token
}
function Jeton {
  if (-not (Test-Path $GIRIS)) { throw "Giriş bilgisi yok. Önce: toplayici.ps1 -Kur" }
  $s = Get-Content $GIRIS -Encoding UTF8
  $sf = ConvertTo-SecureString $s[1].Trim()
  $duz = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
  BulutGiris $s[0].Trim() $duz
}
function Bulut([string]$yol, $nesne, [string]$jeton) {
  $json = ConvertTo-Json $nesne -Depth 5 -Compress
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/$yol" -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $jeton" } -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 300
}
function Kayit([string]$rapor, [string]$durum, $satir, [string]$mesaj, [string]$jeton) {
  try { $null = Bulut "toplama_kaydi" @{ bilgisayar = $env:COMPUTERNAME; rapor = $rapor; durum = $durum; satir = $satir; mesaj = $mesaj } $jeton } catch { Log ("  kayıt yazılamadı: " + $_.Exception.Message) }
}

function EnvanterOku([string]$dosya) { $sat = [IO.File]::ReadAllText($dosya, [Text.Encoding]::GetEncoding(1254)) -split "`r?`n"; $hi = -1; for ($k = 0; $k -lt $sat.Count; $k++) { if ($sat[$k] -match '^#;' -or $sat[$k] -match '^Ürün;') { $hi = $k; break } }; if ($hi -lt 0) { throw "$dosya içinde başlık satırı bulunamadı." }; $bas = @($sat[$hi].Split(';') | ForEach-Object { $_.Trim() }); $des = [ordered]@{ no = '^#$'; ad = '^Ürün'; grup = '^Grup'; uretici = 'Üretici'; stok = '^Stok'; ort = '^Ort\.?\s*Maliyet|Al[ıi]m\s*Mal'; brut = 'Br[üu]t'; envd = '^Envanter|Env\.'; kdv = '^KDV'; psf = '^PSF'; kamu = '^Kamu'; karlilik = '^Bir\.?\s*Karl' }; $idx = @{}; foreach ($a in $des.Keys) { for ($k = 0; $k -lt $bas.Count; $k++) { if ($bas[$k] -match $des[$a]) { $idx[$a] = $k; break } } }; if (-not $idx.ContainsKey('ad') -or -not $idx.ContainsKey('stok')) { throw ("Envanter dosyasında Ürün / Stok sütunu yok. Başlık: " + ($bas -join ' | ')) }; if (-not $idx.ContainsKey('ort')) { Log "  UYARI: Envanter'de maliyet sütunu yok - maliyet boş kalacak" }; Log ("  Envanter sütunları: " + (($idx.Keys | ForEach-Object { "$_=" + $bas[$idx[$_]] }) -join ', ')); $adlar = @(0..($bas.Count - 1) | ForEach-Object { "c$_" }); $satirlar = ($sat[($hi + 1)..($sat.Count - 1)]) | Where-Object { $_ -ne "" } | ConvertFrom-Csv -Delimiter ";" -Header $adlar; $liste = New-Object System.Collections.ArrayList; $beklenen = 1; foreach ($r in $satirlar) { if ($idx.ContainsKey('no')) { $no = [string]$r.("c" + $idx['no']); if (-not ($no -match '^\d+$' -and [int]$no -eq $beklenen)) { continue }; $beklenen++ } else { if (([string]$r.("c" + $idx['ad'])).Trim() -eq "" -or $null -eq (Sayi $r.("c" + $idx['stok']))) { continue } }; $o = [ordered]@{}; foreach ($a in $des.Keys) { $o[$a] = if ($idx.ContainsKey($a)) { $r.("c" + $idx[$a]) } else { $null } }; [void]$liste.Add([pscustomobject]$o) }; @($liste) }
# Envanter (maliyet) + Ürün Döküm (barkod) birleştir → stok_yukle
function StokYukle {
  $envn = EnvanterOku (Join-Path $VERI "envanter.csv")
  $ud  = CsvOku (Join-Path $VERI "urundokum.csv") @("no","ad","barkod","depo","bos","kki","psf","kamu","stok","toppsf","raf")
  Log ("Okundu: envanter {0} satır, ürün döküm {1} satır" -f $envn.Count, $ud.Count)
  # ada göre envanter havuzu
  $havuz = @{}
  foreach ($e in $envn) { $k = AdAnahtar $e.ad; if (-not $havuz.ContainsKey($k)) { $havuz[$k] = New-Object System.Collections.ArrayList }; [void]$havuz[$k].Add($e) }
  $sonuc = New-Object System.Collections.ArrayList
  $eslesmeyen = 0
  foreach ($u in $ud) {
    $k = AdAnahtar $u.ad; $e = $null
    if ($havuz.ContainsKey($k) -and $havuz[$k].Count -gt 0) {
      $aday = $havuz[$k]
      if ($aday.Count -eq 1) { $e = $aday[0] }
      else {
        $e = $aday | Where-Object { (Sayi $_.psf) -eq (Sayi $u.psf) -and (Sayi $_.stok) -eq (Sayi $u.stok) } | Select-Object -First 1
        if (-not $e) { $e = $aday | Where-Object { (Sayi $_.psf) -eq (Sayi $u.psf) } | Select-Object -First 1 }
        if (-not $e) { $e = $aday[0] }
      }
      [void]$aday.Remove($e)
    }
    if (-not $e) { $eslesmeyen++ }
    $ad = ([string]$u.ad).Trim(); if ($ad -eq "") { $ad = "(adsız ürün)" }
    [void]$sonuc.Add([ordered]@{
      barkod = ([string]$u.barkod).Trim(); ad = $ad
      grup = $(if ($e) { ([string]$e.grup).Trim() } else { "" }); uretici = $(if ($e) { ([string]$e.uretici).Trim() } else { "" })
      stok = $(if ($e) { Sayi $e.stok } else { Sayi $u.stok })
      ort_maliyet = $(if ($e) { Sayi $e.ort } else { $null }); ort_brut = $(if ($e) { Sayi $e.brut } else { $null })
      psf = Sayi $u.psf; kamu = Sayi $u.kamu; kdv = $(if ($e) { Sayi $e.kdv } else { $null })
    })
  }
  # Ürün Döküm'de olmayan envanter satırları (emanet vb.) — barkodsuz, adla tutulur
  $kalan = 0
  foreach ($k in $havuz.Keys) { foreach ($e in $havuz[$k]) { $kalan++
    $ad = ([string]$e.ad).Trim(); if ($ad -eq "") { $ad = "(adsız ürün)" }
    [void]$sonuc.Add([ordered]@{ barkod = "AD:" + $ad; ad = $ad; grup = ([string]$e.grup).Trim(); uretici = ([string]$e.uretici).Trim()
      stok = Sayi $e.stok; ort_maliyet = Sayi $e.ort; ort_brut = Sayi $e.brut; psf = Sayi $e.psf; kamu = Sayi $e.kamu; kdv = Sayi $e.kdv }) } }
  $topStok = ($sonuc | ForEach-Object { $_.stok } | Measure-Object -Sum).Sum
  $topMal  = ($sonuc | ForEach-Object { [double]$_.stok * [double]$_.ort_maliyet } | Measure-Object -Sum).Sum
  Log ("Birleşti: {0} ürün, {1:N0} kutu, maliyet {2:N2} TL (eşleşmeyen döküm {3}, barkodsuz envanter {4})" -f $sonuc.Count, $topStok, $topMal, $eslesmeyen, $kalan)
  $j = Jeton
  $tarih = (Get-Date).ToString("yyyy-MM-dd")
  $n = Bulut "rpc/stok_yukle" @{ p_tarih = $tarih; p_satirlar = $sonuc.ToArray() } $j
  Log "Buluta yüklendi: $n ürün ($tarih)"
  Kayit "stok" "tamam" $sonuc.Count ("{0:N0} kutu, {1:N2} TL" -f $topStok, $topMal) $j
}

# Stok Döküm (her karekodlu kutu bir satır) → karekod_yukle
function KarekodYukle {
  $kk = CsvOku (Join-Path $VERI "karekod.csv") @("no","ad","bos","barkod","psf","stok","seri","parti","miad")
  $liste = New-Object System.Collections.ArrayList
  $tr = [Globalization.CultureInfo]::InvariantCulture
  foreach ($r in $kk) {
    $seri = ([string]$r.seri).Trim(); if ($seri -eq "") { continue }
    $m = $null; $d = [datetime]::MinValue
    if ([datetime]::TryParseExact(([string]$r.miad).Trim(), [string[]]@("d.MM.yyyy","dd.MM.yyyy","d.M.yyyy"), $tr, [Globalization.DateTimeStyles]::None, [ref]$d) -and $d.Year -gt 2000) { $m = $d.ToString("yyyy-MM-dd") }
    [void]$liste.Add([ordered]@{ barkod = ([string]$r.barkod).Trim(); seri_no = $seri; parti_no = ([string]$r.parti).Trim(); miad = $m })
  }
  Log ("Karekod: {0} satır okundu, {1} karekodlu kutu" -f $kk.Count, $liste.Count)
  if ($liste.Count -eq 0) { throw "Karekod dosyasında kutu bulunamadı." }
  $j = Jeton
  $tarih = (Get-Date).ToString("yyyy-MM-dd")
  $n = Bulut "rpc/karekod_yukle" @{ p_tarih = $tarih; p_satirlar = $liste.ToArray() } $j
  Log "Buluta yüklendi: $n kutu"
  Kayit "karekod" "tamam" $liste.Count "$($liste.Count) kutu" $j
}

function TarihIso([string]$t) {
  $d = [datetime]::MinValue
  if ([datetime]::TryParseExact($t.Trim(), [string[]]@("d.MM.yyyy","dd.MM.yyyy","d.M.yyyy","dd.MM.yyyy HH:mm:ss","d.MM.yyyy HH:mm:ss","d.MM.yyyy HH:mm"), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.ToString("yyyy-MM-dd") }
  return $null
}
function BulutEkle([string]$tablo, $satirlar, [string]$jeton, [string]$cakisma) {
  $json = ConvertTo-Json @($satirlar) -Depth 4 -Compress
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/${tablo}?on_conflict=$cakisma" -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $jeton"; Prefer = $(if ($tablo -in @("satis","alis","ayar")) { "resolution=merge-duplicates,return=minimal" } else { "resolution=ignore-duplicates,return=minimal" }) } -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 300 | Out-Null
}
function SatisOku([string]$dosya) { $metin = [IO.File]::ReadAllText($dosya, [Text.Encoding]::GetEncoding(1254)); $i = $metin.IndexOf("`n#;"); if ($i -lt 0) { throw "$dosya içinde başlık satırı bulunamadı." }; $j = $metin.IndexOf("`n", $i + 1); $bas = @($metin.Substring($i + 1, $j - $i - 1).TrimEnd("`r").Split(';') | ForEach-Object { $_.Trim() }); $des = [ordered]@{ satis_no = '^Sat[ıi]ş\s*No'; tarih = 'Tarih'; urun = '^Ürün'; barkod = '^Barkod'; islem = '^İşlem'; aciklama = '^Açıklama'; env_maliyet = '^Env'; stok = '^Stok'; adet = '^Sat[ıi]lan|^Adet'; psf_top = '^PSF'; kamu_top = '^Kamu'; birim_sat = '^Birim'; top_sat = '^Top\.?\s*Sat'; kar = '^Karl|^K[âa]r'; top_env = '^Top\.?\s*Env'; iskonto = 'skonto' }; $idx = @{}; foreach ($a in $des.Keys) { for ($k = 0; $k -lt $bas.Count; $k++) { if ($bas[$k] -match $des[$a]) { $idx[$a] = $k; break } } }; $eksik = @(@('satis_no','tarih','barkod','adet','top_sat','kar') | Where-Object { -not $idx.ContainsKey($_) }); if ($eksik.Count) { throw ("Satış dosyasında sütun bulunamadı: " + ($eksik -join ', ') + " | Başlık: " + (($bas | Where-Object { $_ -notmatch 'Hasta' }) -join ' | ')) }; Log ("  Satış sütunları: " + (($des.Keys | Where-Object { $idx.ContainsKey($_) } | ForEach-Object { "$_=" + $bas[$idx[$_]] }) -join ', ')); $adlar = @(0..($bas.Count - 1) | ForEach-Object { "c$_" }); $satirlar = ($metin.Substring($j + 1) -split "`r?`n") | Where-Object { $_ -ne "" } | ConvertFrom-Csv -Delimiter ";" -Header $adlar; $liste = New-Object System.Collections.ArrayList; $beklenen = 1; foreach ($r in $satirlar) { if (-not ($r.c0 -match '^\d+$' -and [int]$r.c0 -eq $beklenen)) { continue }; $beklenen++; $o = [ordered]@{ no = $r.c0 }; foreach ($a in $des.Keys) { $o[$a] = if ($idx.ContainsKey($a)) { $r.("c" + $idx[$a]) } else { $null } }; [void]$liste.Add([pscustomobject]$o) }; @($liste) }
# Ürün Bazlı Satış → satis tablosu. HASTA SÜTUNU OKUNMAZ, YÜKLENMEZ; dosya iş bitince silinir.
function SatisYukle([string]$dosyaAdi) {
  $dosya = Join-Path $VERI $dosyaAdi
  $ss = SatisOku $dosya
  $sayac = @{}; $liste = New-Object System.Collections.ArrayList
  foreach ($r in $ss) {
    $tarih = TarihIso ([string]$r.tarih); $barkod = ([string]$r.barkod).Trim()
    if (-not $tarih -or $barkod -eq "") { continue }
    $sn = ([string]$r.satis_no).Trim()
    $k = "$sn|$barkod"; if ($sayac.ContainsKey($k)) { $sayac[$k]++ } else { $sayac[$k] = 1 }
    [void]$liste.Add([ordered]@{
      satir_kodu = "$k|$($sayac[$k])"; satis_no = $sn; tarih = $tarih; barkod = $barkod; urun_ad = ([string]$r.urun).Trim()
      tip = ([string]$r.aciklama).Trim(); islem_yapan = ([string]$r.islem).Trim()
      adet = Sayi $r.adet; birim_maliyet = Sayi $r.env_maliyet; top_maliyet = Sayi $r.top_env
      psf_toplam = Sayi $r.psf_top; kamu_toplam = Sayi $r.kamu_top; birim_satis = Sayi $r.birim_sat
      top_satis = Sayi $r.top_sat; kar = Sayi $r.kar; iskonto = Sayi $r.iskonto })
  }
  AralikKontrol ($liste | ForEach-Object { $_.tarih })
  $ciro = ($liste | ForEach-Object { [double]$_.top_satis } | Measure-Object -Sum).Sum
  $kar  = ($liste | ForEach-Object { [double]$_.kar } | Measure-Object -Sum).Sum
  Log ("Satış: {0} satır, ciro {1:N2} TL, kâr {2:N2} TL" -f $liste.Count, $ciro, $kar)
  $j = Jeton
  for ($i = 0; $i -lt $liste.Count; $i += 1000) {
    $parca = $liste.GetRange($i, [Math]::Min(1000, $liste.Count - $i))
    BulutEkle "satis" $parca.ToArray() $j "satir_kodu"
  }
  # stokta olmayan ama satılmış ürünlerin adı da görünsün: ürün listesinde olmayanları ekle (var olanlara dokunmaz)
  $adlar = @{}; foreach ($r in $liste) { if (-not $adlar.ContainsKey($r.barkod) -and $r.urun_ad) { $adlar[$r.barkod] = $r.urun_ad } }
  $urunler = @($adlar.Keys | ForEach-Object { [ordered]@{ barkod = $_; ad = $adlar[$_] } })
  for ($i = 0; $i -lt $urunler.Count; $i += 1000) { BulutEkle "urun" $urunler[$i..([Math]::Min($i + 999, $urunler.Count - 1))] $j "barkod" }
  Log "Buluta yüklendi: $($liste.Count) satış satırı, $($urunler.Count) ürün adı"
  Kayit "satis" "tamam" $liste.Count ("{0:N0} TL ciro" -f $ciro) $j
  Remove-Item $dosya -Force -ErrorAction SilentlyContinue      # hasta adı içeren dosya bilgisayarda kalmasın
}
# Aylık satış: verilen aydan bugüne her ay ayrı çekilir
function SatisGecmis([string]$basAy) {
  $p = RxSureci
  $ay = [datetime]::ParseExact($basAy, "MM.yyyy", $null); $ilk = $true
  while ($ay -le (Get-Date)) {
    $son = $ay.AddMonths(1).AddDays(-1); if ($son -gt (Get-Date)) { $son = (Get-Date).Date }
    AsamaSatis $p $ay.ToString("dd.MM.yyyy") $son.ToString("dd.MM.yyyy") "satis.csv" ; $ilk = $false
    try { SatisYukle "satis.csv" } catch { if ($_.Exception.Message -like "*istenen tarihlerde*") { Log "  bu ay boş, geçiliyor"; Remove-Item (Join-Path $VERI "satis.csv") -Force -ErrorAction SilentlyContinue } else { throw } }
    $ay = $ay.AddMonths(1)
  }
}

function BulutOku([string]$yol, [string]$jeton) {
  Invoke-RestMethod -Method Get -Uri "$SB_URL/rest/v1/$yol" -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $jeton" } -TimeoutSec 60
}
# Bugün başka bir bilgisayar topladı mı / şu an topluyor mu?
function GunlukKilit([string]$jeton) {
  $bas = [Uri]::EscapeDataString((Get-Date).Date.ToString("yyyy-MM-ddTHH:mm:sszzz"))
  $k = @(BulutOku "toplama_kaydi?rapor=eq.gunluk&zaman=gte.$bas&select=durum,bilgisayar,zaman&order=zaman.desc" $jeton)
  $tamam = $k | Where-Object { $_.durum -eq "tamam" } | Select-Object -First 1
  if ($tamam) { return "Bugün $($tamam.bilgisayar) zaten topladı." }
  $suren = $k | Where-Object { $_.durum -eq "basladi" -and $_.bilgisayar -ne $env:COMPUTERNAME -and ((Get-Date) - [datetime]$_.zaman).TotalMinutes -lt 40 } | Select-Object -First 1
  if ($suren) { return "$($suren.bilgisayar) şu an topluyor." }
  return $null
}
# Bannerı ayrı süreçte aç (Rx'e tıklamaları engellemeyen, odak çalmayan küçük pencere)
function BannerAc { Remove-Item (Join-Path $KOK "bitti.flag") -Force -ErrorAction SilentlyContinue; $b = Join-Path $KOK "banner.ps1"; if (Test-Path $b) { Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$b`" -Ana $PID" -WindowStyle Hidden } }
# ---------- HASTA TAKİBİ (İlacı Biten / Raporu Biten raporları) ----------
# Hasta adı ve telefon eczanede ŞİFRELENİR, buluta şifreli gider; TC kimlik numarası hiç gönderilmez.
$HASTA_ANAHTAR = Join-Path $KOK "hasta.key"
function HastaSatirlari([string]$dosya) {
  $sat = [IO.File]::ReadAllText($dosya, [Text.Encoding]::GetEncoding(1254)) -split "`r?`n"
  $hi = -1; for ($k = 0; $k -lt $sat.Count; $k++) { if ($sat[$k] -match '(^|;)#;' -and $sat[$k] -match 'Gsm|Hasta') { $hi = $k; break } }
  if ($hi -lt 0) { throw "$dosya içinde başlık satırı bulunamadı." }
  $bas = @($sat[$hi].Split(';') | ForEach-Object { $_.Trim() })
  $adlar = @(0..($bas.Count - 1) | ForEach-Object { "c$_" })
  # bazı dışa aktarımlarda veri satırları başlıktan bir boş sütunla önde başlar → hizala
  $govde = @($sat[($hi + 1)..($sat.Count - 1)] | Where-Object { $_ -ne "" } | ForEach-Object {
    if ($_.StartsWith(";") -and $_.Split(';').Count -gt $bas.Count) { $_.Substring(1) } else { $_ } })
  $satirlar = if ($govde.Count) { $govde | ConvertFrom-Csv -Delimiter ";" -Header $adlar } else { @() }
  @{ bas = $bas; satirlar = @($satirlar) }
}
function Sutunu($bas, [string]$desen) { for ($k = 0; $k -lt $bas.Count; $k++) { if ($bas[$k] -match $desen) { return "c$k" } }; return $null }
function Ozet16([string]$m) { $s = [Security.Cryptography.SHA256]::Create(); (($s.ComputeHash([Text.Encoding]::UTF8.GetBytes($m)) | Select-Object -First 8 | ForEach-Object { $_.ToString("x2") }) -join "") }
function HastaAnahtari {
  if (-not (Test-Path $HASTA_ANAHTAR)) { return $null }
  $b = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($HASTA_ANAHTAR), $null, 'CurrentUser'); $b
}
function Sifrele([byte[]]$anahtar, [string]$metin) {
  $ham = [Text.Encoding]::UTF8.GetBytes($metin)
  $ms = New-Object IO.MemoryStream; $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress); $gz.Write($ham, 0, $ham.Length); $gz.Close(); $ham = $ms.ToArray()
  $aes = [Security.Cryptography.Aes]::Create(); $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = [byte[]]$anahtar[0..31]; $aes.GenerateIV()
  $ct = $aes.CreateEncryptor().TransformFinalBlock($ham, 0, $ham.Length)
  $iv_ct = [byte[]]($aes.IV + $ct)
  $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (,[byte[]]$anahtar[32..63])
  [Convert]::ToBase64String([byte[]]($iv_ct + $h.ComputeHash($iv_ct)))
}
function HastaKur {
  Add-Type -AssemblyName System.Security
  $j = Jeton
  $tuz = @(BulutOku "ayar?select=deger&anahtar=eq.hasta_tuz" $j)
  if (-not $tuz.Count) { Write-Host "Önce Eczane Stok programında Hastalar sekmesini açıp hasta şifresini belirleyin." -ForegroundColor Yellow; return }
  $tb = [Convert]::FromBase64String($tuz[0].deger)
  $kont = @(BulutOku "ayar?select=deger&anahtar=eq.hasta_kontrol" $j)
  for ($d = 0; $d -lt 3; $d++) {
    $sf = Read-Host "Hasta şifresi (programda belirlediğiniz)" -AsSecureString
    $duz = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
    $kd = New-Object Security.Cryptography.Rfc2898DeriveBytes -ArgumentList $duz, $tb, 200000, ([Security.Cryptography.HashAlgorithmName]::SHA256)
    $anahtar = $kd.GetBytes(64)
    # kontrol: programın yazdığı şifreli kontrol metni bu anahtarla doğrulanır
    $hm = [Convert]::FromBase64String($kont[0].deger); $iv_ct = [byte[]]$hm[0..($hm.Length - 33)]; $mac = [byte[]]$hm[($hm.Length - 32)..($hm.Length - 1)]
    $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (,[byte[]]$anahtar[32..63])
    if ([Convert]::ToBase64String($h.ComputeHash($iv_ct)) -eq [Convert]::ToBase64String($mac)) {
      [IO.File]::WriteAllBytes($HASTA_ANAHTAR, [Security.Cryptography.ProtectedData]::Protect($anahtar, $null, 'CurrentUser'))
      Log "Hasta şifresi kaydedildi (bu bilgisayarda şifreli)"; return
    }
    Write-Host "Şifre yanlış, tekrar deneyin." -ForegroundColor Red
  }
}
function IzgaradanCsv($p, $rx, [string]$dosya, [string]$tumu, [string]$sag, [int]$mdx = 43, [int]$mdy = 230, [string]$menu = "Dışa Aktar") {
  # ızgaradaki tüm satırları işaretle → sağ tık → "Dışa Aktar" → önizleme → CSV
  K $tumu; Start-Sleep -Milliseconds 600; Log "Tüm satırlar işaretlendi"
  $ac = { OneAl; [W2]::SagTik([int]($K[$sag][0]*$EO), [int]($K[$sag][1]*$EO)); Start-Sleep -Milliseconds 1200
          $mx = [int](($K[$sag][0] + $mdx)*$EO); $my = [int](($K[$sag][1] + $mdy)*$EO)
          [void][W2]::SetCursorPos($mx, $my); Start-Sleep -Milliseconds 500; [W2]::Tik($mx, $my); Log "$menu tıklandı" }   # değişkenler çağıran işlevden (dinamik kapsam) okunur
  OnizlemedenCsv $p $rx $dosya $ac
}
function IlaciBitenAl($p, [string]$tur) {
  RaporAc $p "HastaRap" "IlaciBiten" "İlacı Biten Hastalar ($tur)"; Start-Sleep 3
  $script:ON = AnaPencere $p
  TarihYaz "IlacBitBas" ((Get-Date).AddDays(-45).ToString("dd.MM.yyyy"))
  K "IlacTurOk"; Start-Sleep -Milliseconds 600; K $(if ($tur -eq "R") { "IlacRaporlu" } else { "IlacRaporsuz" }); Start-Sleep -Milliseconds 600
  K "IlacSorgula"; Log "İlacı biten ($tur) sorgulandı"
  $rx = YuklemeBekle $p 600
  IzgaradanCsv $p $rx (Join-Path $VERI "ilacbiten-$tur.csv") "IlacTumu" "IlacSag" | Out-Null
  SekmeKapat $p
}
function RaporuBitenAl($p) {
  RaporAc $p "HastaRap" "RaporuBiten" "Raporu Biten Hastalar"; Start-Sleep 3
  $script:ON = AnaPencere $p
  K "RaporSorgula"; Log "Raporu biten sorgulandı"
  $rx = YuklemeBekle $p 600
  IzgaradanCsv $p $rx (Join-Path $VERI "raporbiten.csv") "RaporTumu" "RaporSag" 48 44 "Yazdır (sağ tık)" | Out-Null
  SekmeKapat $p
}
function HastaTarih([string]$t) { $t = ([string]$t).Trim(); if ($t -eq "") { return $null }; TarihIso $t }
function HastaYukle([string]$tuz) {
  $anahtar = HastaAnahtari; if (-not $anahtar) { throw "Hasta şifresi bu bilgisayarda kayıtlı değil (toplayici.ps1 -HastaKur)." }
  $ilac = New-Object System.Collections.ArrayList
  foreach ($tur in @("R","S")) {
    $f = Join-Path $VERI "ilacbiten-$tur.csv"; if (-not (Test-Path $f)) { continue }
    $o = HastaSatirlari $f; $b = $o.bas
    $S = @{ no = Sutunu $b '^#$'; hasta = Sutunu $b '^Hasta'; tc = Sutunu $b 'TCKN|TC'; gsm = Sutunu $b '^Gsm'; tel = Sutunu $b '^Tel'; ilac = Sutunu $b '^İlaç$|^Ilaç$|^İlaç Adı'
            adet = Sutunu $b '^Top\.?\s*Adet'; recadet = Sutunu $b 'Re[cç]\.?\s*Adet'; stok = Sutunu $b '^Stok'; alis = Sutunu $b 'Al\.?\s*Tar'
            ver = Sutunu $b '^Verilebilece'; yaz = Sutunu $b '^Yazd'; sms = Sutunu $b '^Sms'; ara = Sutunu $b '^Arand' }
    foreach ($z in @("hasta","ilac","yaz")) { if (-not $S[$z]) { throw "İlacı biten dosyasında '$z' sütunu yok. Başlık: $(($b | Where-Object { $_ -notmatch 'Hasta|TC' }) -join ' | ')" } }
    $beklenen = 1
    foreach ($r in $o.satirlar) {
      if ($S.no) { $n = [string]$r.($S.no); if (-not ($n -match '^\d+$' -and [int]$n -eq $beklenen)) { continue }; $beklenen++ }
      $ad = ([string]$r.($S.hasta)).Trim(); $il = ([string]$r.($S.ilac)).Trim(); if ($ad -eq "" -or $il -eq "") { continue }
      $tc = if ($S.tc) { ([string]$r.($S.tc)).Trim() } else { "" }
      $kim = Ozet16 ($tuz + "|" + $(if ($tc) { $tc } else { $ad }))
      [void]$ilac.Add([ordered]@{ k = (Ozet16 ($kim + "|" + $il)); p = $kim; tur = $tur; h = $ad
        gsm = if ($S.gsm) { ([string]$r.($S.gsm)).Trim() } else { "" }; tel = if ($S.tel) { ([string]$r.($S.tel)).Trim() } else { "" }
        ilac = $il; adet = if ($S.adet) { Sayi $r.($S.adet) } else { $null }; stok = if ($S.stok) { Sayi $r.($S.stok) } else { $null }
        alis = if ($S.alis) { HastaTarih $r.($S.alis) } else { $null }; ver = if ($S.ver) { HastaTarih $r.($S.ver) } else { $null }; yaz = HastaTarih $r.($S.yaz)
        sms = if ($S.sms) { ([string]$r.($S.sms)).Trim() } else { "" }; ara = if ($S.ara) { ([string]$r.($S.ara)).Trim() } else { "" } })
    }
  }
  $rap = New-Object System.Collections.ArrayList
  $f = Join-Path $VERI "raporbiten.csv"
  if (Test-Path $f) {
    $o = HastaSatirlari $f; $b = $o.bas
    $S = @{ hasta = Sutunu $b '^Hasta'; gsm = Sutunu $b '^Gsm'; tel = Sutunu $b '^Tel'; tani = Sutunu $b '^Tan'; no = Sutunu $b 'Rapor\s*No'; bit = Sutunu $b '^Bit'; bas = Sutunu $b '^Ba[sş]'; uyari = Sutunu $b '^Uyar' }
    $sonHasta = ""
    foreach ($r in $o.satirlar) {
      $c0 = ([string]$r.c0).Trim()
      if (-not $S.hasta -and $c0 -and $c0 -notmatch '^\d+$') { $sonHasta = ($c0 -replace '^Hasta\s*:\s*', '').Trim(); continue }   # gruplama satırı: "Hasta: AD SOYAD"
      $ad = if ($S.hasta) { ([string]$r.($S.hasta)).Trim() } else { $sonHasta }
      $bit = if ($S.bit) { HastaTarih $r.($S.bit) } else { $null }
      if ($ad -eq "" -or -not $bit) { continue }
      $gsm = if ($S.gsm) { ([string]$r.($S.gsm)).Trim() } else { "" }
      $kim = Ozet16 ($tuz + "|" + $ad)
      [void]$rap.Add([ordered]@{ k = (Ozet16 ($kim + "|" + ([string]$r.($S.no)) + "|" + $bit)); p = $kim; h = $ad; gsm = $gsm
        tel = if ($S.tel) { ([string]$r.($S.tel)).Trim() } else { "" }; tani = if ($S.tani) { ([string]$r.($S.tani)).Trim() } else { "" }
        no = if ($S.no) { ([string]$r.($S.no)).Trim() } else { "" }; bas = if ($S.bas) { HastaTarih $r.($S.bas) } else { $null }; bit = $bit
        uyari = if ($S.uyari) { ([string]$r.($S.uyari)).Trim() } else { $null } })
    }
  }
  $veri = [ordered]@{ zaman = (Get-Date).ToString("o"); ilac = $ilac.ToArray(); rapor = $rap.ToArray() }
  $sifreli = Sifrele $anahtar (ConvertTo-Json $veri -Depth 5 -Compress)
  $j = Jeton
  BulutEkle "ayar" @([ordered]@{ anahtar = "hasta_liste"; deger = $sifreli; guncelleme = (Get-Date).ToString("o") }) $j "anahtar"
  Log ("Hasta takibi yüklendi: {0} ilaç satırı (raporlu {1}), {2} rapor (şifreli)" -f $ilac.Count, @($ilac | Where-Object { $_.tur -eq "R" }).Count, $rap.Count)
  Kayit "hasta" "tamam" $ilac.Count "" $j
}
function HastaTemizle { foreach ($f in @("ilacbiten-R.csv","ilacbiten-S.csv","raporbiten.csv")) { Remove-Item (Join-Path $VERI $f) -Force -ErrorAction SilentlyContinue } }
function AsamaHasta($p) {
  if (-not (Test-Path $HASTA_ANAHTAR)) { Log "Hasta takibi atlandı: hasta şifresi bu bilgisayarda kayıtlı değil"; return }
  Add-Type -AssemblyName System.Security
  $tuz = @(BulutOku "ayar?select=deger&anahtar=eq.hasta_tuz" (Jeton)); if (-not $tuz.Count) { Log "Hasta takibi atlandı: programda hasta şifresi belirlenmemiş"; return }
  try { IlaciBitenAl $p "R"; IlaciBitenAl $p "S"; RaporuBitenAl $p; HastaYukle $tuz[0].deger }
  catch { if ($_.Exception.Message -like "*Durdur*") { throw }; Log ("HATA (hasta takibi): " + $_.Exception.Message) }
  finally { HastaTemizle }   # hasta bilgisi içeren dosyalar bilgisayarda kalmasın
}
# Deneme: raporları alır, SADECE yapıyı (harfler x, rakamlar 9) gösterir, dosyaları siler. Hasta bilgisi ekrana yazılmaz.
function HastaDene($p) {
  try {
    IlaciBitenAl $p "R"; RaporuBitenAl $p
    foreach ($f in @("ilacbiten-R.csv","raporbiten.csv")) {
      $yol = Join-Path $VERI $f; if (-not (Test-Path $yol)) { Write-Host "$f yok"; continue }
      $sat = [IO.File]::ReadAllText($yol, [Text.Encoding]::GetEncoding(1254)) -split "`r?`n"
      $hi = 0; for ($k = 0; $k -lt $sat.Count; $k++) { if ($sat[$k] -match '^#;') { $hi = $k; break } }
      $hi = -1; for ($k = 0; $k -lt $sat.Count; $k++) { if ($sat[$k] -match '(^|;)#;' -and $sat[$k] -match 'Gsm|Hasta') { $hi = $k; break } }
      Write-Host "----- $f : $($sat.Count) satır, başlık satırı $hi, başlık alan sayısı $($sat[$hi].Split(';').Count) -----"
      $say = @{}; foreach ($s in $sat[($hi+1)..($sat.Count-1)]) { if ($s -ne "") { $n = "$($s.Split(';').Count)" + $(if ($s.StartsWith(";")) { "(;)" } else { "" }); $say[$n] = 1 + [int]$say[$n] } }
      Write-Host ("alan sayıları: " + (($say.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "  "))
      $o = HastaSatirlari $yol; $ilk = $o.satirlar | Where-Object { ([string]$_.c0) -match '^\d+$' -or ([string]$_.c1) -match '^\d+$' } | Select-Object -First 1
      if ($ilk) { Write-Host ("ilk veri satırı alanları: " + ((0..($o.bas.Count-1) | ForEach-Object { "$($o.bas[$_])=" + ((([string]$ilk."c$_") -creplace '\p{L}', 'x') -replace '\d', '9') }) -join " | ")) }
      Write-Host $sat[$hi]
      foreach ($s in $sat[($hi+1)..([Math]::Min($hi+6, $sat.Count-1))]) { Write-Host (($s -creplace '\p{L}', 'x') -replace '\d', '9') }
      Write-Host "son: " ((($sat | Where-Object { $_ -ne "" } | Select-Object -Last 1) -creplace '\p{L}', 'x') -replace '\d', '9')
    }
  } finally { HastaTemizle }
}

function Gunluk {
  $j = Jeton
  $neden = GunlukKilit $j
  if ($neden) { Log "Atlandı: $neden"; return }
  Kayit "gunluk" "basladi" 0 "" $j
  Remove-Item $DURDUR -Force -ErrorAction SilentlyContinue
  BannerAc
  try {
    $p = RxSureci
    AsamaEnvanter $p; AsamaUrunDokum $p; StokYukle
    AsamaKarekod $p; KarekodYukle
    # satış: buluttaki son satış gününden 2 gün öncesinden bugüne
    $son = @(BulutOku "satis?select=tarih&tarih=lte.$((Get-Date).ToString('yyyy-MM-dd'))&order=tarih.desc&limit=1" $j)
    $bas = if ($son.Count -and $son[0].tarih) { ([datetime]$son[0].tarih).AddDays(-2) } else { (Get-Date).Date.AddDays(-30) }
    AsamaSatis $p $bas.ToString("dd.MM.yyyy") (Get-Date).ToString("dd.MM.yyyy") "satis.csv"
    SatisYukle "satis.csv"
    # alış: son fatura gününden 10 gün öncesinden bugüne (geç girilen faturalar da gelsin)
    $sa = @(BulutOku "alis?select=fat_tarih&fat_tarih=lte.$((Get-Date).ToString('yyyy-MM-dd'))&order=fat_tarih.desc&limit=1" (Jeton))
    $ab = if ($sa.Count -and $sa[0].fat_tarih) { ([datetime]$sa[0].fat_tarih).AddDays(-10) } else { (Get-Date).Date.AddDays(-30) }
    AsamaAlis $p $ab.ToString("dd.MM.yyyy") (Get-Date).ToString("dd.MM.yyyy") "alis.csv"
    AlisYukle "alis.csv"
    AsamaHasta $p
    Kayit "gunluk" "tamam" 0 "" (Jeton)
  } catch {
    Kayit "gunluk" "hata" 0 $_.Exception.Message (Jeton)
    throw
  }
}

# ---------- çalıştır ----------
# ======================= DEPOLAR (AS, Sancak) =======================
# Sadece okuma: giriş + ürün arama + ürün detayı. Sepete ekleme / sipariş YOK.
$DEPO_DAT = Join-Path $KOK "depo.dat"
$DEPOLAR = [ordered]@{
  as = @{ ad = "AS Ecza";     giris = "https://webdepo.asecza.com.tr/" }
  sn = @{ ad = "Sancak Ecza"; giris = "https://eticaret.sancakecza.com.tr/" }
}
function DpKoru([string]$s) { Add-Type -AssemblyName System.Security; [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($s), $null, 'CurrentUser')) }
function DpAc([string]$s)   { Add-Type -AssemblyName System.Security; [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($s), $null, 'CurrentUser')) }
function DepoAyarOku { if (Test-Path $DEPO_DAT) { $o = Get-Content $DEPO_DAT -Raw | ConvertFrom-Json; $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }; return $h }; @{} }
# Giriş sayfasındaki formu bulur: şifre kutusu olan form
function DepoForm([string]$url, $ses) {
  $r = Invoke-WebRequest -Uri $url -WebSession $ses -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60
  $html = $r.Content
  $formlar = [regex]::Matches($html, '(?is)<form\b([^>]*)>(.*?)</form>')
  foreach ($f in $formlar) {
    if ($f.Groups[2].Value -notmatch '(?i)type\s*=\s*["'']?password') { continue }
    $act = ([regex]::Match($f.Groups[1].Value, '(?i)action\s*=\s*["'']([^"'']*)')).Groups[1].Value
    $alanlar = New-Object System.Collections.ArrayList
    foreach ($i in [regex]::Matches($f.Groups[2].Value, '(?is)<input\b[^>]*>')) {
      $t = $i.Value
      $ad = ([regex]::Match($t, '(?i)\bname\s*=\s*["'']([^"'']+)')).Groups[1].Value; if (-not $ad) { continue }
      $tip = ([regex]::Match($t, '(?i)\btype\s*=\s*["'']?([a-z]+)')).Groups[1].Value.ToLower(); if (-not $tip) { $tip = "text" }
      $val = [Net.WebUtility]::HtmlDecode(([regex]::Match($t, '(?i)\bvalue\s*=\s*["'']([^"'']*)')).Groups[1].Value)
      $ph  = ([regex]::Match($t, '(?i)placeholder\s*=\s*["'']([^"'']*)')).Groups[1].Value
      [void]$alanlar.Add([pscustomobject]@{ ad = $ad; tip = $tip; deger = $val; ipucu = $ph })
    }
    $hedef = if ($act) { (New-Object Uri((New-Object Uri($r.BaseResponse.ResponseUri.AbsoluteUri)), [Net.WebUtility]::HtmlDecode($act))).AbsoluteUri } else { $r.BaseResponse.ResponseUri.AbsoluteUri }
    return [pscustomobject]@{ hedef = $hedef; alanlar = $alanlar; html = $f.Groups[2].Value }
  }
  throw "Giriş formu bulunamadı ($url)."
}
function DepoKur {
  $ay = DepoAyarOku
  foreach ($k in $DEPOLAR.Keys) {
    $d = $DEPOLAR[$k]
    $c = Read-Host ("{0} kurulsun mu? (e/h)" -f $d.ad); if ($c -notmatch '^[eE]') { continue }
    $ses = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $f = DepoForm $d.giris $ses
    $deger = @{}
    foreach ($a in ($f.alanlar | Where-Object { $_.tip -in @("text","email","tel","number","password") })) {
      $etiket = if ($a.ipucu) { $a.ipucu } else { $a.ad }
      if ($a.tip -eq "password") { $s = Read-Host ("  {0} — {1}" -f $d.ad, $etiket) -AsSecureString; $deger[$a.ad] = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)) }
      else { $deger[$a.ad] = Read-Host ("  {0} — {1}" -f $d.ad, $etiket) }
    }
    $ay[$k] = DpKoru (ConvertTo-Json $deger -Compress)
    ConvertTo-Json $ay | Set-Content $DEPO_DAT -Encoding UTF8
    try { $null = DepoGiris $k; Write-Host ("  {0}: giriş başarılı" -f $d.ad) -ForegroundColor Green } catch { Write-Host ("  {0}: giriş denemesi başarısız — {1}" -f $d.ad, $_.Exception.Message) -ForegroundColor Yellow }
  }
}
function DepoGiris([string]$k) {
  $ay = DepoAyarOku; if (-not $ay[$k]) { throw "kayıtlı değil" }
  $deger = DpAc $ay[$k] | ConvertFrom-Json
  $ses = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $ses.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
  $f = DepoForm $DEPOLAR[$k].giris $ses
  $govde = [ordered]@{}
  foreach ($a in $f.alanlar) {
    if ($a.tip -in @("checkbox","radio","button","image","file","reset")) { continue }
    if ($a.tip -eq "submit") { if (-not ($govde.Keys | Where-Object { $_ -eq "__sub" })) { $govde[$a.ad] = $a.deger; $govde["__sub"] = 1 }; continue }
    $p = $deger.PSObject.Properties[$a.ad]
    $govde[$a.ad] = if ($p) { $p.Value } else { $a.deger }
  }
  $govde.Remove("__sub")
  # Web Forms bağlantı düğmesi (__doPostBack) ile giriş
  if (($f.alanlar | Where-Object { $_.ad -eq "__EVENTTARGET" }) -and -not ($f.alanlar | Where-Object { $_.tip -eq "submit" })) {
    $m = [regex]::Match($f.html, "__doPostBack\(&#39;([^&]+)&#39;|__doPostBack\('([^']+)'")
    if ($m.Success) { $govde["__EVENTTARGET"] = if ($m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Groups[2].Value } }
  }
  $r = Invoke-WebRequest -Uri $f.hedef -Method Post -Body $govde -WebSession $ses -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60 -ContentType "application/x-www-form-urlencoded"
  if ($r.Content -match '(?i)type\s*=\s*["'']?password') {
    $hata = [regex]::Match($r.Content, '(?is)(hatal[ıi][^<]{0,80}|yanl[ıi][şs][^<]{0,80}|ge[çc]ersiz[^<]{0,80})').Value
    throw ("giriş olmadı " + $hata + " | gönderilen alanlar: " + (($govde.Keys) -join ","))
  }
  $ses
}
function DepoPost($ses, [string]$url, $govde, [string]$tur = "form") {
  Start-Sleep -Milliseconds 600
  if ($tur -eq "json") { $r = Invoke-WebRequest -Uri $url -Method Post -Body ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $govde -Compress))) -ContentType "application/json; charset=utf-8" -Headers @{ "X-Requested-With" = "XMLHttpRequest" } -WebSession $ses -UseBasicParsing -TimeoutSec 60 }
  else { $r = Invoke-WebRequest -Uri $url -Method Post -Body $govde -ContentType "application/x-www-form-urlencoded; charset=UTF-8" -Headers @{ "X-Requested-With" = "XMLHttpRequest"; "Referer" = "https://webdepo.asecza.com.tr/Siparis/hizlisiparis.aspx" } -WebSession $ses -UseBasicParsing -TimeoutSec 60 }
  $r.Content | ConvertFrom-Json
}
function DepoAS($ses, [string]$barkod) {
  $barkod = $barkod -replace '^0(\d{13})$', '$1'
  if (-not $script:asSayfa) { $null = Invoke-WebRequest "https://webdepo.asecza.com.tr/Siparis/hizlisiparis.aspx" -WebSession $ses -UseBasicParsing -TimeoutSec 60; $script:asSayfa = $true }   # detay isteği bu sayfa açılmadan "Hata oluştu" döner
  $u = DepoPost $ses "https://webdepo.asecza.com.tr/Siparis/hizlisiparis-ajax.aspx" @{ action = "GetUrunler"; searchText = $barkod; isInculude = "true"; isStoktakiler = "false"; siralama = "ilacASC"; marka = ""; baslangicSayfasi = "0"; topRowNum = "0"; sayfaMaxRowAdet = "10"; s = "s" }
  $l = @($u.obj.urunler); if (-not $l.Count) { return $null }
  $e = $l[0]
  $d = (DepoPost $ses "https://webdepo.asecza.com.tr/Ilac/IlacGetir-ajax.aspx" @{ action = "GetIlacDetay"; kod = $e.kodu; isEsdeger = "false"; esdeger = ""; isJenerik = "false"; jenerikId = ""; tip = "null"; ILACTIP = $e.ILACTIP; kampKodu = "" }).obj
  if (-not $d -or ($d.barkod -and $d.barkod -ne $barkod)) { return $null }
  $mf = @(); $vade = $null
  foreach ($k in @($d.kampanyalar)) {
    if (-not $vade) { $vade = $k.vadeGun }
    for ($i = 0; $i -lt @($k.miktar).Count; $i++) { if ($k.miktar[$i] -gt 0) { $mf += [ordered]@{ a = $k.miktar[$i]; m = $k.mf[$i]; n = [math]::Round([double]$k.netFiyati[$i], 2); v = $k.vadeGun } } }
  }
  [ordered]@{ d = [double]$d.depocuFiyati; s = $(if ("$($e.stokDurumu)" -match '^[1-9]') { 1 } else { 0 }); v = $vade; mf = $mf
              atc = $d.atc.value; atca = $d.atc.display; end = $d.endikasyon.display; etk = $d.etkenMadde.display }
}
function DepoSN($ses, [string]$barkod, [string]$adres) {
  $barkod = $barkod -replace '^0(\d{13})$', '$1'
  $r = DepoPost $ses $adres @{ Key = $barkod; SearchType = 0; StockType = 0; Page = 1; CacheForCampaign = $false; ItemScope = "0" } "json"
  $l = @($r.Value); if (-not $l.Count) { return $null }
  $e = $l[0]
  $tek = @(); foreach ($o in @($e.EQOffers)) { $tek += [ordered]@{ a = $o.Quantity; m = $o.ExtraQuantity; n = [math]::Round([double]$o.NetPrice, 2); v = $o.DaysDue } }
  [ordered]@{ d = [double]$e.SalesPrice; s = [int][bool]$e.HasStock; ad = $e.Name; mf = $tek }
}
# ---- Sancak: Cloudflare yüzünden doğrudan bağlanılamıyor. Chrome'daki "Eczane Stok - Depo Köprüsü" eklentisi
# açık Sancak sekmesinden arar; toplayıcı 127.0.0.1:47811'de iş verir, sonuçları alır. Eklenti yoksa / cevap vermezse
# Sancak bu çalışmada atlanır, önceki Sancak verisi korunur — program durmaz.
function HttpOku($st) {
  $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536; $bas = -1; $uz = 0
  while ($true) {
    $n = $st.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $ms.Write($buf, 0, $n)
    $b = $ms.ToArray()
    if ($bas -lt 0) { $t = [Text.Encoding]::ASCII.GetString($b); $i = $t.IndexOf("`r`n`r`n"); if ($i -ge 0) { $bas = $i + 4; $m = [regex]::Match($t.Substring(0, $i), '(?i)content-length:\s*(\d+)'); $uz = if ($m.Success) { [int]$m.Groups[1].Value } else { 0 } } }
    if ($bas -ge 0 -and $b.Length -ge $bas + $uz) { break }
  }
  $b = $ms.ToArray(); if ($bas -lt 0) { return $null }
  $ilk = ([Text.Encoding]::ASCII.GetString($b, 0, $bas) -split "`r`n")[0]
  [pscustomobject]@{ satir = $ilk; govde = [Text.Encoding]::UTF8.GetString($b, $bas, [math]::Min($uz, $b.Length - $bas)) }
}
function HttpYaz($st, [int]$kod, [string]$govde) {
  $g = [Text.Encoding]::UTF8.GetBytes($govde)
  $h = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $kod OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nCache-Control: no-store`r`nContent-Length: $($g.Length)`r`nConnection: close`r`n`r`n")
  $st.Write($h, 0, $h.Length); $st.Write($g, 0, $g.Length); $st.Flush()
}
function SancakKopru([string[]]$barkodlar, $giris) {
  $sonuc = @{}; $durum = "eklenti_yok"; $mesaj = ""
  $kalan = New-Object System.Collections.Generic.List[string]; foreach ($b in $barkodlar) { $kalan.Add(($b -replace '^0(\d{13})$', '$1')) }
  try { $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 47811); $l.Start() } catch { Log ("  Sancak: köprü portu açılamadı — " + $_.Exception.Message); return @{ sonuc = $sonuc; durum = "hata"; mesaj = "port" } }
  try {
    $bas = Get-Date; $son = Get-Date; $temas = $false; $chromeAcildi = $false; $verilen = @{}
    while ($true) {
      $gecen = ((Get-Date) - $bas).TotalSeconds; $sessiz = ((Get-Date) - $son).TotalSeconds
      if (-not $temas -and $gecen -gt 80 -and -not $chromeAcildi) {
        # eklenti hiç sormadı: Chrome kapalı olabilir → Sancak sayfasıyla küçük açılır (eklenti kendiliğinden başlar)
        $chromeAcildi = $true
        if (-not (Get-Process chrome -ErrorAction SilentlyContinue)) {
          $ch = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
          if ($ch) { try { Start-Process $ch "https://eticaret.sancakecza.com.tr/" -WindowStyle Minimized; Log "  Sancak: Chrome kapalıydı, açıldı" } catch { } }
        }
      }
      if (-not $temas -and $gecen -gt 170) { $durum = "eklenti_yok"; break }
      if ($temas -and $sessiz -gt 150) { if ($durum -eq "ok") { $durum = "yarim" }; break }
      if (-not $kalan.Count -or $gecen -gt 900) { break }
      if (-not $l.Pending()) { Start-Sleep -Milliseconds 200; continue }
      $c = $l.AcceptTcpClient()
      try {
        $st = $c.GetStream(); $st.ReadTimeout = 15000
        $r = HttpOku $st; if (-not $r) { continue }
        $temas = $true; $son = Get-Date
        if ($r.satir -match '^GET /is') {
          $parca = @($kalan | Select-Object -First 25)
          $is = [ordered]@{ barkodlar = $parca; adres = "https://eticaret.sancakecza.com.tr/" }
          if ($giris) { $is.giris = $giris }
          HttpYaz $st 200 (ConvertTo-Json $is -Compress -Depth 4)
        } elseif ($r.satir -match '^POST /sonuc') {
          HttpYaz $st 200 '{"tamam":true}'
          $o = $r.govde | ConvertFrom-Json
          if ($o.sonuc) { foreach ($p in $o.sonuc.PSObject.Properties) { $sonuc[$p.Name] = @($p.Value); [void]$kalan.Remove($p.Name) } }
          $durum = "$($o.durum)"; $mesaj = "$($o.mesaj)"
          if ($durum -ne "ok") { Log ("  Sancak: {0} {1}" -f $durum, $mesaj); break }
        } else { HttpYaz $st 404 '{}' }
      } catch { } finally { $c.Close() }
    }
  } finally { $l.Stop() }
  if ($durum -eq "ok" -and $kalan.Count) { $durum = "yarim" }
  @{ sonuc = $sonuc; durum = $durum; mesaj = $mesaj }
}
function SnCoz($liste, [string]$barkod) {
  $l = @($liste | Where-Object { $_ }); if (-not $l.Count) { return $null }
  # barkodla arayınca Sancak tek ürün döndürür (Barcode alanı boş geliyor)
  $e = $l | Where-Object { "$($_.Barcode)" -and "$($_.Barcode)" -match [regex]::Escape($barkod) } | Select-Object -First 1
  if (-not $e) { $e = $l[0] }
  $tek = @(); foreach ($o in @($e.EQOffers)) { if ($o -and $o.Quantity -gt 0) { $np = if ($o.NetPriceWithTaxes) { $o.NetPriceWithTaxes } else { $o.NetPrice }; $tek += [ordered]@{ a = $o.Quantity; m = $o.ExtraQuantity; n = [math]::Round([double]$np, 2); v = $o.DaysDue } } }
  $fiyat = foreach ($a in "SalesPrice","ListPrice") { if ($e.$a) { [double]$e.$a; break } }
  [ordered]@{ d = [double]$fiyat; s = [int]([bool]$e.HasStock -or [bool]$e.IsAvailableForSales); mf = $tek }
}
function AsamaDepo {
  $ay = DepoAyarOku; if (-not $ay.Count) { Log "Depo bilgisi kayıtlı değil, atlandı (toplayici.ps1 -DepoKur)."; return }
  $j = Jeton
  # sorgulanacak ürünler: son 90 günde satılan ilaçlar (en çok satan 350) + stokta az kalan çok satanlar
  $u = @(BulutOku "urun_ozet?select=barkod,ad,stok,adet_90&adet_90=gt.0&order=adet_90.desc&limit=350" $j | ForEach-Object { $_ })
  $barkodlar = @($u | Where-Object { $_.barkod -match '^\d{8,14}$' } | ForEach-Object { $_.barkod })
  $bilgi = @{}; foreach ($x in $u) { $bilgi[$x.barkod] = $x }
  Log ("Depo: {0} ürün sorgulanacak" -f $barkodlar.Count)
  $sesler = @{}
  foreach ($k in @($ay.Keys | Where-Object { $_ -ne "sn" })) { try { $sesler[$k] = DepoGiris $k; Log ("  {0}: giriş tamam" -f $DEPOLAR[$k].ad) } catch { Log ("  {0}: GİRİŞ HATASI — {1}" -f $DEPOLAR[$k].ad, $_.Exception.Message) } }
  $onceki = @{}; $oncekiSn = $null; try { $o = BulutOku "ayar?anahtar=eq.depo_fiyat&select=deger" $j; if ($o) { $ov = $o[0].deger | ConvertFrom-Json; $oncekiSn = $ov.sn; foreach ($x in $ov.u) { $onceki[$x.b] = $x } } } catch { }
  # Sancak (Chrome eklentisi üzerinden)
  $snGiris = $null; if ($ay["sn"]) { try { $snGiris = DpAc $ay["sn"] | ConvertFrom-Json } catch { } }
  $sn = SancakKopru $barkodlar $snGiris
  $snTamam = @($sn.sonuc.Keys).Count
  Log ("  Sancak: {0} ürün, durum {1}" -f $snTamam, $sn.durum)
  if (-not $sesler.Count -and -not $snTamam) { throw "Hiçbir depoya girilemedi." }
  $kat = @{}; try { $o = BulutOku "ayar?anahtar=eq.ilac_kategori&select=deger" $j; if ($o) { foreach ($p in ($o[0].deger | ConvertFrom-Json).PSObject.Properties) { $y = $p.Value.yok; if ($y -and ($y -isnot [string] -or ((Get-Date) - [datetime]$y).TotalDays -gt 30)) { continue }; $kat[$p.Name] = $p.Value } } } catch { }
  $simdi = (Get-Date).ToString("o"); $sonuc = New-Object System.Collections.ArrayList; $hata = @{}; $ard = @{}
  foreach ($b in $barkodlar) {
    $s = [ordered]@{ b = $b; ad = $bilgi[$b].ad; st = $bilgi[$b].stok; a90 = $bilgi[$b].adet_90 }
    foreach ($k in @($sesler.Keys)) {
      try { $v = DepoAS $sesler[$k] $b
            if ($v) { if ($k -eq "as" -and $v.atc) { $kat[$b] = [ordered]@{ atc = $v.atc; a = $v.atca; e = $v.end; m = $v.etk }; foreach ($z in "atc","atca","end","etk") { $v.Remove($z) } }; $s[$k] = $v }; $ard[$k] = 0 }
      catch { $hata[$k] = 1 + [int]$hata[$k]; $ard[$k] = 1 + [int]$ard[$k]; if ($hata[$k] -eq 3) { Log ("  {0}: tekrarlayan hata — {1}" -f $DEPOLAR[$k].ad, $_.Exception.Message) }
              if ($ard[$k] -ge 8) { Log ("  {0}: üst üste hata, bu çalışmada bırakıldı (depo sunucusu yorulmasın)" -f $DEPOLAR[$k].ad); $sesler.Remove($k); break } }
    }
    $bk = $b -replace '^0(\d{13})$', '$1'
    if ($sn.sonuc.ContainsKey($bk)) { $v = SnCoz $sn.sonuc[$bk] $bk; if ($v) { $s["sn"] = $v } }
    elseif ($onceki[$b] -and $onceki[$b].sn) { $s["sn"] = $onceki[$b].sn }   # bu saat alınamadı: önceki Sancak verisi kalsın
    # yeni MF: önceki çekimde MF yoktu ya da farklıydı → 'y' zamanı (2 gün gösterilir)
    $mfi = (@("as","sn") | ForEach-Object { if ($s[$_]) { $_ + ":" + ((@($s[$_].mf) | Where-Object { $_.m -gt 0 } | ForEach-Object { "$($_.a)+$($_.m)" } | Sort-Object -Unique) -join " ") } }) -join "|"
    $s["k"] = $mfi
    $o = $onceki[$b]
    if ($o -and ($o.as -or $o.sn) -and $o.k -ne $mfi -and ($mfi -match '\d\+\d')) { $s["y"] = $simdi } elseif ($Bas -ne "mfsifirla" -and $o -and $o.y -and ((Get-Date) - [datetime]$o.y).TotalHours -lt 48) { $s["y"] = $o.y }
    [void]$sonuc.Add($s)
  }
  # kategori (etken madde / tedavi grubu) her çalışmada stoktaki 150 ürün daha tamamlanır — arama için
  if ($sesler["as"]) {
    $stoklu = @(BulutOku "urun_ozet?select=barkod&stok=gt.0&limit=10000" $j | ForEach-Object { $_.barkod } | Where-Object { $_ -match '^\d{8,14}$' -and -not $kat.ContainsKey($_) } | Select-Object -First 150)
    foreach ($b in $stoklu) { try { $v = DepoAS $sesler["as"] $b; $kat[$b] = if ($v -and $v.atc) { [ordered]@{ atc = $v.atc; a = $v.atca; e = $v.end; m = $v.etk } } else { [ordered]@{ yok = (Get-Date).ToString("yyyy-MM-dd") } } } catch { } }
  }
  # ilk çekimde ya da toplu değişimde ürünlerin çoğu "yeni" görünür → bu bir başlangıçtır, işaretleri sil
  foreach ($g in ($sonuc | Where-Object { $_.y } | Group-Object { $_.y })) { if ($g.Count -gt [math]::Max(20, $sonuc.Count * 0.3)) { foreach ($x in $g.Group) { $x.Remove("y") } } }
  if (-not $sesler.Count -and -not $snTamam) { throw "Depo çekimi yarıda kaldı, buluta yazılmadı." }
  $dl = @($sesler.Keys | ForEach-Object { $DEPOLAR[$_].ad }); if (@($sonuc | Where-Object { $_.sn }).Count) { $dl += $DEPOLAR["sn"].ad }
  $snBilgi = [ordered]@{ durum = $sn.durum; deneme = $simdi; zaman = $(if ($snTamam) { $simdi } elseif ($oncekiSn) { $oncekiSn.zaman } else { $null }) }
  $veri = [ordered]@{ zaman = $simdi; depolar = @($dl | Select-Object -Unique); sn = $snBilgi; u = $sonuc.ToArray() }
  BulutEkle "ayar" @([ordered]@{ anahtar = "depo_fiyat"; deger = (ConvertTo-Json $veri -Depth 6 -Compress); guncelleme = $simdi }) $j "anahtar"
  BulutEkle "ayar" @([ordered]@{ anahtar = "ilac_kategori"; deger = (ConvertTo-Json $kat -Depth 4 -Compress); guncelleme = $simdi }) $j "anahtar"
  Log ("Depo: {0} ürün yüklendi, {1} yeni MF, {2} ilaç kategorisi" -f $sonuc.Count, @($sonuc | Where-Object { $_.y -eq $simdi }).Count, $kat.Count)
}

try {
  Log "=== Toplayıcı başladı (aşama: $Asama) ==="
  if ($Kur) { GirisKur; Log "Bitti."; return }
  if ($HastaKur) { HastaKur; return }
  if ($DepoKur) { DepoKur; return }
  if ($Asama -eq "depo") { AsamaDepo; Log "Bitti."; $script:KOD = 0; return }
  if ($Asama -eq "yukle") { StokYukle; Log "Bitti."; return }
  if ($Asama -eq "kkyukle") { KarekodYukle; Log "Bitti."; return }
  if ($Asama -eq "gunluk") { Gunluk; Log "Bitti."; $script:KOD = 0; return }
  $p = RxSureci
  # elle çalıştırılınca konsol Rx'in önünde kalıp tıklamaları yutmasın: küçült (sonda geri açılır)
  $script:KONSOL = @(Get-Process -Name WindowsTerminal, powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | ForEach-Object { $_.MainWindowHandle })
  foreach ($h in $script:KONSOL) { [void][W2]::ShowWindow($h, 6) }; Start-Sleep 1
  foreach ($w in (Pencereler $p.Id | Where-Object { $_.Ad -in @("Save As","Farklı Kaydet","Filtreleme") -or $_.Ad -like "*Ayarları*" })) { [void][W2]::SendMessage($w.H, 0x10, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Milliseconds 500 }
  foreach ($w in (Pencereler $p.Id | Where-Object { $_.Ad -in @("Yazdır","Preview") })) { [void][W2]::SendMessage($w.H, 0x10, [IntPtr]::Zero, [IntPtr]::Zero); Log "Açık kalmış önizleme kapatıldı" }
  switch ($Asama) {
    "envanter"  { AsamaEnvanter $p }
    "urundokum" { AsamaUrunDokum $p }
    "stok"      { AsamaEnvanter $p; AsamaUrunDokum $p; StokYukle; AsamaKarekod $p; KarekodYukle }
    "yukle"     { StokYukle }
    "karekod"   { AsamaKarekod $p; KarekodYukle }
    "hasta"     { AsamaHasta $p }
    "hastadene" { HastaDene $p }
    "satis"     { AsamaSatis $p $Bas $Bit "satis.csv"; SatisYukle "satis.csv" }
    "satisgecmis" { SatisGecmis $Bas }
    "alis"      { AsamaAlis $p $Bas $Bit "alis.csv"; AlisYukle "alis.csv" }
    "alisgecmis" { AlisGecmis $Bas }
    "alisdene"  { AsamaAlis $p $Bas $Bit "alis.csv"; CsvBas (Join-Path $VERI "alis.csv") 6 }
    default     { Log "Bilinmeyen aşama: $Asama" }
  }
  Log "Bitti."
} catch {
  Log ("HATA: " + $_.Exception.Message); $script:KOD = 1
} finally {
  New-Item -ItemType File -Force -Path (Join-Path $KOK "bitti.flag") | Out-Null     # banner kapansın
}
if ($Asama -eq "gunluk") { exit $script:KOD }
foreach ($h in @($script:KONSOL)) { if ($h) { [void][W2]::ShowWindow($h, 9); [void][W2]::SetForegroundWindow($h) } }
