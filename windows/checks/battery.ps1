# Battery: wear and cycles (prior use), and design capacity (a replaced battery has a different one).
Section 'Battery'
$batHtml = Join-Path $OutDir 'battery-report.html'
$batXml  = Join-Path $OutDir 'battery-report.xml'
powercfg /batteryreport /output "$batHtml" | Out-Null
powercfg /batteryreport /xml /output "$batXml" | Out-Null
try {
    [xml]$bx = Get-Content $batXml -Raw
    $b = $bx.SelectSingleNode("//*[local-name()='Battery']")
    $design = [double]$b.SelectSingleNode("*[local-name()='DesignCapacity']").InnerText
    $full   = [double]$b.SelectSingleNode("*[local-name()='FullChargeCapacity']").InnerText
    $cycles = [int]$b.SelectSingleNode("*[local-name()='CycleCount']").InnerText
    $pct = [math]::Round(100 * $full / $design, 1)
    $detail = "full $full / design $design mWh = $pct%, cycles $cycles"
    if ($pct -lt $Expect.BatteryHealthMinPct -or $cycles -gt $Expect.BatteryCyclesMax) { Add-Result 'WARN' 'Battery' "$detail (more wear than a new unit)" }
    else { Add-Result 'PASS' 'Battery' $detail }
    # Design capacity is fixed per battery model: a different number means a different battery
    $designWh = [math]::Round($design / 1000, 1)
    if (-not (Test-Spec 'BatteryWh')) { Add-Result 'INFO' 'Battery model' "designed for $designWh Wh" }
    elseif ([math]::Abs($designWh - $Expect.BatteryWh) -le 0.1 * $Expect.BatteryWh) { Add-Result 'PASS' 'Battery model' "designed for $designWh Wh" }
    else { Add-Result 'WARN' 'Battery model' "designed for $designWh Wh, expected about $($Expect.BatteryWh) Wh. Replaced battery? Ask the maker's support which battery this serial shipped with" }
    $batInfo = [ordered]@{}
    foreach ($f in 'Id', 'Manufacturer', 'SerialNumber', 'Chemistry', 'DesignCapacity', 'FullChargeCapacity', 'CycleCount') {
        $node = $b.SelectSingleNode("*[local-name()='$f']")
        $batInfo[$f] = if ($node) { $node.InnerText } else { '' }
    }
    Save-Text 'battery.txt' ($batInfo.GetEnumerator() | ForEach-Object { '{0,-20} {1}' -f $_.Key, $_.Value })
} catch {
    Add-Result 'INFO' 'Battery' 'could not parse the XML report. Open battery-report.html'
}
