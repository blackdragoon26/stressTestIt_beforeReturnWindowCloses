# Profiles

A profile is what one laptop model is supposed to have. With a profile, every spec is compared and any
difference is flagged. Without one, the kit runs in generic mode: specs are listed, not compared, and all
health, tamper and prior-use checks still run.

## Supported laptops

| Profile | Laptop | Status |
| --- | --- | --- |
| `omen` | HP OMEN Transcend 16-u0005TX (834T6PA), i7-13700HX, RTX 4070 | Researched, not yet run on a real unit |
| `asus` | ASUS VivoBook 15 X515DA, Ryzen 5 3500U | Verified on a real unit |

## How a profile is picked

One profile serves all three operating systems. Each script builds an ID and tests it against every
profile's `Detect` pattern (a regular expression, case-insensitive). The first match wins.

| System | ID it builds | Example |
| --- | --- | --- |
| Windows | Model name and board ID | `VivoBook_ASUSLaptop X515DA X515DA` |
| Linux | DMI product name and board name | `VivoBook_ASUSLaptop X515DA X515DA` |
| macOS | Model identifier and model name | `Mac14,10 MacBook Pro` |

To force a profile: `.\omen-audit.ps1 -Laptop omen` on Windows, `--laptop omen` on Linux and macOS. To force
generic mode, use the name `generic`.

## Adding a laptop

1. Run the audit in generic mode on the laptop (`-Laptop generic` or `--laptop generic`). The report lists
   the model, board ID, CPU, GPU, RAM, SSD, display and battery exactly as the system sees them.
2. Copy `profiles/asus.psd1` to `profiles/<short-name>.psd1`.
3. Fill in the values from the maker's spec sheet. Use the report to match the exact spelling Windows uses.
4. Put the pages you used in `Sources`. Where sources disagree, say so in a comment and keep that check
   lenient.
5. Run the full audit again. It should recognise the laptop and PASS everything that is genuinely right.
6. Run `tools/update-hashes.sh` and open a pull request.

## Every key

All keys are optional. A key left out means "list it, do not compare it".

| Key | Example | Compared with | Used on |
| --- | --- | --- | --- |
| `Name` | `'HP OMEN Transcend 16-u0005TX (834T6PA)'` | Shown in the report | All |
| `Detect` | `'Transcend\|8BB3'` | A regex against "model board ID" | All |
| `ProductNumber` | `'834T6PA'` | Firmware SKU. `''` means the maker stores none | Windows, Linux |
| `Model` | `'Transcend'` | Firmware model name (regex) | All |
| `BoardId` | `'8BB3'` | Motherboard product code (exact) | Windows, Linux |
| `Cpu` | `'13700HX'` | CPU name (regex) | All |
| `Cores`, `Threads` | `16`, `24` | Core and thread counts | All |
| `Gpu` | `'RTX 4070'` | Display adapter names (regex). Also used by the GPU dropout check | All |
| `GpuVramGB` | `8` | `nvidia-smi` memory. `0` means no NVIDIA GPU | Windows, Linux |
| `RamModules`, `RamGB` | `2`, `16` | Module count and total | All (macOS: total only) |
| `RamMatched` | `$true` | Same part number on every module. `$false` when one is soldered | Windows, Linux |
| `RamMinMTs` | `4800` | Slowest configured module speed | Windows, Linux |
| `UpgradeNote` | Text | Printed with the RAM upgrade room: slots, soldered memory, SSD slots | Windows |
| `SsdGB` | `1000` | Internal drive size, within 10% | All |
| `SsdMinReadMBs` | `1500` | Uncached sequential read speed of the system drive. WARN if slower | Windows |
| `Display` | `'2560x1600'` | The panel's native resolution | All |
| `DisplayMinHz` | `240` | Highest refresh rate at that resolution | Windows |
| `Panel` | `'AUO.?A3A6'` | Panel maker and product code from EDID (regex). WARN only | Windows |
| `BatteryWh` | `97` | Battery design capacity, within 10% | Windows, Linux |
| `Pk` | `'HP\|Hewlett'` | Secure Boot Platform Key certificate (regex) | Windows, Linux |
| `GpuTempWarn` | `87` | `-Monitor`: WARN at or above this GPU temperature | Windows |
| `GpuMinWatts` | `95` | `-Monitor`: WARN if sustained full-load GPU power is lower. `0` turns it off | Windows |
| `GpuSustainedNote`, `CpuSustainedNote` | Review figures | Printed next to the `-Monitor` results | Windows |
| `Sources` | Links | Where the values came from | Docs only |
| `Verified` | Text | Whether it was run on a real unit | Docs only |

Profiles are PowerShell data files (`.psd1`). Windows reads them with `Import-PowerShellDataFile`, which
only allows plain values, so a profile cannot run code. Linux and macOS read only the simple
`Key = value` lines, so keep every spec on one line of its own.
