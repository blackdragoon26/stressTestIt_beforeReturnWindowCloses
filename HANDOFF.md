# Handoff: context for Claude Code on this machine

Read this first. It replaces the chat history that could not be teleported.

## What this repo is

A dead-on-arrival (DOA) test kit for an open-box HP OMEN Transcend 16-u0005TX bought from
an HP distributor. The seller's warranty is "1-Year EB Warranty" and there is a
15 or 30 day DOA replacement window. Every fault must be found and recorded inside that window.

Repo: github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses
Runbook doc (day-by-day plan, pass criteria, results log): https://claude.ai/artifact/Tkj9tSDxz5hycp7xnBiRxz

## Expected values for the OMEN unit

| Item | Expected |
| --- | --- |
| Product number | 834T6PA#ACJ |
| Board ID | 8BB3 (per github.com/arfelious/omen-fan-control) |
| CPU | i7-13700HX, 16 cores, 24 threads (the 13700H has 14C/20T: that gap catches a swapped board) |
| GPU | RTX 4070 Laptop, 8 GB, about 130W max |
| RAM | 2 x 8 GB DDR5-4800, matched part numbers. Max upgrade 2 x 16 GB DDR5-5600 |
| SSD | 1 TB, one M.2 2280 Gen4 slot only |
| Battery | 97 Wh, full charge at least 95% of design, single-digit cycles |
| Sustained baseline (LaptopMedia) | GPU about 2280 MHz at 109W after 30 min gaming; CPU about 3.0 GHz P-core at 82C |

## Platform

The OMEN will run Windows only. omen-audit.ps1 is the main deliverable; linux-live-audit.sh is an optional
second opinion. The Linux laptop this repo is developed on is only a workbench. It also runs other remote
workloads: install nothing system-wide, touch only this repo.

## Files

- `linux-live-audit.sh`: Linux audit (identity, PCI, RAM, SSD SMART, fwupd HSI, kernel errors, battery,
  optional 15 min stress-ng). Expected values overridable by env vars (EXPECT_SKU, EXPECT_BOARD, EXPECT_CPU,
  EXPECT_THREADS, EXPECT_GPU_REGEX, SSD_HOURS_WARN, EXPECT_PK_REGEX).
- `omen-audit.ps1`: Windows audit, full mode and `-Quick` daily soak mode. Expected values are parameters
  (-ExpectCpu, -ExpectCores, -ExpectThreads, -ExpectGpu, -ExpectRamModules, -ExpectRamGB, -ExpectPk, ...).
  NEVER RUN YET: it could not be parsed or tested in the cloud session.

## Test history

This machine (ASUS VivoBook X515DA, Ryzen 5 3500U) is the test bed.
First run, 2026-11-19, with:
`sudo EXPECT_CPU=3500U EXPECT_THREADS=8 EXPECT_GPU_REGEX='Radeon|Picasso' bash linux-live-audit.sh --install --stress`

- Correct: CPU, GPU, Secure Boot, UEFI passed; mixed RAM part numbers warned (real); battery 60% / 1833 cycles warned (real).
- Product number empty (ASUS firmware has no SKU): expected on this machine.
- Bug, fixed 2026-11-19 (second pass): stress-ng flagged FAIL on a clean run. The first fix still grepped
  "untrustworthy", which matches stress-ng's normal "metrics untrustworthy: 0" line. Now only non-zero counts fail.
- Fixed since: SSD power-on hours now warn above 100 h (this SSD has 19,276 h, 72 TB written).
- Resolved 2026-11-19: the 2 "Kernel hardware errors" lines were noise.
  - "MCE: In-kernel MCE decoding enabled." is a boot notice. Now filtered.
  - "Bluetooth: hci0: Hardware error 0x0c" is the Intel BT radio firmware hiccuping (headphones reconnected
    20 s later). Radio firmware errors (Bluetooth, iwlwifi) now get their own WARN line and
    kernel_radio_errors.txt instead of a FAIL.
  - Also found and fixed: the old exclusion `mce: .*bank` hid real machine check errors
    ("Machine Check: 0 Bank 5: ..."). Narrowed to the "Using N MCE banks" / "CPU supports N MCE banks" notices.
    Tested against 5 real and 5 benign sample lines.
- omen-audit.ps1: added -ExpectModel (the Model check was hardcoded to 'Transcend'). File is pure ASCII,
  which Windows PowerShell 5.1 needs. Still never run.

- 2026-11-19, added after re-reading the original brief (genuineness, BIOS and boot tampering, upgrade room):
  - Secure Boot Platform Key check in both scripts. FAIL on a leaked test key (PKfail, "DO NOT TRUST"),
    WARN if the key is not the maker's (EXPECT_PK_REGEX / -ExpectPk, default HP). Tested on this ASUS's real key.
  - Windows: BIOS setup and power-on password check through HP's BIOS WMI (root\HP\InstrumentedBIOS).
    FAIL if set. Shows INFO on non-HP machines. Untested until it runs on the OMEN.
  - Both: "RAM upgrade room" INFO line (slots, filled, firmware maximum).
  - For the Linux re-run on this ASUS add EXPECT_PK_REGEX=ASUS.
- 2026-11-19: omen-audit.ps1 -Monitor mode (sensor log during stress tests, sensors.csv, built-in sources
  only: nvidia-smi and Windows performance counters). README rewritten as Windows step-by-step.
  Checked bracket and quote balance with a script; PowerShell itself could not be run on this machine.

## To do

1. DONE: kernel_hw_errors.txt lines were noise; filter tuned (see above).
2. Re-run the Linux script with the same overrides and confirm only expected FAIL/WARN remain.
   Expected on this ASUS: FAIL Product number (no SKU), WARN Board ID, WARN RAM matched pair,
   WARN Battery, WARN SSD power-on hours, maybe WARN Radio firmware errors. stress-ng should PASS.
3. FIRST REAL TEST: parse and run omen-audit.ps1 on any Windows machine (full, -Quick, and
   -Monitor -Minutes 2 while something loads the CPU). It has never been executed.
   When this machine is booted into Windows, run omen-audit.ps1 with overrides for this hardware and fix what breaks:
   `.\omen-audit.ps1 -ExpectProductNumber X515DA -ExpectModel VivoBook -ExpectBoardId X515DA -ExpectCpu 3500U -ExpectCores 4 -ExpectThreads 8 -ExpectGpu 'Radeon' -ExpectRamModules 2 -ExpectRamGB 8 -ExpectPk ASUS`
   then `.\omen-audit.ps1 -Quick -ExpectGpu 'Radeon'`.
4. Add a LICENSE if Sankalp wants the repo public.

## Rules (from Sankalp, non-negotiable)

- Commits: authored as Sankalp (blackdragoon26) using his git identity, `git commit -s` (DCO sign-off),
  short conventional commit message. No Claude co-author or attribution lines.
- Never push, publish or open PRs. Sankalp pushes himself.
- No em dashes in any text. Plain English.
