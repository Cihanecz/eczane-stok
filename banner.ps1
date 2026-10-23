# Eczane Stok — "veriler alınıyor" bilgisi. Odak çalmaz, Rx'e yapılan tıklamaları engellemez.
param([int]$Ana = 0)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System.Windows.Forms;
public class SessizForm : Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get { CreateParams c = base.CreateParams; c.ExStyle |= 0x08000000 | 0x00000008 | 0x00000080; return c; } }
}
"@
$KOK = "C:\EczaneStok"
$f = New-Object SessizForm
$f.FormBorderStyle = "None"; $f.TopMost = $true; $f.ShowInTaskbar = $false
$f.BackColor = [Drawing.Color]::FromArgb(14, 90, 71); $f.Width = 560; $f.Height = 64
$f.StartPosition = "Manual"; $f.Location = New-Object Drawing.Point(12, ([Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Bottom - 76))
$l = New-Object Windows.Forms.Label
$l.Text = "Eczane Stok: Rx'ten veriler alınıyor (birkaç dakika).`nLütfen bu sırada fareye ve klavyeye dokunmayın."
$l.ForeColor = "White"; $l.Font = New-Object Drawing.Font("Segoe UI", 10); $l.Location = New-Object Drawing.Point(14, 10); $l.Size = New-Object Drawing.Size(420, 46)
$d = New-Object Windows.Forms.Button
$d.Text = "Durdur"; $d.BackColor = "White"; $d.ForeColor = [Drawing.Color]::FromArgb(180, 35, 24); $d.FlatStyle = "Flat"
$d.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold); $d.Location = New-Object Drawing.Point(450, 14); $d.Size = New-Object Drawing.Size(96, 36)
$d.Add_Click({ New-Item -ItemType File -Force -Path (Join-Path $KOK "durdur.flag") | Out-Null; $l.Text = "Durduruluyor…"; $d.Enabled = $false })
$f.Controls.Add($l); $f.Controls.Add($d)
$t = New-Object Windows.Forms.Timer; $t.Interval = 1000
$t.Add_Tick({
  $yasiyor = $Ana -eq 0 -or (Get-Process -Id $Ana -ErrorAction SilentlyContinue)
  if (-not $yasiyor -or (Test-Path (Join-Path $KOK "bitti.flag"))) { $t.Stop(); $f.Close() }
})
$t.Start()
[Windows.Forms.Application]::Run($f)
