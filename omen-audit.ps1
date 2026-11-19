<#
.SYNOPSIS
  OMEN Transcend 16 (16-u0005TX / 834T6PA) DOA audit.

.DESCRIPTION
  Full mode (default): identity, genuineness, health, security, drivers, event logs.
  -Quick mode: event-log check only (WHEA, unexpected shutdowns, bugchecks, GPU driver
  resets, disk errors) since the last quick run. Use it every evening during the soak.

  Every run writes a timestamped folder under .\reports with a SUMMARY.txt and a
  SHA256 manifest of all files, so the evidence can be shown to be unchanged later.

.EXAMPLE
  Right-click PowerShell > Run as administrator, then:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\omen-audit.ps1
    .\omen-audit.ps1 -Quick
#>
[CmdletBinding()]
param(
    [switch]$Quick,
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
    [int]$ExpectRamGB = 16
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
$mode   = if ($Quick) { 'quick' } else { 'full' }
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
