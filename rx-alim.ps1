# =====================================================================
#  RX-ALIM  (SADECE-OKUMA)  Son ~25 gunun alislarini (eys_view_alis_ozet)
#  barkod bazinda son alis tarihi + depo olarak Supabase ayar.alim_son'a yazar.
#  Web: bir siparis ilaci, siparis tarihinde/sonrasinda alinmissa -> "GELDI".
#  DUZ JSON (PII yok: sadece barkod + tarih + depo adi). MEDULA'ya dokunmaz.
# =====================================================================
$ErrorActionPreference="Stop"
[Console]::OutputEncoding=[Text.Encoding]::UTF8; $env:PGCLIENTENCODING='UTF8'
$KOK="C:\EczaneStok"
$SB_URL="https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY="sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS=Join-Path $KOK "giris.dat"
$PSQL="C:\Program Files (x86)\GEMAS\RxMediaPharma EYS\pgsql\bin\psql.exe"
$RXHOST="127.0.0.1";$RXPORT="5432";$RXDB="EYS_DB";$RXUSER="rx_oku";$RXPASS=""
try{ $m=(Select-String -Path (Join-Path $KOK "rx-hasta.ps1") -Pattern '\$RXPASS\s*=\s*"([^"]+)"').Matches; if($m -and $m.Count){ $RXPASS=$m[0].Groups[1].Value } }catch{}

function Bos($s){ if($null -eq $s){""}else{([string]$s).Trim()} }
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
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{apikey=$SB_KEY;Authorization="Bearer $script:JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120 | Out-Null
}
function PsqlCsv([string]$sql,[string[]]$basliklar){
  $env:PGPASSWORD=$RXPASS
  $csv = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -v ON_ERROR_STOP=1 -c $sql
  if($LASTEXITCODE -ne 0){ throw "psql hata ($LASTEXITCODE)" }
  if(-not $csv){ return @() }
  @(ConvertFrom-Csv -InputObject $csv -Header $basliklar)
}

$sql = @"
copy (
  select urun_barkod, to_char(max(fatura_tarih),'YYYY-MM-DD'), max(depoadi)
  from eys_view_alis_ozet
  where fatura_tarih >= current_date - interval '25 days' and coalesce(urun_barkod,'')<>''
  group by urun_barkod
) to stdout with (format csv)
"@
$rows = PsqlCsv $sql @('bar','t','depo')
$ilac = [ordered]@{}
foreach($r in $rows){ $b=Bos $r.bar; if($b -eq ""){ continue }; $ilac[$b]=[ordered]@{ t=(Bos $r.t); d=(Bos $r.depo) } }
$paket = [ordered]@{ zaman=(Get-Date).ToString("o"); ilac=$ilac } | ConvertTo-Json -Depth 5 -Compress

BulutGiris
AyarYaz "alim_son" $paket
AyarYaz "alim_log" ("barkod=" + $ilac.Count + " zaman=" + (Get-Date -Format "HH:mm:ss"))
Write-Host ("ALIM yazildi: " + $ilac.Count + " barkod")
