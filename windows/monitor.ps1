# Sensor log for -Monitor, -Stress and -GpuTest. Every -IntervalSec seconds it logs CPU and GPU clocks,
# load, temperatures, GPU power and slowdown reasons, the GPU's PCIe link, and the battery's power flow,
# to sensors.csv (row by row, so a crash keeps the log). -Stress adds the verified CPU and RAM load
# (stress.ps1), -GpuTest the verified video memory test (gpumemtest.ps1). At the end it judges the log.

$what = @()
if ($Stress)  { $what += 'verified CPU and RAM load' }
if ($GpuTest) { $what += 'GPU memory test' }
$title = if ($what) { "Load test ($($what -join ' + ')): $Minutes min" } else { "Sensor monitor: $Minutes min" }
Section "$title, a sample every $IntervalSec s"
if (-not $what) { Write-Host 'Start the stress test (OCCT, a game, a benchmark) now.' }
Write-Host 'Keep the laptop on its own charger, lid open. Press Q in this window to stop early.'
$start = Get-Date
$csv   = Join-Path $OutDir 'sensors.csv'

# CPU: Windows performance counters, built in. Real clock = base clock x "% Processor Performance".
# "% Performance Limit" under 100 means the firmware is holding the CPU back (heat or power).
$baseMHz = (Get-CimInstance Win32_Processor | Select-Object -First 1).MaxClockSpeed
$wanted = @(
    '\Processor Information(_Total)\% Processor Utility',
    '\Processor Information(_Total)\% Processor Performance',
    '\Processor Information(_Total)\% Performance Limit',
    '\Thermal Zone Information(*)\Temperature'
)
$counters = @($wanted | Where-Object {
    try { $null = Get-Counter -Counter $_ -MaxSamples 1 -ErrorAction Stop; $true } catch { $false }
})
$missing = @($wanted | Where-Object { $counters -notcontains $_ })
if ($missing.Count -gt 0) { Add-Result 'INFO' 'CPU counters missing' ($missing -join '; ') }

# GPU: nvidia-smi comes with the NVIDIA driver. Newer drivers renamed the slowdown-reason field.
# Laptops whose profile has no NVIDIA GPU (GpuVramGB = 0) skip the GPU sensors.
$smi = Find-NvidiaSmi
$gpuFields = $null
$gpuMaxLanes = $null
if ($NvidiaExpected -and $smi) {
    foreach ($reason in 'clocks_event_reasons.active', 'clocks_throttle_reasons.active') {
        $f = "temperature.gpu,power.draw,clocks.gr,clocks.mem,utilization.gpu,pstate,$reason,pcie.link.gen.current,pcie.link.width.current"
        $null = & $smi "--query-gpu=$f" --format=csv,noheader,nounits 2>&1
        if ($LASTEXITCODE -eq 0) { $gpuFields = $f; break }
    }
    $gpuMaxLanes = ConvertTo-Num "$(& $smi --query-gpu=pcie.link.width.max --format=csv,noheader,nounits 2>$null | Select-Object -First 1)"
}
if (-not $NvidiaExpected) { Add-Result 'INFO' 'GPU sensors' 'this laptop has no NVIDIA GPU: GPU sensors skipped' }
elseif (-not $gpuFields) { Add-Result 'WARN' 'GPU sensors' 'nvidia-smi not available. Install the NVIDIA driver, then rerun' }

# Battery power flow (root\wmi BatteryStatus, mW): positive = charging, negative = draining
function Get-BatteryFlow {
    $s = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $s) { return $null }
    $w = if ($s.Discharging -and $s.DischargeRate) { -[double]$s.DischargeRate / 1000 } elseif ($s.Charging -and $s.ChargeRate) { [double]$s.ChargeRate / 1000 } else { 0 }
    return [math]::Round($w, 1)
}

$cols = 'Time', 'Elapsed_s', 'OnAC', 'BatteryPct', 'Battery_W', 'CpuUtil_pct', 'CpuClock_MHz', 'CpuPerfLimit_pct', 'ThermalZoneMax_C',
        'GpuTemp_C', 'GpuPower_W', 'GpuClock_MHz', 'GpuMemClock_MHz', 'GpuUtil_pct', 'GpuPState', 'GpuLimitReasons', 'GpuPcieGen', 'GpuPcieLanes',
        'VerifyCpuErrors', 'VerifyMemErrors', 'GpuMemErrors'
