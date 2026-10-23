# Eczane Stok — toplayıcıyı internetten indirip kurar (bir kez çalıştırılır)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$KAYNAK = "https://cihanecz.github.io/eczane-stok"
$KOK = "C:\EczaneStok"
New-Item -ItemType Directory -Force -Path $KOK, "$KOK\veri" | Out-Null
$wc = New-Object Net.WebClient
foreach ($d in "toplayici.ps1","banner.ps1","gozcu.ps1","baslat.vbs") {
  $wc.DownloadFile("$KAYNAK/$d" + "?t=" + [DateTime]::Now.Ticks, (Join-Path $KOK $d))
  Write-Host ("indirildi: " + $d + " (" + (Get-Item (Join-Path $KOK $d)).Length + " bayt)")
}
# Gözcü: yönetici yetkisiyle (Rx yönetici olarak çalışıyorsa tıklamalar ancak böyle geçer) oturum açılınca başlar
$yonetici = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$bas = [Environment]::GetFolderPath("Startup")
if ($yonetici) {
  $u = "$env:USERDOMAIN\$env:USERNAME"
  $a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$KOK\gozcu.ps1`""
  $t = New-ScheduledTaskTrigger -AtLogOn -User $u
  $pr = New-ScheduledTaskPrincipal -UserId $u -LogonType Interactive -RunLevel Highest
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName "Eczane Stok Gozcu" -Action $a -Trigger $t -Principal $pr -Settings $s -Force | Out-Null
  Remove-Item (Join-Path $bas "EczaneStok.vbs") -Force -ErrorAction SilentlyContinue
  Write-Host "Gözcü görevi kuruldu (yönetici yetkili)."
} else {
  Copy-Item "$KOK\baslat.vbs" (Join-Path $bas "EczaneStok.vbs") -Force
  Write-Host "UYARI: yönetici olarak çalıştırılmadı; Rx yönetici olarak açılıyorsa toplayıcı tıklayamaz. kur.ps1'i yönetici PowerShell'de çalıştır." -ForegroundColor Yellow
}
Write-Host "Dosyalar kuruldu. Şimdi Eczane Stok programına girişte kullanılan e-posta ve şifreyi gir:" -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File "$KOK\toplayici.ps1" -Kur
if ($yonetici) { Start-ScheduledTask "Eczane Stok Gozcu" } else { Start-Process wscript.exe -ArgumentList "`"$KOK\baslat.vbs`"" }
Write-Host "Tamam. Bundan sonra Rx'e her gün ilk girişte veriler otomatik alınır." -ForegroundColor Green
