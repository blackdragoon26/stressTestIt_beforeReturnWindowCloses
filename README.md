# DOA Kit

Check a laptop before the return window closes. One PowerShell command reads the hardware, firmware and
event logs, and tells you:

- **Is this the machine you paid for?** Serial against the invoice, CPU core count, GPU and its memory,
  RAM, SSD size, the panel's resolution and refresh, battery capacity.
- **Has anyone tampered with it?** Secure Boot and its keys, BIOS passwords, company or MDM enrollment,
  boot entries, leftover software.
- **How much was it really used?** SSD power-on hours and terabytes written, read straight from the drive,
  plus battery wear and past crashes.
- **Does it hold up under load?** A sensor log for every stress test that flags GPU dropouts, thermal and
  power brakes, and low sustained power.

Every run writes a PDF report you can send the seller. Read-only, nothing installed, nothing uploaded.

## Run it

Windows 10 or 11. Press `Win + X`, click **Terminal (Admin)**, paste this and press Enter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Invoke-WebRequest https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.zip -OutFile $env:TEMP\omen-kit.zip -UseBasicParsing
Expand-Archive $env:TEMP\omen-kit.zip -DestinationPath C:\omen-kit -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
.\omen-audit.ps1
```

| Command | When |
| --- | --- |
| `.\omen-audit.ps1` | The full audit, the day the laptop arrives, before installing anything |
| `.\omen-audit.ps1 -Monitor -Minutes 60` | In a second window, during every stress test |
| `.\omen-audit.ps1 -Quick` | Every evening while you use it hard |

Reports land in `C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main\reports`.

## Docs

| Page | What it covers |
| --- | --- |
| [Guide](docs/guide.md) | Setup, the three modes, reading the results, stress tests |
| [Checks](docs/checks.md) | Every check, what it reads, when it passes, warns or fails |
| [Profiles](docs/profiles.md) | Supported laptops, and how to add yours |
| [Trust](docs/trust.md) | What the script does and does not do, checking the download, what reports contain |
| [OMEN day](docs/omen-day.md) | A worked example: the full sequence for one laptop's return window |

## Supported laptops

Any Windows laptop runs in generic mode: every health, tamper and prior-use check, with specs listed.
With a profile, every spec is also compared against what the maker promised.

| Profile | Laptop |
| --- | --- |
| `omen` | HP OMEN Transcend 16-u0005TX (834T6PA) |
| `asus` | ASUS VivoBook 15 X515DA |

## Repository

| Path | What |
| --- | --- |
| `omen-audit.ps1` | The Windows audit |
| `profiles/` | Expected specs, one file per laptop model |
| `docs/` | The docs above, and the website (`index.html`, `docs.html`, `site.css`) |
| `docs/SHA256SUMS.txt` | Fingerprints of every file the kit runs |
| `tools/update-hashes.sh` | Regenerates `SHA256SUMS.txt`. Run it before every commit that changes a script or profile |
| `linux-live-audit.sh` | Optional second opinion from an Ubuntu live USB |
