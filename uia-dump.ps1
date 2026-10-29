# =====================================================================
#  UIA-DUMP - Listele/Karekod ekranindaki metni UI Automation ile okuma testi
#  Amac: Rx gomulu tarayicisindaki "Ok. KK Adet" tablosunu OCR'siz okuyabilir miyiz?
#  Calistir: powershell -ExecutionPolicy Bypass -File C:\EczaneStok\uia-dump.ps1
#  8 sn bekler; bu surede Listele ekranini ONE getir. Sonra C:\EczaneStok\uia-dump.txt'e yazar.
# =====================================================================
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgWin { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }
"@

$cikti = "C:\EczaneStok\uia-dump.txt"
Write-Host "8 saniye icinde Listele / Karekod ekranini ONE getir..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

$h = [FgWin]::GetForegroundWindow()
$el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
if ($null -eq $el) { Write-Host "Pencere bulunamadi." -ForegroundColor Red; return }
Write-Host ("On plan pencere: " + $el.Current.Name + "  (" + $el.Current.ClassName + ")")

$all = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$lines = New-Object System.Collections.Generic.List[string]
foreach ($e in $all) {
  try {
    $n  = $e.Current.Name
    $ct = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.',''
    if ($n -and $n.Trim().Length -gt 0) { $lines.Add(("[" + $ct + "] " + $n.Trim())) }
  } catch {}
}
# Value pattern'i olanlardan da metin cek (text kutulari)
foreach ($e in $all) {
  try {
    $vp = $null
    if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
      $v = $vp.Current.Value
      if ($v -and $v.Trim().Length -gt 0) { $lines.Add("[VALUE] " + $v.Trim()) }
    }
  } catch {}
}

$lines | Out-File -FilePath $cikti -Encoding UTF8
Write-Host ("Toplam eleman: " + $all.Count + "   yazilan satir: " + $lines.Count) -ForegroundColor Green
Write-Host ("Dosya: " + $cikti) -ForegroundColor Green
