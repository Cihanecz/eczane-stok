# =====================================================================
#  RX-EKSIK  (SADECE-OKUMA)  Rx EYS_DB'den KAREKODU EKSIK (tamamlanmamis)
#  SGK recetelerini cek -> ilac/stok/hasta ile birlikte SIFRELE -> Supabase
#  ayar.sgk_eksik_db'ye yaz. Web bunu okur, "SGK eksik bekleyen" listesini gosterir.
#  SINYAL: eys_view_satis_recete.karekod_bilgi=false  (karekodlar tam degil = eksik var)
#  TARIH KURALI: ayin 8'inden ONCE -> onceki ay + bu ay; 8'inden ITIBAREN -> sadece bu ay.
#  MEDULA'YA DOKUNMAZ, Rx'e yalnizca OKUMA. Periyodik calisir (gozcu/zamanlanmis).
# =====================================================================
param([int]$DonguSn=0)   # 0 = tek sefer; >0 = her $DonguSn sn'de bir (anlik), degisince yazar
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
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{apikey=$SB_KEY;Authorization="Bearer $script:JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120 | Out-Null
}
function PsqlCsv([string]$sql,[string[]]$basliklar){
  $env:PGPASSWORD=$RXPASS
  $csv = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -v ON_ERROR_STOP=1 -c $sql
  if($LASTEXITCODE -ne 0){ throw "psql hata ($LASTEXITCODE)" }
  if(-not $csv){ return @() }
  @(ConvertFrom-Csv -InputObject $csv -Header $basliklar)
}

# ---- EKSIK SGK RECETELERI (karekodu tam olmayan) ----
$SQL = @"
copy (
  select s.id::text, coalesce(nullif(s.erecete_no,''),s.protokol_no,''),
         to_char(s.islem_tarihi,'YYYY-MM-DD HH24:MI'),
         trim(coalesce(ch.adi,'')||' '||coalesce(ch.soyadi,'')),
         coalesce(ch.tckn,''), coalesce(nullif(ch.gsm1,''),ch.gsm2,''),
         coalesce(m.urun_adi,''), coalesce(m.urun_barkod,''),
         coalesce(m.stok_miktari,0)::text, coalesce(fk.yazilan_adet,0)::text,
         (coalesce(s.fiyat_farki,0)+coalesce(s.mua_kat_payi_elden,0)+coalesce(s.rec_kat_payi_elden,0)
           +case when s.ilac_katilim_payi_elden then coalesce(sf.hasta_payi,0) else 0 end)::text
  from eys_tbl_satis_recete s
  join eys_view_satis_recete vsr on vsr.id=s.id and vsr.karekod_bilgi=false
  join eys_tbl_satis_fatura sf on sf.id=s.fatura_id
  join eys_tbl_satis_fatura_kalem fk on fk.satis_fatura_id=s.fatura_id
  left join eys_tbl_mustahzar_temel m on m.urun_id=fk.urun_id
  left join eys_tbl_cari_hasta ch on ch.id=s.hasta_id
  where s.sonlandirilmis=false
    and s.medula_fatura_tipi is not null and trim(s.medula_fatura_tipi)<>''
    and s.islem_tarihi >= case when extract(day from current_date)>=8
                               then date_trunc('month',current_date)
                               else date_trunc('month',current_date)-interval '1 month' end
  order by s.id, m.urun_adi
) to stdout with (format csv)
"@
function EksikListe {
  $rows = PsqlCsv $SQL @('id','erec','tarih','ad','tc','tel','ilacad','bar','stok','yaz','tutar')
  $grup=[ordered]@{}
  foreach($r in $rows){
    $id=Bos $r.id; if($id -eq ""){ continue }
    if(-not $grup.Contains($id)){
      $t=0.0; try{ $t=[math]::Round([decimal]::Parse((Bos $r.tutar),[Globalization.CultureInfo]::InvariantCulture),2) }catch{}
      $grup[$id]=[ordered]@{ rec=$id; erec=(Bos $r.erec); tarih=(Bos $r.tarih); ad=(Bos $r.ad); tc=(Bos $r.tc); tel=(Bos $r.tel); tutar=$t; ilac=@() }
    }
    $bar=Bos $r.bar; if($bar -eq ""){ continue }
    $grup[$id].ilac += [ordered]@{ bar=$bar; ad=(Bos $r.ilacad); yaz=([int](Bos $r.yaz)); stok=([int]([decimal]::Parse((Bos $r.stok),[Globalization.CultureInfo]::InvariantCulture))) }
  }
  @($grup.Values | ?{ $_.ilac.Count -gt 0 })
}
function Imza($liste){ ConvertTo-Json @($liste) -Depth 8 -Compress }   # zaman haric icerik imzasi
function Yaz($liste,[byte[]]$anahtar){
  $paket=[ordered]@{ zaman=(Get-Date).ToString("o"); liste=@($liste) }
  AyarYaz "sgk_eksik_db" (Sifrele $anahtar (ConvertTo-Json $paket -Depth 8 -Compress))
  AyarYaz "sgk_eksik_log" ("recete=" + @($liste).Count + " ilac=" + (@($liste|%{$_.ilac.Count})|Measure-Object -Sum).Sum + " zaman=" + (Get-Date -Format "HH:mm:ss"))
}

$anahtar = HastaAnahtari
if(-not $anahtar){ throw "hasta.key yok" }
BulutGiris
if($DonguSn -gt 0){
  # ANLIK DONGU: her $DonguSn sn sorgula; icerik degisince yaz (bos degisiklikte Supabase'i yormaz)
  $sonImza=$null; $girisZaman=Get-Date
  while($true){
    try{
      if(((Get-Date)-$girisZaman).TotalMinutes -gt 50){ BulutGiris; $girisZaman=Get-Date }
      $liste=EksikListe; $imza=Imza $liste
      if($imza -ne $sonImza){ Yaz $liste $anahtar; $sonImza=$imza; Write-Host ("degisti -> yazildi: " + @($liste).Count + " recete " + (Get-Date -Format "HH:mm:ss")) }
    }catch{ Start-Sleep -Seconds 5; try{ BulutGiris; $girisZaman=Get-Date }catch{} }
    Start-Sleep -Seconds $DonguSn
  }
} else {
  $liste=EksikListe; Yaz $liste $anahtar
  Write-Host ("EKSIK yazildi: " + @($liste).Count + " recete")
}
