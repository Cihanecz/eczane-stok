# =====================================================================
#  RX-KART  (SADECE-OKUMA)  Rx EYS_DB eys_tbl_cari_hasta'dan TUM hasta
#  kartlarini cek -> mukerrer birlestir -> SIFRELE -> Supabase ayar.hasta_kart.
#  Web "elden siparis"te hasta adi yazarken oneri icin okur.
#  BIRLESTIRME: ayni TC = ayni kisi (tek kart, telefonu dolu olani tut).
#   Farkli TC = farkli kisi (ikisi de). TC'siz kayitlar: ayni ada sahip bir
#   TC'li kart varsa atlanir; yoksa ada gore tekille (telefonu olani tercih).
#  MEDULA'YA DOKUNMAZ, Rx'e yalnizca OKUMA. Periyodik (gozcu).
# =====================================================================
$ErrorActionPreference="Stop"
[Console]::OutputEncoding=[Text.Encoding]::UTF8; $env:PGCLIENTENCODING='UTF8'
Add-Type -AssemblyName System.Security
$KOK="C:\EczaneStok"
$SB_URL="https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY="sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS=Join-Path $KOK "giris.dat"
$HASTA_ANAHTAR=Join-Path $KOK "hasta.key"
$PSQL="C:\Program Files (x86)\GEMAS\RxMediaPharma EYS\pgsql\bin\psql.exe"
$RXHOST="127.0.0.1";$RXPORT="5432";$RXDB="EYS_DB";$RXUSER="rx_oku";$RXPASS=""
try{ $m=(Select-String -Path (Join-Path $KOK "rx-hasta.ps1") -Pattern '\$RXPASS\s*=\s*"([^"]+)"').Matches; if($m -and $m.Count){ $RXPASS=$m[0].Groups[1].Value } }catch{}

function Bos($s){ if($null -eq $s){""}else{([string]$s).Trim()} }
function AdAnah($s){ (([string]$s).Trim().ToUpperInvariant().Replace([string][char]0x130,"I").Replace([string][char]0x131,"I")) -replace '\s+',' ' }
function HastaAnahtari {
  if(-not (Test-Path $HASTA_ANAHTAR)){ return $null }
  [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($HASTA_ANAHTAR),$null,'CurrentUser')
}
function Sifrele([byte[]]$anahtar,[string]$metin){
  $ham=[Text.Encoding]::UTF8.GetBytes($metin)
  $ms=New-Object IO.MemoryStream; $gz=New-Object IO.Compression.GZipStream($ms,[IO.Compression.CompressionMode]::Compress); $gz.Write($ham,0,$ham.Length); $gz.Close(); $ham=$ms.ToArray()
  $aes=[Security.Cryptography.Aes]::Create(); $aes.Mode='CBC'; $aes.Padding='PKCS7'; $aes.Key=[byte[]]$anahtar[0..31]; $aes.GenerateIV()
  $ct=$aes.CreateEncryptor().TransformFinalBlock($ham,0,$ham.Length)
  $iv_ct=[byte[]]($aes.IV+$ct)
  $h=New-Object Security.Cryptography.HMACSHA256 -ArgumentList (,[byte[]]$anahtar[32..63])
  [Convert]::ToBase64String([byte[]]($iv_ct+$h.ComputeHash($iv_ct)))
}
$script:JETON=$null
function BulutGiris {
  if(-not (Test-Path $GIRIS)){ throw "Giris yok: $GIRIS" }
  $s=Get-Content $GIRIS -Encoding UTF8; $ep=$s[0].Trim(); $sf=$s[1].Trim()|ConvertTo-SecureString
  $pw=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
  $r=Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{apikey=$SB_KEY} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes((@{email=$ep;password=$pw}|ConvertTo-Json -Compress)))
  $script:JETON=$r.access_token
}
function AyarYaz([string]$anahtar,[string]$deger){
  $body=@([ordered]@{anahtar=$anahtar;deger=$deger;guncelleme=(Get-Date).ToString("o")})|ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{apikey=$SB_KEY;Authorization="Bearer $script:JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180 | Out-Null
}

# ---- TUM hasta kartlari ----
$sql = @"
copy (
  select coalesce(tckn,''), trim(coalesce(adi,'')||' '||coalesce(soyadi,'')),
         coalesce(nullif(gsm1,''),gsm2,'')
  from eys_tbl_cari_hasta
  where trim(coalesce(adi,'')||coalesce(soyadi,'')) <> ''
) to stdout with (format csv)
"@
$env:PGPASSWORD=$RXPASS
$csv = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -v ON_ERROR_STOP=1 -c $sql
if($LASTEXITCODE -ne 0){ throw "psql hata ($LASTEXITCODE)" }
$rows = if($csv){ @(ConvertFrom-Csv -InputObject $csv -Header @('tc','ad','tel')) } else { @() }

# ---- birlestirme ----
$tcKart = [ordered]@{}        # tckn -> {ad,tc,tel}
$tcsiz  = [ordered]@{}        # adAnah -> {ad,tc='',tel}
foreach($r in $rows){
  $ad=Bos $r.ad; if($ad -eq ""){ continue }
  $tc=Bos $r.tc; $tel=Bos $r.tel
  if($tc -ne ""){
    if(-not $tcKart.Contains($tc)){ $tcKart[$tc]=[ordered]@{ ad=$ad; tc=$tc; tel=$tel } }
    elseif($tel -ne "" -and (Bos $tcKart[$tc].tel) -eq ""){ $tcKart[$tc].tel=$tel }   # telefonu dolu olani tut
  } else {
    $k=AdAnah $ad
    if(-not $tcsiz.Contains($k)){ $tcsiz[$k]=[ordered]@{ ad=$ad; tc=""; tel=$tel } }
    elseif($tel -ne "" -and (Bos $tcsiz[$k].tel) -eq ""){ $tcsiz[$k].tel=$tel }
  }
}
# TC'li kartlarin adlarini topla; TC'siz ayni ad varsa atla
$tcliAdlar = @{}; foreach($v in $tcKart.Values){ $tcliAdlar[(AdAnah $v.ad)] = $true }
$liste = New-Object System.Collections.ArrayList
foreach($v in $tcKart.Values){ [void]$liste.Add([ordered]@{ ad=$v.ad; tc=$v.tc; tel=$v.tel }) }
foreach($v in $tcsiz.Values){ if(-not $tcliAdlar.ContainsKey((AdAnah $v.ad))){ [void]$liste.Add([ordered]@{ ad=$v.ad; tc=""; tel=$v.tel }) } }

$paket = [ordered]@{ zaman=(Get-Date).ToString("o"); liste=@($liste) }
$anahtar = HastaAnahtari
if(-not $anahtar){ throw "hasta.key yok" }
BulutGiris
$sifreli = Sifrele $anahtar (ConvertTo-Json $paket -Depth 6 -Compress)
AyarYaz "hasta_kart" $sifreli
AyarYaz "hasta_kart_log" ("kayit=" + $liste.Count + " ham=" + $rows.Count + " zaman=" + (Get-Date -Format "HH:mm:ss"))   # PII yok
Write-Host ("HASTA KART yazildi: " + $liste.Count + " kart (" + $rows.Count + " ham)")
