# Hardware inventory: every part with its exact model, maker and serial, in one table.
# Reads everything itself, so it also works when run alone with -Only inventory.
Section 'Hardware inventory'
$inv = New-Object System.Collections.Generic.List[object]
function Add-Inv($cat, $name, $maker, $detail) {
    # WMI pads some strings with NUL characters (seen on the ASUS: the TPM version); strip them
    $clean = { param($s) ("$s" -replace "`0", '').Trim() }
    $inv.Add([pscustomobject]@{ Category = $cat; Model = (& $clean $name); Maker = (& $clean $maker); Detail = (& $clean $detail) })
}

$iCs   = Get-CimInstance Win32_ComputerSystem
$iBios = Get-CimInstance Win32_BIOS
$iBb   = Get-CimInstance Win32_BaseBoard
$iCpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
Add-Inv 'System' $iCs.Model $iCs.Manufacturer "product number $($iCs.SystemSKUNumber), serial $($iBios.SerialNumber), board $($iBb.Product)"
Add-Inv 'BIOS' $iBios.SMBIOSBIOSVersion $iBios.Manufacturer "released $($iBios.ReleaseDate)"
Add-Inv 'CPU' $iCpu.Name $iCpu.Manufacturer "$($iCpu.NumberOfCores) cores, $($iCpu.NumberOfLogicalProcessors) threads, base $($iCpu.MaxClockSpeed) MHz"
foreach ($g in @(Get-CimInstance Win32_VideoController)) { Add-Inv 'GPU' $g.Name $g.AdapterCompatibility "driver $($g.DriverVersion)" }
foreach ($m in @(Get-CimInstance Win32_PhysicalMemory)) { Add-Inv 'RAM' $m.PartNumber $m.Manufacturer "$([math]::Round($m.Capacity / 1GB)) GB at $($m.ConfiguredClockSpeed) MT/s, slot $($m.DeviceLocator), serial $($m.SerialNumber)" }
foreach ($d in @(Get-PhysicalDisk)) { Add-Inv 'Disk' $d.FriendlyName '' "$([math]::Round($d.Size / 1e9)) GB, $($d.BusType), firmware $($d.FirmwareVersion), serial $($d.SerialNumber)" }
foreach ($mon in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)) {
    Add-Inv 'Display' (Get-WmiText $mon.UserFriendlyName) (Get-WmiText $mon.ManufacturerName) "product $(Get-WmiText $mon.ProductCodeID), serial $(Get-WmiText $mon.SerialNumberID), made week $($mon.WeekOfManufacture) of $($mon.YearOfManufacture)"
}
if ($batInfo) { Add-Inv 'Battery' $batInfo.Id $batInfo.Manufacturer "$($batInfo.Chemistry), designed $($batInfo.DesignCapacity) mWh, serial $($batInfo.SerialNumber)" }
foreach ($n in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) { Add-Inv 'Network' $n.InterfaceDescription '' "MAC $($n.MacAddress), driver $($n.DriverVersion)" }
foreach ($x in @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })) { Add-Inv 'Bluetooth' $x.FriendlyName $x.Manufacturer '' }
foreach ($x in @(Get-PnpDevice -PresentOnly -Class Camera, Image -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })) { Add-Inv 'Camera' $x.FriendlyName $x.Manufacturer '' }
foreach ($x in @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)) { Add-Inv 'Audio' $x.Name $x.Manufacturer '' }
foreach ($x in @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue)) { Add-Inv 'Keyboard' $x.Description '' $x.PNPDeviceID }
foreach ($x in @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue)) { Add-Inv 'Touchpad / mouse' $x.Name $x.Manufacturer $x.PNPDeviceID }
foreach ($x in @(Get-CimInstance Win32_USBController -ErrorAction SilentlyContinue)) { Add-Inv 'USB controller' $x.Name $x.Manufacturer '' }
foreach ($x in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Thunderbolt|USB4' })) { Add-Inv 'Thunderbolt' $x.FriendlyName $x.Manufacturer $x.Status }
$iTpm = Get-Tpm -ErrorAction SilentlyContinue
if ($iTpm) { Add-Inv 'TPM' "TPM version $($iTpm.ManufacturerVersion)" $iTpm.ManufacturerIdTxt "ready $($iTpm.TpmReady)" }
$inv | Export-Csv (Join-Path $OutDir 'hardware_inventory.csv') -NoTypeInformation
Add-Result 'INFO' 'Hardware inventory' "$($inv.Count) parts listed in hardware_inventory.csv and the PDF"
