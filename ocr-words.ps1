# =====================================================================
#  OCR-WORDS - Ekrani OCR edip her kelimeyi KONUMU ile dokument eder.
#  Amac: KarekodIslem tablosunu X/Y konumlarindan yeniden kurabilmek icin
#  kelime yerlesimini gormek. Cikti: C:\EczaneStok\ocr-words.txt  (Y  X  GENISLIK  metin)
#  8 sn bekler; Listele ekranini ONE getir.
# =====================================================================
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime

Write-Host "8 sn icinde Listele ekranini ONE getir..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.X, $b.Y, 0, 0, $b.Size)
$png = "C:\EczaneStok\cap.png"
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function AwaitOp($op, $t) { $m = $asTaskGeneric.MakeGenericMethod($t); $tk = $m.Invoke($null, @($op)); $tk.Wait(-1) | Out-Null; $tk.Result }
$IRAS = [Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType = WindowsRuntime]

$sf     = AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
$stream = AwaitOp ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) $IRAS
$dec    = AwaitOp ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$swbmp  = AwaitOp ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$res = AwaitOp ($eng.RecognizeAsync($swbmp)) ([Windows.Media.Ocr.OcrResult])

$rows = New-Object System.Collections.Generic.List[string]
foreach ($ln in $res.Lines) {
  foreach ($w in $ln.Words) {
    $r = $w.BoundingRect
    $rows.Add(("{0,5} {1,5} {2,4}  {3}" -f [int]$r.Y, [int]$r.X, [int]$r.Width, $w.Text))
  }
}
# Y'ye sonra X'e gore sirala
$sorted = $rows | Sort-Object { [int]($_.Substring(0,5).Trim()) }, { [int]($_.Substring(6,5).Trim()) }
$sorted | Out-File "C:\EczaneStok\ocr-words.txt" -Encoding UTF8
Write-Host ("Kelime sayisi: " + $rows.Count + "   Dosya: C:\EczaneStok\ocr-words.txt") -ForegroundColor Green
