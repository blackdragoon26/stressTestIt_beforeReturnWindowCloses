# Which laptop is this, and what is it supposed to have?
# One file per laptop model in .\profiles (format: docs\profiles.md). A laptop without a profile runs in
# generic mode: every health, tamper and prior-use check still runs, only the spec comparison is skipped.
# Sets: $Profiles, $Expect, $IsGeneric, $how, $machineId, $csInfo, $bbInfo, $HasNvidia, $NvidiaExpected

$Profiles = [ordered]@{}
foreach ($pf in @(Get-ChildItem (Join-Path $KitRoot 'profiles') -Filter *.psd1 -ErrorAction SilentlyContinue | Sort-Object Name)) {
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

# Limits that are the same for every laptop
$Expect.BatteryHealthMinPct = 95    # a new unit: full charge at least 95% of design
$Expect.BatteryCyclesMax    = 10    # and single-digit cycles
$Expect.SsdHoursWarn        = 100   # more power-on hours than this = real prior use
if (-not (Test-Spec 'GpuTempWarn')) { $Expect.GpuTempWarn = 87 }
if (-not (Test-Spec 'GpuMinWatts')) { $Expect.GpuMinWatts = 0 }

# NVIDIA checks run when the profile says there is an NVIDIA GPU, or, in generic mode, when one is present
$HasNvidia = [bool](Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' })
$NvidiaExpected = if (Test-Spec 'GpuVramGB') { $Expect.GpuVramGB -gt 0 } else { $HasNvidia }
