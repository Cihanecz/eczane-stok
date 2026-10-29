# cap.png'den tablo bolgesini kirp + 3x buyut + OCR (kucuk rakamlar okunsun diye).
# Cikti: C:\EczaneStok\cap-crop.png  ve  C:\EczaneStok\ocr-words.txt  (Y X W metin, buyutulmus koordinat)
param(
  [int]$CropX = 1080, [int]$CropY = 385, [int]$CropW = 660, [int]$CropH = 140, [int]$Scale = 3
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$src = [System.Drawing.Image]::FromFile("C:\EczaneStok\cap.png")
$crop = New-Object System.Drawing.Bitmap($CropW, $CropH)
$gc = [System.Drawing.Graphics]::FromImage($crop)
$gc.DrawImage($src, (New-Object System.Drawing.Rectangle(0,0,$CropW,$CropH)), $CropX, $CropY, $CropW, $CropH, [System.Drawing.GraphicsUnit]::Pixel)
$gc.Dispose()
$big = New-Object System.Drawing.Bitmap(($CropW*$Scale), ($CropH*$Scale))
$gb = [System.Drawing.Graphics]::FromImage($big)
$gb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gb.DrawImage($crop, 0, 0, ($CropW*$Scale), ($CropH*$Scale))
$gb.Dispose()
$out = "C:\EczaneStok\cap-crop.png"
$big.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$src.Dispose(); $crop.Dispose(); $big.Dispose()
Write-Host "Kirpildi+buyutuldu: $out" -ForegroundColor Green

[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function AwaitOp($op, $t) { $m = $asTaskGeneric.MakeGenericMethod($t); $tk = $m.Invoke($null, @($op)); $tk.Wait(-1) | Out-Null; $tk.Result }
$IRAS = [Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType = WindowsRuntime]
$sf     = AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($out)) ([Windows.Storage.StorageFile])
$stream = AwaitOp ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) $IRAS
$dec    = AwaitOp ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$swbmp  = AwaitOp ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$res = AwaitOp ($eng.RecognizeAsync($swbmp)) ([Windows.Media.Ocr.OcrResult])

$rows = New-Object System.Collections.Generic.List[object]
foreach ($ln in $res.Lines) { foreach ($w in $ln.Words) { $r=$w.BoundingRect; $rows.Add([pscustomobject]@{Y=[int]$r.Y;X=[int]$r.X;W=[int]$r.Width;T=$w.Text}) } }
($rows | Sort-Object Y,X | ForEach-Object { "{0,5} {1,5} {2,4}  {3}" -f $_.Y,$_.X,$_.W,$_.T }) | Out-File "C:\EczaneStok\ocr-words.txt" -Encoding UTF8
Write-Host ("Kelime: " + $rows.Count + "   -> C:\EczaneStok\ocr-words.txt") -ForegroundColor Green
Write-Host "--- TUM METIN ---" -ForegroundColor Cyan
Write-Host $res.Text
