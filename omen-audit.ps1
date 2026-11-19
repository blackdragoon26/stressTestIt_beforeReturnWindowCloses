<#
.SYNOPSIS
  OMEN Transcend 16 (16-u0005TX / 834T6PA) DOA audit.

.DESCRIPTION
  Full mode (default): identity, genuineness, health, security, drivers, event logs.
  -Quick mode: event-log check only (WHEA, unexpected shutdowns, bugchecks, GPU driver
  resets, disk errors) since the last quick run. Use it every evening during the soak.
  -Monitor mode: sensor log for a stress test. Run it in a second window while OCCT or a
  game runs. Logs CPU and GPU clocks, load, temperatures and GPU power to sensors.csv
  every few seconds, then flags GPU dropouts, hardware slowdowns, low sustained GPU power,
  running on battery, and any new errors from the event log during the run.
  Fan speed and CPU package power are not exposed by Windows itself: use HWiNFO for those.

  Every run writes a timestamped folder under .\reports with a SUMMARY.txt and a
  SHA256 manifest of all files, so the evidence can be shown to be unchanged later.

.EXAMPLE
  Right-click PowerShell > Run as administrator, then:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\omen-audit.ps1
    .\omen-audit.ps1 -Quick
    .\omen-audit.ps1 -Monitor -Minutes 60
#>
[CmdletBinding()]
param(
    [switch]$Quick,
    [switch]$Monitor,
    [int]$Minutes = 60,         # -Monitor: how long to log
    [int]$IntervalSec = 2,      # -Monitor: seconds between samples
    [int]$GpuTempWarn = 87,     # -Monitor: WARN at or above this GPU temperature (C)
    [int]$GpuMinWatts = 95,     # -Monitor: WARN if sustained GPU power under full load is below this
                                #   (LaptopMedia measured about 109 W after 30 min on this model)
    [string]$OutRoot = (Join-Path $PSScriptRoot 'reports'),
    [int]$EventDays = 30,
    # Expected values. Defaults are the HP OMEN Transcend 16-u0005TX; override for other machines.
    [string]$ExpectProductNumber = '834T6PA',
    [string]$ExpectModel = 'Transcend',
    [string]$ExpectBoardId = '8BB3',
    [string]$ExpectCpu = '13700HX',
    [int]$ExpectCores = 16,
    [int]$ExpectThreads = 24,
    [string]$ExpectGpu = 'RTX 4070',
    [int]$ExpectRamModules = 2,
    [int]$ExpectRamGB = 16,
    # Who should own the Secure Boot Platform Key (regex). Example override: -ExpectPk 'ASUS'
    [string]$ExpectPk = 'HP|Hewlett'
)

$ErrorActionPreference = 'Continue'

# ---------- expected values for this exact unit ----------
$Expect = @{
    ProductNumber = $ExpectProductNumber   # from the seller sheet and box
    Model         = $ExpectModel
    BoardId       = $ExpectBoardId        # HP OMEN Transcend 16-u0xxx board ID (per arfelious/omen-fan-control)
    CpuName       = $ExpectCpu
    CpuCores      = $ExpectCores           # 13700HX = 8P + 8E. The plain 13700H has 14 cores / 20 threads.
    CpuThreads    = $ExpectThreads
    GpuName       = $ExpectGpu
    RamModules    = $ExpectRamModules
    RamTotalGB    = $ExpectRamGB
    BatteryHealthMinPct = 95
    BatteryCyclesMax    = 10
    SsdHoursWarn        = 100
}

# ---------- setup ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Run this script from an administrator PowerShell.' -ForegroundColor Red
    exit 1
}

$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
if ($Quick -and $Monitor) {
    Write-Host 'Use -Quick or -Monitor, not both.' -ForegroundColor Red
    exit 1
}
$mode   = if ($Quick) { 'quick' } elseif ($Monitor) { 'monitor' } else { 'full' }
$OutDir = Join-Path $OutRoot "$($env:COMPUTERNAME)_$($mode)_$stamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Start-Transcript -Path (Join-Path $OutDir 'transcript.txt') | Out-Null

$Summary = New-Object System.Collections.Generic.List[string]

