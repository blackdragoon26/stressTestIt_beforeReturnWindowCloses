# Every check

What each check reads, and when it passes, warns or fails. Open a section to see its checks. Checks marked
*spec* compare against the laptop's [profile](profiles.md); in generic mode they only list what they find.

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
| Display panel | The panel's maker and product code (EDID), for example `AUO A3A6` | *spec*: WARN if it differs (makers use more than one supplier) |
| RAM layout, matched pair, speed | Each module's part number and speed | *spec*: layout FAIL, mismatch WARN, slow WARN |
| RAM upgrade room | Slots and firmware maximum | INFO |
| SSD size | Internal drives, in the GB printed on the box | *spec*: FAIL (swapped drive) |
| SSD speed | 1 GB written and read back with the file cache bypassed | FAIL if data reads back wrong. WARN below the profile's minimum read speed (800 MB/s for NVMe without one) |
| PCIe links | Lanes in use against lanes supported, for the SSD and the GPU | WARN if the SSD runs on fewer lanes (a bad seat or slot) |
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
| Boot flags | The current boot entry | FAIL on test signing, signature checks off, kernel or boot debugging, or early-launch anti-malware off |
| Memory integrity | Virtualization-based security and HVCI | INFO |
| Kernel driver signatures | Every running kernel driver's signature (Authenticode or catalog) | WARN for any without a valid signature |
| Windows key and activation | Key stored in firmware, activation status | WARN if missing |
| Company join, MDM enrollment | `dsregcmd`, enrollment registry | FAIL if enrolled (a company can lock or wipe it) |
| Local admins, unsigned drivers | Accounts, driver signatures | INFO / WARN |
| Installed software, startup items, scheduled tasks | Registry and Task Scheduler | Saved for review |

## Stability: is anything failing?

Checked by the full audit (last 30 days), by `-Quick` (since the last quick run) and by `-Monitor`
(during the test).

| Check | Result |
| --- | --- |
| WHEA hardware errors | FAIL, with the event IDs (17, 19, 47 are corrected errors; 1 and 18 fatal) |
| Unexpected shutdowns (Kernel-Power 41) | FAIL, with the dates |
| Blue screens (bugcheck 1001), new crash dumps | FAIL |
| NVIDIA driver errors, display driver resets (4101) | FAIL |
| Disk and NVMe errors | FAIL |
| SSD resets and retries (129, 153) | WARN: early sign of a failing drive |
| CPU limited by firmware (Kernel-Processor-Power 37) | INFO: normal on battery, worth a look if it fills the log on the charger |
| Recovered hangs (`LiveKernelReports`) | WARN. `WATCHDOG` means the graphics driver hung and was restarted |
| Devices with driver errors | FAIL |
| Dedicated GPU still present | FAIL if it vanished |

## Under load (`-Stress`, `-GpuTest`, `-Monitor`)

| Check | Result |
| --- | --- |
| Verified CPU load (`-Stress`) | FAIL on any wrong answer from a fixed matrix multiply and SHA-256 repeated on every thread |
| Verified memory load (`-Stress`) | FAIL on any word of RAM that reads back wrong (half the free RAM, a new pattern every pass) |
| GPU memory test (`-GpuTest`) | FAIL on any error memtest_vulkan reports, or if the GPU drops out. PASS needs its standard 5-minute test |
| Charger keeps up | WARN if the battery drains while on the charger in 20% of samples or more |
| GPU PCIe link under load | WARN if it runs on fewer lanes than it supports |
| GPU answers in every sample | FAIL if it stops (GPU dropout) |
| GPU hardware slowdown (thermal or power brake) | WARN |
| GPU temperature | WARN at 87 C or above (profile can change it) |
| Sustained GPU power at full load | *spec*: WARN below the profile's minimum (weak cooling or wrong charger) |
| Samples taken on battery | WARN |
| CPU sustained clock and firmware limit | INFO |
| Board thermal zone | WARN at 100 C |

Fan speed and CPU package power are not exposed by Windows. Use HWiNFO64 for those.

## Hands-on (`-Interactive`)

The faults only a person can see or hear. The kit runs each test and records your answer.

| Test | How | Result |
| --- | --- | --- |
| Screen: pixels | Six full-screen colours | FAIL if you saw a dead or stuck pixel |
| Screen: backlight | Black, white and grey | WARN on patches, bands or leaking light |
| Keyboard | A map of every key; each turns black when Windows registers it | FAIL for any main key that never registered. WARN for chatter (one press registering twice within 40 ms) |
| Touchpad | Left click, right click, scrolling | FAIL if one never registered |
| Speakers | A tone left only, right only, then a sweep from 60 Hz to 12 kHz | FAIL on a missing side, rattle or crackle |
| Microphone | 4 seconds recorded, measured and played back, then deleted | FAIL if silent or unclear |
| Webcam | Opens the Camera app | FAIL if the picture is faulty |
| USB ports | One port at a time: 256 MB written to a stick and read back, uncached | FAIL if nothing appears or the data differs. WARN if a port is under half the speed of the best one |
| Other ports | HDMI, headphone jack, USB-C charging, charger plug | FAIL on your answer, or skip |

## Which checks run in each mode

`-Only` takes these names: `identity`, `cpu`, `gpu`, `display`, `memory`, `storage`, `battery`,
`firmware`, `kernel`, `license`, `ownership`, `devices`, `software`, `inventory`, `msinfo`, `eventlogs`.
Each is one file in `windows/checks`. If one fails with a script error, the others still run, and the
report says which one failed and why.

## Linux

`linux-live-audit.sh` uses the same profiles and the same rules where Linux can see the same thing.

| Area | Checks |
| --- | --- |
| Identity | Serial against `--serial`, product number, model, board ID |
| Genuine parts | CPU model, cores and threads, GPU (PCI bus), GPU memory (`nvidia-smi`), panel resolution, RAM layout, matched pair and speed, SSD size, battery design capacity |
| Prior use | SSD power-on hours, TB written, wear, media errors, unsafe shutdowns (`smartctl`); battery health and cycles |
| Tampering | Secure Boot, the Platform Key (PKfail and maker), UEFI boot, the firmware security report (`fwupdmgr security`) |
| Stability | Kernel hardware errors this boot: machine checks, PCIe errors, NVMe timeouts, GPU hangs. Radio firmware errors are a WARN |
| Under load | `--stress`: 15 minutes of CPU and memory stress with every result verified (`stress-ng`) |

## macOS

`mac-audit.sh` uses the same profiles, matched on the model identifier (for example `Mac14,10`).

| Area | Checks |
| --- | --- |
| Identity | Serial against `--serial`, model name and identifier |
| Genuine parts | Chip, cores and threads, memory, GPU, built-in panel resolution, SSD size, webcam |
| Prior use | SSD power-on hours, TB written and wear (needs smartmontools); battery: Apple's own maximum capacity (as in System Settings, with the raw gauge reading beside it), cycles and condition; the connected charger |
| Tampering | Activation Lock: PASS when Find My is on for the Apple ID signed in on the Mac (shown masked), WARN otherwise (a previous owner's lock), company enrollment through MDM and DEP (FAIL: a DEP Mac re-enrolls after a reset), System Integrity Protection, Gatekeeper, FileVault, firmware password on Intel Macs |
| Stability | Kernel panics and abnormal shutdown causes in the last 30 days |

## Every report also contains

- Every part with its exact model and serial number (the hardware inventory).
- The SHA-256 of every kit file that ran (`kit_files.csv`) and one short kit fingerprint. On Windows it
  also compares them with the fingerprint list that came with the download and WARNs on any difference.
- On Windows, any script errors, at the end, for debugging.
