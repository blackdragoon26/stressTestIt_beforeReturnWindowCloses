# Handoff

Context for the next Claude Code session. Read this first.

## What this is

A dead-on-arrival (DOA) test kit for an open-box HP OMEN Transcend 16-u0005TX (834T6PA) bought from an
HP distributor. Warranty: "1-Year EB Warranty". DOA replacement window: 15 or 30 days. Every fault has to be
found and recorded inside that window.

- Repo: github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses
- Runbook doc (day-by-day plan, stress tools, pass criteria, results log): https://claude.ai/artifact/Tkj9tSDxz5hycp7xnBiRxz

## Platform

The OMEN runs Windows only, so `omen-audit.ps1` matters most for the DOA window. As a product the kit is
OS neutral: Windows (`omen-audit.ps1`, tested), Linux (`linux-live-audit.sh`, tested on the ASUS) and macOS
(`mac-audit.sh`, experimental: written without a Mac, parsers checked against sample output only). All three
read the same `profiles/*.psd1`. The Linux laptop this repo is developed on is the workbench and test
machine. It also runs other remote workloads: install nothing system-wide, touch only this repo.

## Files

| Path | What it is |
| --- | --- |
| `omen-audit.ps1` | Windows audit. Modes: full (default), `-Quick` (daily soak), `-Monitor -Minutes N` (sensor log). Every run writes a PDF report |
| `profiles/*.psd1` | Expected specs per laptop model, read with `Import-PowerShellDataFile` |
| `docs/*.md` | Docs: guide, checks, profiles, trust, omen-day. GitHub shows them; the site renders the same files |
| `docs/index.html`, `docs.html`, `site.css`, `.nojekyll` | The website. Static, hosted from `docs/` (GitHub Pages or Cloudflare Pages) once Sankalp gives a subdomain |
| `docs/SHA256SUMS.txt`, `tools/update-hashes.sh` | Published fingerprints. Re-run the tool before every commit that changes a script or profile |
| `linux-live-audit.sh` | Linux audit (installed or live USB), profile-aware. `DOA_DEV=1` skips the root check for testing without sudo |
| `mac-audit.sh` | macOS audit, experimental. Activation Lock, MDM/DEP, SIP, Gatekeeper, panics, shutdown causes |
| `lib/common.sh` | Shared by the Linux and macOS scripts (bash 3.2): profile reading, results, HTML report, manifest |
| `docs/fonts/` | IBM Plex Sans and Mono (woff2, OFL), self-hosted so the site makes no outside requests |

## How omen-audit.ps1 works

- **Profiles:** the script loads every `profiles/*.psd1` file and matches each one's `Detect` regex against
  "model board ID". With no match it runs in **generic mode** (WARN "not recognised"): specs are listed, not
  compared, and every health, tamper and prior-use check still runs. `-Laptop <name>` forces a profile,
  and `-Laptop generic` forces generic mode. Every spec check is guarded by `Test-Spec '<key>'`.
- **Checks:** identity, serial against the invoice (asks once), CPU, GPU and VRAM, RAM, the SSD (its NVMe
  health log read through IOCTL), display, battery, Secure Boot and keys, BIOS passwords (HP WMI), TPM,
  activation, company or MDM enrollment, devices, event logs.
- **Report:** `DOA_report_<mode>_<stamp>.pdf` is printed from HTML by headless Edge, with the `.html` kept as
  a fallback. It includes the script's own SHA-256. A crash inside the main block still produces a report.
- **Constraints:** the script must stay pure ASCII (Windows PowerShell 5.1). Nothing gets installed.

## Product direction

Sankalp may turn this into a product: a self-serve laptop check for owners and buyers, OS neutral, with a
site on his subdomain. It stays local-first. Seller certification was discussed and set aside for now.

**Open decisions (his):** product name ("DOA Kit" is a working title), license, subdomain, code signing
certificate.

