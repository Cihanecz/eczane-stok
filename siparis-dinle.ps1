# =====================================================================
#  SIPARIS-DINLE - global hotkey dinleyicisi (arka plan servisi)
#  Win32 RegisterHotKey ile SISTEM GENELI hotkey. Oncelik listesindeki ilk
#  BOS kombinasyonu secer (Ctrl+Shift+S bazen ekran-goruntusu araclarinca
#  kapilmis oluyor). Secilen kombinasyon dinle.log'a + aktif-hotkey.txt'ye yazilir.
#  Basilinca siparis-tara.ps1'i GIZLI calistirir (Medula onde kalir, OCR okur).
# =====================================================================
$ErrorActionPreference = "Stop"
$KOK = "C:\EczaneStok"
$TARA = Join-Path $KOK "siparis-tara.ps1"
$LOG  = Join-Path $KOK "dinle.log"
$AKTIF= Join-Path $KOK "aktif-hotkey.txt"
function DLog($m){ try { Add-Content -Path $LOG -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss")+"  "+$m) -Encoding UTF8 } catch {} }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class HotKeyWin {
  [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
  [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
  [StructLayout(LayoutKind.Sequential)] public struct MSG {
    public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int pt_x; public int pt_y;
  }
  [DllImport("user32.dll")] public static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
}
"@

$C=0x0002; $S=0x0004; $A=0x0001; $WM_HOTKEY=0x0312
# Oncelik: Alt'siz (AltGr sorunu olmasin), once harf sonra fonksiyon tuslari
$adaylar = @(
  @{ ad='F8'; mod=0; vk=0x77 },
  @{ ad='Ctrl+Shift+D'; mod=($C -bor $S); vk=0x44 },
  @{ ad='Ctrl+Shift+G'; mod=($C -bor $S); vk=0x47 },
  @{ ad='Ctrl+Shift+B'; mod=($C -bor $S); vk=0x42 },
  @{ ad='Ctrl+Shift+F9'; mod=($C -bor $S); vk=0x78 },
  @{ ad='Ctrl+Shift+F8'; mod=($C -bor $S); vk=0x77 },
  @{ ad='Ctrl+Shift+S'; mod=($C -bor $S); vk=0x53 }
)
$secilen = $null
foreach($h in $adaylar){
  if([HotKeyWin]::RegisterHotKey([IntPtr]::Zero, 1, [uint32]$h.mod, [uint32]$h.vk)){ $secilen=$h; break }
  else { DLog ("dolu: "+$h.ad) }
}
if(-not $secilen){ DLog "HICBIR kombinasyon bos degil - hepsini dene"; exit 1 }
try { Set-Content $AKTIF $secilen.ad -Encoding UTF8 } catch {}
DLog ("Dinleyici basladi - AKTIF HOTKEY: "+$secilen.ad)

$msg = New-Object HotKeyWin+MSG
while ([HotKeyWin]::GetMessage([ref]$msg, [IntPtr]::Zero, 0, 0) -gt 0) {
  if ($msg.message -eq $WM_HOTKEY) {
    DLog "hotkey algilandi -> siparis-tara calisiyor"
    try { Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TARA`" -NoSleep" -WindowStyle Hidden } catch { DLog ("tara baslatilamadi: "+$_.Exception.Message) }
  }
}
