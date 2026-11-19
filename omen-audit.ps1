<#
.SYNOPSIS
  Laptop audit: is this the machine the listing promised, untampered, and how used is it?
  Built for the dead-on-arrival window of an HP OMEN Transcend 16; works on any Windows laptop.
  Laptop profiles (expected specs) live in .\profiles. Without one it runs in generic mode.

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
    # Which profile to check against: 'auto' (recognise it from the model name and board ID),
    # a file name from .\profiles without .psd1 (for example 'omen'), or 'generic' (no spec comparison).
    [string]$Laptop = 'auto',
    # Serial number printed on the invoice or box. If left out, the full audit asks for it.
    [string]$InvoiceSerial,
    [string]$OutRoot = (Join-Path $PSScriptRoot 'reports'),
    [int]$EventDays = 30
)

$ErrorActionPreference = 'Continue'

# ---------- what this laptop is supposed to have ----------
# One file per laptop model in .\profiles (format: docs\profiles.md). A laptop without a profile runs
# in generic mode: every health, tamper and prior-use check still runs, only the spec comparison is skipped.
$profileDir = Join-Path $PSScriptRoot 'profiles'
$Profiles = [ordered]@{}
foreach ($pf in @(Get-ChildItem $profileDir -Filter *.psd1 -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try { $Profiles[$pf.BaseName] = Import-PowerShellDataFile $pf.FullName }
    catch { Write-Host "Skipping profile $($pf.Name): $($_.Exception.Message)" -ForegroundColor Yellow }
}
$generic = @{ Name = 'Generic (no profile for this laptop: specs are listed, not compared)' }

$csInfo = Get-CimInstance Win32_ComputerSystem
$bbInfo = Get-CimInstance Win32_BaseBoard
$machineId = "$($csInfo.Model) $($bbInfo.Product)"
$how = 'chosen with -Laptop'
if ($Laptop -eq 'auto') {
    $Laptop = 'generic'
    $how = "not recognised ('$machineId')"
    foreach ($k in $Profiles.Keys) {
        if ($Profiles[$k].Detect -and $machineId -match $Profiles[$k].Detect) { $Laptop = $k; $how = "recognised from '$machineId'"; break }
    }
}
if ($Laptop -eq 'generic') { $Expect = $generic }
elseif ($Profiles.Contains($Laptop)) { $Expect = $Profiles[$Laptop] }
else {
    Write-Host "No profile '$Laptop'. Available: $((@($Profiles.Keys) + 'generic') -join ', ')" -ForegroundColor Red
    exit 1
}
$IsGeneric = ($Laptop -eq 'generic')
function Test-Spec([string]$Key) { return $Expect.ContainsKey($Key) }   # does the profile define this value?
$Expect.BatteryHealthMinPct = 95    # a new unit: full charge at least 95% of design
$Expect.BatteryCyclesMax    = 10    # and single-digit cycles
$Expect.SsdHoursWarn        = 100   # more power-on hours than this = real prior use
if (-not (Test-Spec 'GpuTempWarn')) { $Expect.GpuTempWarn = 87 }
if (-not (Test-Spec 'GpuMinWatts')) { $Expect.GpuMinWatts = 0 }
# NVIDIA checks run when the profile says there is an NVIDIA GPU, or, in generic mode, when one is present
$HasNvidia = [bool](Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' })
$NvidiaExpected = if (Test-Spec 'GpuVramGB') { $Expect.GpuVramGB -gt 0 } else { $HasNvidia }

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

function ConvertTo-Num([string]$s) {
    if ($null -eq $s) { return $null }
    $d = 0.0
    if ([double]::TryParse($s.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}

function Get-NvmeHealth([int]$Drive) {
    # The NVMe SMART / health log (log page 2), read straight from the drive with the Windows storage
    # IOCTL, as smartmontools does. Windows' own counters can leave power-on hours blank (seen on the
    # ASUS's Kingston drive, which Linux reads as 19,276 h and 72.1 TB written). Needs admin.
    try {
        if (-not ('NvmeHealthLog' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class NvmeHealthLog {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle device, uint code, byte[] inBuffer, int inSize, byte[] outBuffer, int outSize, out int returned, IntPtr overlapped);
    public static byte[] Read(int drive) {
        using (SafeFileHandle h = CreateFile(@"\\.\PhysicalDrive" + drive, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) return null;
            byte[] buf = new byte[8 + 40 + 512];
            BitConverter.GetBytes(50).CopyTo(buf, 0);   // StorageDeviceProtocolSpecificProperty
            BitConverter.GetBytes(0).CopyTo(buf, 4);    // PropertyStandardQuery
            BitConverter.GetBytes(3).CopyTo(buf, 8);    // ProtocolTypeNvme
            BitConverter.GetBytes(2).CopyTo(buf, 12);   // NVMeDataTypeLogPage
            BitConverter.GetBytes(2).CopyTo(buf, 16);   // log page 2: SMART / health information
            BitConverter.GetBytes(40).CopyTo(buf, 24);  // ProtocolDataOffset
            BitConverter.GetBytes(512).CopyTo(buf, 28); // ProtocolDataLength
            int returned;
            if (!DeviceIoControl(h, 0x002D1400, buf, buf.Length, buf, buf.Length, out returned, IntPtr.Zero)) return null;
            int offset = BitConverter.ToInt32(buf, 24);
            int length = BitConverter.ToInt32(buf, 28);
            if (length < 192 || 8 + offset + 512 > buf.Length) return null;
            byte[] log = new byte[512];
            Array.Copy(buf, 8 + offset, log, 0, 512);
            return log;
        }
    }
}
'@
        }
        $log = [NvmeHealthLog]::Read($Drive)
        if (-not $log) { return $null }
        # Data units are 1000 x 512 bytes
        return [ordered]@{
            CriticalWarning   = $log[0]
            TemperatureC      = [BitConverter]::ToUInt16($log, 1) - 273
            AvailableSparePct = $log[3]
            PercentUsed       = $log[5]
            DataReadTB        = [math]::Round([BitConverter]::ToUInt64($log, 32) * 512000 / 1e12, 2)
            DataWrittenTB     = [math]::Round([BitConverter]::ToUInt64($log, 48) * 512000 / 1e12, 2)
            PowerCycles       = [BitConverter]::ToUInt64($log, 112)
            PowerOnHours      = [BitConverter]::ToUInt64($log, 128)
            UnsafeShutdowns   = [BitConverter]::ToUInt64($log, 144)
            MediaErrors       = [BitConverter]::ToUInt64($log, 160)
            ErrorLogEntries   = [BitConverter]::ToUInt64($log, 176)
        }
    } catch { return $null }
}

function Find-NvidiaSmi {
    $s = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $s -and (Test-Path 'C:\Windows\System32\nvidia-smi.exe')) { $s = 'C:\Windows\System32\nvidia-smi.exe' }
    return $s
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
        if ($q.Name -like 'NVIDIA*' -and -not $NvidiaExpected) {
            Add-Result 'INFO' $q.Name 'skipped: this laptop has no NVIDIA GPU'
            continue
        }
        # Get-WinEvent throws even with -ErrorAction SilentlyContinue when a provider is not installed
        # on this machine (seen on the ASUS: "The parameter is incorrect" for nvlddmkm). So: one provider
        # at a time, "not installed" and "no events" count as zero, anything else is reported.
        $events = @(); $problem = $null
        foreach ($p in @($q.Filter.ProviderName)) {
            $f = @{} + $q.Filter
            if ($null -ne $p) { $f.ProviderName = $p }
            try { $events += @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop) }
            catch {
                $msg = $_.Exception.Message
                if ($msg -notmatch 'No events were found|not an event provider|do not write events|parameter is incorrect') { $problem = $msg }
            }
        }
        if ($q.Name -like 'Bugchecks*') {
            $events = @($events | Where-Object { $_.ProviderName -match 'BugCheck|WER-SystemErrorReporting' })
        }
        if ($problem -and $events.Count -eq 0) {
            Add-Result 'WARN' $q.Name "could not read the event log: $problem"
        } elseif ($events.Count -eq 0) {
            Add-Result 'PASS' $q.Name "0 since $($Since.ToString('yyyy-MM-dd HH:mm'))"
        } else {
            $when = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 5 | ForEach-Object { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm') }) -join ', '
            Add-Result 'FAIL' $q.Name "$($events.Count) event(s) since $($Since.ToString('yyyy-MM-dd HH:mm')). Latest: $when. Details in event_errors.csv"
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

    # A dedicated GPU that vanishes from Windows is the classic sign of a failing GPU or board
    $wantGpu = if (Test-Spec 'Gpu') { $Expect.Gpu } elseif ($HasNvidia) { 'NVIDIA' } else { $null }
    if ($wantGpu) {
        $gpu = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match $wantGpu })
        if ($gpu.Count -gt 0) { Add-Result 'PASS' 'GPU present' $gpu[0].Name }
        else { Add-Result 'FAIL' 'GPU present' "$wantGpu not listed. Possible GPU dropout" }
    }
}

# =====================================================================
if ($IsGeneric -and $how -like 'not recognised*') {
    Add-Result 'WARN' 'Laptop profile' "$how. Specs are listed, not compared. All health, tamper and prior-use checks still run. To compare, add a profile (docs\profiles.md) or force one with -Laptop"
} else {
    Add-Result 'INFO' 'Laptop profile' "$($Expect.Name), $how"
}
# Which exact version of this script produced the report: compare with docs/SHA256SUMS.txt in the repo
$ScriptHash = try { (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash.ToLower() } catch { 'unknown' }
Add-Result 'INFO' 'Script version' "sha256 $ScriptHash"

# Safety net: if anything below crashes, the error is recorded and the report is still written
try {
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
    # Laptops whose profile has no NVIDIA GPU (GpuVramGB = 0) skip the GPU sensors.
    $nvidiaExpected = $NvidiaExpected
    $smi = Find-NvidiaSmi
    $gpuFields = $null
    if ($nvidiaExpected -and $smi) {
        foreach ($reason in 'clocks_event_reasons.active', 'clocks_throttle_reasons.active') {
            $f = "temperature.gpu,power.draw,clocks.gr,clocks.mem,utilization.gpu,pstate,$reason"
            $null = & $smi "--query-gpu=$f" --format=csv,noheader,nounits 2>&1
            if ($LASTEXITCODE -eq 0) { $gpuFields = $f; break }
        }
    }
    if (-not $nvidiaExpected) { Add-Result 'INFO' 'GPU sensors' 'this laptop has no NVIDIA GPU: GPU sensors skipped' }
    elseif (-not $gpuFields) { Add-Result 'WARN' 'GPU sensors' 'nvidia-smi not available. Install the NVIDIA driver, then rerun' }

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
    # Serial: the script cannot see the invoice, so it asks for the number once and compares it itself
    $serial = "$($bios.SerialNumber)".Trim()
    $typed  = $InvoiceSerial
    if (-not $typed) {
        try { $typed = Read-Host 'Type the serial number from the invoice (or press Enter to skip)' } catch { }
    }
    if ($typed) {
        if ($typed.Trim() -ieq $serial) { Add-Result 'PASS' 'Serial number' "$serial matches the invoice" }
        else { Add-Result 'FAIL' 'Serial number' "BIOS says '$serial', invoice says '$($typed.Trim())'" }
    } else {
        Add-Result 'INFO' 'Serial number' "$serial (not compared: no invoice serial typed)"
    }
    Add-Result 'INFO' 'BIOS version' "$($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"

    if (-not (Test-Spec 'ProductNumber')) { Add-Result 'INFO' 'Product number' "'$("$($cs.SystemSKUNumber)".Trim())'" }
    elseif (-not $Expect.ProductNumber) { Add-Result 'INFO' 'Product number' "this model's firmware stores none" }
    elseif ($cs.SystemSKUNumber -match $Expect.ProductNumber) { Add-Result 'PASS' 'Product number' $cs.SystemSKUNumber }
    else { Add-Result 'FAIL' 'Product number' "got '$($cs.SystemSKUNumber)', expected $($Expect.ProductNumber)" }

    if (-not (Test-Spec 'Model')) { Add-Result 'INFO' 'Model' "$($cs.Manufacturer) $($cs.Model)" }
    elseif ($cs.Model -match $Expect.Model) { Add-Result 'PASS' 'Model' $cs.Model }
    else { Add-Result 'FAIL' 'Model' "got '$($cs.Model)'" }

    if (-not (Test-Spec 'BoardId')) { Add-Result 'INFO' 'Board ID' $bb.Product }
    elseif ($bb.Product -eq $Expect.BoardId) { Add-Result 'PASS' 'Board ID' $bb.Product }
    else { Add-Result 'WARN' 'Board ID' "got '$($bb.Product)', expected $($Expect.BoardId). Ask the maker or the seller why it differs" }

    if ($bios.SerialNumber -and $bb.SerialNumber -and ($bb.SerialNumber -notmatch [regex]::Escape($bios.SerialNumber))) {
        Add-Result 'INFO' 'Board serial' "board serial '$($bb.SerialNumber)' differs from system serial (normal on most laptops, record it)"
    }

    # ---------- 2. CPU ----------
    Section 'CPU'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Save-Text 'cpu.txt' ($cpu | Format-List Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize, L3CacheSize, ProcessorId | Out-String)
    if (-not (Test-Spec 'Cpu')) { Add-Result 'INFO' 'CPU model' $cpu.Name.Trim() }
    elseif ($cpu.Name -match $Expect.Cpu) { Add-Result 'PASS' 'CPU model' $cpu.Name.Trim() }
    else { Add-Result 'FAIL' 'CPU model' "got '$($cpu.Name.Trim())', expected $($Expect.Cpu)" }
    if (-not (Test-Spec 'Cores')) {
        Add-Result 'INFO' 'CPU cores/threads' "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T"
    } elseif ($cpu.NumberOfCores -eq $Expect.Cores -and $cpu.NumberOfLogicalProcessors -eq $Expect.Threads) {
        Add-Result 'PASS' 'CPU cores/threads' "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T"
    } else {
        Add-Result 'FAIL' 'CPU cores/threads' "got $($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T, expected $($Expect.Cores)C / $($Expect.Threads)T"
    }

    # ---------- 3. GPU ----------
    Section 'GPU'
    $gpus = Get-CimInstance Win32_VideoController
    Save-Text 'gpu.txt' ($gpus | Format-List Name, DriverVersion, DriverDate, AdapterRAM, VideoProcessor, PNPDeviceID | Out-String)
    if (-not (Test-Spec 'Gpu')) { Add-Result 'INFO' 'GPU model' (($gpus.Name) -join ', ') }
    else {
        $nv = @($gpus | Where-Object { $_.Name -match $Expect.Gpu })
        if ($nv.Count -gt 0) { Add-Result 'PASS' 'GPU model' $nv[0].Name }
        else { Add-Result 'FAIL' 'GPU model' "got $(($gpus.Name) -join ', '), expected $($Expect.Gpu)" }
    }

    if ($NvidiaExpected) {
        $smi = Find-NvidiaSmi
        if ($smi) {
            $q = & $smi --query-gpu=name,vbios_version,memory.total,power.max_limit,pcie.link.gen.max,pcie.link.width.max --format=csv 2>&1
            Save-Text 'nvidia-smi.txt' $q
            Add-Result 'INFO' 'nvidia-smi' (($q | Select-Object -Last 1) -as [string])
            $vals = @("$(& $smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1)" -split ',\s*')
            $mib = ConvertTo-Num $vals[0]
            if ($null -ne $mib) {
                $vram = [math]::Round($mib / 1024)
                if (-not (Test-Spec 'GpuVramGB')) { Add-Result 'INFO' 'GPU memory' "$vram GB" }
                elseif ($vram -eq $Expect.GpuVramGB) { Add-Result 'PASS' 'GPU memory' "$vram GB" }
                else { Add-Result 'FAIL' 'GPU memory' "$vram GB, expected $($Expect.GpuVramGB) GB" }
            }
        } else {
            Add-Result 'INFO' 'nvidia-smi' 'not found yet (comes with the NVIDIA driver). GPU memory is checked after the reinstall'
        }
    }

    # ---------- 3b. Display ----------
    # Native resolution and top refresh rate of the built-in panel, from the panel's own mode list (EDID).
    # A different resolution means a replaced panel.
    Section 'Display'
    $conn  = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue)
    $lists = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue)
    # 6 = LVDS, 11 = embedded DisplayPort, 13 = embedded UDI, 0x80000000 = internal
    $panel = $conn | Where-Object { @(6, 11, 13, 2147483648) -contains [int64]$_.VideoOutputTechnology } | Select-Object -First 1
    $list  = if ($panel) { $lists | Where-Object { $_.InstanceName -eq $panel.InstanceName } | Select-Object -First 1 }
             elseif ($lists.Count -eq 1) { $lists[0] }
    if ($list -and $list.MonitorSourceModes) {
        $modes = @($list.MonitorSourceModes | ForEach-Object {
            [pscustomobject]@{
                W  = [int]$_.HorizontalActivePixels
                H  = [int]$_.VerticalActivePixels
                Hz = if ($_.VerticalRefreshRateDenominator) { [math]::Round($_.VerticalRefreshRateNumerator / $_.VerticalRefreshRateDenominator, 1) } else { 0 }
            } })
        $native = $modes | Sort-Object { $_.W * $_.H } -Descending | Select-Object -First 1
        $res    = "$($native.W)x$($native.H)"
        $maxHz  = ($modes | Where-Object { $_.W -eq $native.W -and $_.H -eq $native.H } | Measure-Object Hz -Maximum).Maximum
        Save-Text 'display_modes.txt' ($modes | Sort-Object W, H, Hz -Unique | Format-Table -AutoSize | Out-String)
        if (-not (Test-Spec 'Display')) { Add-Result 'INFO' 'Display resolution' $res }
        elseif ($res -eq $Expect.Display) { Add-Result 'PASS' 'Display resolution' $res }
        else { Add-Result 'FAIL' 'Display resolution' "panel reports $res, expected $($Expect.Display). Replaced panel?" }
        if (-not (Test-Spec 'DisplayMinHz')) { Add-Result 'INFO' 'Display refresh' "$maxHz Hz" }
        elseif ($maxHz + 1 -ge $Expect.DisplayMinHz) { Add-Result 'PASS' 'Display refresh' "$maxHz Hz" }
        else { Add-Result 'WARN' 'Display refresh' "panel lists at most $maxHz Hz, expected $($Expect.DisplayMinHz) Hz. Check Settings, Display, Advanced display" }
    } else {
        Add-Result 'INFO' 'Display' 'panel mode list not available. Check resolution and refresh in Settings, Display'
    }

    # ---------- 4. RAM ----------
    Section 'Memory'
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $ram | Select-Object DeviceLocator, Manufacturer, PartNumber, SerialNumber, Capacity, Speed, ConfiguredClockSpeed |
        Export-Csv (Join-Path $OutDir 'ram.csv') -NoTypeInformation
    $totalGB = [math]::Round((($ram | Measure-Object Capacity -Sum).Sum) / 1GB)
    if (-not (Test-Spec 'RamModules')) {
        Add-Result 'INFO' 'RAM layout' "$($ram.Count) modules, $totalGB GB"
    } elseif ($ram.Count -eq $Expect.RamModules -and $totalGB -eq $Expect.RamGB) {
        Add-Result 'PASS' 'RAM layout' "$($ram.Count) modules, $totalGB GB"
    } else {
        Add-Result 'FAIL' 'RAM layout' "$($ram.Count) modules, $totalGB GB (expected $($Expect.RamModules) modules, $($Expect.RamGB) GB)"
    }
    $parts = @($ram | ForEach-Object { ($_.PartNumber -as [string]).Trim() } | Sort-Object -Unique)
    if ($parts.Count -eq 1) { Add-Result 'PASS' 'RAM matched pair' "$($ram[0].Manufacturer) $($parts[0])" }
    elseif (-not (Test-Spec 'RamMatched')) { Add-Result 'INFO' 'RAM matched pair' "different part numbers ($($parts -join ' / ')). Normal if one module is soldered; otherwise it can mean a swapped module" }
    elseif (-not $Expect.RamMatched) { Add-Result 'PASS' 'RAM matched pair' "different part numbers ($($parts -join ' / ')), normal for this model: one soldered, one in the slot" }
    else { Add-Result 'WARN' 'RAM matched pair' "different part numbers: $($parts -join ' / '). Could mean a swapped module" }
    $mts = ($ram | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
    if (-not (Test-Spec 'RamMinMTs')) { Add-Result 'INFO' 'RAM speed' "$mts MT/s" }
    elseif ($mts -ge $Expect.RamMinMTs) { Add-Result 'PASS' 'RAM speed' "$mts MT/s" }
    else { Add-Result 'WARN' 'RAM speed' "$mts MT/s, expected at least $($Expect.RamMinMTs). Slower or mismatched module?" }

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
    foreach ($d in @($disks | Where-Object { "$($_.BusType)" -ne 'USB' })) {
        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($r) {
            $r | Select-Object PowerOnHours, StartStopCycleCount, Wear, Temperature, TemperatureMax,
                ReadErrorsTotal, ReadErrorsUncorrected, WriteErrorsTotal, WriteErrorsUncorrected |
                Format-List | Out-String | Out-File (Join-Path $OutDir "disk$($d.DeviceId)_reliability.txt") -Encoding utf8
        }
        $nh = if ("$($d.BusType)" -eq 'NVMe') { Get-NvmeHealth ([int]$d.DeviceId) } else { $null }
        $detail = "$($d.FriendlyName) fw $($d.FirmwareVersion), health $($d.HealthStatus)"
        $hours = $null
        $level = 'PASS'
        if ($nh) {
            Save-Text "disk$($d.DeviceId)_nvme_health.txt" ($nh.GetEnumerator() | ForEach-Object { '{0,-18} {1}' -f $_.Key, $_.Value })
            $hours = $nh.PowerOnHours
            $detail += ", power-on $hours h, written $($nh.DataWrittenTB) TB, wear $($nh.PercentUsed)%, media errors $($nh.MediaErrors), unsafe shutdowns $($nh.UnsafeShutdowns)"
            if ($nh.CriticalWarning -ne 0 -or $nh.MediaErrors -gt 0) { $level = 'FAIL' }
        } elseif ($r -and $null -ne $r.PowerOnHours) {
            $hours = $r.PowerOnHours
            $detail += ", power-on $hours h, wear $($r.Wear)%"
        }
        if ($d.HealthStatus -ne 'Healthy' -or ($r -and ($r.ReadErrorsUncorrected -gt 0 -or $r.WriteErrorsUncorrected -gt 0))) { $level = 'FAIL' }
        if ($level -eq 'PASS') {
            if ($null -eq $hours) { $level = 'WARN'; $detail += '. Power-on hours not readable here: check them in CrystalDiskInfo, they are the best proof of prior use' }
            elseif ($hours -gt $Expect.SsdHoursWarn) { $level = 'WARN'; $detail += ' (heavy prior use?)' }
        }
        Add-Result $level 'SSD health' $detail
    }
    # Size of the internal SSD in decimal GB (the number on the box). USB drives are ignored.
    $internal = @($disks | Where-Object { "$($_.BusType)" -ne 'USB' })
    $sizes = @($internal | ForEach-Object { [math]::Round($_.Size / 1e9) })
    $okSize = @($sizes | Where-Object { $_ -ge 0.9 * $Expect.SsdGB -and $_ -le 1.1 * $Expect.SsdGB })
    if (-not (Test-Spec 'SsdGB')) { Add-Result 'INFO' 'SSD size' "$($sizes -join ', ') GB" }
    elseif ($okSize.Count -gt 0) { Add-Result 'PASS' 'SSD size' "$($okSize[0]) GB" }
    else { Add-Result 'FAIL' 'SSD size' "found $($sizes -join ', ') GB, expected about $($Expect.SsdGB) GB. Swapped drive?" }
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
        else {
            # Generic mode: the key should name the laptop's maker (first word of the manufacturer, e.g. HP, LENOVO, Dell)
            $pkWant = if (Test-Spec 'Pk') { $Expect.Pk } else { [regex]::Escape((("$($cs.Manufacturer)" -split '\s+')[0])) }
            if ($pkWant -and (($pkStrings -join "`n") -match $pkWant)) { Add-Result 'PASS' 'Secure Boot keys' "PK: $pkName" }
            else { Add-Result 'WARN' 'Secure Boot keys' "PK '$pkName' does not name the maker ($pkWant). Custom keys? Check BIOS and secureboot_keys.txt" }
        }
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
        Add-Result 'INFO' 'BIOS passwords' 'only HP exposes this to Windows. Check in BIOS setup that no password is set'
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

    # Every Windows install has built-in enrollment entries (seen on the ASUS: Deploy, Cloud and Local
    # Authority). A real company enrollment (Intune and others) has a user (UPN) or another provider.
    $builtin = 'Deploy Authority', 'Cloud Authority', 'Local Authority'
    $allEnroll = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.ProviderID -or $_.UPN })
    Save-Text 'mdm_enrollments.txt' ($allEnroll | Select-Object PSChildName, ProviderID, UPN, EnrollmentType | Format-Table -AutoSize | Out-String)
    $enroll = @($allEnroll | Where-Object { $_.UPN -or ($builtin -notcontains "$($_.ProviderID)") })
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
    $cam = @(Get-PnpDevice -PresentOnly -Class Camera, Image -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
    if ($cam.Count -gt 0) { Add-Result 'PASS' 'Webcam' (($cam.FriendlyName) -join '; ') } else { Add-Result 'FAIL' 'Webcam' 'no working camera device' }
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

    # ---------- 11b. Hardware inventory: every part with its exact model ----------
    Section 'Hardware inventory'
    $inv = New-Object System.Collections.Generic.List[object]
    function Add-Inv($cat, $name, $maker, $detail) {
        $inv.Add([pscustomobject]@{ Category = $cat; Model = "$name".Trim(); Maker = "$maker".Trim(); Detail = "$detail".Trim() })
    }
    function Get-WmiText($arr) { (@($arr | Where-Object { $_ -ne 0 }) | ForEach-Object { [char]$_ }) -join '' }

    Add-Inv 'System' $cs.Model $cs.Manufacturer "product number $($cs.SystemSKUNumber), serial $serial, board $($bb.Product)"
    Add-Inv 'BIOS' $bios.SMBIOSBIOSVersion $bios.Manufacturer "released $($bios.ReleaseDate)"
    Add-Inv 'CPU' $cpu.Name $cpu.Manufacturer "$($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads, base $($cpu.MaxClockSpeed) MHz"
    foreach ($g in $gpus) { Add-Inv 'GPU' $g.Name $g.AdapterCompatibility "driver $($g.DriverVersion)" }
    foreach ($m in $ram) { Add-Inv 'RAM' $m.PartNumber $m.Manufacturer "$([math]::Round($m.Capacity / 1GB)) GB at $($m.ConfiguredClockSpeed) MT/s, slot $($m.DeviceLocator), serial $($m.SerialNumber)" }
    foreach ($d in $disks) { Add-Inv 'Disk' $d.FriendlyName '' "$([math]::Round($d.Size / 1e9)) GB, $($d.BusType), firmware $($d.FirmwareVersion), serial $($d.SerialNumber)" }
    foreach ($mon in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)) {
        Add-Inv 'Display' (Get-WmiText $mon.UserFriendlyName) (Get-WmiText $mon.ManufacturerName) "product $(Get-WmiText $mon.ProductCodeID), serial $(Get-WmiText $mon.SerialNumberID), made week $($mon.WeekOfManufacture) of $($mon.YearOfManufacture)"
    }
    if ($batInfo) { Add-Inv 'Battery' $batInfo.Id $batInfo.Manufacturer "$($batInfo.Chemistry), designed $($batInfo.DesignCapacity) mWh, serial $($batInfo.SerialNumber)" }
    foreach ($n in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) { Add-Inv 'Network' $n.InterfaceDescription '' "MAC $($n.MacAddress), driver $($n.DriverVersion)" }
    foreach ($x in $bt) { Add-Inv 'Bluetooth' $x.FriendlyName $x.Manufacturer '' }
    foreach ($x in $cam) { Add-Inv 'Camera' $x.FriendlyName $x.Manufacturer '' }
    foreach ($x in @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)) { Add-Inv 'Audio' $x.Name $x.Manufacturer '' }
    foreach ($x in @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue)) { Add-Inv 'Keyboard' $x.Description '' $x.PNPDeviceID }
    foreach ($x in @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue)) { Add-Inv 'Touchpad / mouse' $x.Name $x.Manufacturer $x.PNPDeviceID }
    foreach ($x in @(Get-CimInstance Win32_USBController -ErrorAction SilentlyContinue)) { Add-Inv 'USB controller' $x.Name $x.Manufacturer '' }
    foreach ($x in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Thunderbolt|USB4' })) { Add-Inv 'Thunderbolt' $x.FriendlyName $x.Manufacturer $x.Status }
    if ($tpm) { Add-Inv 'TPM' "TPM version $($tpm.ManufacturerVersion)" $tpm.ManufacturerIdTxt "ready $($tpm.TpmReady)" }
    $inv | Export-Csv (Join-Path $OutDir 'hardware_inventory.csv') -NoTypeInformation
    Add-Result 'INFO' 'Hardware inventory' "$($inv.Count) parts listed in hardware_inventory.csv and the PDF"

    # ---------- 12. msinfo32 full report ----------
    Section 'msinfo32'
    Write-Host 'Writing msinfo32 report (takes about a minute)...'
    Start-Process -FilePath msinfo32.exe -ArgumentList "/report `"$(Join-Path $OutDir 'msinfo32.txt')`"" -Wait

    # ---------- 13. event logs ----------
    Section "Event logs (last $EventDays days)"
    Test-EventLogs -Since (Get-Date).AddDays(-$EventDays)
}
} catch {
    Add-Result 'WARN' 'Script error' "a script problem, not a laptop fault: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber)). Checks after this point did not run; the report shows what was collected"
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

# ---------- detailed report: HTML, printed to PDF by Microsoft Edge (built into Windows) ----------
# Everything the run collected, in one shareable file: results, exact parts, sensor charts, raw
# outputs, and any script errors (so a person or another agent can review it later).
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
        'display_modes.txt' = 'Display modes listed by the panel'; 'battery.txt' = 'Battery'
        'sensors_stats.csv' = 'Sensor summary (min, median, max)'; 'event_errors.csv' = 'Event log errors'
        'minidumps.csv' = 'Crash dumps'; 'secureboot_keys.txt' = 'Secure Boot keys'
        'bios_passwords.txt' = 'BIOS passwords'; 'tpm.txt' = 'TPM'; 'deviceguard.txt' = 'Device Guard'
        'bitlocker.txt' = 'BitLocker'; 'bcdedit.txt' = 'Boot entries'; 'dsregcmd.txt' = 'Company / Azure AD join'
        'local_users.txt' = 'Local users and admins'; 'network.csv' = 'Network adapters'
        'pnp_devices.csv' = 'Devices'; 'drivers.csv' = 'Drivers'; 'installed_software.csv' = 'Installed software'
        'startup_items.csv' = 'Startup items'; 'scheduled_tasks_nonms.csv' = 'Scheduled tasks (not Microsoft)'
    }
    # Too big or not useful in a PDF; they stay in the folder
    $skipFiles = @('SUMMARY.txt', 'MANIFEST.sha256', 'transcript.txt', 'msinfo32.txt', 'battery-report.html',
                   'battery-report.xml', 'sensors.csv', "$reportBase.html", "$reportBase.pdf")

    $css = @'
@page { size: A4 landscape; margin: 12mm; }
body { font-family: Segoe UI, Arial, sans-serif; font-size: 10px; color: #111; }
h1 { font-size: 18px; margin: 0 0 4px; } h2 { font-size: 13px; margin: 18px 0 6px; border-bottom: 1px solid #ccc; }
table { border-collapse: collapse; width: 100%; table-layout: fixed; }
th, td { border: 1px solid #ccc; padding: 2px 4px; text-align: left; vertical-align: top; word-wrap: break-word; }
th { background: #f0f0f0; } pre { font-size: 9px; white-space: pre-wrap; word-wrap: break-word; background: #fafafa; border: 1px solid #ddd; padding: 4px; }
.muted { color: #666; } .ct { font-weight: bold; margin-top: 8px; }
.FAIL { background: #ffd7d7; } .WARN { background: #fff3c4; } .PASS { background: #dff5df; }
.box { padding: 6px; border: 1px solid #999; margin: 6px 0; font-size: 12px; }
* { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
'@
    $h = New-Object System.Text.StringBuilder
    [void]$h.Append("<!doctype html><html><head><meta charset=`"utf-8`"><title>$reportBase</title><style>$css</style></head><body>")
    [void]$h.Append("<h1>Laptop DOA audit report ($mode)</h1>")
    [void]$h.Append("<div>Run at $(Enc (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')) on $(Enc $env:COMPUTERNAME). Profile: $(Enc $Expect.Name) ($(Enc $how)).</div>")
    [void]$h.Append("<div>Machine: $(Enc $machineId). Serial: $(Enc (Get-CimInstance Win32_BIOS).SerialNumber).</div>")
    [void]$h.Append("<div class=`"box $(if ($fails) {'FAIL'} elseif ($warns) {'WARN'} else {'PASS'})`"><b>$fails FAIL, $warns WARN.</b> FAIL = DOA evidence. WARN = check by hand. The raw files and MANIFEST.sha256 are in the same folder.</div>")

    [void]$h.Append('<h2>Results</h2><table><tr><th style="width:6%">Result</th><th style="width:20%">Check</th><th>Detail</th></tr>')
    foreach ($line in $Summary) {
        if ($line -match '^(\S+)\s+(.*?) : (.*)$') { [void]$h.Append("<tr class=`"$($Matches[1])`"><td>$(Enc $Matches[1])</td><td>$(Enc $Matches[2])</td><td>$(Enc $Matches[3])</td></tr>") }
    }
    [void]$h.Append('</table>')

    [void]$h.Append('<h2>Expected values for this profile</h2>')
    [void]$h.Append((ConvertTo-HtmlTable ($Expect.GetEnumerator() | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Item = $_.Name; Expected = (@($_.Value) -join '; ') } })))

    $sensorCsv = Join-Path $OutDir 'sensors.csv'
    if (Test-Path $sensorCsv) {
        $sr = @(Import-Csv $sensorCsv)
        if ($sr.Count -gt 1) {
            [void]$h.Append('<h2>Sensor charts</h2>')
            $xs = @($sr | ForEach-Object { $_.Elapsed_s })
            foreach ($pair in @(@('GpuTemp_C', 'GPU temperature', 'C'), @('GpuPower_W', 'GPU power', 'W'), @('GpuClock_MHz', 'GPU clock', 'MHz'),
                                @('GpuUtil_pct', 'GPU load', '%'), @('CpuClock_MHz', 'CPU clock, all cores', 'MHz'), @('CpuUtil_pct', 'CPU load', '%'),
                                @('CpuPerfLimit_pct', 'CPU firmware limit', '%'), @('ThermalZoneMax_C', 'Board thermal zone', 'C'))) {
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
        [pscustomobject]@{ Line = $_.InvocationInfo.ScriptLineNumber; Command = "$($_.InvocationInfo.MyCommand)"; Message = "$($_.Exception.Message)" }
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
        $profileDir = Join-Path $env:TEMP 'omen-audit-edge'
        $edgeArgs = @('--headless', '--disable-gpu', '--no-pdf-header-footer', '--print-to-pdf-no-header',
                      "--user-data-dir=`"$profileDir`"", "--print-to-pdf=`"$pdfPath`"", ([Uri]$htmlPath).AbsoluteUri)
        $p = Start-Process -FilePath $edge -ArgumentList $edgeArgs -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { } }
        # Edge can hand the job to a helper process and exit first: give the file time to appear
        for ($i = 0; $i -lt 30 -and -not (Test-Path $pdfPath); $i++) { Start-Sleep -Seconds 1 }
    }
    if (Test-Path $pdfPath) { Write-Host "PDF report: $pdfPath" -ForegroundColor Green }
    else { Write-Host "PDF could not be made (Edge missing or failed). Open $htmlPath and print it to PDF." -ForegroundColor Yellow }
} catch {
    Write-Host "Report could not be built: $($_.Exception.Message). SUMMARY.txt and the raw files are still in $OutDir" -ForegroundColor Yellow
}

Get-ChildItem $OutDir -File | Where-Object { $_.Name -ne 'MANIFEST.sha256' } | ForEach-Object {
    $h = Get-FileHash $_.FullName -Algorithm SHA256
    '{0}  {1}' -f $h.Hash.ToLower(), $_.Name
} | Out-File (Join-Path $OutDir 'MANIFEST.sha256') -Encoding ascii

Write-Host "`n$fails FAIL, $warns WARN. Report: $OutDir" -ForegroundColor $(if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' })
Write-Host 'Upload the whole folder to Drive today.'