**Live preview of the site (private):** https://claude.ai/artifact/4k5aNmbJ6nzXibhgzvA5oQ
(a copy built from `docs/`, with the page skeleton stripped for the artifact host).

## Spec sources and open questions (OMEN)

- CPU, GPU, RAM: HP OMEN Transcend 16 spec page, LaptopMedia's review of the 16-u0000, and Intel's
  i7-13700HX spec (DDR5-4800).
- Display (2560x1600, 240 Hz) and SSD (1 TB): 91mobiles listing for 834T6PA.
- **Battery:** 91mobiles says 45 Wh, a review of this model says 97 Wh. The check is a WARN only.
- **Not checked:** the Wi-Fi chip model and charger wattage (230 W vs 280 W). Sources conflict.
- **HP-only checks still untested:** BIOS password (HP WMI) and the board ID 8BB3. They first run on the OMEN.

## Status

- **First Windows run on the ASUS (2026-11-19):** profile detection, display, RAM, battery, Secure Boot keys
  and the PDF all worked. Fixed after that run:
  - The event log crashed with "The parameter is incorrect" on the `nvlddmkm` query (no NVIDIA driver
    installed). Queries now run one provider at a time inside try/catch, and NVIDIA checks are skipped on
    non-NVIDIA profiles.
  - MDM falsely FAILed on Windows' built-in enrollments (Deploy, Cloud and Local Authority). Now only
    entries with a UPN or another provider count.
  - The SSD wrongly PASSED: Windows' reliability counter left power-on hours blank. Now the NVMe health
    log is read directly through IOCTL_STORAGE_QUERY_PROPERTY (`Get-NvmeHealth`). If hours still cannot
    be read, the check WARNs.
  - README: the ZIP unpacks to a doubly nested `stressTestIt_beforeReturnWindowCloses-main` folder, and the
    old `cd` search returned nothing. Setup is now one pasted block that unpacks to `C:\omen-kit`.
- **Second Windows run on the ASUS (2026-11-19), all fixes verified:** the Step 1 setup block worked;
  no script error; MDM PASS; the event log lists dates. The NVMe health log reader matches Linux's
  smartctl on the same drive: 19,278 h vs 19,276 h, 72.21 TB vs 72.1 TB, wear 100%, 207 unsafe
  shutdowns, 0 media errors. Result: 1 FAIL, 2 WARN, all real:
  - FAIL: 4 Kernel-Power 41 events (2026-10-25, 11-07, 11-10, 11-11)
  - WARN: the SSD (19,278 h, 72 TB, 100% of rated life used)
  - WARN: the battery (61%, 1,833 cycles)
- `linux-live-audit.sh` ran on the ASUS. Its findings are fixed.

## To do

1. **Before the OMEN arrives (about 2026-11-26):**
   - On the ASUS in Windows, paste the Step 1 block to update, then run:
     - `.\omen-audit.ps1`: profiles now load from files
     - `.\omen-audit.ps1 -Laptop generic`: generic mode, never run yet
     - `.\omen-audit.ps1 -Quick` and `-Monitor -Minutes 2`: never run yet
   - On the ASUS in Linux: `sudo bash linux-live-audit.sh --install` (profile-aware rewrite; verified without
     sudo only, so check the SSD, RAM and serial lines with sudo).
   - Fix whatever breaks.
   - Sankalp: make the MemTest86+ USB, and get the DOA window in writing (docs/omen-day.md).
2. **OMEN day:** follow docs/omen-day.md. After the first real run, update `profiles/omen.psd1` (`Verified`,
   exact model string, battery Wh) and settle the 45 vs 97 Wh question.
3. **Product:** pick a name and a license, host `docs/` on the subdomain, get a code signing certificate,
   then more profiles.

## Rules (from Sankalp)

- **Commits:** as Sankalp (blackdragoon26, his git identity), `git commit -s`, short conventional message.
  No Claude co-author or attribution lines.
- **Pushing:** push only when Sankalp explicitly says "push", every time. Never open PRs.
- **Text:** no em dashes. Plain English.
