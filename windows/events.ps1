# Event log check: used by the full audit (last 30 days), -Quick (since the last quick run) and the
# load modes (during the test). Each query has the result it gives when events are found.

function Test-EventLogs {
    param([datetime]$Since)

    # iaStorVD / iaStorAC: Intel VMD and RST storage drivers, common on 12th to 14th gen Intel laptops
    $storage = @('disk', 'stornvme', 'storahci', 'iaStorVD', 'iaStorAC')
    $queries = @(
        @{ Name = 'WHEA hardware errors'; Found = 'FAIL'; Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $Since } },
        @{ Name = 'Unexpected shutdowns (Kernel-Power 41)'; Found = 'FAIL'; Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $Since } },
        @{ Name = 'Bugchecks / BSOD (1001)'; Found = 'FAIL'; Filter = @{ LogName = 'System'; Id = 1001; StartTime = $Since } },
        @{ Name = 'NVIDIA driver errors (nvlddmkm)'; Found = 'FAIL'; Filter = @{ LogName = 'System'; ProviderName = 'nvlddmkm'; StartTime = $Since } },
        @{ Name = 'Display driver resets (4101)'; Found = 'FAIL'; Filter = @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $Since } },
        @{ Name = 'Disk / NVMe errors'; Found = 'FAIL'; Filter = @{ LogName = 'System'; ProviderName = $storage; Level = @(1, 2); StartTime = $Since } },
        # 129 = the driver reset the SSD after a command timed out, 153 = an I/O was retried. Logged as
        # warnings, so the error query above misses them, yet repeated ones are an early sign of a failing drive
        @{ Name = 'SSD resets and retries (129, 153)'; Found = 'WARN'; Filter = @{ LogName = 'System'; ProviderName = $storage; Id = @(129, 153); StartTime = $Since } },
        # 37 = "the speed of processor N is being limited by system firmware": normal on battery or briefly
        # under heat, worth a look if it fills the log while on the charger
        @{ Name = 'CPU limited by firmware (Kernel-Processor-Power 37)'; Found = 'INFO'; Filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = $Since } }
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
        $sinceText = $Since.ToString('yyyy-MM-dd HH:mm')
        if ($problem -and $events.Count -eq 0) {
            Add-Result 'WARN' $q.Name "could not read the event log: $problem"
        } elseif ($events.Count -eq 0) {
            $okLevel = if ($q.Found -eq 'INFO') { 'INFO' } else { 'PASS' }
            Add-Result $okLevel $q.Name "0 since $sinceText"
        } else {
            $when = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 5 | ForEach-Object { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm') }) -join ', '
            # Which event IDs, and how many of each (WHEA 17 / 19 / 47 are corrected errors, 1 / 18 fatal)
            $ids = ($events | Group-Object Id | Sort-Object Count -Descending | ForEach-Object { "ID $($_.Name) x$($_.Count)" }) -join ', '
            Add-Result $q.Found $q.Name "$($events.Count) event(s) since $sinceText ($ids). Latest: $when. Details in event_errors.csv"
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

    # Hangs Windows recovered from without a blue screen. WATCHDOG = the display driver stopped responding
    # (a GPU or VRAM fault looks like this), USBXHCI / NDIS = USB or network.
    $live = @(Get-ChildItem 'C:\Windows\LiveKernelReports' -Recurse -Filter *.dmp -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since })
    if ($live.Count -gt 0) {
        $kinds = ($live | Group-Object { $_.Directory.Name } | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
        Add-Result 'WARN' 'Recovered hangs (LiveKernelReports)' "$($live.Count) report(s): $kinds. WATCHDOG means the graphics driver hung and was restarted"
        $live | Select-Object @{ n = 'Kind'; e = { $_.Directory.Name } }, Name, LastWriteTime, Length |
            Export-Csv (Join-Path $OutDir 'live_kernel_reports.csv') -NoTypeInformation
    } else {
        Add-Result 'PASS' 'Recovered hangs (LiveKernelReports)' 'none new'
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
