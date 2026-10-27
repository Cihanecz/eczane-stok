# Eczane Stok — gözcü. Windows açılınca gizli başlar; Rx'e giriş yapılınca (saat fark etmez) günde bir kez toplayıcıyı çalıştırır; depoları saatte bir okur.
$KOK = "C:\EczaneStok"
$RX_ANA = "RxMediaPharma Eczane Y"   # ana pencere adı bununla başlar (Türkçe harfe güvenilmez; giriş ekranı eşleşmez)
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class GZ {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static bool Var(string ad) { bool v = false; EnumWindows((h, l) => { if (IsWindowVisible(h)) { var s = new StringBuilder(256); GetWindowText(h, s, 256); if (s.ToString().StartsWith(ad)) { v = true; return false; } } return true; }, IntPtr.Zero); return v; }
}
"@
function Log($m) { Add-Content -Path (Join-Path $KOK "gozcu.txt") -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $m) -Encoding UTF8 }
# Telefondan "sepete ekle" istekleri: bulutta bekleyen istek varsa toplayıcıyı "sepet" aşamasında çalıştır (15 sn'de bir bakılır)
$SB_URL = "https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY = "sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$script:jt = $null; $script:jtZaman = [datetime]::MinValue; $script:sepetPr = $null
function SepetBak {
  try {
    if ($script:sepetPr -and -not $script:sepetPr.HasExited) { return }
    if (-not $script:jt -or ((Get-Date) - $script:jtZaman).TotalMinutes -gt 45) {
      $g = Join-Path $KOK "giris.dat"; if (-not (Test-Path $g)) { return }
      $s = Get-Content $g -Encoding UTF8
      $sf = ConvertTo-SecureString $s[1].Trim()
      $duz = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
      $govde = @{ email = $s[0].Trim(); password = $duz } | ConvertTo-Json
      $r = Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{ apikey = $SB_KEY } -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($govde)) -TimeoutSec 30
      $script:jt = $r.access_token; $script:jtZaman = Get-Date
    }
    $o = Invoke-RestMethod -Uri "$SB_URL/rest/v1/ayar?anahtar=eq.sepet_istek&select=deger" -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $($script:jt)" } -TimeoutSec 20
    if ($o -and "$($o[0].deger)" -match '"durum":"bekliyor"') {
      Log "Sepet isteği var, işleniyor"
      $script:sepetPr = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$KOK\toplayici.ps1`" -Asama sepet" -WindowStyle Hidden -PassThru
    }
  } catch { $script:jt = $null }
}
# Sürekli açık sepet döngüsü (toplayici.ps1 -Asama sepetdongu): kapanırsa 15 sn içinde yeniden açılır
function SepetDonguBak {
  try {
    if ($script:sepetPr -and -not $script:sepetPr.HasExited) { return }
    if (-not (Test-Path (Join-Path $KOK "giris.dat"))) { return }
    $script:sepetPr = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$KOK\toplayici.ps1`" -Asama sepetdongu" -WindowStyle Hidden -PassThru
  } catch { }
}
Log "Gözcü başladı"
$deneme = @{}
$depoSon = [datetime]::MinValue
$tur = 0
while ($true) {
  # 60 sn'lik ana döngü; arada 15 sn'de bir sepet isteklerine bak
  for ($k = 0; $k -lt 4; $k++) { SepetDonguBak; Start-Sleep 15 }
  # Depolar (Rx'e dokunmaz): depo kaydı (depo.dat) VEYA eklenti-aktif işareti (depo-aktif.txt) varsa 08:00-21:00 arası saatte bir fiyat/MF çek
  $h = (Get-Date).Hour
  if (((Test-Path (Join-Path $KOK "depo.dat")) -or (Test-Path (Join-Path $KOK "depo-aktif.txt"))) -and $h -ge 8 -and $h -lt 21 -and ((Get-Date) - $depoSon).TotalMinutes -ge 60) {
    $depoSon = Get-Date
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$KOK\toplayici.ps1`" -Asama depo" -WindowStyle Hidden | Out-Null
  }
  $bugun = (Get-Date).ToString("yyyy-MM-dd")
  $isaret = Join-Path $KOK "tamam-$bugun.txt"
  if (Test-Path $isaret) { continue }
  if (-not (Get-Process -Name "RxMediaPharmaEYS" -ErrorAction SilentlyContinue)) { continue }
  if (-not [GZ]::Var($RX_ANA)) { continue }                 # henüz giriş yapılmamış
  if (-not $deneme.ContainsKey($bugun)) { $deneme[$bugun] = @{ n = 0; son = [datetime]::MinValue } }
  $d = $deneme[$bugun]
  if ($d.n -ge 6 -or ((Get-Date) - $d.son).TotalMinutes -lt 10) { continue }   # günde 6 deneme, 10 dk arayla
  if ($d.n -eq 0) { Log "Rx'e giriş görüldü, 45 sn sonra başlanacak"; Start-Sleep 45 }
  $d.n++; $d.son = Get-Date
  $pr = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$KOK\toplayici.ps1`" -Asama gunluk" -WindowStyle Hidden -PassThru -Wait
  Log "Toplayıcı bitti, çıkış kodu $($pr.ExitCode) (deneme $($d.n))"
  if ($pr.ExitCode -eq 0) { Set-Content -Path $isaret -Value (Get-Date) }
}
