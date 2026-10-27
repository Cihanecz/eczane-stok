# Eczane Stok — dosyaları belirtilen GitHub sürümünden günceller, gözcüyü yeniden başlatır.
# Kullanım: powershell -ExecutionPolicy Bypass -File guncelle.ps1 -Repo Cihanecz/eczane-stok -Sha 8af07d7
param([string]$Repo, [string]$Sha)
$ErrorActionPreference = "Stop"
$KOK = "C:\EczaneStok"
$dosyalar = "toplayici.ps1", "gozcu.ps1", "eklenti/arka.js", "eklenti/as.js", "eklenti/bek.js", "eklenti/manifest.json", "eklenti/sancak.js"
function Surecler($desen) { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match $desen }) }
# Rx'ten toplama sürüyorsa bitmesini bekle (yarıda kesilmesin)
while ((Surecler 'toplayici\.ps1.*-Asama (gunluk|depo)').Count) { "Toplama suruyor, bitmesi bekleniyor..."; Start-Sleep 10 }
foreach ($d in $dosyalar) {
  $hedef = Join-Path $KOK ($d -replace '/', '\')
  Invoke-WebRequest "https://raw.githubusercontent.com/$Repo/$Sha/$d" -UseBasicParsing -OutFile "$hedef.yeni"
  Move-Item -Force "$hedef.yeni" $hedef
  "indi: $d  " + (Get-FileHash $hedef).Hash.Substring(0, 12)
}
# eski gözcü ve sepet süreçlerini kapat, gözcüyü yeniden başlat
foreach ($p in (Surecler 'gozcu\.ps1|-Asama sepet')) { Stop-Process -Id $p.ProcessId -Force; "kapatildi: $($p.ProcessId)" }
if (Get-ScheduledTask -TaskName "Eczane Stok Gozcu" -ErrorAction SilentlyContinue) { Start-ScheduledTask "Eczane Stok Gozcu"; "gozcu: zamanlanmis gorevle baslatildi" }
else { Start-Process wscript.exe -ArgumentList "`"$KOK\baslat.vbs`""; "gozcu: baslat.vbs ile baslatildi" }
Start-Sleep 25
foreach ($p in (Surecler 'gozcu\.ps1|sepetdongu')) { "calisiyor: " + ($p.CommandLine -replace '^.*-File\s+', '') }
"BITTI"