Set-Content -Path $csv -Value ($cols -join ',') -Encoding ascii
$rows = New-Object System.Collections.Generic.List[object]

# Start the load after the header, so the first samples show the idle state for a moment
$gpuRun = $null
if ($Stress) { Start-VerifiedLoad -MemoryPct $StressMemoryPct }
if ($GpuTest) { $gpuRun = Start-GpuMemTest }
$gpuLog = $null

$end = $start.AddMinutes($Minutes)
$nextPrint = $start

# Keep Windows from sleeping while the monitor runs (seen on the ASUS: a 60 min run slept after 25 min).
# Closing the lid or pressing the power button still sleeps; the gap check below reports that.
try {
    if (-not ('MonitorAwake' -as [type])) {
        Add-Type -Namespace '' -Name MonitorAwake -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
    }
    [void][MonitorAwake]::SetThreadExecutionState([uint32]2147483651)   # 0x80000003: continuous + system + display
} catch { }
$gaps = New-Object System.Collections.Generic.List[object]
$prevTick = $null
$stop = $false

try {
    while ((Get-Date) -lt $end) {
        $tick = Get-Date
        # A long pause between samples means the laptop slept or the system stopped responding
        if ($prevTick -and ($tick - $prevTick).TotalSeconds -gt [math]::Max(30, 10 * $IntervalSec)) {
            $gaps.Add([pscustomobject]@{ From = $prevTick; To = $tick; Minutes = [math]::Round(($tick - $prevTick).TotalMinutes, 1) })
        }
        $prevTick = $tick
        $r = [ordered]@{}
        foreach ($c in $cols) { $r[$c] = '' }
        $r.Time = $tick.ToString('yyyy-MM-dd HH:mm:ss')
        $r.Elapsed_s = [int](($tick - $start).TotalSeconds)

        # BatteryStatus 1 = discharging (on battery). Anything else = on the charger.
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bat) { $r.OnAC = [int]($bat.BatteryStatus -ne 1); $r.BatteryPct = $bat.EstimatedChargeRemaining }
        $flow = Get-BatteryFlow
        if ($null -ne $flow) { $r.Battery_W = $flow }

        if ($counters.Count -gt 0) {
            $samples = (Get-Counter -Counter $counters -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples
            foreach ($c in $samples) {
                if ($c.Path -like '*% processor utility') { $r.CpuUtil_pct = [math]::Round($c.CookedValue, 1) }
                elseif ($c.Path -like '*% processor performance') { $r.CpuClock_MHz = [math]::Round($baseMHz * $c.CookedValue / 100) }
                elseif ($c.Path -like '*% performance limit') { $r.CpuPerfLimit_pct = [math]::Round($c.CookedValue, 1) }
            }
            # Thermal zones report Kelvin
            $tz = @($samples | Where-Object { $_.Path -like '*thermal zone information*' -and $_.CookedValue -gt 0 } |
                ForEach-Object { $_.CookedValue - 273.15 })
            if ($tz.Count -gt 0) { $r.ThermalZoneMax_C = [math]::Round(($tz | Measure-Object -Maximum).Maximum, 1) }
        }

        if ($gpuFields) {
            $out  = @(& $smi "--query-gpu=$gpuFields" --format=csv,noheader,nounits 2>$null)
            $smiOk = ($LASTEXITCODE -eq 0)
            $v = @("$($out | Select-Object -First 1)" -split ',\s*')
            if ($smiOk -and $v.Count -ge 9) {
                $r.GpuTemp_C       = ConvertTo-Num $v[0]
                $r.GpuPower_W      = ConvertTo-Num $v[1]
                $r.GpuClock_MHz    = ConvertTo-Num $v[2]
                $r.GpuMemClock_MHz = ConvertTo-Num $v[3]
                $r.GpuUtil_pct     = ConvertTo-Num $v[4]
                $r.GpuPState       = $v[5].Trim()
                $r.GpuLimitReasons = $v[6].Trim()
                $r.GpuPcieGen      = ConvertTo-Num $v[7]
                $r.GpuPcieLanes    = ConvertTo-Num $v[8]
            }
        }

        if ($Stress) { $vs = Get-VerifiedLoadStatus; $r.VerifyCpuErrors = $vs.CpuErrors; $r.VerifyMemErrors = $vs.MemErrors }
        if ($gpuRun -and $tick -ge $nextPrint) { $gpuLog = Read-GpuMemTestLog $gpuRun }
        if ($gpuLog) { $r.GpuMemErrors = $gpuLog.Errors }

        # Written row by row, so the log survives even if the laptop crashes mid-test
        $rows.Add([pscustomobject]$r)
        Add-Content -Path $csv -Value (($cols | ForEach-Object { "$($r[$_])" }) -join ',') -Encoding ascii

        if ($tick -ge $nextPrint) {
            $line = '{0,5}s  CPU {1} MHz, load {2}%, limit {3}%, zone {4} C' -f
                $r.Elapsed_s, $r.CpuClock_MHz, $r.CpuUtil_pct, $r.CpuPerfLimit_pct, $r.ThermalZoneMax_C
            if ($gpuFields) {
                $line += '  |  GPU {0} C, {1} W, {2} MHz, load {3}%' -f $r.GpuTemp_C, $r.GpuPower_W, $r.GpuClock_MHz, $r.GpuUtil_pct
            }
            if ($Stress) { $line += "  |  wrong results: CPU $($vs.CpuErrors), RAM $($vs.MemErrors) (RAM passes $($vs.MemPasses))" }
            if ($gpuLog) { $line += "  |  VRAM errors $($gpuLog.Errors), $($gpuLog.CheckedGB) GB checked" }
            Write-Host $line
            $nextPrint = $tick.AddSeconds(30)
        }

        try { while ([Console]::KeyAvailable) { if ([Console]::ReadKey($true).Key -eq 'Q') { $stop = $true } } } catch { }
        if ($stop) { Write-Host 'Stopped early.'; break }
        $wait = $IntervalSec - ((Get-Date) - $tick).TotalSeconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
    }
} finally {
    # Ctrl+C lands here too: never leave the load running
    if ($Stress) { try { [StressEngine]::Stop() } catch { } }
    if ($gpuRun) {
        $gpuExitedEarly = $gpuRun.Process.HasExited   # it runs until stopped, so exiting by itself means it failed
        if (-not $gpuExitedEarly) { & taskkill.exe /PID $gpuRun.Process.Id /T /F 2>&1 | Out-Null }
    }
    try { [void][MonitorAwake]::SetThreadExecutionState([uint32]2147483648) } catch { }   # 0x80000000: sleep allowed again
}

