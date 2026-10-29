# =====================================================================
#  SIPARIS-TARA  (Ctrl+Alt+S ile tetiklenir)
#  Medula "Listele" (KarekodIslem) ekranini OCR'la oku -> eksik ilaclar
#  (eksik = Adet - Ok.KK ; Ok.KK = okutulan karekod adedi = fiilen verilen).
#  Rx EYS_DB'den (rx_oku, SADECE-OKUMA) son 30 gunun ACIK SGK recetelerini cek,
#  OCR'daki ilac adi/barkod kumesiyle ESLESTIR -> hastayi bul (ad/tc/tel).
#  Tek aday olustur -> hasta.key ile SIFRELE -> Supabase ayar.sgk_son'a yaz.
#  Web tarafi sgk_son'u yoklar, kendi kalici listesine ekler (2 buton: olustur/olusturma).
#  MEDULA'YA DOKUNMAZ (sadece ekran pikseli OCR). Rx'e yalnizca OKUMA.
#  Kullanim:  powershell -ExecutionPolicy Bypass -File siparis-tara.ps1
#            (-NoSleep: 8sn bekleme yok)  (-Dok: her satirin kelimeleri)
# =====================================================================
param([switch]$NoSleep, [switch]$Dok, [int]$Scale=3, [int]$GunGeri=30)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding=[Text.Encoding]::UTF8; $env:PGCLIENTENCODING='UTF8'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Security

# ---------- ayarlar (ECZANE 1) ----------
$KOK    = "C:\EczaneStok"
$SB_URL = "https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY = "sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS  = Join-Path $KOK "giris.dat"
$HASTA_ANAHTAR = Join-Path $KOK "hasta.key"
$PSQL   = "C:\Program Files (x86)\GEMAS\RxMediaPharma EYS\pgsql\bin\psql.exe"
$RXHOST = "127.0.0.1"; $RXPORT = "5432"; $RXDB = "EYS_DB"; $RXUSER = "rx_oku"
$RXPASS = ""
try { $m = (Select-String -Path (Join-Path $KOK "rx-hasta.ps1") -Pattern '\$RXPASS\s*=\s*"([^"]+)"').Matches; if ($m -and $m.Count) { $RXPASS = $m[0].Groups[1].Value } } catch {}

$LOG = "$KOK\tara-log.txt"
try { "=== " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " tara basladi ===" | Out-File $LOG -Encoding UTF8 } catch {}
function Yaz($m,$c="Gray"){ Write-Host $m -ForegroundColor $c; try { Add-Content -Path $LOG -Value ([string]$m) -Encoding UTF8 } catch {} }

