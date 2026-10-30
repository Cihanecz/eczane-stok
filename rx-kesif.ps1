# =====================================================================
#  RX-KESIF  (SADECE-OKUMA)  Rx EYS_DB semasini/verisini inceler,
#  sonucu Supabase ayar.rx_kesif'e yazar (uzaktan okunur).
#  Kullanim: powershell -ExecutionPolicy Bypass -File rx-kesif.ps1 -Sql "select ..."
#  PII YAZMA: sadece sema (tablo/kolon) + barkod/sayac sorgula; isim/TC yazma.
# =====================================================================
param([string]$Sql="")
$ErrorActionPreference="Stop"
[Console]::OutputEncoding=[Text.Encoding]::UTF8; $env:PGCLIENTENCODING='UTF8'
$KOK="C:\EczaneStok"
$SB_URL="https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY="sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS=Join-Path $KOK "giris.dat"
$PSQL="C:\Program Files (x86)\GEMAS\RxMediaPharma EYS\pgsql\bin\psql.exe"
$RXHOST="127.0.0.1";$RXPORT="5432";$RXDB="EYS_DB";$RXUSER="rx_oku";$RXPASS=""
try{ $m=(Select-String -Path (Join-Path $KOK "rx-hasta.ps1") -Pattern '\$RXPASS\s*=\s*"([^"]+)"').Matches; if($m -and $m.Count){ $RXPASS=$m[0].Groups[1].Value } }catch{}

function RxSorgu([string]$sql){
  $env:PGPASSWORD=$RXPASS
  $out = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -A -F '|' -c $sql 2>&1
  return ($out -join "`n")
}

# default kesif: karekod tablolari + karekod kolonlari + satis_fatura_kalem kolonlari
if(-not $Sql){
  $q1 = "select coalesce(string_agg(table_name,', '),'(yok)') from information_schema.tables where table_schema='public' and (table_name ilike '%karekod%')"
  $q2 = "select coalesce(string_agg(table_name||'.'||column_name,', '),'(yok)') from information_schema.columns where table_schema='public' and column_name ilike '%karekod%'"
  $q3 = "select string_agg(column_name,', ' order by ordinal_position) from information_schema.columns where table_name='eys_tbl_satis_fatura_kalem'"
  $sonuc = "== KAREKOD TABLOLARI ==`n" + (RxSorgu $q1) + "`n`n== KAREKOD KOLONLARI ==`n" + (RxSorgu $q2) + "`n`n== fatura_kalem KOLONLARI ==`n" + (RxSorgu $q3)
} else {
  $sonuc = RxSorgu $Sql
}

# Supabase'e yaz
$s=Get-Content $GIRIS -Encoding UTF8; $ep=$s[0].Trim(); $sf=$s[1].Trim()|ConvertTo-SecureString
$pw=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
$r=Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{apikey=$SB_KEY} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes((@{email=$ep;password=$pw}|ConvertTo-Json -Compress)))
$JETON=$r.access_token
$body=@([ordered]@{anahtar="rx_kesif";deger=$sonuc;guncelleme=(Get-Date).ToString("o")})|ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{apikey=$SB_KEY;Authorization="Bearer $JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
Write-Host "YAZILDI (rx_kesif)."
Write-Host $sonuc
