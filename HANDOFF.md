# Handoff

Context for the next Claude Code session. Read this first.

## What this is

A dead-on-arrival (DOA) test kit for an open-box HP OMEN Transcend 16-u0005TX (834T6PA) bought from an
HP distributor. Warranty: "1-Year EB Warranty". DOA replacement window: 15 or 30 days. Every fault has to be
found and recorded inside that window.

- Repo: github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses
- Runbook doc (day-by-day plan, stress tools, pass criteria, results log): https://claude.ai/artifact/Tkj9tSDxz5hycp7xnBiRxz

## Platform

The OMEN runs Windows only, so `omen-audit.ps1` is the deliverable. `linux-live-audit.sh` is an optional
second opinion. The Linux laptop this repo is developed on (ASUS VivoBook X515DA) is a workbench and the
test machine. It also runs other remote workloads: install nothing system-wide, touch only this repo.

## Files

| File | What it is |
| --- | --- |
| `omen-audit.ps1` | Windows audit. Modes: full (default), `-Quick` (daily soak), `-Monitor -Minutes N` (sensor log during a stress test). Every run writes a PDF report |
| `README.md` | Step-by-step instructions for running it on Windows |
| `linux-live-audit.sh` | Optional Linux audit from an Ubuntu live USB |

## How omen-audit.ps1 works

- **Profiles:** built-in expected values for two laptops, `omen` and `asus`, picked automatically from the
  model name and board ID. An unrecognised laptop is checked against `omen`. `-Laptop` forces one.
- **Checks:** identity, serial against the invoice (asks once), CPU, GPU and VRAM, RAM layout and speed,
  SSD size and health, display resolution and refresh, battery health and design capacity, Secure Boot
  and its keys, BIOS passwords (HP WMI), TPM, Windows activation, company or MDM enrollment, drivers,
  Wi-Fi, Bluetooth, webcam, event log errors.
- **Report:** `DOA_report_<mode>_<stamp>.pdf`, printed from HTML by headless Edge, with the `.html` kept as
  a fallback. The main work is wrapped in try/catch, so a crash still produces a report
  (WARN "Script error", not FAIL).
- **Constraints:** the file must stay pure ASCII (Windows PowerShell 5.1). It only uses what Windows and
  the NVIDIA driver provide: nothing gets installed before the first audit.

## Spec sources and open questions (OMEN)

- CPU, GPU, RAM: HP OMEN Transcend 16 spec page, LaptopMedia's review of the 16-u0000, and Intel's
  i7-13700HX spec (DDR5-4800).
- Display (2560x1600, 240 Hz) and SSD (1 TB): 91mobiles listing for 834T6PA.
- **Battery:** 91mobiles says 45 Wh, a review of this model says 97 Wh. The check is a WARN only.
- **Not checked:** the Wi-Fi chip model and charger wattage (230 W vs 280 W). Sources conflict.
- **HP-only checks still untested:** BIOS password (HP WMI) and the board ID 8BB3. They first run on the OMEN.
- **Untested until the next run:** the NVMe health log reader (no C# compiler on the Linux workbench).

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
- Real findings on the ASUS: 4 Kernel-Power 41 events in 30 days (FAIL, as designed), battery at 61%
  after 1,833 cycles (WARN).
- `linux-live-audit.sh` ran on the ASUS. Its findings are fixed.

## To do

1. **Re-run on the ASUS in Windows:** paste the Step 1 block from the README, then run `.\omen-audit.ps1`.
   Confirm:
   - "SSD health" shows about 19,276 h and 72 TB written (Linux's numbers for this drive) and WARNs.
   - The event log section finishes with no "Script error".
   - MDM enrollment PASSes.
   Then try `-Quick` and `-Monitor -Minutes 2`.
2. Optional: re-run `linux-live-audit.sh` with
   `sudo EXPECT_CPU=3500U EXPECT_THREADS=8 EXPECT_GPU_REGEX='Radeon|Picasso' EXPECT_PK_REGEX=ASUS bash linux-live-audit.sh --install --stress`.
3. Add a LICENSE if Sankalp wants the repo public.

## Rules (from Sankalp)

- **Commits:** as Sankalp (blackdragoon26, his git identity), `git commit -s`, short conventional message.
  No Claude co-author or attribution lines.
- **Pushing:** push only when Sankalp explicitly says "push", every time. Never open PRs.
- **Text:** no em dashes. Plain English.
