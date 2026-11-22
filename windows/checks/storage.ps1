# Storage: SSD health and prior use (the NVMe health log), size, and real sequential speed.
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

# Sequential speed of the system drive, 1 GB written and read back with the file cache bypassed.
# A slow result points to a drive running on fewer PCIe lanes, a cheaper drive, or a failing one.
$sysDrive = $env:SystemDrive
$free = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction SilentlyContinue).FreeSpace
if ($free -and $free -gt 5GB) {
    Write-Host 'Measuring SSD speed (1 GB, a few seconds)...'
    $sp = Measure-DriveSpeed -Folder $env:TEMP -SizeMB 1024
    $isNvme = [bool]($internal | Where-Object { "$($_.BusType)" -eq 'NVMe' })
    $minRead = if (Test-Spec 'SsdMinReadMBs') { $Expect.SsdMinReadMBs } elseif ($isNvme) { 800 } else { 300 }
    if ($sp.Error) { Add-Result 'WARN' 'SSD speed' "could not measure: $($sp.Error)" }
    elseif ($sp.BadChunks -gt 0) { Add-Result 'FAIL' 'SSD speed' "$($sp.BadChunks) of $($sp.SizeMB / 4) blocks read back different from what was written. The drive returns wrong data" }
    elseif ($sp.ReadMBs -lt $minRead) { Add-Result 'WARN' 'SSD speed' "read $($sp.ReadMBs) MB/s, write $($sp.WriteMBs) MB/s, expected reads of at least $minRead MB/s. Check the PCIe link below, and run it again with nothing else open" }
    else { Add-Result 'PASS' 'SSD speed' "read $($sp.ReadMBs) MB/s, write $($sp.WriteMBs) MB/s (1 GB, uncached), data read back intact" }
} else {
    Add-Result 'INFO' 'SSD speed' 'skipped: less than 5 GB free on the system drive'
}

$smartctl = Get-Command smartctl -ErrorAction SilentlyContinue
if ($smartctl) {
    Save-Text 'smartctl_nvme0.txt' (& smartctl -a /dev/nvme0 2>&1)
    Add-Result 'INFO' 'smartctl' 'saved smartctl_nvme0.txt (check Data Units Written and Power On Hours)'
}
