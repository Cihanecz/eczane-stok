# =====================================================================
#  SIPARIS-DINLE  - Ctrl+Shift+S global hotkey dinleyicisi (arka plan servisi)
#  Win32 RegisterHotKey ile SISTEM GENELI hotkey kaydeder (hangi pencere onde
#  olursa olsun calisir - .lnk kisayol-hotkey'in aksine guvenilir).
#  Basilinca siparis-tara.ps1'i GIZLI calistirir (Medula onde kalir, OCR okur).
#  Logon'da zamanlanmis gorevle baslar; gizli calisir.
# =====================================================================
$ErrorActionPreference = "Stop"
$KOK = "C:\EczaneStok"
$TARA = Join-Path $KOK "siparis-tara.ps1"
$LOG  = Join-Path $KOK "dinle.log"
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

$MOD_CONTROL = 0x0002; $MOD_SHIFT = 0x0004; $VK_S = 0x53; $WM_HOTKEY = 0x0312
if (-not [HotKeyWin]::RegisterHotKey([IntPtr]::Zero, 1, ($MOD_CONTROL -bor $MOD_SHIFT), $VK_S)) {
  DLog "RegisterHotKey BASARISIZ (Ctrl+Shift+S baska uygulamada olabilir)"; exit 1
}
DLog "Dinleyici basladi - Ctrl+Shift+S aktif"
$msg = New-Object HotKeyWin+MSG
while ([HotKeyWin]::GetMessage([ref]$msg, [IntPtr]::Zero, 0, 0) -gt 0) {
  if ($msg.message -eq $WM_HOTKEY) {
    DLog "Ctrl+Shift+S algilandi -> siparis-tara calisiyor"
    try { Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TARA`" -NoSleep" -WindowStyle Hidden } catch { DLog ("tara baslatilamadi: "+$_.Exception.Message) }
  }
}