# A pause after the last sample counts too: the loop ends on waking when the time is already up
# (seen on the ASUS: samples stopped at 25 min, the laptop slept 47 min, the run ended on wake)
if (-not $stop -and $prevTick -and ((Get-Date) - $prevTick).TotalSeconds -gt [math]::Max(30, 10 * $IntervalSec)) {
    $now = Get-Date
    $gaps.Add([pscustomobject]@{ From = $prevTick; To = $now; Minutes = [math]::Round(($now - $prevTick).TotalMinutes, 1) })
}

# ---------- what the log says ----------
if ($Stress) { Stop-VerifiedLoad }
if ($gpuRun) { Stop-GpuMemTest $gpuRun $gpuExitedEarly }

$n = $rows.Count
$covered = [math]::Round($n * $IntervalSec / 60, 1)
Add-Result 'INFO' 'Samples' "$n over $([math]::Round(((Get-Date) - $start).TotalMinutes, 1)) min (about $covered min logged), saved sensors.csv"
foreach ($g in $gaps) {
    # Kernel-Power 42 = entering sleep, 107 = resumed from sleep
    $slept = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 42, 107; StartTime = $g.From.AddSeconds(-5); EndTime = $g.To.AddSeconds(5) } -ErrorAction SilentlyContinue)
    $when = "$($g.From.ToString('HH:mm:ss')) to $($g.To.ToString('HH:mm:ss'))"
    if ($slept.Count -gt 0) {
        Add-Result 'WARN' 'Monitor gap' "logging paused $($g.Minutes) min ($when): the laptop slept (lid closed or sleep button). Those minutes are not covered; run again"
    } else {
        Add-Result 'WARN' 'Monitor gap' "logging paused $($g.Minutes) min ($when) with no sleep in the event log: the system may have stopped responding. Check event_errors.csv and run again"
    }
}
$late = @($rows | Select-Object -Skip ([int][math]::Floor($n / 2)))   # second half = sustained behaviour

