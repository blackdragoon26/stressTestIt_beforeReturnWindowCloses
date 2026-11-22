# CPU: model, cores and threads. The core count catches a cheaper chip with a similar name.
Section 'CPU'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Save-Text 'cpu.txt' ($cpu | Format-List Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize, L3CacheSize, ProcessorId | Out-String)
if (-not (Test-Spec 'Cpu')) { Add-Result 'INFO' 'CPU model' $cpu.Name.Trim() }
elseif ($cpu.Name -match $Expect.Cpu) { Add-Result 'PASS' 'CPU model' $cpu.Name.Trim() }
else { Add-Result 'FAIL' 'CPU model' "got '$($cpu.Name.Trim())', expected $($Expect.Cpu)" }
if (-not (Test-Spec 'Cores')) {
    Add-Result 'INFO' 'CPU cores/threads' "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T"
} elseif ($cpu.NumberOfCores -eq $Expect.Cores -and $cpu.NumberOfLogicalProcessors -eq $Expect.Threads) {
    Add-Result 'PASS' 'CPU cores/threads' "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T"
} else {
    Add-Result 'FAIL' 'CPU cores/threads' "got $($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T, expected $($Expect.Cores)C / $($Expect.Threads)T"
}
