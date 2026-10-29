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
  if(-not $NoSleep){ Yaz "8 sn icinde Listele ekranini ONE getir..." "Yellow"; Start-Sleep -Seconds 8 }
  else { Start-Sleep -Milliseconds 1200 }   # hotkey: Medula zaten onde, odak otursun
  $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $full=New-Object System.Drawing.Bitmap($b.Width,$b.Height)
  $g=[System.Drawing.Graphics]::FromImage($full);$g.CopyFromScreen($b.X,$b.Y,0,0,$b.Size);$g.Dispose()
  $full.Save("$KOK\cap.png",[System.Drawing.Imaging.ImageFormat]::Png); $full.Dispose()

  $w1=OcrFile "$KOK\cap.png"
  $hBar=$w1|?{$_.T -match '^Barkod'}|Select-Object -First 1
  if(-not $hBar){ Yaz "  (OCR) 'Barkod' basligi yok - Listele tam onde degil (pencere kapatiyor olabilir)" "Yellow"; return $null }
  $hy=$hBar.Y
  $hrow=$w1|?{[math]::Abs($_.Y-$hy) -lt 18}
  $hRaf=$hrow|?{$_.T -match 'Raf'}|Select-Object -First 1
  $hDozaj=$hrow|?{$_.T -match 'Dozaj'}|Select-Object -First 1
  $rightEnd= if($hRaf){$hRaf.X-10} elseif($hDozaj){$hDozaj.X+260} else {$hBar.X+760}
  $barRows=$w1|?{ [math]::Abs($_.X-$hBar.X) -lt 70 -and $_.T -match '^8[56]\d{10,12}$' -and $_.Y -gt $hy } | Sort-Object Y
  $rowYs=@(); foreach($r in $barRows){ if(($rowYs|?{[math]::Abs($_-$r.Y) -lt 12}).Count -eq 0){$rowYs+=$r.Y} }
  Yaz ("  (OCR) Barkod.X={0} Y={1} rightEnd={2} satir={3}" -f $hBar.X,$hy,$rightEnd,$rowYs.Count)
  if($rowYs.Count -eq 0){ return $null }

  $cropX=[math]::Max(0,$hBar.X-12); $cropY=[math]::Max(0,$hy-6)
  $cropR=[math]::Min($b.Width,$rightEnd); $cropB=[math]::Min($b.Height,$rowYs[-1]+40)
  $cw=$cropR-$cropX; $ch=$cropB-$cropY
  $src=[System.Drawing.Image]::FromFile("$KOK\cap.png")
  $cr=New-Object System.Drawing.Bitmap($cw,$ch); $gc=[System.Drawing.Graphics]::FromImage($cr)
  $gc.DrawImage($src,(New-Object System.Drawing.Rectangle(0,0,$cw,$ch)),$cropX,$cropY,$cw,$ch,[System.Drawing.GraphicsUnit]::Pixel);$gc.Dispose()
  $big=New-Object System.Drawing.Bitmap(($cw*$Scale),($ch*$Scale)); $gb=[System.Drawing.Graphics]::FromImage($big)
  $gb.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gb.DrawImage($cr,0,0,($cw*$Scale),($ch*$Scale));$gb.Dispose()
  $big.Save("$KOK\cap-crop.png",[System.Drawing.Imaging.ImageFormat]::Png)
  $src.Dispose();$cr.Dispose();$big.Dispose()
  $w2=OcrFile "$KOK\cap-crop.png"

  $bar2=$w2|?{ $_.X -lt (120*$Scale) -and $_.T -match '^\d{10,14}$' }|Sort-Object Y
  $ry2=@(); foreach($r in $bar2){ if(($ry2|?{[math]::Abs($_-$r.Y) -lt (14*$Scale)}).Count -eq 0){$ry2+=$r.Y} }
  if($ry2.Count -eq 0){ $ry2 = $rowYs | %{ ($_-$cropY)*$Scale } }

  $rows=New-Object System.Collections.Generic.List[object]
  foreach($ry in ($ry2|Sort-Object)){
    $row = $w2|?{ [math]::Abs($_.Y-$ry) -lt (14*$Scale) } | Sort-Object X
    if($Dok){ Yaz ("  -- Y=$($ry): " + (($row|%{$_.T}) -join ' | ')) "DarkGray" }
    $bar = ($row|?{ $_.T -match '^\d{10,14}$' -and $_.X -lt (140*$Scale) }|Sort-Object X|Select-Object -First 1).T
    $nameW=@(); $hitNum=$false
    foreach($wd in $row){ if($wd.T -match '^\d'){ if($wd.T.Length -ge 2){$hitNum=$true} }
      if(-not $hitNum -and $wd.T -match '[A-Za-zÇĞİÖŞÜ]' -and $wd.X -gt (60*$Scale)){ $nameW+=$wd.T } }
    $ad = ($nameW -join ' ')
    $stokL=$null; $stokRx=0
    $stokW = $row|?{ $_.T -match '^-?\d+\s*/\s*[0-9oO]+$' }|Select-Object -First 1
    if($stokW){ $stokL=$stokW.X; $stokRx=$stokW.R }
    else { for($i=0;$i -lt $row.Count-2;$i++){ if($row[$i].T -match '^-?\d+$' -and $row[$i+1].T -match '^/$' -and $row[$i+2].T -match '^[0-9oO]+$'){ $stokL=$row[$i].X; $stokRx=$row[$i+2].R; break } } }
    $adet=0; $okkk=0
    if($stokL -ne $null){
      $stokCX = ($stokL + $stokRx)/2
      $before = $row|?{ $_.X -lt $stokL -and $_.T -match '^\d+$' }|Sort-Object X
      if($before.Count -gt 0){ $adet=[int]($before[-1].T) }
      $afterAll = $row|?{ $_.CX -gt $stokCX -and $_.CX -gt $stokRx-20 }|Sort-Object X
      $dozIdx=-1; for($i=0;$i -lt $afterAll.Count;$i++){ if($afterAll[$i].T -match 'G[uü]nde|Hafta'){ $dozIdx=$i; break } }
      $scan = if($dozIdx -ge 0){ if($dozIdx -gt 0){ $afterAll[0..($dozIdx-1)] } else { @() } } else { $afterAll }
      $nums = @($scan | ?{ $_.T -match '^\d+$' })
      if($nums.Count -ge 2){ $okkk=[int]$nums[0].T } else { $okkk=0 }
    }
    $eksik=$adet-$okkk
    $rows.Add([pscustomobject]@{ bar=([string]$bar); ad=$ad; adet=$adet; okkk=$okkk; eksik=$eksik })
  }
  return $rows
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

