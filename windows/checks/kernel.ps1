# Kernel and boot integrity: has someone weakened what Windows loads at boot?
# Boot flags that let unsigned or debug code into the kernel, memory integrity, and the signature of
# every kernel driver that is running right now.
Section 'Kernel and boot integrity'
Save-Text 'bcdedit.txt' (bcdedit /enum all 2>&1)
$cur = @(bcdedit /enum '{current}' 2>&1 | ForEach-Object { "$_" })
$flags = [ordered]@{
    'testsigning'        = 'test signing: kernel drivers load without a trusted signature'
    'nointegritychecks'  = 'driver signature checks are off'
    'debug'              = 'kernel debugging is on'
    'bootdebug'          = 'boot debugging is on'
    'disableelamdrivers' = 'early-launch anti-malware is off'
}
$bad = @(foreach ($k in $flags.Keys) { if ($cur -match "^\s*$k\s+(Yes|On|1)\b") { $flags[$k] } })
if ($cur.Count -lt 3) { Add-Result 'WARN' 'Boot flags' 'bcdedit gave no boot entry. Check bcdedit.txt' }
elseif ($bad.Count -gt 0) { Add-Result 'FAIL' 'Boot flags' (($bad -join '; ') + '. Not a factory setting: someone changed it') }
else { Add-Result 'PASS' 'Boot flags' 'no test signing, signature bypass or debugging in the current boot entry' }
Add-Result 'INFO' 'Boot entries' 'saved bcdedit.txt. Look for entries you do not recognise'

# Memory integrity (HVCI) and virtualization-based security, as Windows reports them
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
if ($dg) {
    Save-Text 'deviceguard.txt' ($dg | Format-List * | Out-String)
    $vbs  = switch ([int]$dg.VirtualizationBasedSecurityStatus) { 2 { 'running' } 1 { 'enabled, not running' } default { 'off' } }
    $hvci = if (@($dg.SecurityServicesRunning) -contains 2) { 'on' } else { 'off' }
    Add-Result 'INFO' 'Memory integrity' "virtualization-based security $vbs, memory integrity (HVCI) $hvci"
}

# Every running kernel driver should carry a valid signature (Authenticode or a Windows catalog)
Write-Host 'Checking the signature of every running kernel driver (up to a minute)...'
$rows = foreach ($d in @(Get-CimInstance Win32_SystemDriver -Filter "State='Running'" -ErrorAction SilentlyContinue)) {
    $p = "$($d.PathName)" -replace '^\\\?\?\\', '' -replace '^\\SystemRoot\\', "$env:windir\" -replace '^(?i)system32\\', "$env:windir\System32\"
    $p = $p.Trim('"')
    $st = 'NotFound'; $signer = ''
    if ($p -and (Test-Path -LiteralPath $p)) {
        try {
            $s = Get-AuthenticodeSignature -LiteralPath $p -ErrorAction Stop
            $st = "$($s.Status)"
            if ($s.SignerCertificate) { $signer = ($s.SignerCertificate.Subject -replace '^CN=([^,]+).*$', '$1') }
        } catch { $st = 'Unreadable' }
    }
    [pscustomobject]@{ Name = $d.Name; Status = $st; Signer = $signer; Path = $p }
}
$rows = @($rows)
$rows | Sort-Object Status, Name | Export-Csv (Join-Path $OutDir 'kernel_drivers.csv') -NoTypeInformation
$unsigned = @($rows | Where-Object { $_.Status -notin 'Valid', 'NotFound' })
$missing  = @($rows | Where-Object { $_.Status -eq 'NotFound' })
if ($rows.Count -eq 0) { Add-Result 'WARN' 'Kernel driver signatures' 'could not list the running drivers' }
elseif ($unsigned.Count -gt 0) { Add-Result 'WARN' 'Kernel driver signatures' "$($unsigned.Count) of $($rows.Count) running drivers without a valid signature: $((($unsigned | ForEach-Object { "$($_.Name) ($($_.Status))" }) -join ', ')). See kernel_drivers.csv" }
else { Add-Result 'PASS' 'Kernel driver signatures' "all $($rows.Count - $missing.Count) running drivers with a file on disk are validly signed" }