function Add-Result {
    param([string]$Level, [string]$Check, [string]$Detail)
    $line = '{0,-5} {1} : {2}' -f $Level, $Check, $Detail
    $Summary.Add($line)
    $color = switch ($Level) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
}

function Save-Text {
    param([string]$Name, $Content)
    $Content | Out-File -FilePath (Join-Path $OutDir $Name) -Encoding utf8 -Width 400
}

function Section { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

# ---------- event log check (both modes) ----------
function Test-EventLogs {
    param([datetime]$Since)

    $queries = @(
        @{ Name = 'WHEA hardware errors'; Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $Since } },
        @{ Name = 'Unexpected shutdowns (Kernel-Power 41)'; Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $Since } },
        @{ Name = 'Bugchecks / BSOD (1001)'; Filter = @{ LogName = 'System'; Id = 1001; StartTime = $Since } },
        @{ Name = 'NVIDIA driver errors (nvlddmkm)'; Filter = @{ LogName = 'System'; ProviderName = 'nvlddmkm'; StartTime = $Since } },
        @{ Name = 'Display driver resets (4101)'; Filter = @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $Since } },
        @{ Name = 'Disk / NVMe errors'; Filter = @{ LogName = 'System'; ProviderName = @('disk', 'stornvme', 'storahci'); Level = @(1, 2); StartTime = $Since } }
    )

    $all = @()
    foreach ($q in $queries) {
        $events = @(Get-WinEvent -FilterHashtable $q.Filter -ErrorAction SilentlyContinue)
        if ($q.Name -like 'Bugchecks*') {
            $events = @($events | Where-Object { $_.ProviderName -match 'BugCheck|WER-SystemErrorReporting' })
        }
        if ($events.Count -eq 0) {
            Add-Result 'PASS' $q.Name "0 since $($Since.ToString('yyyy-MM-dd HH:mm'))"
        } else {
            Add-Result 'FAIL' $q.Name "$($events.Count) event(s) since $($Since.ToString('yyyy-MM-dd HH:mm'))"
            $all += $events | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName,
                @{ n = 'Message'; e = { ($_.Message -split "`r?`n")[0] } }
        }
    }
    if ($all.Count -gt 0) {
        $all | Sort-Object TimeCreated | Export-Csv (Join-Path $OutDir 'event_errors.csv') -NoTypeInformation
    }

    $dumps = @(Get-ChildItem 'C:\Windows\Minidump' -Filter *.dmp -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since })
    if ($dumps.Count -gt 0) {
        Add-Result 'FAIL' 'Crash dumps' "$($dumps.Count) new minidump(s) in C:\Windows\Minidump"
        $dumps | Select-Object Name, LastWriteTime, Length | Export-Csv (Join-Path $OutDir 'minidumps.csv') -NoTypeInformation
    } else {
        Add-Result 'PASS' 'Crash dumps' 'none new'
    }

    $badDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    if ($badDevices.Count -gt 0) {
        Add-Result 'FAIL' 'Devices with errors' (($badDevices | ForEach-Object { "$($_.Name) [code $($_.ConfigManagerErrorCode)]" }) -join '; ')
    } else {
        Add-Result 'PASS' 'Devices with errors' 'none'
    }

    $gpu = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match $Expect.GpuName })
    if ($gpu.Count -gt 0) { Add-Result 'PASS' 'dGPU present' $gpu[0].Name }
    else { Add-Result 'FAIL' 'dGPU present' "$($Expect.GpuName) not listed. Possible GPU dropout" }
}

