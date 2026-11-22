# Verified video memory test (-GpuTest): memtest_vulkan by GpuZelenograd (zlib license,
# github.com/GpuZelenograd/memtest_vulkan). It fills the GPU's memory with patterns through Vulkan
# compute, reads them back and counts every wrong bit, the way gpu-burn checks its results. Works on
# NVIDIA, AMD and Intel GPUs with the normal graphics driver; nothing is installed.
#
# The kit downloads one exact release and checks its SHA-256 before running it. Started as
# "memtest_vulkan.exe 1" it tests device 1 without asking questions (it lists dedicated GPUs first),
# writes memtest_vulkan.log into the report folder, and runs until stopped.

$MemtestVulkan = @{
    Version = '0.5.0'
    File    = 'memtest_vulkan-v0.5.0.exe'
    Url     = 'https://github.com/GpuZelenograd/memtest_vulkan/releases/download/v0.5.0/memtest_vulkan-v0.5.0.exe'
    Sha256  = '09e67704210762ae8d8ad70fe6d71275eefbe815cc2c0658cd5afc8e231d0df6'
}

function Get-MemtestVulkan {
    $dir = Join-Path $KitRoot 'tools'
    $exe = Join-Path $dir $MemtestVulkan.File
    if (-not (Test-Path $exe)) {
        Write-Host "Downloading memtest_vulkan v$($MemtestVulkan.Version) (600 KB) from github.com/GpuZelenograd..."
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest $MemtestVulkan.Url -OutFile "$exe.part" -UseBasicParsing
            Move-Item "$exe.part" $exe -Force
        } catch {
            Remove-Item "$exe.part" -Force -ErrorAction SilentlyContinue
            return @{ Error = "download failed: $($_.Exception.Message). Download $($MemtestVulkan.Url) yourself and put it in $dir" }
        }
    }
    $h = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $MemtestVulkan.Sha256) {
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        return @{ Error = "the downloaded file's SHA-256 ($h) is not the published one ($($MemtestVulkan.Sha256)). Deleted, not run" }
    }
    return @{ Exe = $exe }
}

function Start-GpuMemTest {
    $got = Get-MemtestVulkan
    if ($got.Error) { Add-Result 'WARN' 'GPU memory test' $got.Error; return $null }
    try { Unblock-File $got.Exe -ErrorAction SilentlyContinue } catch { }
    $p = Start-Process -FilePath $got.Exe -ArgumentList '1' -WorkingDirectory $OutDir -WindowStyle Hidden -PassThru
    Write-Host "GPU memory test running (memtest_vulkan, process $($p.Id))"
    return [pscustomobject]@{ Process = $p; Started = Get-Date; Log = (Join-Path $OutDir 'memtest_vulkan.log') }
}

# Reads the log while the test runs or after it. The tool locks the file for a moment while it writes.
function Read-GpuMemTestLog($Run) {
    $text = $null
    for ($i = 0; $i -lt 5 -and $null -eq $text; $i++) {
        try {
            $fs = [IO.File]::Open($Run.Log, 'Open', 'Read', 'ReadWrite')
            try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
        } catch { Start-Sleep -Milliseconds 200 }
    }
    $lines = @("$text" -split "`r?`n")
    $iter = @($lines | Where-Object { $_ -match '^\s*\d+ iteration\.' })
    $last = $iter | Select-Object -Last 1
    $checked = if ($last -match 'checked:\s*([\d.]+)GB') { [double]$Matches[1] } else { 0 }
    $device = ($lines | Where-Object { $_ -match '^Standard 5-minute test of ' } | Select-Object -First 1) -replace '^Standard 5-minute test of ', ''
    return [pscustomobject]@{
        Lines      = $lines
        Errors     = @($lines | Where-Object { $_ -match '^Error found' }).Count
        Iterations = $iter.Count
        CheckedGB  = $checked
        Device     = "$device".Trim()
        Standard   = [bool]($lines | Where-Object { $_ -match 'Standard 5-minute test PASSed' })
        Failed     = [bool]($lines | Where-Object { $_ -match 'Standard 5-minute test fail|ERRORS FOUND' })
        Runtime    = ($lines | Where-Object { $_ -match 'Runtime error|ERROR_DEVICE_LOST|early exit during init|INIT OR FIRST testing failed' } | Select-Object -First 1)
    }
}

function Stop-GpuMemTest($Run, [bool]$ExitedEarly) {
    if (-not $Run) { return }
    $exitedEarly = $ExitedEarly
    if (-not $Run.Process.HasExited) { & taskkill.exe /PID $Run.Process.Id /T /F 2>&1 | Out-Null }
    Start-Sleep -Seconds 1
    $minutes = [math]::Round(((Get-Date) - $Run.Started).TotalMinutes, 1)
    if (-not (Test-Path $Run.Log)) { Add-Result 'WARN' 'GPU memory test' 'memtest_vulkan wrote no log: it did not start. Is the graphics driver installed?'; return }
    $r = Read-GpuMemTestLog $Run
    $dev = if ($r.Device) { $r.Device } else { 'unknown device' }
    if ($r.Errors -gt 0 -or $r.Failed) {
        Add-Result 'FAIL' 'GPU memory test' "$($r.Errors) error report(s) from memtest_vulkan on $dev. The video memory returned wrong data: a VRAM or GPU fault. See memtest_vulkan.log"
    } elseif ($r.Runtime) {
        Add-Result 'FAIL' 'GPU memory test' "the test stopped with '$($r.Runtime.Trim())' after $minutes min on $dev. A GPU that drops out under load is a fault; check event_errors.csv"
    } elseif ($exitedEarly) {
        Add-Result 'WARN' 'GPU memory test' "memtest_vulkan exited on its own after $minutes min. See memtest_vulkan.log"
    } elseif ($r.Iterations -eq 0) {
        Add-Result 'WARN' 'GPU memory test' "no test round finished in $minutes min. See memtest_vulkan.log"
    } elseif (-not $r.Standard) {
        Add-Result 'WARN' 'GPU memory test' "no errors in $minutes min ($($r.CheckedGB) GB checked on $dev), but the standard 5-minute test did not finish. Run at least 6 minutes"
    } else {
        Add-Result 'PASS' 'GPU memory test' "no errors in $minutes min: $($r.CheckedGB) GB of video memory checked on $dev, standard 5-minute test passed"
    }
    # It should have tested the GPU the profile expects (the dedicated one)
    if ($r.Device -and (Test-Spec 'Gpu') -and $r.Device -notmatch $Expect.Gpu) {
        Add-Result 'WARN' 'GPU memory test device' "tested '$($r.Device)', expected the $($Expect.Gpu). Is the dedicated GPU missing or disabled?"
    }
}
