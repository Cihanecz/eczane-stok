# =====================================================================
#  RX-PRIM  (SADECE-OKUMA)  Rx EYS_DB'den kisi bazli gunluk satisi
#  (ilac / ilac-disi: adet, tutar, kar) okur; Supabase prim_satis_gunluk'e yazar.
#  Kullanim: powershell -ExecutionPolicy Bypass -File rx-prim.ps1 [-Gun 45]
#  - Rx'e HICBIR SEY yazmaz. Hasta/TC cekmez; sadece satici adi + tutar/adet/kar.
#  - islem_tipi 1 (perakende) + 4 (receteli) = satis. ilac_tipi=1 ilac, gerisi ilac-disi.
#  - kar = net tutar - (donemsel birim maliyet * adet).
# =====================================================================
param([int]$Gun=45)
$ErrorActionPreference="Stop"
[Console]::OutputEncoding=[Text.Encoding]::UTF8; $env:PGCLIENTENCODING='UTF8'
$KOK="C:\EczaneStok"
$SB_URL="https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY="sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS=Join-Path $KOK "giris.dat"
$PSQL="C:\Program Files (x86)\GEMAS\RxMediaPharma EYS\pgsql\bin\psql.exe"
$RXHOST="127.0.0.1";$RXPORT="5432";$RXDB="EYS_DB";$RXUSER="rx_oku";$RXPASS=""
try{ $m=(Select-String -Path (Join-Path $KOK "rx-hasta.ps1") -Pattern '\$RXPASS\s*=\s*"([^"]+)"').Matches; if($m -and $m.Count){ $RXPASS=$m[0].Groups[1].Value } }catch{}

$bas=(Get-Date).AddDays(-1*$Gun).ToString("yyyy-MM-dd")

$sql=@"
select f.satis_tarih::date, vk.kullanici_adi,
  case when m.ilac_tipi=1 then 'ilac' else 'dis' end,
  case when f.islem_tipi=4 then 'recete' else 'perakende' end,
  sum(kl.verilen_adet),
  round(sum(kl.kalem_tum_iskontolar_sonrasi_net_tutar),2),
  round(sum(kl.kalem_tum_iskontolar_sonrasi_net_tutar - coalesce(kl.donemsel_birim_maliyet, kl.urun_gecerli_depocu_fiyat, 0)*kl.verilen_adet),2)
from eys_view_satis_kalem_kullanici vk
join eys_tbl_satis_fatura f on f.id=vk.satis_fatura_id
join eys_tbl_satis_fatura_kalem kl on kl.satis_fatura_id=vk.satis_fatura_id and kl.urun_id=vk.urun_id
join eys_tbl_mustahzar_temel m on m.urun_id=vk.urun_id
where f.satis_tarih >= '$bas' and f.satis_tarih < (current_date + 1) and f.islem_tipi in (1,4) and coalesce(vk.kullanici_adi,'')<>''
group by f.satis_tarih::date, vk.kullanici_adi, (m.ilac_tipi=1), (f.islem_tipi=4)
"@

$env:PGPASSWORD=$RXPASS
$ciktilar = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -A -t -F '|' -c $sql 2>&1
$metin = ($ciktilar -join "`n")
if($metin -match "ERROR|FATAL"){ Write-Host "RX HATASI: $metin"; exit 1 }

$inv=[Globalization.CultureInfo]::InvariantCulture
$rows=@{}
foreach($satir in ($metin -split "`n")){
  $satir=$satir.Trim(); if(-not $satir){ continue }
  $p=$satir.Split('|'); if($p.Count -lt 7){ continue }
  $tarih=$p[0].Trim(); $kisi=$p[1].Trim(); $grup=$p[2].Trim(); $kanal=$p[3].Trim()
  $adet=[double]::Parse($p[4],$inv); $tutar=[double]::Parse($p[5],$inv); $kar=[double]::Parse($p[6],$inv)
  $k="$tarih|$kisi"
  if(-not $rows.ContainsKey($k)){ $rows[$k]=[ordered]@{tarih=$tarih;personel=$kisi;ilac_adet=0.0;ilac_tutar=0.0;ilac_kar=0.0;dis_adet=0.0;dis_tutar=0.0;dis_kar=0.0;recete_adet=0.0;recete_tutar=0.0;recete_kar=0.0;perakende_adet=0.0;perakende_tutar=0.0;perakende_kar=0.0} }
  $r=$rows[$k]
  if($grup -eq 'ilac'){ $r.ilac_adet+=$adet; $r.ilac_tutar+=$tutar; $r.ilac_kar+=$kar } else { $r.dis_adet+=$adet; $r.dis_tutar+=$tutar; $r.dis_kar+=$kar }
  if($kanal -eq 'recete'){ $r.recete_adet+=$adet; $r.recete_tutar+=$tutar; $r.recete_kar+=$kar } else { $r.perakende_adet+=$adet; $r.perakende_tutar+=$tutar; $r.perakende_kar+=$kar }
}
$liste=@($rows.Values)
$gun2=(Get-Date).ToString("o")
foreach($r in $liste){ $r["guncelleme"]=$gun2 }

# Supabase auth
$s=Get-Content $GIRIS -Encoding UTF8; $ep=$s[0].Trim(); $sf=$s[1].Trim()|ConvertTo-SecureString
$pw=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
$r=Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{apikey=$SB_KEY} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes((@{email=$ep;password=$pw}|ConvertTo-Json -Compress)))
$JETON=$r.access_token

# prim_satis_gunluk upsert (tek tek JSON -> dizi)
if($liste.Count -gt 0){
  $json = "[" + (($liste | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }) -join ",") + "]"
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/prim_satis_gunluk?on_conflict=tarih,personel" -Headers @{apikey=$SB_KEY;Authorization="Bearer $JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
}

# durum isareti (uzaktan dogrulama icin)
$durum=@{zaman=$gun2; gun=$Gun; satir=$liste.Count; kisiler=(($liste|ForEach-Object{$_.personel}|Sort-Object -Unique) -join ",")}|ConvertTo-Json -Compress
$body=@([ordered]@{anahtar="prim_rx_durum";deger=$durum;guncelleme=$gun2})|ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{apikey=$SB_KEY;Authorization="Bearer $JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null

Write-Host "PRIM YAZILDI: $($liste.Count) satir ($bas -> bugun). Kisiler: $(($liste|ForEach-Object{$_.personel}|Sort-Object -Unique) -join ', ')"
