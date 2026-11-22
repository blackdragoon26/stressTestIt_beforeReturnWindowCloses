# Firmware security: Secure Boot and its keys, BIOS passwords, TPM, HP BIOS settings.
Section 'Firmware security'
try {
    if (Confirm-SecureBootUEFI) { Add-Result 'PASS' 'Secure Boot' 'enabled' } else { Add-Result 'FAIL' 'Secure Boot' 'disabled' }
} catch { Add-Result 'FAIL' 'Secure Boot' 'not supported or legacy boot' }

# The Platform Key (PK) is the root of Secure Boot and should belong to the laptop maker.
# Certificate names are plain ASCII inside the key bytes, so a text search is enough.
# "DO NOT TRUST" / "DO NOT SHIP" = a leaked test key (PKfail, 2024): anyone can sign boot code.
try {
    $pkText  = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name PK).Bytes)
    $kekText = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name KEK).Bytes)
    $names = @([regex]::Matches($pkText + $kekText, '[ -~]{6,}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    Save-Text 'secureboot_keys.txt' (@('Readable strings in PK and KEK:') + $names)
    $pkStrings = @([regex]::Matches($pkText, '[ -~]{6,}') | ForEach-Object { $_.Value })
    $pkName = $pkStrings | Where-Object { $_ -match 'PK|Key|Cert|Secure Boot' } | Select-Object -First 1
    if (($names -join "`n") -match 'DO NOT (TRUST|SHIP)') { Add-Result 'FAIL' 'Secure Boot keys' 'test key found (PKfail), see secureboot_keys.txt' }
    else {
        # Generic mode: the key should name the laptop's maker (first word of the manufacturer, e.g. HP, LENOVO, Dell)
        $pkWant = if (Test-Spec 'Pk') { $Expect.Pk } else { [regex]::Escape((("$($csInfo.Manufacturer)" -split '\s+')[0])) }
        if ($pkWant -and (($pkStrings -join "`n") -match $pkWant)) { Add-Result 'PASS' 'Secure Boot keys' "PK: $pkName" }
        else { Add-Result 'WARN' 'Secure Boot keys' "PK '$pkName' does not name the maker ($pkWant). Custom keys? Check BIOS and secureboot_keys.txt" }
    }
} catch { Add-Result 'WARN' 'Secure Boot keys' 'could not read PK (empty, setup mode, or legacy boot). Check BIOS' }

# BIOS passwords: a password set by someone else locks you out of BIOS settings and updates.
# HP exposes this through its BIOS WMI interface; other brands do not have it.
$hpPw = @(Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSPassword -ErrorAction SilentlyContinue)
if ($hpPw.Count -gt 0) {
    Save-Text 'bios_passwords.txt' ($hpPw | Select-Object Name, IsSet | Format-Table -AutoSize | Out-String)
    $set = @($hpPw | Where-Object { $_.IsSet -eq 1 })
    if ($set.Count -gt 0) { Add-Result 'FAIL' 'BIOS passwords' ("set: " + (($set.Name) -join ', ') + '. Ask the seller to remove them or reject the unit') }
    else { Add-Result 'PASS' 'BIOS passwords' 'none set' }
} else {
    Add-Result 'INFO' 'BIOS passwords' 'only HP exposes this to Windows. Check in BIOS setup that no password is set'
}

# Every HP BIOS setting with its current value, for the record (read only)
$hpSet = @(Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSEnumeration -ErrorAction SilentlyContinue)
if ($hpSet.Count -gt 0) {
    Save-Text 'hp_bios_settings.txt' ($hpSet | Sort-Object Name | Format-Table Name, CurrentValue -AutoSize | Out-String -Width 300)
    Add-Result 'INFO' 'HP BIOS settings' "$($hpSet.Count) settings saved to hp_bios_settings.txt. HP's own hardware test: restart, press F2 at the logo, run the extensive test"
}

$tpm = Get-Tpm -ErrorAction SilentlyContinue
if ($tpm -and $tpm.TpmPresent -and $tpm.TpmReady) { Add-Result 'PASS' 'TPM' "present and ready (owned: $($tpm.TpmOwned))" }
else { Add-Result 'WARN' 'TPM' 'not present or not ready. Check BIOS' }
Save-Text 'tpm.txt' ($tpm | Format-List * | Out-String)
Save-Text 'bitlocker.txt' (manage-bde -status 2>&1)
