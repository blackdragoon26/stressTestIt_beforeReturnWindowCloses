# Memory: module count and size, matched pair, speed, and how much room there is to upgrade.
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
    $note = if ($Expect.UpgradeNote) { ". $($Expect.UpgradeNote)" } else { '' }
    Add-Result 'INFO' 'RAM upgrade room' "$($arr.MemoryDevices) slot(s), $($ram.Count) filled, firmware max $maxGB GB$note"
}
