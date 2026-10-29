# =====================================================================
#  OCR-SMART v2 - Listele ekranini DINAMIK + SIRA BAZLI oku
#  Pass1 (tam ekran): Barkod basligi + ilac satirlari (barkod Y'leri) + saga uzanim
#  Pass2 (kirp+3x buyut): her satirda stok "N/N" capasi -> Adet=ondan onceki sayi,
#    Ok.KK=ondan sonraki sayi (yoksa 0, cunku 0 OCR'da cikmaz). eksik=Adet-OkKK.
#  8 sn bekler -> Listele ekranini ONE getir.  -Verbose ile her satirin kelimeleri dokumlenir.
# =====================================================================
param([switch]$NoSleep, [switch]$Dok, [int]$Scale=3)
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
$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$full=New-Object System.Drawing.Bitmap($b.Width,$b.Height)
$g=[System.Drawing.Graphics]::FromImage($full);$g.CopyFromScreen($b.X,$b.Y,0,0,$b.Size);$g.Dispose()
$full.Save("C:\EczaneStok\cap.png",[System.Drawing.Imaging.ImageFormat]::Png)

# --- PASS 1: tablo konumu ---
$w1=OcrFile "C:\EczaneStok\cap.png"
$hBar=$w1|?{$_.T -match '^Barkod'}|Select-Object -First 1
if(-not $hBar){Write-Host "Baslik 'Barkod' yok - Listele ekrani onde mi?" -ForegroundColor Red;return}
$hy=$hBar.Y
$hrow=$w1|?{[math]::Abs($_.Y-$hy) -lt 18}
$hDozaj=$hrow|?{$_.T -match 'Dozaj'}|Select-Object -First 1
$hRaf=$hrow|?{$_.T -match 'Raf'}|Select-Object -First 1
$rightEnd= if($hRaf){$hRaf.X-10} elseif($hDozaj){$hDozaj.X+260} else {$hBar.X+760}
$barRows=$w1|?{ [math]::Abs($_.X-$hBar.X) -lt 70 -and $_.T -match '^8[56]\d{10,12}$' -and $_.Y -gt $hy } | Sort-Object Y
$rowYs=@(); foreach($r in $barRows){ if(($rowYs|?{[math]::Abs($_-$r.Y) -lt 12}).Count -eq 0){$rowYs+=$r.Y} }
Write-Host ("Barkod.X={0} Y={1} rightEnd={2} ilac_satiri={3}" -f $hBar.X,$hy,$rightEnd,$rowYs.Count) -ForegroundColor Cyan
if($rowYs.Count -eq 0){Write-Host "Ilac satiri yok." -ForegroundColor Red;return}

# --- PASS 2: kirp+buyut ---
$cropX=[math]::Max(0,$hBar.X-12); $cropY=[math]::Max(0,$hy-6)
$cropR=[math]::Min($b.Width,$rightEnd); $cropB=[math]::Min($b.Height,$rowYs[-1]+40)
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

# satir Y'leri (buyutulmus): barkoddan (sol, 13 hane) kumele
$bar2=$w2|?{ $_.X -lt (120*$Scale) -and $_.T -match '^\d{10,13}$' }|Sort-Object Y
$ry2=@(); foreach($r in $bar2){ if(($ry2|?{[math]::Abs($_-$r.Y) -lt (14*$Scale)}).Count -eq 0){$ry2+=$r.Y} }
if($ry2.Count -eq 0){ $ry2 = $rowYs | %{ ($_-$cropY)*$Scale } }   # yedek: pass1 satirlari

Write-Host ("`n=== OKUNAN (satir=" + $ry2.Count + ") ===") -ForegroundColor Cyan
Write-Host ("{0,-40} {1,5} {2,6} {3,6}" -f "Ilac","Adet","Ok.KK","EKSIK")
$sonuc=New-Object System.Collections.Generic.List[object]
foreach($ry in ($ry2|Sort-Object)){
  $row = $w2|?{ [math]::Abs($_.Y-$ry) -lt (14*$Scale) } | Sort-Object X
  if($Dok){ Write-Host ("  -- satir Y=$($ry): " + (($row|%{$_.T}) -join ' | ')) -ForegroundColor DarkGray }
  # isim: barkoddan sonraki ilk harfli kelimeler (sayi/stok gelene kadar)
  $nameW=@(); $hitNum=$false
  foreach($wd in $row){ if($wd.T -match '^\d'){ if($wd.T.Length -ge 2){$hitNum=$true} }
    if(-not $hitNum -and $wd.T -match '[A-Za-zÇĞİÖŞÜ]' -and $wd.X -gt (60*$Scale)){ $nameW+=$wd.T } }
  $ad = ($nameW -join ' ')
  # stok capasi: "N/N" ya da "-N/N" (0 bazen 'o'/'O' okunur). Tek kelime ya da "N" "/" "N" bolunmus.
  $stokL=$null; $stokRx=0
  $stokW = $row|?{ $_.T -match '^-?\d+\s*/\s*[0-9oO]+$' }|Select-Object -First 1
  if($stokW){ $stokL=$stokW.X; $stokRx=$stokW.R }
  else {
    # bolunmus: bir sayi + "/" + (sayi ya da o)
    for($i=0;$i -lt $row.Count-2;$i++){
      if($row[$i].T -match '^-?\d+$' -and $row[$i+1].T -match '^/$' -and $row[$i+2].T -match '^[0-9oO]+$'){
        $stokL=$row[$i].X; $stokRx=$row[$i+2].R; break
      }
    }
  }
  $adet=0; $okkk=0
  if($stokL -ne $null){
    $stokCX = ($stokL + $stokRx)/2
    $before = $row|?{ $_.X -lt $stokL -and $_.T -match '^\d+$' }|Sort-Object X
    if($before.Count -gt 0){ $adet=[int]($before[-1].T) }
    # stoktan sonraki kelimeler (merkez stok merkezinin sagi); dozaj "N Gunde" -> Gunde'den HEMEN ONCEKI sayi dozaj
    $afterAll = $row|?{ $_.CX -gt $stokCX -and $_.CX -gt $stokRx-20 }|Sort-Object X
    $dozIdx=-1
    for($i=0;$i -lt $afterAll.Count;$i++){ if($afterAll[$i].T -match 'G[uü]nde|Hafta'){ $dozIdx=$i; break } }
    $scan = if($dozIdx -ge 0){ if($dozIdx -gt 0){ $afterAll[0..($dozIdx-1)] } else { @() } } else { $afterAll }
    $nums = @($scan | ?{ $_.T -match '^\d+$' })
    # Gunde'den hemen onceki sayi = dozaj; ondan onceki (varsa) = Ok.KK
    if($nums.Count -ge 2){ $okkk=[int]$nums[0].T } else { $okkk=0 }
  }
  $eksik=$adet-$okkk
  $kisa= if($ad.Length -gt 40){$ad.Substring(0,40)}else{$ad}
  Write-Host ("{0,-40} {1,5} {2,6} {3,6}" -f $kisa,$adet,$okkk,$eksik)
  $sonuc.Add([pscustomobject]@{ad=$ad;adet=$adet;okkk=$okkk;eksik=$eksik})
}
$sonuc|ConvertTo-Json -Compress|Out-File "C:\EczaneStok\ocr-sonuc.json" -Encoding UTF8
Write-Host "`nJSON: C:\EczaneStok\ocr-sonuc.json" -ForegroundColor Green
