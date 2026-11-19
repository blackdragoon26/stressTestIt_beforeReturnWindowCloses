# Every check

What the full audit, `-Quick` and `-Monitor` look at, and when each one passes, warns or fails.
"Profile" means the expected values for the laptop model ([Profiles](profiles.md)). In generic mode, the
checks marked *spec* only list what they find.

## Identity: is it the laptop on the invoice?

| Check | Reads | Result |
| --- | --- | --- |
| Serial number | BIOS serial, compared with the one you type from the invoice | FAIL if they differ |
| Product number | Firmware SKU (HP stores it, ASUS does not) | *spec*: FAIL if it differs |
| Model | Firmware model name | *spec*: FAIL if it differs |
| Board ID | Motherboard product code | *spec*: WARN if it differs (possible board swap) |
| BIOS version, board serial | Firmware | INFO |

## Genuine parts: is everything inside what was promised?

| Check | Reads | Result |
| --- | --- | --- |
| CPU model, cores, threads | Windows CPU info | *spec*: FAIL. Core count catches a cheaper chip with a similar name (13700H vs 13700HX) |
| GPU model | Windows display adapters | *spec*: FAIL |
| GPU memory | `nvidia-smi` (comes with the NVIDIA driver) | *spec*: FAIL |
| Display resolution and refresh | The panel's own mode list (EDID) | *spec*: resolution FAIL (replaced panel), refresh WARN |
| RAM layout, matched pair, speed | Each module's part number and speed | *spec*: layout FAIL, mismatch WARN, slow WARN |
| RAM upgrade room | Slots and firmware maximum | INFO |
| SSD size | Internal drives, in the GB printed on the box | *spec*: FAIL (swapped drive) |
| Battery model | Design capacity in Wh | *spec*: WARN (replaced battery) |
| Webcam, Wi-Fi, Bluetooth | Working devices | FAIL if missing |

## Prior use: how much has it really been used?

| Check | Reads | Result |
| --- | --- | --- |
| SSD health | The NVMe health log, read straight from the drive: power-on hours, TB written, wear, media errors, unsafe shutdowns | FAIL on media errors or a critical warning. WARN above 100 hours, or if hours cannot be read |
| Battery | Full charge against design capacity, cycle count | WARN under 95% or above 10 cycles |
| Event logs (last 30 days) | Hardware errors, crashes and unexpected shutdowns before you got it | See "Stability" |

The SSD's power-on hours are the strongest proof of prior use. Windows' own storage counters often leave
them blank, so the kit reads the drive's health log directly, the same data `smartctl` shows on Linux.

## Tampering: has someone changed it?

| Check | Reads | Result |
| --- | --- | --- |
| Secure Boot | Firmware state | FAIL if off |
| Secure Boot keys | The Platform Key certificate | FAIL on a leaked test key ("DO NOT TRUST", the 2024 PKfail issue). WARN if it does not name the maker |
| BIOS passwords | HP's BIOS interface (HP only) | FAIL if a password is set |
| TPM | Windows TPM status | WARN if missing or not ready |
| Boot entries | `bcdedit` | Saved for review |
| Windows key and activation | Key stored in firmware, activation status | WARN if missing |
| Company join, MDM enrollment | `dsregcmd`, enrollment registry | FAIL if enrolled (a company can lock or wipe it) |
| Local admins, unsigned drivers | Accounts, driver signatures | INFO / WARN |
| Installed software, startup items, scheduled tasks | Registry and Task Scheduler | Saved for review |

## Stability: is anything failing?

Checked by the full audit (last 30 days), by `-Quick` (since the last quick run) and by `-Monitor`
(during the test).

| Check | Result |
| --- | --- |
| WHEA hardware errors | FAIL |
| Unexpected shutdowns (Kernel-Power 41) | FAIL, with the dates |
| Blue screens (bugcheck 1001), new crash dumps | FAIL |
| NVIDIA driver errors, display driver resets (4101) | FAIL |
| Disk and NVMe errors | FAIL |
| Devices with driver errors | FAIL |
| Dedicated GPU still present | FAIL if it vanished |

## Under load (`-Monitor`)

| Check | Result |
| --- | --- |
| GPU answers in every sample | FAIL if it stops (GPU dropout) |
| GPU hardware slowdown (thermal or power brake) | WARN |
| GPU temperature | WARN at 87 C or above (profile can change it) |
| Sustained GPU power at full load | *spec*: WARN below the profile's minimum (weak cooling or wrong charger) |
| Samples taken on battery | WARN |
| CPU sustained clock and firmware limit | INFO |
| Board thermal zone | WARN at 100 C |

Fan speed and CPU package power are not exposed by Windows. Use HWiNFO64 for those.

## Every report also contains

- Every part with its exact model and serial number (the hardware inventory).
- The script's own SHA-256, so you know which version produced it.
- Any script errors, at the end, for debugging.
