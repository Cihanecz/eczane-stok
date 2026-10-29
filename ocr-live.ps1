# =====================================================================
#  OCR-LIVE - Canli Listele ekranini oku, eksik ilaclari cikar (test)
#  8 sn bekler -> Listele ekranini ONE getir. Tabloyu kirp+3x buyut+OCR,
#  konumdan Adet & Ok.KK sutunlarini oku, eksik = Adet - Ok.KK.
#  Sutun X'leri BUYUTULMUS kirpik koordinatinda. Pencere ayni yerdeyse calisir.
# =====================================================================
param(
  [int]$CropX = 1080, [int]$CropY = 385, [int]$CropW = 690, [int]$CropH = 180, [int]$Scale = 3,
  [int]$NameColX = 342, [int]$AdetColX = 1038, [int]$OkKKColX = 1530, [int]$Tol = 90, [int]$RowTol = 32,
  [switch]$NoSleep
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime

if (-not $NoSleep) { Write-Host "8 sn icinde Listele ekranini ONE getir..." -ForegroundColor Yellow; Start-Sleep -Seconds 8 }

# --- yakala (tam ekran) ---
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$full = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($full); $g.CopyFromScreen($b.X,$b.Y,0,0,$b.Size); $g.Dispose()
$full.Save("C:\EczaneStok\cap.png", [System.Drawing.Imaging.ImageFormat]::Png)

# --- kirp + buyut ---
$crop = New-Object System.Drawing.Bitmap($CropW, $CropH)
$gc = [System.Drawing.Graphics]::FromImage($crop)
$gc.DrawImage($full, (New-Object System.Drawing.Rectangle(0,0,$CropW,$CropH)), $CropX,$CropY,$CropW,$CropH, [System.Drawing.GraphicsUnit]::Pixel); $gc.Dispose()
$big = New-Object System.Drawing.Bitmap(($CropW*$Scale),($CropH*$Scale))
$gb = [System.Drawing.Graphics]::FromImage($big); $gb.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gb.DrawImage($crop,0,0,($CropW*$Scale),($CropH*$Scale)); $gb.Dispose()
$out="C:\EczaneStok\cap-crop.png"; $big.Save($out,[System.Drawing.Imaging.ImageFormat]::Png)
$full.Dispose(); $crop.Dispose(); $big.Dispose()

# --- OCR ---
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function AwaitOp($op,$t){ $m=$asTaskGeneric.MakeGenericMethod($t); $tk=$m.Invoke($null,@($op)); $tk.Wait(-1)|Out-Null; $tk.Result }
$IRAS=[Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType = WindowsRuntime]
$sf=AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($out)) ([Windows.Storage.StorageFile])
$st=AwaitOp ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) $IRAS
$dc=AwaitOp ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sb=AwaitOp ($dc.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$eng=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$res=AwaitOp ($eng.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])

$words = New-Object System.Collections.Generic.List[object]
foreach($ln in $res.Lines){ foreach($w in $ln.Words){ $r=$w.BoundingRect; $words.Add([pscustomobject]@{Y=[int]($r.Y+$r.Height/2); X=[int]$r.X; CX=[int]($r.X+$r.Width/2); T=$w.Text}) } }

# --- satirlara kumele (isim sutununda harfli kelime olan Y'ler) ---
$nameWords = $words | Where-Object { [math]::Abs($_.X - $NameColX) -lt 140 -and $_.T -match '^[A-Za-zÇĞİÖŞÜçğıöşü]{3,}$' }
$rowsY = @()
foreach($nw in ($nameWords | Sort-Object Y)){ if( ($rowsY | Where-Object { [math]::Abs($_ - $nw.Y) -lt $RowTol }).Count -eq 0 ){ $rowsY += $nw.Y } }

function NumAt($rowY,$colX){
  $cand = $words | Where-Object { [math]::Abs($_.Y-$rowY) -lt $RowTol -and [math]::Abs($_.CX-$colX) -lt $Tol -and $_.T -match '^\d+$' }
  if($cand.Count -eq 0){ return 0 }
  return [int](($cand | Sort-Object { [math]::Abs($_.CX-$colX) })[0].T)
}
function NameAt($rowY){
  $cand = $words | Where-Object { [math]::Abs($_.Y-$rowY) -lt $RowTol -and $_.X -lt ($AdetColX-120) -and $_.T -match '[A-Za-zÇĞİÖŞÜçğıöşü]{3,}' } | Sort-Object X
  if($cand.Count -eq 0){ return "?" }
  return ($cand | ForEach-Object { $_.T }) -join ' '
}

Write-Host ("`n=== OKUNAN TABLO (satir=" + $rowsY.Count + ") ===") -ForegroundColor Cyan
Write-Host ("{0,-45} {1,5} {2,6} {3,6}" -f "Ilac","Adet","Ok.KK","EKSIK")
$sonuc = New-Object System.Collections.Generic.List[object]
foreach($ry in ($rowsY | Sort-Object)){
  $ad = NameAt $ry
  $adet = NumAt $ry $AdetColX
  $okkk = NumAt $ry $OkKKColX
  $eksik = $adet - $okkk
  Write-Host ("{0,-45} {1,5} {2,6} {3,6}" -f $ad.Substring(0,[math]::Min(45,$ad.Length)), $adet, $okkk, $eksik)
  $sonuc.Add([pscustomobject]@{ad=$ad; adet=$adet; okkk=$okkk; eksik=$eksik})
}
$sonuc | ConvertTo-Json -Compress | Out-File "C:\EczaneStok\ocr-sonuc.json" -Encoding UTF8
Write-Host "`nJSON: C:\EczaneStok\ocr-sonuc.json" -ForegroundColor Green
