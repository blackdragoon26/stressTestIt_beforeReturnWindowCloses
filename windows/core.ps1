# Shared helpers for every component: results, saving raw output, small conversions.
# Dot-sourced by omen-audit.ps1, so these live in the script's scope. Pure ASCII (Windows PowerShell 5.1).

function Add-Result {
    param([string]$Level, [string]$Check, [string]$Detail)
    $line = '{0,-5} {1} : {2}' -f $Level, $Check, $Detail
    $Summary.Add($line)
    $color = switch ($Level) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
}

function Save-Text {
    param([string]$Name, $Content)
    $Content | Out-File -FilePath (Join-Path $OutDir $Name) -Encoding utf8 -Width 400
}

function ConvertTo-Num([string]$s) {
    if ($null -eq $s) { return $null }
    $d = 0.0
    if ([double]::TryParse($s.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}

function Get-Median($vals) {
    $s = @($vals | Where-Object { "$_" -ne '' } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($s.Count -eq 0) { return $null }
    return $s[[int][math]::Floor(($s.Count - 1) / 2)]
}

function Find-NvidiaSmi {
    $s = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $s -and (Test-Path 'C:\Windows\System32\nvidia-smi.exe')) { $s = 'C:\Windows\System32\nvidia-smi.exe' }
    return $s
}

function Section { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

function Test-Spec([string]$Key) { return $Expect.ContainsKey($Key) }   # does the profile define this value?

# Text from WMI arrays of character codes (monitor names and serials). Empty or missing gives ''.
function Get-WmiText($arr) {
    if (-not $arr) { return '' }
    return ((@($arr) | Where-Object { [int]$_ -ne 0 } | ForEach-Object { [char][int]$_ }) -join '').Trim()
}

# Asks a yes / no question in the console. Returns $true for yes.
function Read-YesNo([string]$Question) {
    while ($true) {
        $a = "$(Read-Host "$Question [y/n]")".Trim().ToLower()
        if ($a -eq 'y' -or $a -eq 'yes') { return $true }
        if ($a -eq 'n' -or $a -eq 'no') { return $false }
    }
}

# The SHA-256 of every file the kit runs, so a report says exactly which code produced it
function Get-KitHashes {
    $rel = @('omen-audit.ps1') + @($KitComponents | ForEach-Object { "windows/$_.ps1" }) +
           @(Get-ChildItem (Join-Path $KitRoot 'profiles') -Filter *.psd1 -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "profiles/$($_.Name)" })
    foreach ($r in $rel) {
        $p = Join-Path $KitRoot ($r -replace '/', '\')
        $h = if (Test-Path $p) { try { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() } catch { 'unreadable' } } else { 'missing' }
        [pscustomobject]@{ File = $r; Sha256 = $h }
    }
}
