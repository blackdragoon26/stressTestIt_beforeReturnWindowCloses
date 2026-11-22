# The report: SUMMARY.txt, a detailed HTML report printed to PDF by Microsoft Edge (built into
# Windows), and MANIFEST.sha256 over every file. Everything the run collected goes into one shareable
# file: results, exact parts, sensor charts, raw outputs, the kit's own fingerprints, and any script
# errors, so a person or another agent can review it later.

$header = @(
    "SecondTrust audit ($mode)",
    "Run at   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
    "Computer : $env:COMPUTERNAME",
    "Output   : $OutDir",
    ''
)
$fails = @($Summary | Where-Object { $_ -like 'FAIL*' }).Count
$warns = @($Summary | Where-Object { $_ -like 'WARN*' }).Count
$footer = @('', "Totals: $fails FAIL, $warns WARN")
Save-Text 'SUMMARY.txt' ($header + $Summary + $footer)

Stop-Transcript | Out-Null

function Enc($s) { [System.Net.WebUtility]::HtmlEncode("$s") }

function ConvertTo-HtmlTable($rows, [int]$max = 400) {
    $rows = @($rows)
    if ($rows.Count -eq 0) { return '<p class="muted">(empty)</p>' }
    $names = @($rows[0].PSObject.Properties.Name)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<table><tr>')
    foreach ($c in $names) { [void]$sb.Append("<th>$(Enc $c)</th>") }
    [void]$sb.Append('</tr>')
    foreach ($row in ($rows | Select-Object -First $max)) {
        [void]$sb.Append('<tr>')
        foreach ($c in $names) { [void]$sb.Append("<td>$(Enc $row.$c)</td>") }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</table>')
    if ($rows.Count -gt $max) { [void]$sb.Append("<p class=`"muted`">First $max of $($rows.Count) rows. The full list is in the CSV file.</p>") }
    return $sb.ToString()
}

function New-SvgChart($title, $xs, $ys, $unit) {
    $pts = @()
    for ($i = 0; $i -lt $ys.Count; $i++) { if ("$($ys[$i])" -ne '') { $pts += , @([double]$xs[$i], [double]$ys[$i]) } }
    if ($pts.Count -lt 2) { return '' }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $x0 = ($pts | ForEach-Object { $_[0] } | Measure-Object -Minimum -Maximum)
    $y0 = ($pts | ForEach-Object { $_[1] } | Measure-Object -Minimum -Maximum)
    $xr = [math]::Max(1, $x0.Maximum - $x0.Minimum); $yr = [math]::Max(1, $y0.Maximum - $y0.Minimum)
    $w = 900; $ht = 160; $l = 50; $t = 10
    $poly = ($pts | ForEach-Object {
        [string]::Format($inv, '{0:0.0},{1:0.0}', $l + ($_[0] - $x0.Minimum) / $xr * ($w - $l - 10), $t + ($y0.Maximum - $_[1]) / $yr * ($ht - $t - 25))
    }) -join ' '
    $mins = [math]::Round($x0.Maximum / 60, 1)
    return @"
<div class="chart"><div class="ct">$(Enc $title) ($unit): min $([math]::Round($y0.Minimum,1)), max $([math]::Round($y0.Maximum,1))</div>
<svg width="$w" height="$ht" viewBox="0 0 $w $ht" xmlns="http://www.w3.org/2000/svg">
<line x1="$l" y1="$($ht-25)" x2="$($w-10)" y2="$($ht-25)" stroke="#999"/><line x1="$l" y1="$t" x2="$l" y2="$($ht-25)" stroke="#999"/>
<text x="2" y="$($t+10)" font-size="10">$([math]::Round($y0.Maximum,1))</text><text x="2" y="$($ht-27)" font-size="10">$([math]::Round($y0.Minimum,1))</text>
<text x="$l" y="$($ht-8)" font-size="10">0 min</text><text x="$($w-60)" y="$($ht-8)" font-size="10">$mins min</text>
<polyline fill="none" stroke="#1f6feb" stroke-width="1.5" points="$poly"/></svg></div>
"@
}

$reportBase = "DOA_report_$($mode)_$stamp"
$htmlPath = Join-Path $OutDir "$reportBase.html"
$pdfPath  = Join-Path $OutDir "$reportBase.pdf"
try {
    $titles = [ordered]@{
        'hardware_inventory.csv' = 'Hardware inventory: every part with its exact model'
        'identity.txt' = 'Identity from firmware'; 'cpu.txt' = 'CPU'; 'gpu.txt' = 'GPU (Windows)'
        'nvidia-smi.txt' = 'GPU (nvidia-smi)'; 'ram.csv' = 'RAM modules'; 'disks.csv' = 'Disks'
        'pcie_links.csv' = 'PCIe links'; 'display_modes.txt' = 'Display modes listed by the panel'; 'battery.txt' = 'Battery'
        'sensors_stats.csv' = 'Sensor summary (min, median, max)'; 'event_errors.csv' = 'Event log errors'
        'minidumps.csv' = 'Crash dumps'; 'live_kernel_reports.csv' = 'Recovered hangs'; 'memtest_vulkan.log' = 'GPU memory test log'
        'usb_ports.csv' = 'USB ports'; 'secureboot_keys.txt' = 'Secure Boot keys'
        'bios_passwords.txt' = 'BIOS passwords'; 'hp_bios_settings.txt' = 'HP BIOS settings'; 'tpm.txt' = 'TPM'; 'deviceguard.txt' = 'Device Guard'
        'kernel_drivers.csv' = 'Running kernel drivers and their signatures'
        'bitlocker.txt' = 'BitLocker'; 'bcdedit.txt' = 'Boot entries'; 'dsregcmd.txt' = 'Company / Azure AD join'
        'local_users.txt' = 'Local users and admins'; 'network.csv' = 'Network adapters'
        'pnp_devices.csv' = 'Devices'; 'drivers.csv' = 'Drivers'; 'installed_software.csv' = 'Installed software'
        'startup_items.csv' = 'Startup items'; 'scheduled_tasks_nonms.csv' = 'Scheduled tasks (not Microsoft)'
        'kit_files.csv' = 'Kit files that produced this report (SHA-256)'
    }
    # Too big or not useful in a PDF; they stay in the folder
    $skipFiles = @('SUMMARY.txt', 'MANIFEST.sha256', 'transcript.txt', 'msinfo32.txt', 'battery-report.html',
                   'battery-report.xml', 'sensors.csv', "$reportBase.html", "$reportBase.pdf")

    $css = @'
@page { size: A4 landscape; margin: 12mm; }
body { font-family: Segoe UI, Arial, sans-serif; font-size: 10.5px; color: #111; }
h1 { font-size: 18px; margin: 0 0 4px; } h2 { font-size: 13px; margin: 18px 0 6px; border-bottom: 1px solid #ccc; }
table { border-collapse: collapse; width: 100%; table-layout: fixed; }
th, td { border: 1px solid #ccc; padding: 2px 4px; text-align: left; vertical-align: top; word-wrap: break-word; }
th { background: #f0f0f0; } pre { font-size: 9px; white-space: pre-wrap; word-wrap: break-word; background: #fafafa; border: 1px solid #ddd; padding: 4px; }
.muted { color: #555; } .ct { font-weight: bold; margin-top: 8px; }
.chart { break-inside: avoid; page-break-inside: avoid; }
.FAIL { background: #ffd7d7; } .WARN { background: #fff3c4; } .PASS { background: #dff5df; }
.box { padding: 6px; border: 1px solid #999; margin: 6px 0; font-size: 12px; }
* { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
'@
    $h = New-Object System.Text.StringBuilder
    [void]$h.Append("<!doctype html><html><head><meta charset=`"utf-8`"><title>$reportBase</title><style>$css</style></head><body>")
    [void]$h.Append("<h1>SecondTrust report ($mode)</h1>")
    [void]$h.Append("<div>Run at $(Enc (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')) on $(Enc $env:COMPUTERNAME). Profile: $(Enc $Expect.Name) ($(Enc $how)).</div>")
    [void]$h.Append("<div>Machine: $(Enc $machineId). Serial: $(Enc (Get-CimInstance Win32_BIOS).SerialNumber). Kit fingerprint: $(Enc $KitFingerprint).</div>")
    [void]$h.Append("<div class=`"box $(if ($fails) {'FAIL'} elseif ($warns) {'WARN'} else {'PASS'})`"><b>$fails FAIL, $warns WARN.</b> FAIL = DOA evidence. WARN = check by hand. The raw files and MANIFEST.sha256 are in the same folder.</div>")

    [void]$h.Append('<h2>Results</h2><table><tr><th style="width:6%">Result</th><th style="width:20%">Check</th><th>Detail</th></tr>')
    foreach ($line in $Summary) {
        if ($line -match '^(\S+)\s+(.*?) : (.*)$') { [void]$h.Append("<tr class=`"$($Matches[1])`"><td>$(Enc $Matches[1])</td><td>$(Enc $Matches[2])</td><td>$(Enc $Matches[3])</td></tr>") }
    }
    [void]$h.Append('</table>')

    if ($mode -eq 'full') {   # the spec comparison only happens in the full audit
        [void]$h.Append('<h2>Expected values for this profile</h2>')
        [void]$h.Append((ConvertTo-HtmlTable ($Expect.GetEnumerator() | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Item = $_.Name; Expected = (@($_.Value) -join '; ') } })))
    }

    $sensorCsv = Join-Path $OutDir 'sensors.csv'
    if (Test-Path $sensorCsv) {
        $sr = @(Import-Csv $sensorCsv)
        if ($sr.Count -gt 1) {
            [void]$h.Append('<h2>Sensor charts</h2>')
            $xs = @($sr | ForEach-Object { $_.Elapsed_s })
            foreach ($pair in @(@('GpuTemp_C', 'GPU temperature', 'C'), @('GpuPower_W', 'GPU power', 'W'), @('GpuClock_MHz', 'GPU clock', 'MHz'),
                                @('GpuUtil_pct', 'GPU load', '%'), @('CpuClock_MHz', 'CPU clock, all cores', 'MHz'), @('CpuUtil_pct', 'CPU load, measured against the base clock (turbo goes above 100)', '%'),
                                @('CpuPerfLimit_pct', 'CPU firmware limit', '%'), @('ThermalZoneMax_C', 'Board thermal zone', 'C'),
                                @('Battery_W', 'Battery power flow (negative = draining)', 'W'), @('BatteryPct', 'Battery charge', '%'))) {
                [void]$h.Append((New-SvgChart $pair[1] $xs @($sr | ForEach-Object { $_.($pair[0]) }) $pair[2]))
            }
        }
    }

    # Every collected file: known ones first, in a sensible order, then anything else
    $files = @(Get-ChildItem $OutDir -File | Where-Object { $skipFiles -notcontains $_.Name })
    $ordered = @($titles.Keys | ForEach-Object { $k = $_; $files | Where-Object { $_.Name -eq $k } }) +
               @($files | Where-Object { -not $titles.Contains($_.Name) } | Sort-Object Name)
    foreach ($f in $ordered) {
        $title = if ($titles.Contains($f.Name)) { $titles[$f.Name] } else { $f.Name }
        [void]$h.Append("<h2>$(Enc $title) <span class=`"muted`">($(Enc $f.Name))</span></h2>")
        if ($f.Extension -eq '.csv') { [void]$h.Append((ConvertTo-HtmlTable (Import-Csv $f.FullName))) }
        else {
            $text = Get-Content $f.FullName -Raw
            if ($text.Length -gt 60000) { $text = $text.Substring(0, 60000) + "`n... (cut, see the file)" }
            [void]$h.Append("<pre>$(Enc $text)</pre>")
        }
    }

    # Script errors: for whoever debugs the script later. Many are harmless (a missing optional tool).
    $errs = @($Error | Select-Object -First 60 | ForEach-Object {
        $file = if ($_.InvocationInfo.ScriptName) { Split-Path $_.InvocationInfo.ScriptName -Leaf } else { '' }
        [pscustomobject]@{ File = $file; Line = $_.InvocationInfo.ScriptLineNumber; Command = "$($_.InvocationInfo.MyCommand)"; Message = "$($_.Exception.Message)" }
    })
    [void]$h.Append('<h2>Script errors (for debugging; many are harmless)</h2>')
    [void]$h.Append((ConvertTo-HtmlTable $errs))
    [void]$h.Append("<h2>Files in this report folder</h2>")
    [void]$h.Append((ConvertTo-HtmlTable (Get-ChildItem $OutDir -File | Select-Object Name, Length, LastWriteTime)))
    [void]$h.Append('</body></html>')
    Set-Content -Path $htmlPath -Value $h.ToString() -Encoding UTF8

    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) {
        $edgeProfile = Join-Path $env:TEMP 'omen-audit-edge'
        $edgeArgs = @('--headless', '--disable-gpu', '--no-pdf-header-footer', '--print-to-pdf-no-header',
                      "--user-data-dir=`"$edgeProfile`"", "--print-to-pdf=`"$pdfPath`"", ([Uri]$htmlPath).AbsoluteUri)
        $p = Start-Process -FilePath $edge -ArgumentList $edgeArgs -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { } }
        # Edge can hand the job to a helper process and exit first: give the file time to appear
        for ($i = 0; $i -lt 30 -and -not (Test-Path $pdfPath); $i++) { Start-Sleep -Seconds 1 }
        # Edge's temporary profile is not needed after printing: leave nothing behind
        Start-Sleep -Seconds 2
        Remove-Item $edgeProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $pdfPath) { Write-Host "PDF report: $pdfPath" -ForegroundColor Green }
    else { Write-Host "PDF could not be made (Edge missing or failed). Open $htmlPath and print it to PDF." -ForegroundColor Yellow }
} catch {
    Write-Host "Report could not be built: $($_.Exception.Message). SUMMARY.txt and the raw files are still in $OutDir" -ForegroundColor Yellow
}

Get-ChildItem $OutDir -File | Where-Object { $_.Name -ne 'MANIFEST.sha256' } | ForEach-Object {
    $fh = Get-FileHash $_.FullName -Algorithm SHA256
    '{0}  {1}' -f $fh.Hash.ToLower(), $_.Name
} | Out-File (Join-Path $OutDir 'MANIFEST.sha256') -Encoding ascii

Write-Host "`n$fails FAIL, $warns WARN. Report: $OutDir" -ForegroundColor $(if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' })
Write-Host 'Upload the whole folder to Drive today. When you are done with the kit: .\omen-audit.ps1 -Cleanup'