$onBat = @($rows | Where-Object { "$($_.OnAC)" -eq '0' })
if ($onBat.Count -gt 0) { Add-Result 'WARN' 'Power source' "$($onBat.Count) of $n samples on battery. Stress tests must run on the laptop's own charger" }

# On the charger yet the battery drains: the load needs more than the charger gives. Brief dips at full
# CPU and GPU load happen on some gaming laptops; a steady drain means a weak, wrong or failing charger.
$drain = @($rows | Where-Object { "$($_.OnAC)" -eq '1' -and "$($_.Battery_W)" -ne '' -and [double]$_.Battery_W -lt -1 })
$onAc = @($rows | Where-Object { "$($_.OnAC)" -eq '1' }).Count
if ($drain.Count -gt 0 -and $onAc -gt 0) {
    $worst = ($drain | ForEach-Object { [double]$_.Battery_W } | Measure-Object -Minimum).Minimum
    $pct = [math]::Round(100 * $drain.Count / $onAc)
    $lvl = if ($pct -ge 20) { 'WARN' } else { 'INFO' }
    Add-Result $lvl 'Charger keeps up' "battery drained in $($drain.Count) of $onAc samples on the charger ($pct%), up to $([math]::Abs($worst)) W. Use the original charger; a steady drain at full load means it cannot supply enough"
} elseif ($onAc -gt 0) {
    Add-Result 'PASS' 'Charger keeps up' 'the battery never drained while on the charger'
}

if ($gpuFields) {
    $noGpu = @($rows | Where-Object { "$($_.GpuTemp_C)" -eq '' })
    if ($noGpu.Count -gt 0) { Add-Result 'FAIL' 'GPU readings' "$($noGpu.Count) of $n samples had no GPU reading. Possible GPU dropout: check Device Manager and event_errors.csv" }
    else { Add-Result 'PASS' 'GPU readings' "GPU answered in all $n samples" }

    $temps = @($rows | Where-Object { "$($_.GpuTemp_C)" -ne '' } | ForEach-Object { [double]$_.GpuTemp_C })
    if ($temps.Count -gt 0) {
        $gmax = ($temps | Measure-Object -Maximum).Maximum
        if ($gmax -ge $Expect.GpuTempWarn) { Add-Result 'WARN' 'GPU max temperature' "$gmax C (warn at $($Expect.GpuTempWarn) C)" }
        else { Add-Result 'PASS' 'GPU max temperature' "$gmax C" }
    }

    $loaded = @($late | Where-Object { "$($_.GpuUtil_pct)" -ne '' -and [double]$_.GpuUtil_pct -ge 90 })
    if ($loaded.Count -ge 5) {
        $p = Get-Median ($loaded | ForEach-Object { $_.GpuPower_W })
        $c = Get-Median ($loaded | ForEach-Object { $_.GpuClock_MHz })
        $note = if ($Expect.GpuSustainedNote) { " ($($Expect.GpuSustainedNote))" } else { '' }
        if ($Expect.GpuMinWatts -le 0) {
            Add-Result 'INFO' 'GPU sustained power' "median $p W at $c MHz under full load (no expected value in this profile)"
        } elseif ($null -ne $p -and $p -lt $Expect.GpuMinWatts) {
            Add-Result 'WARN' 'GPU sustained power' "median $p W at $c MHz under full load, expected at least $($Expect.GpuMinWatts) W$note. Check the performance mode and the original charger; if both are right, suspect cooling"
        } else {
            Add-Result 'PASS' 'GPU sustained power' "median $p W at $c MHz under full load$note"
        }
        # The link drops to fewer lanes only with a seating or board fault; under load it should be full width
        $lanes = Get-Median ($loaded | ForEach-Object { $_.GpuPcieLanes })
        if ($null -ne $lanes -and $gpuMaxLanes) {
            if ($lanes -lt $gpuMaxLanes) { Add-Result 'WARN' 'GPU PCIe link under load' "x$lanes, the GPU supports x$gpuMaxLanes. A board or connection fault can cause this" }
            else { Add-Result 'PASS' 'GPU PCIe link under load' "x$lanes (full width), Gen $(Get-Median ($loaded | ForEach-Object { $_.GpuPcieGen }))" }
        }
    } else {
        $hint = if ($GpuTest) { 'the memory test loads the GPU memory more than its cores; for sustained GPU power, run a game or OCCT 3D with -Monitor' } else { 'Run a GPU test (OCCT 3D, a game) during the monitor' }
        Add-Result 'INFO' 'GPU sustained power' "GPU was not under full load in the second half. $hint"
    }

    # Hardware slowdown bits: 0x8 HW slowdown, 0x40 HW thermal slowdown, 0x80 HW power brake.
    # 0x4 (software power cap) is normal under load and is ignored.
    $hwSlow = @($rows | Where-Object {
        $x = "$($_.GpuLimitReasons)"
        ($x -match '^0x[0-9a-fA-F]+$') -and (([Convert]::ToUInt64($x.Substring(2), 16) -band 0xC8) -ne 0)
    })
    if ($hwSlow.Count -gt 0) { Add-Result 'WARN' 'GPU hardware slowdown' "$($hwSlow.Count) of $n samples. Hardware thermal or power brake: a cooling or charger problem, record it" }
    else { Add-Result 'PASS' 'GPU hardware slowdown' 'none' }
}

