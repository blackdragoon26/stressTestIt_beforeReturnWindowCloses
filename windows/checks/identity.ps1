# Identity: is this the laptop on the invoice? Serial, product number, model, board ID, BIOS.
Section 'Identity'
$cs   = Get-CimInstance Win32_ComputerSystem
$csp  = Get-CimInstance Win32_ComputerSystemProduct
$bios = Get-CimInstance Win32_BIOS
$bb   = Get-CimInstance Win32_BaseBoard
$identity = [ordered]@{
    Manufacturer     = $cs.Manufacturer
    Model            = $cs.Model
    SystemSKU        = $cs.SystemSKUNumber
    SerialNumber     = $bios.SerialNumber
    ProductName      = $csp.Name
    UUID             = $csp.UUID
    BaseBoardProduct = $bb.Product
    BaseBoardSerial  = $bb.SerialNumber
    BIOSVersion      = $bios.SMBIOSBIOSVersion
    BIOSReleaseDate  = $bios.ReleaseDate
}
Save-Text 'identity.txt' ($identity.GetEnumerator() | ForEach-Object { '{0,-18} {1}' -f $_.Key, $_.Value })

# Serial: the script cannot see the invoice, so it asks for the number once and compares it itself
$serial = "$($bios.SerialNumber)".Trim()
$typed  = $InvoiceSerial
if (-not $typed) {
    try { $typed = Read-Host 'Type the serial number from the invoice (or press Enter to skip)' } catch { }
}
if ($typed) {
    if ($typed.Trim() -ieq $serial) { Add-Result 'PASS' 'Serial number' "$serial matches the invoice" }
    else { Add-Result 'FAIL' 'Serial number' "BIOS says '$serial', invoice says '$($typed.Trim())'" }
} else {
    Add-Result 'INFO' 'Serial number' "$serial (not compared: no invoice serial typed)"
}
Add-Result 'INFO' 'BIOS version' "$($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"

$sku = "$($cs.SystemSKUNumber)".Trim()
$skuText = if ($sku) { $sku } else { '(none stored)' }
if (-not (Test-Spec 'ProductNumber')) { Add-Result 'INFO' 'Product number' $skuText }
elseif (-not $Expect.ProductNumber) { Add-Result 'INFO' 'Product number' "this model's firmware stores none" }
elseif ($sku -match $Expect.ProductNumber) { Add-Result 'PASS' 'Product number' $sku }
else { Add-Result 'FAIL' 'Product number' "got $skuText, expected $($Expect.ProductNumber)" }

if (-not (Test-Spec 'Model')) { Add-Result 'INFO' 'Model' "$($cs.Manufacturer) $($cs.Model)" }
elseif ($cs.Model -match $Expect.Model) { Add-Result 'PASS' 'Model' $cs.Model }
else { Add-Result 'FAIL' 'Model' "got '$($cs.Model)', expected $($Expect.Model)" }

if (-not (Test-Spec 'BoardId')) { Add-Result 'INFO' 'Board ID' $bb.Product }
elseif ($bb.Product -eq $Expect.BoardId) { Add-Result 'PASS' 'Board ID' $bb.Product }
else { Add-Result 'WARN' 'Board ID' "got '$($bb.Product)', expected $($Expect.BoardId). Ask the maker or the seller why it differs" }

if ($bios.SerialNumber -and $bb.SerialNumber -and ($bb.SerialNumber -notmatch [regex]::Escape($bios.SerialNumber))) {
    Add-Result 'INFO' 'Board serial' "board serial '$($bb.SerialNumber)' differs from system serial (normal on most laptops, record it)"
}
if ("$($cs.Manufacturer)" -match 'HP|Hewlett') {
    Add-Result 'INFO' 'Warranty' "check serial $serial at support.hp.com (Check warranty): the start date shows when the unit was first sold"
}
