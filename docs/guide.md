# How to run it

Pick your operating system. Each one downloads the kit, unpacks it, and runs the audit. Nothing is uploaded,
and nothing is installed unless you ask for it.

| System | Script | Report | Status |
| --- | --- | --- | --- |
| Windows 10 and 11 | `omen-audit.ps1` | PDF and HTML | Tested |
| Linux (installed or live USB) | `linux-live-audit.sh` | HTML | Tested |
| macOS | `mac-audit.sh` | HTML | Experimental: not yet run on a real Mac |

Want to check the download first? See [Trust](trust.md).

## Windows

Press `Win + X`, click **Terminal (Admin)** (or **Windows PowerShell (Admin)**), then **Yes**. Paste this
and press Enter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Invoke-WebRequest https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.zip -OutFile $env:TEMP\omen-kit.zip -UseBasicParsing
Expand-Archive $env:TEMP\omen-kit.zip -DestinationPath C:\omen-kit -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
.\omen-audit.ps1
```

The first line allows scripts in this window only; it resets when the window closes. The audit asks once
for the serial number on your invoice and compares it with the BIOS. Press Enter to skip.

| Command | When |
| --- | --- |
| `.\omen-audit.ps1` | The full audit, the day the laptop arrives, before you install anything |
| `.\omen-audit.ps1 -Monitor -Minutes 60` | In a second window, during every stress test or gaming session |
| `.\omen-audit.ps1 -Quick` | Every evening while you use it hard |
| `.\omen-audit.ps1 -InvoiceSerial 5CD1234XYZ` | Pass the serial instead of typing it |
| `.\omen-audit.ps1 -Laptop omen` | Force a profile (see below) |

Reports land in `C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main\reports`. Pasting the block again
updates the kit and keeps the reports. In a new window later, you only need the first and fourth lines.

**During stress tests**, run the stress tool (OCCT, Cinebench, a game) in one window and the monitor in
another. Every 2 seconds it logs CPU and GPU clocks, load, temperatures, GPU power, GPU slowdown reasons and
whether the charger is plugged in. At the end it flags GPU dropouts, hardware slowdowns, low sustained GPU
power and any crash during the test. Press `Q` to stop early. Windows does not report fan speed or CPU
package power: keep HWiNFO64 logging alongside for those.

## Linux

Open a terminal. Paste this and press Enter:

```bash
(curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz || wget -qO- https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz) | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
sudo bash linux-live-audit.sh --install
```

| Option | What it does |
| --- | --- |
| `--install` | Installs the tools it reads with (smartmontools, dmidecode, fwupd, stress-ng, and others). Debian and Ubuntu only; elsewhere, install them yourself |
| `--stress` | Adds a 15 minute CPU and memory stress test that verifies every result |
| `--serial 5CD1234XYZ` | Compares the firmware serial with your invoice |
| `--laptop omen` | Forces a profile, or `--laptop generic` |

The report folder is `linux-audit-<date>` in the folder you ran it from. It needs `sudo` to read the serial,
the RAM modules and the SSD's health.

**Checking a Windows laptop from outside Windows:** boot Ubuntu from a USB stick ("Try Ubuntu"), connect to
Wi-Fi, and run the same three lines. Windows cannot influence anything this sees. Copy the report folder to
another stick before you reboot: a live session forgets everything.

## macOS

Open Terminal. Paste this and press Enter:

```bash
curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
bash mac-audit.sh
```

| Option | What it does |
| --- | --- |
| `--serial C02XXXXXXX` | Compares the serial with your invoice |
| `--laptop generic` | Forces a profile or generic mode |
| run with `sudo` | Adds the firmware password check on Intel Macs |

For SSD power-on hours, the best proof of prior use, install smartmontools first
(`brew install smartmontools`). Without it the report shows the drive's SMART status only.

The macOS script is experimental. It was written without a Mac to test on, so if anything looks wrong, open
an issue with the report.

## Every command, ready to copy

One block per command, each with its own Copy button. Run them inside the kit folder from the steps above.

### Windows (admin PowerShell)

Open the kit folder in a new window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
```

Full audit:

```powershell
.\omen-audit.ps1
```

Full audit with the invoice serial, comparing against a known profile:

```powershell
.\omen-audit.ps1 -Laptop omen -InvoiceSerial PASTE-SERIAL-HERE
```

Generic mode (no spec comparison, every other check):

```powershell
.\omen-audit.ps1 -Laptop generic
```

Sensor log during a stress test (a second window; press Q to stop early):

```powershell
.\omen-audit.ps1 -Monitor -Minutes 60
```

A short monitor run to try it out:

```powershell
.\omen-audit.ps1 -Monitor -Minutes 2
```

Evening check (new errors since the last one):

```powershell
.\omen-audit.ps1 -Quick
```

Fingerprint of the script, to compare with SHA256SUMS.txt:

```powershell
(Get-FileHash .\omen-audit.ps1).Hash
```

### Linux (terminal, inside `~/stressTestIt_beforeReturnWindowCloses-main`)

Full audit, installing the tools it needs first:

```bash
sudo bash linux-live-audit.sh --install
```

Full audit plus the 15 minute verified stress test:

```bash
sudo bash linux-live-audit.sh --stress
```

With the invoice serial and a known profile:

```bash
sudo bash linux-live-audit.sh --laptop omen --serial PASTE-SERIAL-HERE
```

Generic mode:

```bash
sudo bash linux-live-audit.sh --laptop generic
```

Fingerprints:

```bash
sha256sum linux-live-audit.sh lib/common.sh
```

### macOS (Terminal, inside `~/stressTestIt_beforeReturnWindowCloses-main`)

Full audit:

```bash
bash mac-audit.sh
```

With the firmware password check (Intel Macs) and the invoice serial:

```bash
sudo bash mac-audit.sh --serial PASTE-SERIAL-HERE
```

Generic mode:

```bash
bash mac-audit.sh --laptop generic
```

Fingerprints:

```bash
shasum -a 256 mac-audit.sh lib/common.sh
```

## Reading the result

| Label | Meaning | What you do |
| --- | --- | --- |
| FAIL | Evidence of a fault, a swap or tampering | Keep the report, contact the seller the same day |
| WARN | Needs a look by hand | Check it and write down what you found |
| PASS | As expected | Nothing |
| INFO | A value worth recording | Keep it |

Every report folder holds the report, every raw output, and `MANIFEST.sha256`, whose fingerprints prove no
file was edited later. Every check and its rules: [Checks](checks.md).

## Which laptop it compares against

All three scripts read the same profiles from the `profiles` folder. Each script recognises the laptop from
its model name and board ID (on a Mac, its model identifier) and says which profile it picked.

| Situation | Result |
| --- | --- |
| A profile matches | Every spec is compared: FAIL or WARN on any difference |
| No profile matches | **Generic mode.** Specs are listed, not compared. All health, tamper and prior-use checks still run |
| You force a profile | That profile is used even if the laptop does not look like it |

Force the profile when you know what you paid for. A swapped or wrong model then FAILs instead of quietly
running in generic mode. Supported laptops and how to add one: [Profiles](profiles.md).
