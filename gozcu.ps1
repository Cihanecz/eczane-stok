# Eczane Stok — gözcü. Windows açılınca gizli başlar; Rx'e giriş yapılınca (saat fark etmez) günde bir kez toplayıcıyı çalıştırır.
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
Log "Gözcü başladı"
$deneme = @{}
while ($true) {
  Start-Sleep 60
  $bugun = (Get-Date).ToString("yyyy-MM-dd")
  $isaret = Join-Path $KOK "tamam-$bugun.txt"
  if (Test-Path $isaret) { continue }
  if (-not (Get-Process -Name "RxMediaPharmaEYS" -ErrorAction SilentlyContinue)) { continue }
  if (-not [GZ]::Var($RX_ANA)) { continue }                 # henüz giriş yapılmamış
  if (-not $deneme.ContainsKey($bugun)) { $deneme[$bugun] = @{ n = 0; son = [datetime]::MinValue } }
  $d = $deneme[$bugun]
  if ($d.n -ge 3 -or ((Get-Date) - $d.son).TotalMinutes -lt 30) { continue }
  if ($d.n -eq 0) { Log "Rx'e giriş görüldü, 90 sn sonra başlanacak"; Start-Sleep 90 }
  $d.n++; $d.son = Get-Date
  $pr = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$KOK\toplayici.ps1`" -Asama gunluk" -WindowStyle Hidden -PassThru -Wait
  Log "Toplayıcı bitti, çıkış kodu $($pr.ExitCode) (deneme $($d.n))"
  if ($pr.ExitCode -eq 0) { Set-Content -Path $isaret -Value (Get-Date) }
}
