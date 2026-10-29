# =====================================================================
#  OCR-TEST - Windows yerlesik OCR (Windows.Media.Ocr) ile ekran okuma denemesi
#  Amac: Listele/Karekod tablosundaki barkod + Adet + Ok.KK Adet rakamlari temiz okunuyor mu?
#  8 sn bekler; bu surede Listele ekranini ONE getir. Ekrani yakalar, OCR eder, C:\EczaneStok\ocr.txt'e yazar.
# =====================================================================
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime

Write-Host "8 sn icinde Listele / Karekod ekranini ONE getir..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

# --- ekran yakala ---
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.X, $b.Y, 0, 0, $b.Size)
$png = "C:\EczaneStok\cap.png"
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "Ekran yakalandi: $png" -ForegroundColor Green

# --- WinRT tipleri ---
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.FileAccessMode, Windows.Foundation, ContentType = WindowsRuntime]

# --- async await yardimcisi ---
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function AwaitOp($op, $resultType) {
  $m = $asTaskGeneric.MakeGenericMethod($resultType)
  $task = $m.Invoke($null, @($op))
  $task.Wait(-1) | Out-Null
  $task.Result
}

$IRAS = [Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType = WindowsRuntime]

$sf     = AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
$stream = AwaitOp ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) $IRAS
$dec    = AwaitOp ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$swbmp  = AwaitOp ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

$eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $eng) { Write-Host "OCR motoru yok (dil paketi eksik olabilir)." -ForegroundColor Red; return }
$res = AwaitOp ($eng.RecognizeAsync($swbmp)) ([Windows.Media.Ocr.OcrResult])

$res.Text | Out-File "C:\EczaneStok\ocr.txt" -Encoding UTF8
Write-Host ("OCR tamam. Satir sayisi: " + $res.Lines.Count + "   Dosya: C:\EczaneStok\ocr.txt") -ForegroundColor Green
