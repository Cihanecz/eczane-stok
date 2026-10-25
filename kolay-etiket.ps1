param([string]$Test = "", [int]$Bekle = 8)
# Kolay Asistan'dan ilac etiket yazilarini (endikasyon + kullanim) tek tek okur.
# Sadece okur; Kolay'in kendisine baska bir sey yapmaz. Kaldigi yerden devam eder.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class KW {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, int f, int e);
 [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint e);
 [DllImport("user32.dll")] public static extern short GetKeyState(int k);
 public delegate bool EP(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EP f, IntPtr l);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
 public static IntPtr Bul(string bas) {
  IntPtr r = IntPtr.Zero;
  EnumWindows(delegate(IntPtr h, IntPtr l) { var sb = new System.Text.StringBuilder(256); GetWindowText(h, sb, 256);
    if (sb.ToString().StartsWith(bas)) { r = h; return false; } return true; }, IntPtr.Zero);
  return r;
 }
}
"@

$KDIR = "${env:ProgramFiles(x86)}\Kolay Asistan"
$CIKTI = "C:\EczaneStok\kolay-etiket.csv"
$DURUM = "C:\EczaneStok\kolay-etiket-durum.txt"
$A = [Windows.Automation.AutomationElement]
$TS = [Windows.Automation.TreeScope]
# arama kutusunun pencereye gore yeri (olculdu: imlec 601,153 / pencere 278,40)
$OX = 323; $OY = 113