$cpuLoaded = @($late | Where-Object { "$($_.CpuUtil_pct)" -ne '' -and [double]$_.CpuUtil_pct -ge 90 })
if ($cpuLoaded.Count -ge 5) {
    $clk = Get-Median ($cpuLoaded | ForEach-Object { $_.CpuClock_MHz })
    $lim = Get-Median ($cpuLoaded | ForEach-Object { $_.CpuPerfLimit_pct })
    $cnote = if ($Expect.CpuSustainedNote) { ". $($Expect.CpuSustainedNote)" } else { '' }
    Add-Result 'INFO' 'CPU sustained clock' "median $clk MHz averaged across all cores under full load, firmware limit median $lim% (100 = not limited)$cnote"
} else {
    Add-Result 'INFO' 'CPU sustained clock' 'CPU was not under full load in the second half'
}

$zones = @($rows | Where-Object { "$($_.ThermalZoneMax_C)" -ne '' } | ForEach-Object { [double]$_.ThermalZoneMax_C })
if ($zones.Count -gt 0) {
    $zmax = ($zones | Measure-Object -Maximum).Maximum
    if ($zmax -ge 100) { Add-Result 'WARN' 'Thermal zone max' "$zmax C. The CPU throttles at 100 C" }
    else { Add-Result 'INFO' 'Thermal zone max' "$zmax C (board sensor, not the exact CPU core temperature: HWiNFO shows that)" }
}

# Min / median / max per sensor, for the report
$skip = 'Time', 'Elapsed_s', 'GpuPState', 'GpuLimitReasons'
$stats = foreach ($col in ($cols | Where-Object { $skip -notcontains $_ })) {
    $vals = @($rows | ForEach-Object { $_.$col } | Where-Object { "$_" -ne '' } | ForEach-Object { [double]$_ })
    if ($vals.Count -gt 0) {
        $m = $vals | Measure-Object -Minimum -Maximum
        [pscustomobject]@{ Sensor = $col; Samples = $vals.Count; Min = $m.Minimum; Median = (Get-Median $vals); Max = $m.Maximum }
    }
}
@($stats) | Export-Csv (Join-Path $OutDir 'sensors_stats.csv') -NoTypeInformation

# Anything that broke while the test ran
Test-EventLogs -Since $start
