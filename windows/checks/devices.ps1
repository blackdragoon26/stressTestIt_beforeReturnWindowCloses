# Drivers, devices, network, and the PCIe links of the SSD and the GPU.
Section 'Drivers and devices'
$drv = Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, DriverDate, IsSigned, InfName
$drv | Export-Csv (Join-Path $OutDir 'drivers.csv') -NoTypeInformation
$unsignedDrv = @($drv | Where-Object { $_.IsSigned -eq $false -and $_.DeviceName })
if ($unsignedDrv.Count -gt 0) { Add-Result 'WARN' 'Unsigned drivers' (($unsignedDrv.DeviceName) -join '; ') }
else { Add-Result 'PASS' 'Unsigned drivers' 'none' }

Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
    Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion |
    Export-Csv (Join-Path $OutDir 'network.csv') -NoTypeInformation
$wifi = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN|AX2|BE2' }
if ($wifi) { Add-Result 'INFO' 'Wi-Fi adapter' "$($wifi[0].InterfaceDescription), $($wifi[0].Status), $($wifi[0].LinkSpeed)" }
else { Add-Result 'FAIL' 'Wi-Fi adapter' 'not found' }
$bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
if ($bt.Count -gt 0) { Add-Result 'PASS' 'Bluetooth' "$($bt.Count) device(s) OK" } else { Add-Result 'FAIL' 'Bluetooth' 'no working Bluetooth device' }
$cam = @(Get-PnpDevice -PresentOnly -Class Camera, Image -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
if ($cam.Count -gt 0) { Add-Result 'PASS' 'Webcam' (($cam.FriendlyName) -join '; ') } else { Add-Result 'FAIL' 'Webcam' 'no working camera device' }
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -match 'USB|System|Net|Bluetooth|Display|Camera|Biometric|AudioEndpoint|MEDIA' } |
    Select-Object Class, FriendlyName, Status, InstanceId | Export-Csv (Join-Path $OutDir 'pnp_devices.csv') -NoTypeInformation

# PCIe links: a device running on fewer lanes than it supports (x2 instead of x4) points to a bad seat,
# a damaged slot or a board fault. Link speed (the generation) drops at idle to save power, so only the
# width is judged here; -Monitor checks the GPU's link again under load.
$linkKeys = 'DEVPKEY_PciDevice_CurrentLinkSpeed', 'DEVPKEY_PciDevice_CurrentLinkWidth', 'DEVPKEY_PciDevice_MaxLinkSpeed', 'DEVPKEY_PciDevice_MaxLinkWidth'
$pciRows = foreach ($dev in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -like 'PCI\*' -and ($_.Class -eq 'Display' -or $_.FriendlyName -match 'NVM Express|NVMe|SSD') })) {
    $v = @{}
    foreach ($p in @(Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName $linkKeys -ErrorAction SilentlyContinue)) { $v[$p.KeyName] = $p.Data }
    if ($null -eq $v['DEVPKEY_PciDevice_MaxLinkWidth']) { continue }
    [pscustomobject]@{
        Device = $dev.FriendlyName; Class = $dev.Class
        Gen = $v['DEVPKEY_PciDevice_CurrentLinkSpeed']; MaxGen = $v['DEVPKEY_PciDevice_MaxLinkSpeed']
        Lanes = $v['DEVPKEY_PciDevice_CurrentLinkWidth']; MaxLanes = $v['DEVPKEY_PciDevice_MaxLinkWidth']
    }
}
$pciRows = @($pciRows)
if ($pciRows.Count -gt 0) {
    $pciRows | Export-Csv (Join-Path $OutDir 'pcie_links.csv') -NoTypeInformation
    foreach ($l in $pciRows) {
        $txt = "Gen $($l.Gen) x$($l.Lanes) (device supports Gen $($l.MaxGen) x$($l.MaxLanes))"
        if ($l.Class -ne 'Display' -and $l.Lanes -lt $l.MaxLanes) { Add-Result 'WARN' "PCIe link: $($l.Device)" "$txt. The SSD runs on fewer lanes than it supports: reseat it or suspect the slot" }
        elseif ($l.Class -ne 'Display') { Add-Result 'PASS' "PCIe link: $($l.Device)" $txt }
        else { Add-Result 'INFO' "PCIe link: $($l.Device)" "$txt at idle. -Monitor checks it under load" }
    }
} else {
    Add-Result 'INFO' 'PCIe links' 'Windows did not report link widths on this machine'
}
