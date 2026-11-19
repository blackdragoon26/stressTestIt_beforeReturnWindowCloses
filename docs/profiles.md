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

The script joins the firmware model name and the board ID, for example
`VivoBook_ASUSLaptop X515DA X515DA`, and tests it against each profile's `Detect` pattern. The first match
wins. To force one: `.\omen-audit.ps1 -Laptop omen`. To force generic mode: `-Laptop generic`.

## Adding a laptop

1. Run `.\omen-audit.ps1 -Laptop generic` on the laptop. The report lists the model, board ID, CPU, GPU,
   RAM, SSD, display and battery exactly as Windows sees them.
2. Copy `profiles/asus.psd1` to `profiles/<short-name>.psd1`.
3. Fill in the values from the maker's spec sheet. Use the report to match the exact spelling Windows uses.
4. Put the pages you used in `Sources`. Where sources disagree, say so in a comment and keep that check
   lenient.
5. Run the full audit again. It should recognise the laptop and PASS everything that is genuinely right.
6. Run `tools/update-hashes.sh` and open a pull request.

## Every key

All keys are optional. A key left out means "list it, do not compare it".

| Key | Example | Compared with |
| --- | --- | --- |
| `Name` | `'HP OMEN Transcend 16-u0005TX (834T6PA)'` | Shown in the report |
| `Detect` | `'Transcend\|8BB3'` | A regex against "model board ID" |
| `ProductNumber` | `'834T6PA'` | Firmware SKU. `''` means the maker stores none |
| `Model` | `'Transcend'` | Firmware model name (regex) |
| `BoardId` | `'8BB3'` | Motherboard product code (exact) |
| `Cpu` | `'13700HX'` | CPU name (regex) |
| `Cores`, `Threads` | `16`, `24` | Core and thread counts |
| `Gpu` | `'RTX 4070'` | Display adapter names (regex). Also used by the GPU dropout check |
| `GpuVramGB` | `8` | `nvidia-smi` memory. `0` means no NVIDIA GPU |
| `RamModules`, `RamGB` | `2`, `16` | Module count and total |
| `RamMatched` | `$true` | Same part number on every module. `$false` when one is soldered |
| `RamMinMTs` | `4800` | Slowest configured module speed |
| `SsdGB` | `1000` | Internal drive size, within 10% |
| `Display` | `'2560x1600'` | The panel's native resolution |
| `DisplayMinHz` | `240` | Highest refresh rate at that resolution |
| `BatteryWh` | `97` | Battery design capacity, within 10% |
| `Pk` | `'HP\|Hewlett'` | Secure Boot Platform Key certificate (regex) |
| `GpuTempWarn` | `87` | `-Monitor`: WARN at or above this GPU temperature |
| `GpuMinWatts` | `95` | `-Monitor`: WARN if sustained full-load GPU power is lower. `0` turns it off |
| `GpuSustainedNote`, `CpuSustainedNote` | Review figures | Printed next to the `-Monitor` results |
| `Sources` | Links | Where the values came from |
| `Verified` | Text | Whether it was run on a real unit |

Profiles are PowerShell data files (`.psd1`). Windows reads them with `Import-PowerShellDataFile`, which
only allows plain values, so a profile cannot run code.