# =====================================================================
#  1) OCR  (ocr-smart ile ayni mantik + barkod yakalama)
# =====================================================================
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Foundation, ContentType=WindowsRuntime]
$asTaskGeneric=([System.WindowsRuntimeSystemExtensions].GetMethods()|?{$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'})[0]
function AwaitOp($op,$t){$m=$asTaskGeneric.MakeGenericMethod($t);$tk=$m.Invoke($null,@($op));$tk.Wait(-1)|Out-Null;$tk.Result}
$IRAS=[Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType=WindowsRuntime]
function OcrFile($path){
  $sf=AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
  $st=AwaitOp ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) $IRAS
  $dc=AwaitOp ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb=AwaitOp ($dc.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $eng=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  $res=AwaitOp ($eng.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $w=New-Object System.Collections.Generic.List[object]
  foreach($ln in $res.Lines){foreach($wd in $ln.Words){$r=$wd.BoundingRect;$w.Add([pscustomobject]@{Y=[int]($r.Y+$r.Height/2);X=[int]$r.X;CX=[int]($r.X+$r.Width/2);R=[int]($r.X+$r.Width);T=$wd.Text})}}
  return $w
}
function Tara {
  # YONTEM: kucuk sayilari OKUMA. Recetedeki barkodlar (13 hane, net) ile okutulan
  # karekodlari (ortadaki kutudaki uzun "0108..." GS1 stringleri, net) cikar.
  # Recetede olup hic karekodu okutulmayan barkod = okutulmamis = EKSIK.
  # Her barkodun kac kez okutuldugunu de sayar (karekod icinde barkod substring).
  if(-not $NoSleep){ Yaz "8 sn icinde Listele ekranini ONE getir..." "Yellow"; Start-Sleep -Seconds 8 }
  else { Start-Sleep -Milliseconds 1200 }   # hotkey: Medula zaten onde, odak otursun
  $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $full=New-Object System.Drawing.Bitmap($b.Width,$b.Height)
  $g=[System.Drawing.Graphics]::FromImage($full);$g.CopyFromScreen($b.X,$b.Y,0,0,$b.Size);$g.Dispose()
  $full.Save("$KOK\cap.png",[System.Drawing.Imaging.ImageFormat]::Png); $full.Dispose()

  $w1=OcrFile "$KOK\cap.png"
  $hBar=$w1|?{$_.T -match '^Barkod'}|Select-Object -First 1
  if(-not $hBar){ $script:KKDBG="Barkod-yok | kelime=" + $w1.Count + " ilk14=" + ((@($w1|%{$_.T})|Select-Object -First 14) -join ' '); Yaz "  (OCR) 'Barkod' basligi yok - Listele tam onde degil" "Yellow"; return $null }

  # Recetedeki barkodlar (13 hane, 85/86 ile baslar). Ust+alt tabloda tekrar eder -> uniq.
  $recete = @($w1 | ?{ $_.T -match '^8[56]\d{10,12}$' } | %{ ([string]$_.T) } | Sort-Object -Unique)
  Yaz ("  recete barkod (" + $recete.Count + "): " + ($recete -join ', '))

  # Okutulan karekodlar ORTADAKI KUTUDA kucuk font -> KIRP + 4x BUYUT + OCR.
  # Kutu "Listele" dugmesinin HEMEN USTUNDE (hem "Recete" hem "Karekod Islemleri" ekraninda boyle).
  $kk=@(); $script:KKDBG=""
  $lst = $w1|?{ $_.T -match '^Listele$' -and $_.X -gt 400 }|Sort-Object Y|Select-Object -First 1
  if($lst){
    $taBot=[math]::Max(40,$lst.Y-8); $taTop=[math]::Max(0,$lst.Y-310)  # karekodlar kutunun UST kisminda -> yuksege al
    $txX=[math]::Max(0,$hBar.X-55); $txW=[math]::Min($b.Width-$txX,1000); $txH=$taBot-$taTop
    Yaz ("  (OCR) karekod kutu: Listele.Y=$($lst.Y) taTop=$taTop taBot=$taBot txX=$txX")
    if($txH -gt 20 -and $txW -gt 50){
      $src=[System.Drawing.Image]::FromFile("$KOK\cap.png")
      $cr=New-Object System.Drawing.Bitmap($txW,$txH); $gc=[System.Drawing.Graphics]::FromImage($cr)
      $gc.DrawImage($src,(New-Object System.Drawing.Rectangle(0,0,$txW,$txH)),$txX,$taTop,$txW,$txH,[System.Drawing.GraphicsUnit]::Pixel);$gc.Dispose()
      $sc=5; $big=New-Object System.Drawing.Bitmap(($txW*$sc),($txH*$sc)); $gb=[System.Drawing.Graphics]::FromImage($big)
      $gb.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $gb.DrawImage($cr,0,0,($txW*$sc),($txH*$sc));$gb.Dispose()
      $big.Save("$KOK\cap-kk.png",[System.Drawing.Imaging.ImageFormat]::Png)
      $src.Dispose();$cr.Dispose();$big.Dispose()
      $w3=OcrFile "$KOK\cap-kk.png"
      $kk=@($w3 | ?{ $_.T -match '^0\d{13,}' } | %{ ([string]$_.T) })
      $script:KKDBG = "Lst=$($lst.Y) t=$taTop b=$taBot x=$txX | w3=" + ((@($w3|%{ if($_.T.Length -gt 24){$_.T.Substring(0,24)}else{$_.T} })|Select-Object -First 12) -join ' ')
    }
  } else { $script:KKDBG="Listele-yok"; Yaz "  (OCR) 'Listele' dugmesi bulunamadi" "Yellow" }
  Yaz ("  okutulan karekod token (" + $kk.Count + "): " + (($kk | %{ if($_.Length -gt 22){$_.Substring(0,22)+'..'}else{$_} }) -join '  '))

  # --- ALT "Okutulan Karekodlar" tablosu: Recete Adet (yazilan) EKRANDAN oku ---
  # (DB yazilan ayni hastanin baska recetesinden gelebiliyor; ekran kesindir.)
  # Her satir: Barkod | Ad(+strength) | Recete Adet | Karekod Adet. Kucuk sayilar en sagda.
  $recNums=@{}
  try {
  if($lst){
    $altBar=@($w1|?{ $_.T -match '^8[56]\d{10,12}$' -and $_.Y -gt ($lst.Y+5) }|Sort-Object Y)
    if($altBar.Count -ge 1){
      $aTop=[math]::Max(0,$altBar[0].Y-16); $aBot=[math]::Min($b.Height,$altBar[-1].Y+20)
      $aX=[math]::Max(0,$hBar.X-55); $aW=[math]::Min($b.Width-$aX,1000); $aH=$aBot-$aTop
      if($aH -gt 15 -and $aW -gt 50){
        $src=[System.Drawing.Image]::FromFile("$KOK\cap.png")
        $cr=New-Object System.Drawing.Bitmap($aW,$aH); $gc=[System.Drawing.Graphics]::FromImage($cr)
        $gc.DrawImage($src,(New-Object System.Drawing.Rectangle(0,0,$aW,$aH)),$aX,$aTop,$aW,$aH,[System.Drawing.GraphicsUnit]::Pixel);$gc.Dispose()
        $sc2=4; $big=New-Object System.Drawing.Bitmap(($aW*$sc2),($aH*$sc2)); $gb=[System.Drawing.Graphics]::FromImage($big)
        $gb.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gb.DrawImage($cr,0,0,($aW*$sc2),($aH*$sc2));$gb.Dispose()
        $big.Save("$KOK\cap-alt.png",[System.Drawing.Imaging.ImageFormat]::Png)
        $src.Dispose();$cr.Dispose();$big.Dispose()
        $w4=OcrFile "$KOK\cap-alt.png"
        $bA=@($w4|?{ $_.X -lt (170*$sc2) -and $_.T -match '^\d{10,14}$' }|Sort-Object Y)
        $ryA=@(); foreach($r in $bA){ if(($ryA|?{[math]::Abs($_-$r.Y) -lt (14*$sc2)}).Count -eq 0){$ryA+=$r.Y} }
        foreach($ry in $ryA){
          $row=@($w4|?{ [math]::Abs($_.Y-$ry) -lt (14*$sc2) }|Sort-Object X)
          $bk=($row|?{ $_.T -match '^\d{10,14}$' }|Select-Object -First 1).T
          if(-not $bk){ continue }
          $nums=@($row|?{ $_.T -match '^\d{1,3}$' }|%{ [int]$_.T })
          if($nums.Count -ge 1){ $recNums[(BarNorm $bk)] = $nums }
        }
      }
    }
  }
  } catch { $recNums=@{}; $script:KKDBG += " | altHata:" + $_.Exception.Message }
  $dbgRN = ($recNums.Keys | %{ "$($_)=[$(($recNums[$_]) -join ',')]" }) -join ' '
  Yaz ("  alt tablo Recete Adet: " + $dbgRN)

  if($recete.Count -eq 0){ return $null }
  return [pscustomobject]@{ recete=$recete; karekod=$kk; recNums=$recNums }
}
# bir barkod karekod kutusunda kac kez gecer (karekod GS1 = 01 + barkod + ...)
# karekod icinde barkodu TOLERANSLI ara (OCR 6<->5 gibi hatalar icin; en fazla maxH hane farki)
function FuzzyIcerir([string]$b,[string]$k,[int]$maxH){
  $lb=$b.Length; if($k.Length -lt $lb){ return $false }
  for($i=0;$i -le ($k.Length-$lb);$i++){ $h=0
    for($j=0;$j -lt $lb;$j++){ if($k[$i+$j] -ne $b[$j]){ $h++; if($h -gt $maxH){ break } } }
    if($h -le $maxH){ return $true } }
  return $false
}
function OkutulanSay([string]$barkod,$kkListe){
  $b=$barkod.TrimStart('0'); if($b.Length -lt 10){ return 0 }
  @($kkListe | ?{ FuzzyIcerir $b $_ 2 }).Count
}

# =====================================================================
#  2) Rx DB -> acik SGK receteleri (son 30 gun) ; OCR ile eslestir
# =====================================================================
function PsqlCsv([string]$sql,[string[]]$basliklar){
  $env:PGPASSWORD=$RXPASS
  $csv = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -v ON_ERROR_STOP=1 -c $sql
  if($LASTEXITCODE -ne 0){ throw "psql hata ($LASTEXITCODE)" }
  if(-not $csv){ return @() }
  @(ConvertFrom-Csv -InputObject $csv -Header $basliklar)
}
function Bos($s){ if($null -eq $s){""}else{([string]$s).Trim()} }
function Norm($s){ (([string]$s).ToUpper() -replace '[^A-Z0-9]','') }
function BarNorm($s){ $d=(([string]$s) -replace '[^0-9]',''); if($d.Length -gt 13){$d=$d.Substring($d.Length-13)}; $d.TrimStart('0') }

function HastaBul($receteBar,$kk){
  $sql = @"
copy (
  select coalesce(s.erecete_no,''), coalesce(s.protokol_no,''),
         to_char(s.islem_tarihi,'YYYY-MM-DD HH24:MI'),
         trim(coalesce(ch.adi,'')||' '||coalesce(ch.soyadi,'')),
         coalesce(ch.tckn,''), coalesce(nullif(ch.gsm1,''),ch.gsm2,''),
         coalesce(m.urun_adi,''), coalesce(m.urun_barkod,''),
         coalesce(m.stok_miktari,0)::text, coalesce(fk.yazilan_adet,0)::text
  from eys_tbl_satis_recete s
  join eys_tbl_satis_fatura_kalem fk on fk.satis_fatura_id=s.fatura_id
  left join eys_tbl_mustahzar_temel m on m.urun_id=fk.urun_id
  left join eys_tbl_cari_hasta ch on ch.id=s.hasta_id
  where s.sonlandirilmis=false
    and s.medula_fatura_tipi is not null and trim(s.medula_fatura_tipi)<>''
    and s.islem_tarihi >= current_date - interval '$GunGeri days'
) to stdout with (format csv)
"@
  $rows = PsqlCsv $sql @('rec','prot','tarih','ad','tc','tel','ilac','bar','stok','yazilan')
  if(-not $rows -or $rows.Count -eq 0){ return $null }
  $ocrBar = @($receteBar | %{ BarNorm $_ } | ?{ $_ })

  $grup=[ordered]@{}
  foreach($r in $rows){
    $rec = Bos $r.rec; if($rec -eq ""){ $rec = Bos $r.prot }; if($rec -eq ""){ continue }
    if(-not $grup.Contains($rec)){ $grup[$rec]=[ordered]@{ rec=$rec; prot=(Bos $r.prot); tarih=(Bos $r.tarih); ad=(Bos $r.ad); tc=(Bos $r.tc); tel=(Bos $r.tel); dr=@() } }
    $grup[$rec].dr += [pscustomobject]@{
      ad=(Bos $r.ilac); bar=(Bos $r.bar); barN=(BarNorm $r.bar)
      stok=([int]([decimal]::Parse((Bos $r.stok),[Globalization.CultureInfo]::InvariantCulture)))
      yazilan=([int]([decimal]::Parse((Bos $r.yazilan),[Globalization.CultureInfo]::InvariantCulture)))
    }
  }
  # Aday receteler: once en cok barkod eslesme. Ayni hastanin birden cok re
  # recetesi varsa: "okutulan <= yazilan" KISITINI saglayan (fiziksel olarak mumkun)
  # ve EN SIKI OTURAN (en kucuk toplam yazilan) receteyi sec -> dogru recete + dogru adet.
  $aday=@()
  foreach($rec in $grup.Keys){
    $g=$grup[$rec]
    $ov=@($g.dr | ?{ $_.barN -and ($ocrBar -contains $_.barN) }).Count
    if($ov -le 0){ continue }
    $tot=0; $fits=$true
    foreach($d in $g.dr){ $tot+=$d.yazilan; if((OkutulanSay $d.bar $kk) -gt $d.yazilan){ $fits=$false } }
    $aday += [pscustomobject]@{ g=$g; ov=$ov; tot=$tot; fits=[int]$fits; tarih=$g.tarih }
  }
  if($aday.Count -eq 0){ return $null }
  $maxOv=($aday | Measure-Object ov -Maximum).Maximum
  $en = $aday | ?{ $_.ov -eq $maxOv } | Sort-Object @{Expression={$_.fits};Descending=$true}, @{Expression={$_.tot};Descending=$false}, @{Expression={$_.tarih};Descending=$true} | Select-Object -First 1
  return $en.g
}

# =====================================================================
#  3) sifrele + Supabase'e yaz
# =====================================================================
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
  if(-not (Test-Path $GIRIS)){ throw "Giris bilgisi yok: $GIRIS" }
  $s=Get-Content $GIRIS -Encoding UTF8; $ep=$s[0].Trim(); $sf=$s[1].Trim()|ConvertTo-SecureString
  $pw=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
  $r=Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" -Headers @{apikey=$SB_KEY} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes((@{email=$ep;password=$pw}|ConvertTo-Json -Compress)))
  $script:JETON=$r.access_token
}
function AyarYaz([string]$anahtar,[string]$deger){
  $body=@([ordered]@{anahtar=$anahtar;deger=$deger;guncelleme=(Get-Date).ToString("o")})|ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" -Headers @{apikey=$SB_KEY;Authorization="Bearer $script:JETON";Prefer="resolution=merge-duplicates,return=minimal"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120 | Out-Null
}

# =====================================================================
#  ANA AKIS
# =====================================================================
function LogDurum([string]$m){ try{ BulutGiris; AyarYaz "sgk_log" $m }catch{} }
trap { try{ LogDurum ("TRAP: " + $_.Exception.Message + " @satir " + $_.InvocationInfo.ScriptLineNumber) }catch{}; exit 9 }

if(-not $RXPASS){ Yaz "RXPASS okunamadi - rx-hasta.ps1 C:\EczaneStok'ta olmali" "Red"; exit 1 }
$anahtar = HastaAnahtari
if(-not $anahtar){ Yaz "hasta.key yok - once rx-hasta.ps1 -HastaKur" "Red"; exit 1 }

Yaz "`n[1/3] Ekran okunuyor (OCR)..." "Cyan"
$t = Tara
if(-not $t -or $t.recete.Count -eq 0){ Yaz "Listele ekrani bulunamadi. Medula Listele ekrani onde mi?" "Red"; LogDurum ("exit2: Listele/Barkod bulunamadi | " + $script:KKDBG); exit 2 }

Yaz "`n[2/3] Hasta + yazilan adet (Rx DB)..." "Cyan"
$h = HastaBul $t.recete $t.karekod
if(-not $h){ Yaz "Hasta eslesmedi - recete DB'de yok (son $GunGeri gun, acik SGK)." "Red"; LogDurum ("exit3: hasta eslesmedi | recete=" + $t.recete.Count + " kk=" + $t.karekod.Count); exit 3 }
Yaz ("Eslesen hasta: {0}  ({1})  tel={2}  ilac={3}" -f $h.ad,$h.rec,$h.tel,$h.dr.Count) "Green"

# EKSIK = yazilan - okutulan(karekod kutusunda barkod sayisi). Hic okutulmayan = tam eksik.
Yaz ("{0,-30} {1,4} {2,4} {3,5}  {4}" -f "Ilac","Yaz","Oku","EKSIK","Barkod")
$drIlac=@()
foreach($d in $h.dr){
  if(-not $d.bar){ continue }
  $ok = OkutulanSay $d.bar $t.karekod
  # Recete Adet: ONCE ekrandan (alt "Okutulan Karekodlar" tablosu) - DB yazilan
  # ayni hastanin BASKA recetesinden gelebiliyor; ekran kesindir. Ekran yoksa DB.
  $yaz = $d.yazilan
  $en = $null
  if($t.recNums.ContainsKey($d.barN)){ $en = $t.recNums[$d.barN] }
  else {
    foreach($rk in $t.recNums.Keys){
      $len=[math]::Min($rk.Length,$d.barN.Length); $hh=[math]::Abs($rk.Length-$d.barN.Length)
      for($i=0;$i -lt $len;$i++){ if($rk[$i] -ne $d.barN[$i]){ $hh++ } }
      if($hh -le 2){ $en=$t.recNums[$rk]; break }
    }
  }
  if($en -and $en.Count -ge 1){
    # Alt tablo satiri: ...strength... | Recete Adet | Karekod Adet
    # Karekod Adet = okutulan sayisi (ok). Son sayi ok'a esitse o Karekod Adet'tir
    # -> Recete Adet bir onceki. Degilse Karekod Adet(0) hic basilmamis -> son sayi Recete Adet.
    if($en.Count -ge 2 -and ([int]$en[-1] -eq $ok)){ $yaz = [int]$en[-2] }
    else { $yaz = [int]$en[-1] }
  }
  if($yaz -lt 1){ $yaz = $d.yazilan }
  $eksik = $yaz - $ok
  $kisa = if($d.ad.Length -gt 30){$d.ad.Substring(0,30)}else{$d.ad}
  Yaz ("{0,-30} {1,4} {2,4} {3,5}  {4}" -f $kisa,$yaz,$ok,$eksik,$d.bar)
  if($eksik -gt 0){ $drIlac += [ordered]@{ ad=$d.ad; bar=$d.bar; adet=$yaz; okkk=$ok; eksik=$eksik; stok=$d.stok } }
}
# TANI: buluta plaintext log (PII yok - barkod/sayac) -> uzaktan gorulebilsin
try {
  $tani = ("recete=" + $t.recete.Count + " kk=" + $t.karekod.Count + " || KK: " + (($t.karekod | %{ if($_.Length -gt 26){$_.Substring(0,26)}else{$_} }) -join ' '))
  $tani += " || " + (($h.dr | %{ "$($_.bar):y$($_.yazilan)/o$(OkutulanSay $_.bar $t.karekod)/e[$(($t.recNums[$_.barN]) -join ',')]" }) -join ' ')
  $tani += " || " + $script:KKDBG
  BulutGiris; AyarYaz "sgk_log" $tani
} catch {}

if($drIlac.Count -eq 0){ Yaz "`nEksik ilac yok - hepsi okutulmus. Siparis olusturulmadi." "Green"; exit 0 }

$aday = [ordered]@{
  zaman=(Get-Date).ToString("o"); rec=$h.rec; prot=$h.prot; tarih=$h.tarih
  ad=$h.ad; tc=$h.tc; tel=$h.tel; ilac=$drIlac
}
Yaz "`n[3/3] Sifrelenip buluta yaziliyor (sgk_son)..." "Cyan"
BulutGiris
$sifreli = Sifrele $anahtar (ConvertTo-Json $aday -Depth 6 -Compress)
AyarYaz "sgk_son" $sifreli
Yaz ("TAMAM: {0} eksik ilac, hasta '{1}' -> web listesine dustu." -f $drIlac.Count, $h.ad) "Green"
