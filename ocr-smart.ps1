# =====================================================================
#  OCR-SMART - Listele ekranini DINAMIK oku (pencere konumundan bagimsiz)
#  1) Tam ekran OCR -> "Barkod/Adet/KK" basliklarindan sutun X'leri + ilac satirlari (barkod+ad+Y)
#  2) Tablo bolgesini kirp+3x buyut -> rakamlari (Adet, Ok.KK) konumdan oku
#  eksik = Adet - Ok.KK.  8 sn bekler -> Listele ekranini ONE getir.
# =====================================================================
param([switch]$NoSleep, [int]$Scale=3)
[Console]::OutputEncoding=[Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
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

if(-not $NoSleep){Write-Host "8 sn icinde Listele ekranini ONE getir..." -ForegroundColor Yellow;Start-Sleep -Seconds 8}
# --- tam ekran yakala ---
$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$full=New-Object System.Drawing.Bitmap($b.Width,$b.Height)
$g=[System.Drawing.Graphics]::FromImage($full);$g.CopyFromScreen($b.X,$b.Y,0,0,$b.Size);$g.Dispose()
$full.Save("C:\EczaneStok\cap.png",[System.Drawing.Imaging.ImageFormat]::Png)

# --- PASS 1: tam ekran OCR, basliklari bul ---
$w1=OcrFile "C:\EczaneStok\cap.png"
$hBar=$w1|?{$_.T -match '^Barkod'}|Select-Object -First 1
if(-not $hBar){Write-Host "Baslik 'Barkod' bulunamadi - Listele ekrani onde mi?" -ForegroundColor Red;return}
$hy=$hBar.Y
$hrow=$w1|?{[math]::Abs($_.Y-$hy) -lt 18}
$hMevcut=$hrow|?{$_.T -match 'Mevcut|Kritik'}|Select-Object -First 1
$hKK=$hrow|?{$_.T -match '^KK$|KK'}|Select-Object -First 1
$hDozaj=$hrow|?{$_.T -match 'Dozaj'}|Select-Object -First 1
$adetHdrs=$hrow|?{$_.T -match '^Adet'}|Sort-Object X
$mevX= if($hMevcut){$hMevcut.X}else{99999}
$adetX=($adetHdrs|?{$_.X -lt $mevX}|Select-Object -First 1).CX
$kkX= if($hKK){$hKK.CX}elseif($adetHdrs.Count -ge 2){($adetHdrs[-1]).CX}else{0}
$dozX= if($hDozaj){$hDozaj.X}else{99999}
Write-Host ("Basliklar: Barkod.X={0} Adet.X={1} KK.X={2} Dozaj.X={3} Y={4}" -f $hBar.X,$adetX,$kkX,$dozX,$hy) -ForegroundColor Cyan

# --- ilac satirlari: barkod sutununda 13 haneli (86/85 ile baslayan) numaralar ---
$barRows=$w1|?{ [math]::Abs($_.X-$hBar.X) -lt 60 -and $_.T -match '^8[56]\d{10,12}$' -and $_.Y -gt $hy } | Sort-Object Y
$rowYs=@(); foreach($r in $barRows){ if(($rowYs|?{[math]::Abs($_-$r.Y) -lt 12}).Count -eq 0){$rowYs+=$r.Y} }
Write-Host ("Ilac satiri sayisi: " + $rowYs.Count) -ForegroundColor Cyan
if($rowYs.Count -eq 0){Write-Host "Ilac satiri yok." -ForegroundColor Red;return}

# ilac adini al (isim sutunu: barkodun sagi ile adet sutunu solu arasi, harfli)
function AdAl($ry){ ($w1|?{[math]::Abs($_.Y-$ry) -lt 12 -and $_.X -gt ($hBar.R) -and $_.X -lt ($adetX-60) -and $_.T -match '[A-Za-zÇĞİÖŞÜ]'}|Sort-Object X|%{$_.T}) -join ' ' }

# --- PASS 2: tablo bolgesini kirp + buyut, rakamlari oku ---
$cropX=[math]::Max(0,$hBar.X-10); $cropY=[math]::Max(0,$hy-6)
$cropR=[math]::Min($b.Width, ($(if($dozX -lt 99999){$dozX}else{$kkX+120})+10))
$cropB=[math]::Min($b.Height, ($rowYs[-1]+40))
$cw=$cropR-$cropX; $ch=$cropB-$cropY
$src=[System.Drawing.Image]::FromFile("C:\EczaneStok\cap.png")
$cr=New-Object System.Drawing.Bitmap($cw,$ch); $gc=[System.Drawing.Graphics]::FromImage($cr)
$gc.DrawImage($src,(New-Object System.Drawing.Rectangle(0,0,$cw,$ch)),$cropX,$cropY,$cw,$ch,[System.Drawing.GraphicsUnit]::Pixel);$gc.Dispose()
$big=New-Object System.Drawing.Bitmap(($cw*$Scale),($ch*$Scale)); $gb=[System.Drawing.Graphics]::FromImage($big)
$gb.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gb.DrawImage($cr,0,0,($cw*$Scale),($ch*$Scale));$gb.Dispose()
$big.Save("C:\EczaneStok\cap-crop.png",[System.Drawing.Imaging.ImageFormat]::Png)
$src.Dispose();$cr.Dispose();$big.Dispose()
$w2=OcrFile "C:\EczaneStok\cap-crop.png"

# native -> buyutulmus donusum
function ToBigX($nx){ ($nx-$cropX)*$Scale }
function ToBigY($ny){ ($ny-$cropY)*$Scale }
$adetBX=ToBigX $adetX; $kkBX=ToBigX $kkX; $tolX=42*$Scale; $tolY=16*$Scale
function NumAt($ry,$cx){ $c=$w2|?{[math]::Abs($_.Y-$ry) -lt $tolY -and [math]::Abs($_.CX-$cx) -lt $tolX -and $_.T -match '^\d+$'}; if($c.Count -eq 0){return 0}; [int](($c|Sort-Object {[math]::Abs($_.CX-$cx)})[0].T) }

Write-Host ("`n=== OKUNAN ===") -ForegroundColor Cyan
Write-Host ("{0,-42} {1,5} {2,6} {3,6}" -f "Ilac","Adet","Ok.KK","EKSIK")
$sonuc=New-Object System.Collections.Generic.List[object]
foreach($ry in $rowYs){
  $ad=AdAl $ry
  $by=ToBigY $ry
  $adet=NumAt $by $adetBX
  $okkk=NumAt $by $kkBX
  $eksik=$adet-$okkk
  $kisa= if($ad.Length -gt 42){$ad.Substring(0,42)}else{$ad}
  Write-Host ("{0,-42} {1,5} {2,6} {3,6}" -f $kisa,$adet,$okkk,$eksik)
  $sonuc.Add([pscustomobject]@{ad=$ad;adet=$adet;okkk=$okkk;eksik=$eksik})
}
$sonuc|ConvertTo-Json -Compress|Out-File "C:\EczaneStok\ocr-sonuc.json" -Encoding UTF8
Write-Host "`nJSON yazildi: C:\EczaneStok\ocr-sonuc.json" -ForegroundColor Green
