# Var olan C:\EczaneStok\cap.png'i (onceki ÖZKAN ekrani) OCR edip kelime konumlarini dokumentle.
# Canli ekran GEREKMEZ. Cikti: C:\EczaneStok\ocr-words.txt  (Y  X  GENISLIK  metin), Y sonra X'e gore.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$png = "C:\EczaneStok\cap.png"
if (-not (Test-Path $png)) { Write-Host "cap.png yok: $png" -ForegroundColor Red; return }

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

$rows = New-Object System.Collections.Generic.List[object]
foreach ($ln in $res.Lines) {
  foreach ($w in $ln.Words) {
    $r = $w.BoundingRect
    $rows.Add([pscustomobject]@{ Y = [int]$r.Y; X = [int]$r.X; W = [int]$r.Width; T = $w.Text })
  }
}
$sorted = $rows | Sort-Object Y, X
$lines = $sorted | ForEach-Object { "{0,5} {1,5} {2,4}  {3}" -f $_.Y, $_.X, $_.W, $_.T }
$lines | Out-File "C:\EczaneStok\ocr-words.txt" -Encoding UTF8
Write-Host ("Kelime sayisi: " + $rows.Count + "   Dosya: C:\EczaneStok\ocr-words.txt") -ForegroundColor Green
