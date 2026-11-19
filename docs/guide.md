# How to run it

Windows 10 or 11. You need an administrator account and an internet connection for the download.
Nothing gets installed.

## 1. Get the kit

1. Press `Win + X`, then click **Terminal (Admin)** (or **Windows PowerShell (Admin)**). Click **Yes**.
2. Copy this whole block, paste it into the window, and press Enter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Invoke-WebRequest https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.zip -OutFile $env:TEMP\omen-kit.zip -UseBasicParsing
Expand-Archive $env:TEMP\omen-kit.zip -DestinationPath C:\omen-kit -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
```

Line by line:

- Allow scripts in this window only. The setting resets when the window closes.
- Download the kit from GitHub.
- Unpack it into `C:\omen-kit`.
- Go into the kit folder.

Paste the same block again any time to update. Your reports are kept.

**Every later time**, in a new admin window, you only need:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
```

| What | Where |
| --- | --- |
| The kit | `C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main` |
| Reports | `C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main\reports` |

Want to check the download first? See [Trust](trust.md).

## 2. Run it

| Command | When | Takes |
| --- | --- | --- |
| `.\omen-audit.ps1` | The full audit. Run it the day the laptop arrives, before you install anything | A few minutes |
| `.\omen-audit.ps1 -Monitor -Minutes 60` | In a second window, during every stress test or gaming session | As long as you set |
| `.\omen-audit.ps1 -Quick` | Every evening while you use the laptop hard | Seconds |

The full audit asks once for the serial number printed on the invoice, and compares it with the one in the
BIOS. Press Enter to skip, or pass it directly: `.\omen-audit.ps1 -InvoiceSerial 5CD1234XYZ`.

## 3. Read the result

| Label | Meaning | What you do |
| --- | --- | --- |
| FAIL | Evidence of a fault, a swap or tampering | Keep the report, contact the seller the same day |
| WARN | Needs a look by hand | Check it and write down what you found |
| PASS | As expected | Nothing |
| INFO | A value worth recording | Keep it |

Every check and its rules: [Checks](checks.md).

## 4. Keep the report

Every run makes a folder in `reports` containing:

- **`DOA_report_<mode>_<date>.pdf`: the file to share.** All results, the expected values, every part with
  its exact model and serial, sensor charts from `-Monitor`, the raw outputs, and any script errors.
- **The same report as `.html`.** Use it if the PDF could not be made (Microsoft Edge prints the PDF).
- **`SUMMARY.txt`, the raw files, and `MANIFEST.sha256`.** The manifest fingerprints prove no file was
  edited later.

Upload the folder somewhere safe the same day. If you plan to reset Windows, upload it first: the reset
erases it.

## Which laptop it compares against

The script reads the model name and board ID and picks a matching profile from the `profiles` folder.
The first line of the report says which one.

| Situation | Result |
| --- | --- |
| A profile matches | Every spec is compared: FAIL or WARN on any difference |
| No profile matches | **Generic mode.** Specs are listed, not compared. All health, tamper and prior-use checks still run |
| You force a profile: `.\omen-audit.ps1 -Laptop omen` | That profile is used even if the laptop does not look like it |

Force the profile when you know what you paid for. A swapped or wrong model then FAILs instead of quietly
running in generic mode. Supported laptops and how to add one: [Profiles](profiles.md).

## During stress tests

Run the stress tool (OCCT, Cinebench, a game) in one window and the monitor in another:

```powershell
.\omen-audit.ps1 -Monitor -Minutes 60
```

- Every 2 seconds it logs CPU and GPU clocks, load, temperatures, GPU power, GPU slowdown reasons and
  whether the charger is plugged in. Press `Q` to stop early.
- At the end it flags GPU dropouts, hardware slowdowns, low sustained GPU power, running on battery, and
  any crash or hardware error that happened during the test.
- Windows does not report fan speed or CPU package power. Keep HWiNFO64 logging alongside for those.

## Optional: a second opinion from Linux

`linux-live-audit.sh` runs from an Ubuntu live USB, outside Windows, so Windows cannot influence it:

```bash
sudo bash linux-live-audit.sh --install            # identity, SSD, firmware security, kernel errors
sudo bash linux-live-audit.sh --install --stress   # plus a 15 minute CPU and memory stress test
```
