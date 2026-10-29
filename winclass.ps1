# Gomulu tarayici tipini anlamak icin: on plandaki pencerenin tum cocuk pencere siniflari
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class WinEnum {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
  public static List<string> Classes(IntPtr parent){
    var list = new List<string>();
    EnumChildWindows(parent, delegate(IntPtr h, IntPtr l){
      var sb = new StringBuilder(256); GetClassName(h, sb, 256); list.Add(sb.ToString()); return true;
    }, IntPtr.Zero);
    return list;
  }
}
"@
Write-Host "8 sn icinde Listele/Karekod ekranini ONE getir..." -ForegroundColor Yellow
Start-Sleep -Seconds 8
$h = [WinEnum]::GetForegroundWindow()
$cls = [WinEnum]::Classes($h)
Write-Host ("Cocuk pencere sayisi: " + $cls.Count) -ForegroundColor Green
$cls | Group-Object | Sort-Object Count -Descending | ForEach-Object { "{0,4}  {1}" -f $_.Count, $_.Name }