function Pencere {
  $w = $null
  foreach ($e in $A::RootElement.FindAll($TS::Children, [Windows.Automation.Condition]::TrueCondition)) {
    if ($e.Current.Name -like 'Kolay Asistan |*') { $w = $e; break }
  }
  return $w
}
function Alan($w, $id) {
  $e = $w.FindFirst($TS::Descendants, (New-Object Windows.Automation.PropertyCondition($A::AutomationIdProperty, $id)))
  if (-not $e) { return "" }
  try { return [string]$e.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { return "" }
}
function Tikla($x, $y) {
  [KW]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 80
  [KW]::mouse_event(2, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [KW]::mouse_event(4, 0, 0, 0, 0)
}
function OneGetir($w) {
  $h = [IntPtr]$w.Current.NativeWindowHandle
  if ([KW]::IsIconic($h)) { [KW]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 400 }
  [KW]::keybd_event(0x12, 0, 0, 0); [KW]::SetForegroundWindow($h) | Out-Null; [KW]::keybd_event(0x12, 0, 2, 0)
  Start-Sleep -Milliseconds 250
}
function Duz($s) { return (($s -replace '^\(\d+\)\s*', '' -replace '\.\.\.$', '').Trim()) }
function Temiz($s) { return (($s -replace '\u00AD', '' -replace '[\r\n\t]+', ' ' -replace '\s{2,}', ' ').Trim()) }

function Etiketler($w) {
  $r = @()
  foreach ($t in $w.FindAll($TS::Descendants, (New-Object Windows.Automation.PropertyCondition($A::ClassNameProperty, 'ucTicketMedicine')))) {
    $r += [pscustomobject]@{ el = $t; ad = (Alan $t 'txtMedicineName'); y = $t.Current.BoundingRectangle.Y }
  }
  return $r
}
# Turkce harf / noktalama farklarini yok sayarak karsilastirir (UNIKLAR / FiLM farklari)
function Sade($s) {
  $s = "$s".ToUpperInvariant()
  # Turkce harfler karakter koduyla (dosya kodlamasindan etkilenmesin)
  foreach ($c in @(@(0x130,'I'),@(0x131,'I'),@(0x15E,'S'),@(0x15F,'S'),@(0x11E,'G'),@(0x11F,'G'),@(0xDC,'U'),@(0xFC,'U'),@(0xD6,'O'),@(0xF6,'O'),@(0xC7,'C'),@(0xE7,'C'))) { $s = $s.Replace([string][char]$c[0], $c[1]) }
  return ($s -replace '[^A-Z0-9]', '')
}
function AdUyar($etiketAd, $ad) {
  $k = Sade (Duz $etiketAd); $a = Sade $ad
  if ($k.Length -lt 3) { return $false }
  if ($a.StartsWith($k)) { return $true }
  # etiket adi kisaltilmis olabilir: ilk 8 harf ayniysa kabul
  $n = [Math]::Min(8, [Math]::Min($k.Length, $a.Length))
  return ($n -ge 5 -and $a.Substring(0, $n) -eq $k.Substring(0, $n))
}

function Oku($w, $barkod, $ad) {
  $once = @(Etiketler $w)
  $imza = ($once | ForEach-Object { $_.ad }) -join '|'
  OneGetir $w
  $r = $w.Current.BoundingRectangle
  Tikla ([int]($r.X + $OX)) ([int]($r.Y + $OY))
  Start-Sleep -Milliseconds 200
  [Windows.Forms.SendKeys]::SendWait("^a"); Start-Sleep -Milliseconds 100
  [Windows.Forms.SendKeys]::SendWait($barkod)
  Start-Sleep -Milliseconds 1200
  [Windows.Forms.SendKeys]::SendWait("{ENTER}")
  Start-Sleep -Milliseconds 1500
  [Windows.Forms.SendKeys]::SendWait("{DOWN}{ENTER}")
  $son = (Get-Date).AddSeconds($Bekle); $sonra = @()
  while ((Get-Date) -lt $son) {
    Start-Sleep -Milliseconds 400
    $sonra = @(Etiketler $w)
    if ((($sonra | ForEach-Object { $_.ad }) -join '|') -ne $imza) { Start-Sleep -Milliseconds 500; $sonra = @(Etiketler $w); break }
  }
  $o = [ordered]@{ barkod = $barkod; ad = $ad; etiketAd = ""; endikasyon = ""; kullanim = ""; uyari = ""; durum = "YENI_ETIKET_YOK" }
  if ((($sonra | ForEach-Object { $_.ad }) -join '|') -eq $imza) { return [pscustomobject]$o }
  $uyan = @($sonra | Where-Object { AdUyar $_.ad $ad } | Sort-Object y)
  if (-not $uyan) { $o.durum = "AD_UYMUYOR"; $o.etiketAd = (($sonra | Sort-Object y | Select-Object -Last 1).ad); return [pscustomobject]$o }
  $e = $uyan[-1].el
  $o.etiketAd = Duz $uyan[-1].ad
  $o.endikasyon = Temiz (Alan $e 'txtIndication')
  $o.kullanim = Temiz (Alan $e 'txtUsage')
  $o.uyari = Temiz (Alan $e 'txtWarning')
  $o.durum = "OK"
  return [pscustomobject]$o
}

# --- bulut (Eczane Stok sitesinin ayar tablosu; sadece kolay_etiket_* satirlari)
$SB_URL = "https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY = "sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$script:jt = $null; $script:jtZaman = [datetime]::MinValue
Add-Type -AssemblyName System.Web
function JS($t) { return [Web.HttpUtility]::JavaScriptStringEncode("$t", $true) }
function Jeton {
  if ($script:jt -and ((Get-Date) - $script:jtZaman).TotalMinutes -lt 45) { return $script:jt }
  $s = Get-Content "C:\EczaneStok\giris.dat" -Encoding UTF8
  $sf = ConvertTo-SecureString $s[1].Trim()
  $duz = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
  $govde = @{ email = $s[0].Trim(); password = $duz } | ConvertTo-Json
  $r = Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{ apikey = $SB_KEY } -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($govde)) -TimeoutSec 30
  $script:jt = $r.access_token; $script:jtZaman = Get-Date
  return $script:jt
}
function AyarYaz([string]$anahtar, [string]$deger) {
  if ($Test) { return }
  try {
    $json = '[{"anahtar":' + (JS $anahtar) + ',"deger":' + (JS $deger) + ',"guncelleme":' + (JS (Get-Date).ToString("o")) + '}]'
    Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $(Jeton)"; Prefer = "resolution=merge-duplicates,return=minimal" } -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 120 | Out-Null
  } catch { $script:jt = $null; Add-Content "C:\EczaneStok\kolay-etiket-hata.txt" ("$(Get-Date -f s) bulut: " + $_.Exception.Message) }
}
function VeriYukle {
  if ($Test -or -not (Test-Path $CIKTI)) { return }
  $g = @{}; foreach ($r in (Import-Csv $CIKTI -Encoding UTF8)) { if ($r.durum -eq "OK") { $g[$r.barkod] = $r } }
  $sb = New-Object Text.StringBuilder; [void]$sb.Append('{"tarih":' + (JS (Get-Date).ToString("o")) + ',"alanlar":["barkod","ad","etiketAd","endikasyon","kullanim","uyari"],"l":[')
  $ilk = $true
  foreach ($r in $g.Values) { if (-not $ilk) { [void]$sb.Append(',') }; $ilk = $false; [void]$sb.Append('[' + (JS $r.barkod) + ',' + (JS $r.ad) + ',' + (JS $r.etiketAd) + ',' + (JS $r.endikasyon) + ',' + (JS $r.kullanim) + ',' + (JS $r.uyari) + ']') }
  [void]$sb.Append(']}')
  AyarYaz "kolay_etiket_veri" $sb.ToString()
}

# --- Kolay'i yeniden baslat (etiket listesi birikince Windows pencere kaynagi doluyor)
function KolayYenile {
  AyarYaz "kolay_etiket_durum" "$(Get-Date -f 'dd.MM HH:mm') Kolay yeniden baslatiliyor"
  Get-Process 'Kolay Asistan' -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep 4
  Start-Process "$KDIR\Kolay Asistan.exe" -WorkingDirectory $KDIR
  $son = (Get-Date).AddSeconds(120)
  while ((Get-Date) -lt $son) {
    Start-Sleep 3
    $w = Pencere
    if (-not $w) { $h = [KW]::Bul("Kolay Asistan |"); if ($h -ne [IntPtr]::Zero) { [KW]::ShowWindow($h, 5) | Out-Null; [KW]::ShowWindow($h, 9) | Out-Null } ; continue }
    if (@(Etiketler $w).Count -ge 0 -and $w.Current.BoundingRectangle.Width -gt 500) { Start-Sleep 8; return }
  }
}

# --- liste
$dosya = Get-ChildItem "$KDIR\Assets\Medicine\MedicineList_v*.json" | Sort-Object Name -Descending | Select-Object -First 1
$L = [IO.File]::ReadAllText($dosya.FullName) | ConvertFrom-Json
$L = @($L | Where-Object { $_.t -lt 2 -and $_.a -eq 1 } | Sort-Object n)
$TL = @($Test -split "[,; ]+" | Where-Object { $_ })
if ($Test) { $L = @($L | Where-Object { $TL -contains $_.b }); if (-not $L) { $L = @($TL | ForEach-Object { [pscustomobject]@{ b = $_; n = "" } }) } }

for ($tur = 1; $tur -le 2; $tur++) {
$bitti = @{}
if (-not $Test -and (Test-Path $CIKTI)) { Import-Csv $CIKTI -Encoding UTF8 | Where-Object { $_.durum -eq "OK" } | ForEach-Object { $bitti[$_.barkod] = 1 } }
$kalan = @($L | Where-Object { -not $bitti.ContainsKey($_.b) })
"Tur $tur - Toplam $($L.Count), biten $($bitti.Count), kalan $($kalan.Count)"
if (-not $kalan) { break }

$i = 0; $bas = Get-Date; $ardHata = 0; $okSay = 0; $sonYenile = 0
foreach ($x in $kalan) {
  $i++
  [KW]::SetThreadExecutionState(2147483651) | Out-Null   # ekran/uyku acik kalsin (sadece bu calisirken)
  if (([KW]::GetKeyState(0x91) -band 1) -ne 0) {         # Scroll Lock yanikken duraklat
    AyarYaz "kolay_etiket_durum" "$(Get-Date -f 'dd.MM HH:mm') DURAKLATILDI (Scroll Lock) - islenen $($bitti.Count + $okSay)/$($L.Count)"
    while (([KW]::GetKeyState(0x91) -band 1) -ne 0) { Start-Sleep 3 }
  }
  $w = Pencere
  if (-not $w) {
    $h = [KW]::Bul("Kolay Asistan |")   # tepsiye gizlendiyse geri ac
    if ($h -ne [IntPtr]::Zero) { [KW]::ShowWindow($h, 5) | Out-Null; [KW]::ShowWindow($h, 9) | Out-Null; Start-Sleep 2; $w = Pencere }
  }
  if (-not $w -or ($i - $sonYenile) -ge 80) { KolayYenile; $sonYenile = $i; $w = Pencere }
  if (-not $w) { AyarYaz "kolay_etiket_durum" "$(Get-Date -f 'dd.MM HH:mm') Kolay penceresi acilamadi, 60 sn sonra tekrar"; Start-Sleep 60; continue }
  $s = $null
  for ($d = 0; $d -lt 2; $d++) {
    try { $s = Oku $w $x.b $x.n } catch { $s = [pscustomobject]@{ barkod = $x.b; ad = $x.n; etiketAd = ""; endikasyon = ""; kullanim = ""; uyari = ""; durum = "HATA " + $_.Exception.Message } }
    if ($s.durum -eq "OK") { break }
    Start-Sleep 2
  }
  if ($s.durum -eq "OK") { $ardHata = 0; $okSay++ } else { $ardHata++ }
  if ($Test) { $s | Format-List | Out-String -Width 200 }
  else { $s | Export-Csv $CIKTI -Append -NoTypeInformation -Encoding UTF8 }
  if ($ardHata -eq 3 -or $ardHata -eq 8) { KolayYenile; $sonYenile = $i }
  if ($ardHata -ge 15) { AyarYaz "kolay_etiket_durum" "$(Get-Date -f 'dd.MM HH:mm') ust uste 15 hata, 5 dk bekleniyor. Son: $($x.n) [$($s.durum)]"; Start-Sleep 300; $ardHata = 0 }
  if ($i % 10 -eq 0 -or $i -eq $kalan.Count) {
    $hiz = ((Get-Date) - $bas).TotalSeconds / $i
    $yazi = "$(Get-Date -f 'dd.MM HH:mm') tur $tur  islenen $($bitti.Count + $okSay)/$($L.Count)  ilac basi $([Math]::Round($hiz,1)) sn  tahmini bitis $((Get-Date).AddSeconds($hiz * ($kalan.Count - $i)).ToString('dd.MM HH:mm'))  son: $($x.n) -> $($s.endikasyon) [$($s.durum)]"
    $yazi | Set-Content $DURUM -Encoding UTF8
    AyarYaz "kolay_etiket_durum" $yazi
  }
  if ($i % 250 -eq 0) { VeriYukle }
}
VeriYukle
}
AyarYaz "kolay_etiket_durum" "$(Get-Date -f 'dd.MM HH:mm') BITTI"
[KW]::SetThreadExecutionState(2147483648) | Out-Null
"BITTI"
