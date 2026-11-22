# Windows license: the OEM key in firmware and activation.
Section 'Windows license'
$sls = Get-CimInstance SoftwareLicensingService
$oa3 = $sls.OA3xOriginalProductKey
if ($oa3) { Add-Result 'PASS' 'OEM key in firmware' ("present (ends -{0})" -f $oa3.Substring($oa3.Length - 5)) }
else { Add-Result 'WARN' 'OEM key in firmware' 'none found. Most laptops sold with Windows have one' }
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
    Where-Object { $_.Name -like 'Windows*' } | Select-Object -First 1
if ($lic) {
    if ($lic.LicenseStatus -eq 1) { Add-Result 'PASS' 'Windows activation' "$($lic.Name) / $($lic.Description)" }
    else { Add-Result 'WARN' 'Windows activation' "status $($lic.LicenseStatus): $($lic.Description)" }
}
