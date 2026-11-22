# SecondTrust

Check your laptop before the return window closes. One command on Windows, Linux or macOS reads the
hardware, firmware and logs, and tells you:

- **Is this the machine you paid for?** Serial against the invoice, CPU core count, GPU and its memory,
  RAM, SSD size, the panel's resolution and refresh, battery capacity.
- **Has anyone tampered with it?** Secure Boot and its keys, BIOS passwords, company or MDM enrollment,
  boot entries, leftover software.
- **How much was it really used?** SSD power-on hours and terabytes written, read straight from the drive,
  plus battery wear and past crashes.
- **Does it hold up under load?** CPU, RAM and GPU memory tests that check every answer, not just
  survive, plus a sensor log that flags GPU dropouts, thermal and power brakes, low sustained power and a
  charger that cannot keep up.
- **Does every part work?** Guided hands-on tests for the screen, every key, the touchpad, speakers,
  microphone, webcam and each USB port, with real port speeds.

Every run writes a report to keep as proof. Read-only, nothing uploaded, nothing installed unless you ask.

## Run it

| System | Script | Report | Status |
| --- | --- | --- | --- |
| Windows 10 and 11 | `omen-audit.ps1` | PDF and HTML | Tested |
| Linux (installed or live USB) | `linux-live-audit.sh` | HTML | Tested |
| macOS | `mac-audit.sh` | HTML | Tested on one Mac |

**Windows.** Press `Win + X`, click **Terminal (Admin)**, paste this and press Enter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Invoke-WebRequest https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.zip -OutFile $env:TEMP\omen-kit.zip -UseBasicParsing
Expand-Archive $env:TEMP\omen-kit.zip -DestinationPath C:\omen-kit -Force; Remove-Item $env:TEMP\omen-kit.zip
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
.\omen-audit.ps1
```

| Command | When |
| --- | --- |
| `.\omen-audit.ps1` | The full audit, the day the laptop arrives, before installing anything |
| `.\omen-audit.ps1 -Interactive` | Hands-on tests: screen, keys, touchpad, speakers, mic, webcam, ports |
| `.\omen-audit.ps1 -Stress -GpuTest -Minutes 60` | Verified CPU, RAM and GPU memory load, with the sensor log |
| `.\omen-audit.ps1 -Monitor -Minutes 60` | Sensor log only, while a game or another stress tool runs |
| `.\omen-audit.ps1 -Quick` | Every evening while you use it hard |

Reports land in `reports` inside the kit folder on every system. When you are done, `-Cleanup` (Windows) or
`--cleanup` (Linux, macOS) keeps the reports in your home folder under `SecondTrust-reports` and removes
the kit. Every cleanup command, including removing the Linux tools: [Clean up](docs/guide.md#clean-up).

**Linux.** In a terminal (add `--stress` for a 15 minute verified stress test):

```bash
(curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz || wget -qO- https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz) | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
sudo bash linux-live-audit.sh --install
```

**macOS.** In Terminal (install smartmontools first for SSD hours):

```bash
curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
bash mac-audit.sh
```

All three read the same laptop profiles. Options and details: [Guide](docs/guide.md).

## Docs

| Page | What it covers |
| --- | --- |
| [Guide](docs/guide.md) | Setup, every mode, reading the results, stress tests |
| [Checks](docs/checks.md) | Every check, what it reads, when it passes, warns or fails |
| [Profiles](docs/profiles.md) | Supported laptops, and how to add yours |
| [Trust](docs/trust.md) | What the script does and does not do, checking the download, what reports contain |
| [OMEN day](docs/omen-day.md) | A worked example: the full sequence for one laptop's return window |

## Supported laptops

Any laptop runs in generic mode: every health, tamper and prior-use check, with specs listed.
With a profile, every spec is also compared against what the maker promised.

| Profile | Laptop |
| --- | --- |
| `omen` | HP OMEN Transcend 16-u0005TX (834T6PA) |
| `asus` | ASUS VivoBook 15 X515DA |
| `macbook-air-m3` | Apple MacBook Air 13-inch, M3 |

## Repository

| Path | What |
| --- | --- |
| `omen-audit.ps1` | The Windows audit: starts the parts below |
| `windows/` | The Windows checks, one file per job ([map](windows/README.md)) |
| `linux-live-audit.sh` | The Linux audit, for an installed system or a live USB |
| `mac-audit.sh` | The macOS audit (run on one Mac so far) |
| `lib/common.sh` | Shared by the Linux and macOS scripts: profiles, results, the HTML report |
| `profiles/` | Expected specs, one file per laptop model, read by all three scripts |
| `docs/` | The docs above, and the website (`index.html`, `docs.html`, `site.css`, `fonts/`) |
| `docs/SHA256SUMS.txt` | Fingerprints of every file the kit runs |
| `tools/update-hashes.sh` | Regenerates `SHA256SUMS.txt`. Run it before every commit that changes a script or profile |
| `deploy/` | The website's container (nginx, port 8080) and the Myprod handoff: [deploy/MYPROD.md](deploy/MYPROD.md) |
| `.github/workflows/site.yml` | Publishes the website image to GHCR and deploys it through Myprod |

The site uses IBM Plex Sans and IBM Plex Mono, served from `docs/fonts` under the SIL Open Font License
(`docs/fonts/OFL.txt`).
