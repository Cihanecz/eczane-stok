# Rx penceresindeki "Raporlar" adlı öğeleri listeler (sadece okur)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$A = [Windows.Automation.AutomationElement]; $TS = [Windows.Automation.TreeScope]
$p = Get-Process RxMediaPharmaEYS | Select-Object -First 1
$rx = $A::FromHandle($p.MainWindowHandle)
$kos = New-Object Windows.Automation.PropertyCondition($A::NameProperty, "Raporlar")
foreach ($e in $rx.FindAll($TS::Descendants, $kos)) {
  $r = $e.Current.BoundingRectangle
  "{0,-14} {1,-22} x={2} y={3} w={4} h={5} off={6}" -f $e.Current.ControlType.ProgrammaticName.Replace('ControlType.',''), $e.Current.ClassName, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height, $e.Current.IsOffscreen
  foreach ($c in $e.FindAll($TS::Children, [Windows.Automation.Condition]::TrueCondition)) { $q = $c.Current.BoundingRectangle; "     - {0} '{1}' x={2} y={3} w={4}" -f $c.Current.ControlType.ProgrammaticName.Replace('ControlType.',''), $c.Current.Name, [int]$q.X, [int]$q.Y, [int]$q.Width }
}
"--- sekme sinifi adaylari:"
$tc = New-Object Windows.Automation.PropertyCondition($A::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)
foreach ($e in $rx.FindAll($TS::Descendants, $tc)) { $r = $e.Current.BoundingRectangle; "TabItem '{0}' x={1} y={2} w={3}" -f $e.Current.Name, [int]$r.X, [int]$r.Y, [int]$r.Width }
