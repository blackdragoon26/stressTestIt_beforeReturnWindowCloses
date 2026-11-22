# GPU: model and video memory. nvidia-smi comes with the NVIDIA driver.
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
