<#
.SYNOPSIS
  SecondTrust laptop audit for Windows: is this the machine the listing promised, untampered, how used
  is it, and does it hold up under load? Built for the dead-on-arrival window of an HP OMEN Transcend 16;
  works on any Windows laptop. Laptop profiles (expected specs) live in .\profiles.

.DESCRIPTION
  This file only starts things. Every check is its own file under .\windows (see windows\README.md):
    full audit (default)  windows\checks\*.ps1, in the order listed below
    -Quick                event logs since the last quick run (every evening of the soak)
    -Monitor              sensor log while you run your own stress test (OCCT, a game)
    -Stress               verified CPU and RAM load plus the sensor log: every result is checked
    -GpuTest              verified video memory test (memtest_vulkan) plus the sensor log
    -Interactive          hands-on tests: screen, keyboard, touchpad, speakers, mic, webcam, ports
  -Stress and -GpuTest can run together. Every run writes a folder under .\reports with a PDF report,
  SUMMARY.txt and a SHA-256 manifest, so the evidence can be shown to be unchanged later.

.EXAMPLE
  In an administrator PowerShell, inside the kit folder:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\omen-audit.ps1
    .\omen-audit.ps1 -Stress -Minutes 30
    .\omen-audit.ps1 -Stress -GpuTest -Minutes 60
    .\omen-audit.ps1 -Interactive
    .\omen-audit.ps1 -Only storage,battery
#>
[CmdletBinding()]
param(
    [switch]$Quick,
    [switch]$Monitor,
    [switch]$Stress,
    [switch]$GpuTest,
    [switch]$Interactive,
    [int]$Minutes = 60,           # -Monitor, -Stress, -GpuTest: how long
    [int]$IntervalSec = 2,        # seconds between sensor samples
    [int]$StressMemoryPct = 50,   # -Stress: share of the free RAM to test
    # Full audit: run only these checks, for example -Only storage,battery (names below)
    [string[]]$Only,
    # Which profile to check against: 'auto' (recognise it from the model name and board ID),
    # a file name from .\profiles without .psd1 (for example 'omen'), or 'generic' (no spec comparison).
    [string]$Laptop = 'auto',
    # Serial number printed on the invoice or box. If left out, the full audit asks for it.
    [string]$InvoiceSerial,
    [string]$OutRoot = (Join-Path $PSScriptRoot 'reports'),
    [int]$EventDays = 30
)

$ErrorActionPreference = 'Continue'
$KitRoot = $PSScriptRoot
$Kit = Join-Path $KitRoot 'windows'

# The full audit, in order. Each name is a file in windows\checks. A fixed list, not every file in the
# folder, so a stale file left over from an older download can never run.
$FullChecks = @('identity', 'cpu', 'gpu', 'display', 'memory', 'storage', 'battery', 'firmware', 'kernel',
                'license', 'ownership', 'devices', 'software', 'inventory', 'msinfo', 'eventlogs')
# Everything the kit runs, for the fingerprints in each report
$KitComponents = @('core', 'profile', 'nvme', 'diskspeed', 'events', 'monitor', 'stress', 'gpumemtest', 'interactive', 'report') +
                 @($FullChecks | ForEach-Object { "checks/$_" })

foreach ($f in @($KitComponents | ForEach-Object { Join-Path $Kit "$($_ -replace '/', '\').ps1" })) {
    if (-not (Test-Path $f)) {
        Write-Host "Missing kit file: $f. Paste the setup block again to download the whole kit." -ForegroundColor Red
        exit 1
    }
}

. (Join-Path $Kit 'core.ps1')

# ---------- which mode ----------
$loadMode = $Monitor -or $Stress -or $GpuTest
if ((@([bool]$Quick, [bool]$loadMode, [bool]$Interactive, [bool]$Only) | Where-Object { $_ }).Count -gt 1) {
    Write-Host 'Use one of -Quick, -Monitor / -Stress / -GpuTest, -Interactive or -Only at a time.' -ForegroundColor Red
    exit 1
}
if ($Only) {
    $Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    $unknown = @($Only | Where-Object { $FullChecks -notcontains $_ })
    if ($unknown.Count -gt 0) {
        Write-Host "Unknown check: $($unknown -join ', '). Choose from: $($FullChecks -join ', ')" -ForegroundColor Red
        exit 1
    }
}
if ($GpuTest -and $Minutes -lt 6) {
    Write-Host 'The GPU memory test needs at least 6 minutes (its standard test takes 5). Running 6.' -ForegroundColor Yellow
    $Minutes = 6
}
$mode = if ($Quick) { 'quick' }
        elseif ($Stress -and $GpuTest) { 'stress-gpu' }
        elseif ($Stress) { 'stress' }
        elseif ($GpuTest) { 'gputest' }
        elseif ($Monitor) { 'monitor' }
        elseif ($Interactive) { 'interactive' }
        elseif ($Only) { 'partial' }
        else { 'full' }

