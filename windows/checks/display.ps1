# Display: native resolution, top refresh rate and panel maker of the built-in screen, from the panel's
# own data (EDID). A different resolution or panel code means a replaced panel.
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

# Panel maker and product code, as "AUO A3A6". Makers buy panels from more than one supplier, so a
# different code is a WARN: compare it with the maker's parts list before calling it a swap.
$ids = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
$pid0 = if ($panel) { $ids | Where-Object { $_.InstanceName -eq $panel.InstanceName } | Select-Object -First 1 } elseif ($ids.Count -eq 1) { $ids[0] }
if ($pid0) {
    $panelCode = "$(Get-WmiText $pid0.ManufacturerName) $(Get-WmiText $pid0.ProductCodeID)".Trim()
    $made = "made week $($pid0.WeekOfManufacture) of $($pid0.YearOfManufacture)"
    if (-not (Test-Spec 'Panel')) { Add-Result 'INFO' 'Display panel' "$panelCode, $made" }
    elseif ($panelCode -match $Expect.Panel) { Add-Result 'PASS' 'Display panel' "$panelCode, $made" }
    else { Add-Result 'WARN' 'Display panel' "$panelCode, $made; reviewed units have $($Expect.Panel). A second supplier, or a replaced panel: check for uneven gaps around the bezel" }
}
