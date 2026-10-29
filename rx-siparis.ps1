# =====================================================================
#  ECZANE STOK - Rx EKSIK ILAC / SGK RECETE SIPARIS KOPRUSU (rx-siparis.ps1)
#  Rx EYS_DB'den (rx_oku, SADECE-OKUMA) gunun EKSIK verilen recetelerini okur:
#    eksik = yazilan_adet - verilen_adet  (satis_fatura_kalem)
#  Hasta adi/TC/telefon + eksik ilac (barkod/ad/adet/stok) -> ECZANEDE SIFRELER
#  (hasta.key, program ile birebir) -> Supabase ayar.sgk_aday'a yazar.
#  Rx'e DOKUNMAZ. TC GONDERILMEZ (sadece sifreli). Web tarafi hasta sifresiyle acar.
#  NOT: Bu "aday" listesidir (gunun eksikleri). Eczaci web'de onaylayinca kalici
#       siparis olusur; bu kopru aday listesini her donguda tazeler (ustune yazar).
#
#  Dogrulanan sema (29.10.2026, gercek veriyle test edildi - 2R7VV8S):
#    satis_recete (erecete_no, protokol_no, islem_tarihi, hasta_id, fatura_id)
#      -> satis_fatura_kalem (satis_fatura_id=fatura_id : yazilan_adet, verilen_adet)
#      -> mustahzar_temel   (urun_id : urun_barkod, urun_adi, stok_miktari)
#      -> cari_hasta        (id=hasta_id : adi, soyadi, tckn, gsm1, gsm2)
#    NOT: hasta adi satis_recete.hasta_ad_soyad'ta BOS; cari_hasta.adi+soyadi kullanilir (dogrulandi 29.10).
#    MATOFIN XR yaz 2 / ver 1 -> eksik 1  (DOGRULANDI)
#    Ilk kurulum (bir kerelik):  powershell -ExecutionPolicy Bypass -File rx-siparis.ps1 -HastaKur
# =====================================================================
param(
  [switch]$Once,
  [switch]$HastaKur,
  [int]$Periyot   = 120,    # saniye (2 dk) - verilen_adet canli degisir, sik tarariz
  [int]$GunGeri   = 30      # bugun + son GunGeri gun icindeki receteler (eksikler 30 gun listede kalir)
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $env:PGCLIENTENCODING = 'UTF8'
Add-Type -AssemblyName System.Security

# ---------- ayarlar (ECZANE 1) ----------
$KOK    = "C:\EczaneStok"
$SB_URL = "https://crgfvsfncazexynzhwmo.supabase.co"
$SB_KEY = "sb_publishable_WqWzwvumk9pMhBoV6LeMMA_tEgvzbPw"
$GIRIS  = Join-Path $KOK "giris.dat"
$GUNLUK = Join-Path $KOK "siparis-kopru.log"
$HASTA_ANAHTAR = Join-Path $KOK "hasta.key"
$PSQL   = "C:\Program Files (x86)\GEMAS\RxMediaPharma EYS\pgsql\bin\psql.exe"
$RXHOST = "127.0.0.1"; $RXPORT = "5432"; $RXDB = "EYS_DB"
$RXUSER = "rx_oku"
# RXPASS git'e girmesin diye calisma aninda rx-hasta.ps1'den okunur (ayni PC'de kurulu)
$RXPASS = ""
try { $m = (Select-String -Path (Join-Path $KOK "rx-hasta.ps1") -Pattern '\$RXPASS\s*=\s*"([^"]+)"').Matches; if ($m -and $m.Count) { $RXPASS = $m[0].Groups[1].Value } } catch {}
if (-not $RXPASS) { throw "RXPASS okunamadi - rx-hasta.ps1 C:\EczaneStok'ta olmali" }

New-Item -ItemType Directory -Force -Path $KOK | Out-Null
function Log($m) { $s = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $m
  Add-Content -Path $GUNLUK -Value $s -Encoding UTF8; Write-Host $s }

# ---------- Supabase ----------
$script:JETON = $null; $script:JZAMAN = [datetime]::MinValue
function BulutGiris {
  if (-not (Test-Path $GIRIS)) { throw "Giris bilgisi yok: $GIRIS" }
  $s  = Get-Content $GIRIS -Encoding UTF8
  $ep = $s[0].Trim(); $sf = $s[1].Trim() | ConvertTo-SecureString
  $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sf))
  $r = Invoke-RestMethod -Method Post -Uri "$SB_URL/auth/v1/token?grant_type=password" `
        -Headers @{ apikey = $SB_KEY } -ContentType "application/json; charset=utf-8" `
        -Body ([Text.Encoding]::UTF8.GetBytes((@{ email = $ep; password = $pw } | ConvertTo-Json -Compress)))
  $script:JETON = $r.access_token; $script:JZAMAN = Get-Date; Log "Supabase girisi tamam ($ep)"
}
function Jeton { if ($null -eq $script:JETON -or ((Get-Date)-$script:JZAMAN).TotalMinutes -gt 45) { BulutGiris }; $script:JETON }
function AyarOku([string]$anahtar) {
  $j = Jeton
  $r = Invoke-RestMethod -Method Get -Uri "$SB_URL/rest/v1/ayar?select=deger&anahtar=eq.$anahtar" `
        -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $j" } -TimeoutSec 60
  if ($r -and $r.Count) { return $r[0].deger } else { return $null }
}
function AyarYaz([string]$anahtar, [string]$deger) {
  $j = Jeton
  $body = @([ordered]@{ anahtar = $anahtar; deger = $deger; guncelleme = (Get-Date).ToString("o") }) | ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri "$SB_URL/rest/v1/ayar?on_conflict=anahtar" `
    -Headers @{ apikey = $SB_KEY; Authorization = "Bearer $j"; Prefer = "resolution=merge-duplicates,return=minimal" } `
    -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120 | Out-Null
}

# ---------- sifreleme (program toplayici.ps1 / rx-hasta.ps1 ile BIREBIR) ----------
function HastaAnahtari {
  if (-not (Test-Path $HASTA_ANAHTAR)) { return $null }
  [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($HASTA_ANAHTAR), $null, 'CurrentUser')
}
function Sifrele([byte[]]$anahtar, [string]$metin) {
  $ham = [Text.Encoding]::UTF8.GetBytes($metin)
  $ms = New-Object IO.MemoryStream; $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress); $gz.Write($ham, 0, $ham.Length); $gz.Close(); $ham = $ms.ToArray()
  $aes = [Security.Cryptography.Aes]::Create(); $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = [byte[]]$anahtar[0..31]; $aes.GenerateIV()
  $ct = $aes.CreateEncryptor().TransformFinalBlock($ham, 0, $ham.Length)
  $iv_ct = [byte[]]($aes.IV + $ct)
  $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (,[byte[]]$anahtar[32..63])
  [Convert]::ToBase64String([byte[]]($iv_ct + $h.ComputeHash($iv_ct)))
}
function HastaKur {
  # rx-hasta.ps1 ile ayni anahtar kurulumu; zaten rx-hasta kurduysa gerek yok (ayni hasta.key).
  if (Test-Path $HASTA_ANAHTAR) { Write-Host "hasta.key zaten var (rx-hasta ile kurulmus)." -ForegroundColor Green; return }
  Write-Host "Once rx-hasta.ps1 -HastaKur ile hasta sifresini kur; ayni hasta.key kullanilir." -ForegroundColor Yellow
}

# ---------- Rx oku ----------
function PsqlCsv([string]$sql, [string[]]$basliklar) {
  $env:PGPASSWORD = $RXPASS
  $csv = & $PSQL -h $RXHOST -p $RXPORT -U $RXUSER -d $RXDB -w -v ON_ERROR_STOP=1 -c $sql
  if ($LASTEXITCODE -ne 0) { throw "psql hata ($LASTEXITCODE)" }
  if (-not $csv) { return @() }
  @(ConvertFrom-Csv -InputObject $csv -Header $basliklar)
}
function Sayi($s) { if ([string]::IsNullOrWhiteSpace($s)) { return 0 }; try { [int][decimal]::Parse($s, [Globalization.CultureInfo]::InvariantCulture) } catch { 0 } }
function Bos($s) { if ($null -eq $s) { "" } else { ([string]$s).Trim() } }

function SiparisDongu {
  $anahtar = HastaAnahtari
  if (-not $anahtar) { throw "hasta.key yok - once: rx-hasta.ps1 -HastaKur" }

  # --- BEKLEYEN EKSIK: eksik>0 VE sonlandirilmamis (hasta bekliyor) VE aya faturalanmamis ---
  $sql = @"
copy (
  select coalesce(s.erecete_no,''),
         coalesce(s.protokol_no,''),
         to_char(s.islem_tarihi,'YYYY-MM-DD HH24:MI'),
         trim(coalesce(ch.adi,'') || ' ' || coalesce(ch.soyadi,'')),
         coalesce(ch.tckn,''),
         coalesce(nullif(ch.gsm1,''), ch.gsm2, ''),
         coalesce(m.urun_adi,''),
         coalesce(m.urun_barkod,''),
         (fk.yazilan_adet - fk.verilen_adet)::text,
         coalesce(m.stok_miktari,0)::text
  from eys_tbl_satis_recete s
  join eys_tbl_satis_fatura_kalem fk on fk.satis_fatura_id = s.fatura_id
  left join eys_tbl_mustahzar_temel m on m.urun_id = fk.urun_id
  left join eys_tbl_cari_hasta ch on ch.id = s.hasta_id
  where (fk.yazilan_adet - fk.verilen_adet) > 0
    and s.sonlandirilmis = false      -- sonlanmamis = hasta hala bekliyor (sonlandi=bitti, cikar)
    and s.faturalandirilmis = false   -- aya faturalanmamis (fatura sonlandirilinca eski aylar duser)
    and s.islem_tarihi >= date_trunc('month', current_date - interval '1 month')  -- onceki ay basindan itibaren
) to stdout with (format csv)
"@
  $rows = PsqlCsv $sql @('rec','prot','tarih','ad','tc','tel','ilac','bar','eksik','stok')

  # recete bazinda grupla
  $grup = [ordered]@{}
  foreach ($r in $rows) {
    $rec = Bos $r.rec; if ($rec -eq "") { $rec = Bos $r.prot }; if ($rec -eq "") { continue }
    $il  = Bos $r.ilac; $ek = Sayi $r.eksik; if ($ek -le 0) { continue }
    if (-not $grup.Contains($rec)) {
      $grup[$rec] = [ordered]@{
        rec = $rec; prot = Bos $r.prot; tarih = Bos $r.tarih
        ad = Bos $r.ad; tc = Bos $r.tc; tel = Bos $r.tel
        ilac = New-Object System.Collections.ArrayList
      }
    }
    [void]$grup[$rec].ilac.Add([ordered]@{
      ad = $il; bar = Bos $r.bar; eksik = $ek; stok = Sayi $r.stok
    })
  }
  $liste = @($grup.Values | ForEach-Object { $_.ilac = $_.ilac.ToArray(); $_ })

  $veri = [ordered]@{ zaman = (Get-Date).ToString("o"); liste = $liste }
  $sifreli = Sifrele $anahtar (ConvertTo-Json $veri -Depth 6 -Compress)
  AyarYaz "sgk_aday" $sifreli
  $toplamIlac = ($liste | ForEach-Object { $_.ilac.Count } | Measure-Object -Sum).Sum
  Log ("SGK aday yazildi: {0} recete, {1} eksik ilac (sifreli)" -f $liste.Count, [int]$toplamIlac)
}

# ---------- ana ----------
# Surum: 2026-10-29a (eksik = yazilan - verilen, satis zinciri + cari_hasta)
if ($HastaKur) { HastaKur; return }
Log "=== Rx siparis koprusu basladi (periyot ${Periyot}sn, GunGeri=$GunGeri, Once=$Once) ==="
BulutGiris
do {
  try { SiparisDongu }
  catch {
    Log "HATA: $($_.Exception.Message)"
    if ($_.Exception.Response.StatusCode.value__ -eq 401) { try { BulutGiris } catch {} }
  }
  if (-not $Once) { Start-Sleep -Seconds $Periyot }
} while (-not $Once)
Log "Siparis koprusu bitti."