# ---------- setup ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Run this script from an administrator PowerShell.' -ForegroundColor Red
    exit 1
}

. (Join-Path $Kit 'profile.ps1')

$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$OutDir = Join-Path $OutRoot "$($env:COMPUTERNAME)_$($mode)_$stamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Start-Transcript -Path (Join-Path $OutDir 'transcript.txt') | Out-Null
$Summary = New-Object System.Collections.Generic.List[string]

if ($IsGeneric -and $how -like 'not recognised*') {
    Add-Result 'WARN' 'Laptop profile' "$how. Specs are listed, not compared. All health, tamper and prior-use checks still run. To compare, add a profile (docs\profiles.md) or force one with -Laptop"
} else {
    Add-Result 'INFO' 'Laptop profile' "$($Expect.Name), $how"
}

# Which exact code produced this report. Compare kit_files.csv with docs/SHA256SUMS.txt in the repo.
$kitHashes = @(Get-KitHashes)
$kitHashes | Export-Csv (Join-Path $OutDir 'kit_files.csv') -NoTypeInformation
$sha = [Security.Cryptography.SHA256]::Create()
$KitFingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes((($kitHashes | ForEach-Object { "$($_.Sha256)  $($_.File)" }) -join "`n")))) -replace '-', '').ToLower().Substring(0, 16)
Add-Result 'INFO' 'Script version' "kit fingerprint $KitFingerprint, $($kitHashes.Count) files (each listed in kit_files.csv)"
# The download also carries the published list: a difference means an edited or half-updated kit
$sumsFile = Join-Path $KitRoot 'docs\SHA256SUMS.txt'
if (Test-Path $sumsFile) {
    $published = @{}
    foreach ($l in (Get-Content $sumsFile)) { if ($l -match '^([0-9a-f]{64})\s+(\S+)') { $published[$Matches[2]] = $Matches[1] } }
    $diff = @($kitHashes | Where-Object { $published.ContainsKey($_.File) -and $published[$_.File] -ne $_.Sha256 } | ForEach-Object { $_.File })
    if ($diff.Count -gt 0) { Add-Result 'WARN' 'Kit files' "differ from docs\SHA256SUMS.txt: $($diff -join ', '). Edited by someone, or a partial update: paste the setup block again" }
    else { Add-Result 'PASS' 'Kit files' 'every file matches the fingerprint list that came with the download' }
}

# ---------- run ----------
. (Join-Path $Kit 'nvme.ps1')
. (Join-Path $Kit 'diskspeed.ps1')
. (Join-Path $Kit 'events.ps1')

# Each component runs inside its own guard: if one crashes, the error is recorded and the rest still run.
# Dot-sourcing here, at the top level of this script, keeps every component in the same scope.
$run = if ($Quick) { @() } elseif ($loadMode) { @() } elseif ($Interactive) { @() } elseif ($Only) { $Only } else { $FullChecks }
try {
    if ($Quick) {
        Section 'Quick soak check'
        $marker = Join-Path $OutRoot 'last_quick_run.txt'
        $since  = (Get-Date).AddHours(-24)
        if (Test-Path $marker) {
            try { $since = [datetime]::Parse((Get-Content $marker -Raw).Trim()) } catch { }
        }
        Test-EventLogs -Since $since
        (Get-Date).ToString('o') | Out-File $marker -Encoding ascii
    }
    elseif ($loadMode) {
        . (Join-Path $Kit 'stress.ps1')
        . (Join-Path $Kit 'gpumemtest.ps1')
        . (Join-Path $Kit 'monitor.ps1')
    }
    elseif ($Interactive) {
        . (Join-Path $Kit 'interactive.ps1')
    }
} catch {
    Add-Result 'WARN' 'Script error' "a script problem, not a laptop fault: $($_.Exception.Message) ($(Split-Path "$($_.InvocationInfo.ScriptName)" -Leaf) line $($_.InvocationInfo.ScriptLineNumber)). The report shows what was collected"
}
foreach ($c in $run) {
    try { . (Join-Path $Kit "checks\$c.ps1") }
    catch {
        Add-Result 'WARN' 'Script error' "in the $c check, a script problem, not a laptop fault: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber)). The other checks still ran"
    }
}

. (Join-Path $Kit 'report.ps1')