function HastaBul($ocrRows){
  $sql = @"
copy (
  select coalesce(s.erecete_no,''), coalesce(s.protokol_no,''),
         to_char(s.islem_tarihi,'YYYY-MM-DD HH24:MI'),
         trim(coalesce(ch.adi,'')||' '||coalesce(ch.soyadi,'')),
         coalesce(ch.tckn,''), coalesce(nullif(ch.gsm1,''),ch.gsm2,''),
         coalesce(m.urun_adi,''), coalesce(m.urun_barkod,''),
         coalesce(m.stok_miktari,0)::text
  from eys_tbl_satis_recete s
  join eys_tbl_satis_fatura_kalem fk on fk.satis_fatura_id=s.fatura_id
  left join eys_tbl_mustahzar_temel m on m.urun_id=fk.urun_id
  left join eys_tbl_cari_hasta ch on ch.id=s.hasta_id
  where s.sonlandirilmis=false
    and s.medula_fatura_tipi is not null and trim(s.medula_fatura_tipi)<>''
    and s.islem_tarihi >= current_date - interval '$GunGeri days'
) to stdout with (format csv)
"@
  $rows = PsqlCsv $sql @('rec','prot','tarih','ad','tc','tel','ilac','bar','stok')
  if(-not $rows -or $rows.Count -eq 0){ return $null }

  # OCR kumeleri
  $ocrBar  = @($ocrRows | %{ BarNorm $_.bar } | ?{ $_ })
  $ocrAd   = @($ocrRows | %{ Norm (($_.ad -split '\s+')[0]) } | ?{ $_.Length -ge 3 })

  # recete bazinda grupla + skorla
  $grup=[ordered]@{}
  foreach($r in $rows){
    $rec = Bos $r.rec; if($rec -eq ""){ $rec = Bos $r.prot }; if($rec -eq ""){ continue }
    if(-not $grup.Contains($rec)){ $grup[$rec]=[ordered]@{ rec=$rec; prot=(Bos $r.prot); tarih=(Bos $r.tarih); ad=(Bos $r.ad); tc=(Bos $r.tc); tel=(Bos $r.tel); dr=@() } }
    $grup[$rec].dr += [pscustomobject]@{ ad=(Bos $r.ilac); bar=(BarNorm $r.bar); stok=([int]([decimal]::Parse((Bos $r.stok),[Globalization.CultureInfo]::InvariantCulture))) }
  }
  $enIyi=$null; $enSkor=0
  foreach($rec in $grup.Keys){
    $g=$grup[$rec]; $sk=0
    foreach($d in $g.dr){
      if($d.bar -and ($ocrBar -contains $d.bar)){ $sk+=2 }
      $dn = Norm (($d.ad -split '\s+')[0])
      if($dn.Length -ge 3 -and ($ocrAd | ?{ $_.StartsWith($dn.Substring(0,[math]::Min(4,$dn.Length))) -or $dn.StartsWith($_.Substring(0,[math]::Min(4,$_.Length))) }).Count -gt 0){ $sk+=1 }
    }
    if($sk -gt $enSkor){ $enSkor=$sk; $enIyi=$g }
    elseif($sk -eq $enSkor -and $enIyi -and $sk -gt 0){ if(($g.tarih) -gt ($enIyi.tarih)){ $enIyi=$g } }  # esitlikte en yeni
  }
  if($enSkor -le 0){ return $null }
  return $enIyi
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
if(-not $RXPASS){ Yaz "RXPASS okunamadi - rx-hasta.ps1 C:\EczaneStok'ta olmali" "Red"; exit 1 }
$anahtar = HastaAnahtari
if(-not $anahtar){ Yaz "hasta.key yok - once rx-hasta.ps1 -HastaKur" "Red"; exit 1 }

Yaz "`n[1/3] Ekran okunuyor (OCR)..." "Cyan"
$ocr = Tara
if(-not $ocr -or $ocr.Count -eq 0){ Yaz "Listele ekrani/tablo bulunamadi. Medula Listele ekrani onde mi?" "Red"; exit 2 }
Yaz ("{0,-28} {1,5} {2,6} {3,6}  {4}" -f "Ilac","Adet","Ok.KK","EKSIK","Barkod")
foreach($r in $ocr){ Yaz ("{0,-28} {1,5} {2,6} {3,6}  {4}" -f (($r.ad)[0..27] -join '').Trim(),$r.adet,$r.okkk,$r.eksik,$r.bar) }
$eksikler = @($ocr | ?{ $_.eksik -gt 0 })
if($eksikler.Count -eq 0){ Yaz "`nEksik ilac yok - hepsi okutulmus. Siparis olusturulmadi." "Green"; exit 0 }

Yaz "`n[2/3] Hasta eslestiriliyor (Rx DB)..." "Cyan"
$h = HastaBul $ocr
if($h){ Yaz ("Eslesen hasta: {0}  ({1})  tel={2}" -f $h.ad,$h.rec,$h.tel) "Green" }
else  { Yaz "Hasta eslesmedi - aday isimsiz gidecek (web'de telefon elle girilir)." "Yellow" }

# aday ilac listesi: OCR eksikleri (stok DB'den eslerse)
$drIlac = @()
foreach($e in $eksikler){
  $stok=0
  if($h){ $bn=BarNorm $e.bar; $en=Norm (($e.ad -split '\s+')[0])
    $m = $h.dr | ?{ ($_.bar -and $_.bar -eq $bn) -or (Norm (($_.ad -split '\s+')[0])).StartsWith($en.Substring(0,[math]::Min(4,$en.Length))) } | Select-Object -First 1
    if($m){ $stok=$m.stok; if(-not $e.ad){ $e.ad=$m.ad } } }
  $drIlac += [ordered]@{ ad=$e.ad; bar=$e.bar; adet=$e.adet; okkk=$e.okkk; eksik=$e.eksik; stok=$stok }
}
$aday = [ordered]@{
  zaman = (Get-Date).ToString("o")
  rec   = if($h){$h.rec}else{"OCR-"+(Get-Date -Format "HHmmss")}
  prot  = if($h){$h.prot}else{""}
  tarih = if($h){$h.tarih}else{(Get-Date -Format "yyyy-MM-dd HH:mm")}
  ad    = if($h){$h.ad}else{""}
  tc    = if($h){$h.tc}else{""}
  tel   = if($h){$h.tel}else{""}
  ilac  = $drIlac
}

Yaz "`n[3/3] Sifrelenip buluta yaziliyor (sgk_son)..." "Cyan"
BulutGiris
$sifreli = Sifrele $anahtar (ConvertTo-Json $aday -Depth 6 -Compress)
AyarYaz "sgk_son" $sifreli
Yaz ("TAMAM: {0} eksik ilac, hasta '{1}' -> web listesine dustu." -f $drIlac.Count, $aday.ad) "Green"