# =====================================================================
if ($Quick) {
    Section 'Quick soak check'
    $marker = Join-Path $OutRoot 'last_quick_run.txt'
    $since  = (Get-Date).AddHours(-24)
    if (Test-Path $marker) {
        try { $since = [datetime]::Parse((Get-Content $marker -Raw).Trim()) } catch { }
    }
    Test-EventLogs -Since $since
    (Get-Date).ToString('o') | Out-File $marker -Encoding ascii
}
elseif ($Monitor) {
    Section "Sensor monitor: $Minutes min, a sample every $IntervalSec s"
    Write-Host 'Start the stress test (OCCT, a game, a benchmark) now. Press Q in this window to stop early.'
    $start = Get-Date
    $csv   = Join-Path $OutDir 'sensors.csv'

    function ConvertTo-Num([string]$s) {
        if ($null -eq $s) { return $null }
        $d = 0.0
        if ([double]::TryParse($s.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
        return $null
    }
    function Get-Median($vals) {
        $s = @($vals | Where-Object { "$_" -ne '' } | ForEach-Object { [double]$_ } | Sort-Object)
        if ($s.Count -eq 0) { return $null }
        return $s[[int][math]::Floor(($s.Count - 1) / 2)]
    }

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
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi -and (Test-Path 'C:\Windows\System32\nvidia-smi.exe')) { $smi = 'C:\Windows\System32\nvidia-smi.exe' }
    $gpuFields = $null
    if ($smi) {
        foreach ($reason in 'clocks_event_reasons.active', 'clocks_throttle_reasons.active') {
            $f = "temperature.gpu,power.draw,clocks.gr,clocks.mem,utilization.gpu,pstate,$reason"
            $null = & $smi "--query-gpu=$f" --format=csv,noheader,nounits 2>&1
            if ($LASTEXITCODE -eq 0) { $gpuFields = $f; break }
        }
    }
    if (-not $gpuFields) { Add-Result 'INFO' 'GPU sensors' 'nvidia-smi not available. Install the NVIDIA driver, then rerun' }

    $cols = 'Time', 'Elapsed_s', 'OnAC', 'CpuUtil_pct', 'CpuClock_MHz', 'CpuPerfLimit_pct', 'ThermalZoneMax_C',
            'GpuTemp_C', 'GpuPower_W', 'GpuClock_MHz', 'GpuMemClock_MHz', 'GpuUtil_pct', 'GpuPState', 'GpuLimitReasons'
    Set-Content -Path $csv -Value ($cols -join ',') -Encoding ascii
    $rows = New-Object System.Collections.Generic.List[object]
    $end = $start.AddMinutes($Minutes)
    $nextPrint = $start

    while ((Get-Date) -lt $end) {
        $tick = Get-Date
        $r = [ordered]@{}
        foreach ($c in $cols) { $r[$c] = '' }
        $r.Time = $tick.ToString('yyyy-MM-dd HH:mm:ss')
        $r.Elapsed_s = [int](($tick - $start).TotalSeconds)

        # BatteryStatus 1 = discharging (on battery). Anything else = on the charger.
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bat) { $r.OnAC = [int]($bat.BatteryStatus -ne 1) }

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
            if ($smiOk -and $v.Count -ge 7) {
                $r.GpuTemp_C       = ConvertTo-Num $v[0]
                $r.GpuPower_W      = ConvertTo-Num $v[1]
                $r.GpuClock_MHz    = ConvertTo-Num $v[2]
                $r.GpuMemClock_MHz = ConvertTo-Num $v[3]
                $r.GpuUtil_pct     = ConvertTo-Num $v[4]
                $r.GpuPState       = $v[5].Trim()
                $r.GpuLimitReasons = $v[6].Trim()
            }
        }

        # Written row by row, so the log survives even if the laptop crashes mid-test
        $rows.Add([pscustomobject]$r)
        Add-Content -Path $csv -Value (($cols | ForEach-Object { "$($r[$_])" }) -join ',') -Encoding ascii

        if ($tick -ge $nextPrint) {
            Write-Host ('{0,5}s  CPU {1} MHz, load {2}%, limit {3}%, zone {4} C  |  GPU {5} C, {6} W, {7} MHz, load {8}%' -f
                $r.Elapsed_s, $r.CpuClock_MHz, $r.CpuUtil_pct, $r.CpuPerfLimit_pct, $r.ThermalZoneMax_C,
                $r.GpuTemp_C, $r.GpuPower_W, $r.GpuClock_MHz, $r.GpuUtil_pct)
            $nextPrint = $tick.AddSeconds(30)
        }

        $stop = $false
        try { while ([Console]::KeyAvailable) { if ([Console]::ReadKey($true).Key -eq 'Q') { $stop = $true } } } catch { }
        if ($stop) { Write-Host 'Stopped early.'; break }
        $wait = $IntervalSec - ((Get-Date) - $tick).TotalSeconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
    }

    # ---------- what the log says ----------
    $n = $rows.Count
    Add-Result 'INFO' 'Samples' "$n over $([math]::Round(((Get-Date) - $start).TotalMinutes, 1)) min, saved sensors.csv"
    $late = @($rows | Select-Object -Skip ([int][math]::Floor($n / 2)))   # second half = sustained behaviour

    $onBat = @($rows | Where-Object { "$($_.OnAC)" -eq '0' })
    if ($onBat.Count -gt 0) { Add-Result 'WARN' 'Power source' "$($onBat.Count) of $n samples on battery. Stress tests must run on the HP charger" }

    if ($gpuFields) {
        $noGpu = @($rows | Where-Object { "$($_.GpuTemp_C)" -eq '' })
        if ($noGpu.Count -gt 0) { Add-Result 'FAIL' 'GPU readings' "$($noGpu.Count) of $n samples had no GPU reading. Possible GPU dropout: check Device Manager and event_errors.csv" }
        else { Add-Result 'PASS' 'GPU readings' "GPU answered in all $n samples" }

        $temps = @($rows | Where-Object { "$($_.GpuTemp_C)" -ne '' } | ForEach-Object { [double]$_.GpuTemp_C })
        if ($temps.Count -gt 0) {
            $gmax = ($temps | Measure-Object -Maximum).Maximum
            if ($gmax -ge $GpuTempWarn) { Add-Result 'WARN' 'GPU max temperature' "$gmax C (warn at $GpuTempWarn C)" }
            else { Add-Result 'PASS' 'GPU max temperature' "$gmax C" }
        }

        $loaded = @($late | Where-Object { "$($_.GpuUtil_pct)" -ne '' -and [double]$_.GpuUtil_pct -ge 90 })
        if ($loaded.Count -ge 5) {
            $p = Get-Median ($loaded | ForEach-Object { $_.GpuPower_W })
            $c = Get-Median ($loaded | ForEach-Object { $_.GpuClock_MHz })
            if ($null -ne $p -and $p -lt $GpuMinWatts) {
                Add-Result 'WARN' 'GPU sustained power' "median $p W at $c MHz under full load, expected at least $GpuMinWatts W. Check Performance mode and the HP charger; if both are right, suspect cooling"
            } else {
                Add-Result 'PASS' 'GPU sustained power' "median $p W at $c MHz under full load (LaptopMedia: about 109 W, 2280 MHz after 30 min)"
            }
        } else {
            Add-Result 'INFO' 'GPU sustained power' 'GPU was not under full load in the second half. Run a GPU test (OCCT 3D, a game) during the monitor'
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
        Add-Result 'INFO' 'CPU sustained clock' "median $clk MHz across all cores under full load (E-cores included, so below the P-core figure of about 3000 MHz), firmware limit median $lim% (100 = not limited)"
    } else {
        Add-Result 'INFO' 'CPU sustained clock' 'CPU was not under full load in the second half'
    }

    $zones = @($rows | Where-Object { "$($_.ThermalZoneMax_C)" -ne '' } | ForEach-Object { [double]$_.ThermalZoneMax_C })
    if ($zones.Count -gt 0) {
        $zmax = ($zones | Measure-Object -Maximum).Maximum
        if ($zmax -ge 100) { Add-Result 'WARN' 'Thermal zone max' "$zmax C. The CPU throttles at 100 C" }
        else { Add-Result 'INFO' 'Thermal zone max' "$zmax C (board sensor, not the exact CPU core temperature: HWiNFO shows that)" }
    }

    # Anything that broke while the test ran
    Test-EventLogs -Since $start
}
else {
    # ---------- 1. identity ----------
    Section 'Identity'
    $cs   = Get-CimInstance Win32_ComputerSystem
    $csp  = Get-CimInstance Win32_ComputerSystemProduct
    $bios = Get-CimInstance Win32_BIOS
    $bb   = Get-CimInstance Win32_BaseBoard
    $identity = [ordered]@{
        Manufacturer     = $cs.Manufacturer
        Model            = $cs.Model
        SystemSKU        = $cs.SystemSKUNumber
        SerialNumber     = $bios.SerialNumber
        ProductName      = $csp.Name
        UUID             = $csp.UUID
        BaseBoardProduct = $bb.Product
        BaseBoardSerial  = $bb.SerialNumber
        BIOSVersion      = $bios.SMBIOSBIOSVersion
        BIOSReleaseDate  = $bios.ReleaseDate
    }
    Save-Text 'identity.txt' ($identity.GetEnumerator() | ForEach-Object { '{0,-18} {1}' -f $_.Key, $_.Value })
    Add-Result 'INFO' 'Serial number' "$($bios.SerialNumber)  <- must match box, bottom sticker and invoice"
    Add-Result 'INFO' 'BIOS version' "$($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"

    if ($cs.SystemSKUNumber -match $Expect.ProductNumber) { Add-Result 'PASS' 'Product number' $cs.SystemSKUNumber }
    else { Add-Result 'FAIL' 'Product number' "got '$($cs.SystemSKUNumber)', expected $($Expect.ProductNumber)" }

    if ($cs.Model -match $Expect.Model) { Add-Result 'PASS' 'Model' $cs.Model }
    else { Add-Result 'FAIL' 'Model' "got '$($cs.Model)'" }

    if ($bb.Product -eq $Expect.BoardId) { Add-Result 'PASS' 'Board ID' $bb.Product }
    else { Add-Result 'WARN' 'Board ID' "got '$($bb.Product)', expected $($Expect.BoardId). Ask HP or the seller if this differs" }

    if ($bios.SerialNumber -and $bb.SerialNumber -and ($bb.SerialNumber -notmatch [regex]::Escape($bios.SerialNumber))) {
        Add-Result 'INFO' 'Board serial' "board serial '$($bb.SerialNumber)' differs from system serial (often normal on HP, record it)"
    }

    # ---------- 2. CPU ----------
    Section 'CPU'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Save-Text 'cpu.txt' ($cpu | Format-List Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize, L3CacheSize, ProcessorId | Out-String)
    if ($cpu.Name -match $Expect.CpuName) { Add-Result 'PASS' 'CPU model' $cpu.Name.Trim() }
    else { Add-Result 'FAIL' 'CPU model' "got '$($cpu.Name.Trim())'" }
    if ($cpu.NumberOfCores -eq $Expect.CpuCores -and $cpu.NumberOfLogicalProcessors -eq $Expect.CpuThreads) {
        Add-Result 'PASS' 'CPU cores/threads' "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T"
    } else {
        Add-Result 'FAIL' 'CPU cores/threads' "got $($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T, expected $($Expect.CpuCores)C / $($Expect.CpuThreads)T"
    }

    # ---------- 3. GPU ----------
    Section 'GPU'
    $gpus = Get-CimInstance Win32_VideoController
    Save-Text 'gpu.txt' ($gpus | Format-List Name, DriverVersion, DriverDate, AdapterRAM, VideoProcessor, PNPDeviceID | Out-String)
    $nv = $gpus | Where-Object { $_.Name -match $Expect.GpuName }
    if ($nv) { Add-Result 'PASS' 'GPU model' $nv[0].Name } else { Add-Result 'FAIL' 'GPU model' (($gpus.Name) -join ', ') }

    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi -and (Test-Path 'C:\Windows\System32\nvidia-smi.exe')) { $smi = 'C:\Windows\System32\nvidia-smi.exe' }
    if ($smi) {
        $q = & $smi --query-gpu=name,vbios_version,memory.total,power.max_limit,pcie.link.gen.max,pcie.link.width.max --format=csv 2>&1
        Save-Text 'nvidia-smi.txt' $q
        Add-Result 'INFO' 'nvidia-smi' (($q | Select-Object -Last 1) -as [string])
    } else {
        Add-Result 'INFO' 'nvidia-smi' 'not found (install the NVIDIA driver, then rerun)'
    }

    # ---------- 4. RAM ----------
    Section 'Memory'
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $ram | Select-Object DeviceLocator, Manufacturer, PartNumber, SerialNumber, Capacity, Speed, ConfiguredClockSpeed |
        Export-Csv (Join-Path $OutDir 'ram.csv') -NoTypeInformation
    $totalGB = [math]::Round((($ram | Measure-Object Capacity -Sum).Sum) / 1GB)
    if ($ram.Count -eq $Expect.RamModules -and $totalGB -eq $Expect.RamTotalGB) {
        Add-Result 'PASS' 'RAM layout' "$($ram.Count) modules, $totalGB GB"
    } else {
        Add-Result 'FAIL' 'RAM layout' "$($ram.Count) modules, $totalGB GB (expected $($Expect.RamModules) modules, $($Expect.RamTotalGB) GB)"
    }
    $parts = @($ram | ForEach-Object { ($_.PartNumber -as [string]).Trim() } | Sort-Object -Unique)
    if ($parts.Count -eq 1) { Add-Result 'PASS' 'RAM matched pair' "$($ram[0].Manufacturer) $($parts[0]) @ $($ram[0].ConfiguredClockSpeed) MT/s" }
    else { Add-Result 'WARN' 'RAM matched pair' "different part numbers: $($parts -join ' / '). Could mean a swapped module" }

    # Upgrade room: slots on the board and the firmware's stated maximum (MaxCapacityEx is in KB)
    $arr = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Where-Object { $_.Use -eq 3 } | Select-Object -First 1
    if ($arr) {
        $maxKB = if ($arr.MaxCapacityEx) { $arr.MaxCapacityEx } else { $arr.MaxCapacity }
        $maxGB = [math]::Round($maxKB / 1MB)
        Add-Result 'INFO' 'RAM upgrade room' "$($arr.MemoryDevices) slot(s), $($ram.Count) filled, firmware max $maxGB GB"
    }

    # ---------- 5. Storage ----------
    Section 'Storage'
    $disks = @(Get-PhysicalDisk)
    $disks | Select-Object DeviceId, FriendlyName, SerialNumber, MediaType, BusType, FirmwareVersion, HealthStatus,
        @{ n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB) } } | Export-Csv (Join-Path $OutDir 'disks.csv') -NoTypeInformation
    foreach ($d in $disks) {
        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $detail = "$($d.FriendlyName) fw $($d.FirmwareVersion), health $($d.HealthStatus)"
        if ($r) {
            $r | Select-Object PowerOnHours, StartStopCycleCount, Wear, Temperature, TemperatureMax,
                ReadErrorsTotal, ReadErrorsUncorrected, WriteErrorsTotal, WriteErrorsUncorrected |
                Format-List | Out-String | Out-File (Join-Path $OutDir "disk$($d.DeviceId)_reliability.txt") -Encoding utf8
            $detail += ", power-on $($r.PowerOnHours) h, wear $($r.Wear)%"
            $level = 'PASS'
            if ($d.HealthStatus -ne 'Healthy' -or $r.ReadErrorsUncorrected -gt 0 -or $r.WriteErrorsUncorrected -gt 0) { $level = 'FAIL' }
            elseif ($r.PowerOnHours -gt $Expect.SsdHoursWarn) { $level = 'WARN'; $detail += ' (heavy prior use?)' }
            Add-Result $level 'SSD health' $detail
        } else {
            Add-Result 'INFO' 'SSD health' "$detail. Reliability counters unavailable, use CrystalDiskInfo"
        }
    }
    $smartctl = Get-Command smartctl -ErrorAction SilentlyContinue
    if ($smartctl) {
        Save-Text 'smartctl_nvme0.txt' (& smartctl -a /dev/nvme0 2>&1)
        Add-Result 'INFO' 'smartctl' 'saved smartctl_nvme0.txt (check Data Units Written and Power On Hours)'
    } else {
        Add-Result 'INFO' 'smartctl' 'not installed. CrystalDiskInfo shows total host writes; screenshot it'
    }

    # ---------- 6. Battery ----------
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
    } catch {
        Add-Result 'INFO' 'Battery' 'could not parse the XML report. Open battery-report.html'
    }

    # ---------- 7. Firmware security ----------
    Section 'Firmware security'
    try {
        if (Confirm-SecureBootUEFI) { Add-Result 'PASS' 'Secure Boot' 'enabled' } else { Add-Result 'FAIL' 'Secure Boot' 'disabled' }
    } catch { Add-Result 'FAIL' 'Secure Boot' 'not supported or legacy boot' }

    # The Platform Key (PK) is the root of Secure Boot and should belong to the laptop maker.
    # Certificate names are plain ASCII inside the key bytes, so a text search is enough.
    # "DO NOT TRUST" / "DO NOT SHIP" = a leaked test key (PKfail, 2024): anyone can sign boot code.
    try {
        $pkText  = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name PK).Bytes)
        $kekText = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name KEK).Bytes)
        $names = @([regex]::Matches($pkText + $kekText, '[ -~]{6,}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        Save-Text 'secureboot_keys.txt' (@('Readable strings in PK and KEK:') + $names)
        $pkStrings = @([regex]::Matches($pkText, '[ -~]{6,}') | ForEach-Object { $_.Value })
        $pkName = $pkStrings | Where-Object { $_ -match 'PK|Key|Cert|Secure Boot' } | Select-Object -First 1
        if (($names -join "`n") -match 'DO NOT (TRUST|SHIP)') { Add-Result 'FAIL' 'Secure Boot keys' 'test key found (PKfail), see secureboot_keys.txt' }
        elseif (($pkStrings -join "`n") -match $ExpectPk) { Add-Result 'PASS' 'Secure Boot keys' "PK: $pkName" }
        else { Add-Result 'WARN' 'Secure Boot keys' "PK '$pkName' does not match '$ExpectPk'. Custom keys? Check BIOS and secureboot_keys.txt" }
    } catch { Add-Result 'WARN' 'Secure Boot keys' 'could not read PK (empty, setup mode, or legacy boot). Check BIOS' }

    # BIOS passwords: a password set by someone else locks you out of BIOS settings and updates.
    # HP exposes this through its BIOS WMI interface; other brands do not have it.
    $hpPw = @(Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSPassword -ErrorAction SilentlyContinue)
    if ($hpPw.Count -gt 0) {
        Save-Text 'bios_passwords.txt' ($hpPw | Select-Object Name, IsSet | Format-Table -AutoSize | Out-String)
        $set = @($hpPw | Where-Object { $_.IsSet -eq 1 })
        if ($set.Count -gt 0) { Add-Result 'FAIL' 'BIOS passwords' ("set: " + (($set.Name) -join ', ') + '. Ask the seller to remove them or reject the unit') }
        else { Add-Result 'PASS' 'BIOS passwords' 'none set' }
    } else {
        Add-Result 'INFO' 'BIOS passwords' 'HP BIOS WMI not available here. Check in BIOS setup (F10)'
    }

    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    if ($tpm -and $tpm.TpmPresent -and $tpm.TpmReady) { Add-Result 'PASS' 'TPM' "present and ready (owned: $($tpm.TpmOwned))" }
    else { Add-Result 'WARN' 'TPM' 'not present or not ready. Check BIOS' }
    Save-Text 'tpm.txt' ($tpm | Format-List * | Out-String)

    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) { Save-Text 'deviceguard.txt' ($dg | Format-List * | Out-String) }

    Save-Text 'bitlocker.txt' (manage-bde -status 2>&1)
    Save-Text 'bcdedit.txt' (bcdedit /enum all 2>&1)
    Add-Result 'INFO' 'Boot config' 'saved bcdedit.txt. Look for unknown boot entries'

    # ---------- 8. Windows license ----------
    Section 'Windows license'
    $sls = Get-CimInstance SoftwareLicensingService
    $oa3 = $sls.OA3xOriginalProductKey
    if ($oa3) { Add-Result 'PASS' 'OEM key in firmware' ("present (ends -{0})" -f $oa3.Substring($oa3.Length - 5)) }
    else { Add-Result 'WARN' 'OEM key in firmware' 'none found. HP units ship with one' }
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
        Where-Object { $_.Name -like 'Windows*' } | Select-Object -First 1
    if ($lic) {
        if ($lic.LicenseStatus -eq 1) { Add-Result 'PASS' 'Windows activation' "$($lic.Name) / $($lic.Description)" }
        else { Add-Result 'WARN' 'Windows activation' "status $($lic.LicenseStatus): $($lic.Description)" }
    }

    # ---------- 9. Ownership / management ----------
    Section 'Ownership'
    $dsreg = dsregcmd /status 2>&1
    Save-Text 'dsregcmd.txt' $dsreg
    $joined = $dsreg | Select-String -Pattern '^\s*(AzureAdJoined|DomainJoined|EnterpriseJoined)\s*:\s*YES'
    if ($joined) { Add-Result 'FAIL' 'Org join' (($joined | ForEach-Object { $_.Line.Trim() }) -join '; ') }
    else { Add-Result 'PASS' 'Org join' 'not joined to Azure AD, a domain or an enterprise' }

    $enroll = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.ProviderID -or $_.UPN })
    if ($enroll.Count -gt 0) { Add-Result 'FAIL' 'MDM enrollment' (($enroll | ForEach-Object { "$($_.ProviderID) $($_.UPN)" }) -join '; ') }
    else { Add-Result 'PASS' 'MDM enrollment' 'none' }

    $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue)
    Save-Text 'local_users.txt' ((Get-LocalUser | Format-Table Name, Enabled, LastLogon -AutoSize | Out-String) + "`nAdministrators:`n" + ($admins | Format-Table Name, ObjectClass, PrincipalSource -AutoSize | Out-String))
    Add-Result 'INFO' 'Local admins' (($admins.Name) -join ', ')

    # ---------- 10. Drivers, devices, network ----------
    Section 'Drivers and devices'
    $drv = Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, DriverDate, IsSigned, InfName
    $drv | Export-Csv (Join-Path $OutDir 'drivers.csv') -NoTypeInformation
    $unsigned = @($drv | Where-Object { $_.IsSigned -eq $false -and $_.DeviceName })
    if ($unsigned.Count -gt 0) { Add-Result 'WARN' 'Unsigned drivers' (($unsigned.DeviceName) -join '; ') }
    else { Add-Result 'PASS' 'Unsigned drivers' 'none' }

    Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion |
        Export-Csv (Join-Path $OutDir 'network.csv') -NoTypeInformation
    $wifi = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|AX211' }
    if ($wifi) { Add-Result 'INFO' 'Wi-Fi adapter' "$($wifi[0].InterfaceDescription), $($wifi[0].Status), $($wifi[0].LinkSpeed)" }
    else { Add-Result 'FAIL' 'Wi-Fi adapter' 'not found' }
    $bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
    if ($bt.Count -gt 0) { Add-Result 'PASS' 'Bluetooth' "$($bt.Count) device(s) OK" } else { Add-Result 'FAIL' 'Bluetooth' 'no working Bluetooth device' }
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -match 'USB|System|Net|Bluetooth|Display|Camera|Biometric|AudioEndpoint|MEDIA' } |
        Select-Object Class, FriendlyName, Status, InstanceId | Export-Csv (Join-Path $OutDir 'pnp_devices.csv') -NoTypeInformation

    # ---------- 11. Software inventory (what the previous owner left) ----------
    Section 'Software inventory'
    $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName |
        Export-Csv (Join-Path $OutDir 'installed_software.csv') -NoTypeInformation
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User |
        Export-Csv (Join-Path $OutDir 'startup_items.csv') -NoTypeInformation
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
        Select-Object TaskPath, TaskName, State, Author | Export-Csv (Join-Path $OutDir 'scheduled_tasks_nonms.csv') -NoTypeInformation
    Add-Result 'INFO' 'Software inventory' 'installed_software.csv, startup_items.csv, scheduled_tasks_nonms.csv. Look for anything not from HP, Microsoft, Intel or NVIDIA'

    # ---------- 12. msinfo32 full report ----------
    Section 'msinfo32'
    Write-Host 'Writing msinfo32 report (takes about a minute)...'
    Start-Process -FilePath msinfo32.exe -ArgumentList "/report `"$(Join-Path $OutDir 'msinfo32.txt')`"" -Wait

    # ---------- 13. event logs ----------
    Section "Event logs (last $EventDays days)"
    Test-EventLogs -Since (Get-Date).AddDays(-$EventDays)
}

# ---------- summary + manifest ----------
$header = @(
    "OMEN DOA audit ($mode)",
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

Get-ChildItem $OutDir -File | Where-Object { $_.Name -ne 'MANIFEST.sha256' } | ForEach-Object {
    $h = Get-FileHash $_.FullName -Algorithm SHA256
    '{0}  {1}' -f $h.Hash.ToLower(), $_.Name
} | Out-File (Join-Path $OutDir 'MANIFEST.sha256') -Encoding ascii

Write-Host "`n$fails FAIL, $warns WARN. Report: $OutDir" -ForegroundColor $(if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' })
Write-Host 'Upload the whole folder to Drive today.'
