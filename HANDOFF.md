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
(`mac-audit.sh`, first real run 2026-11-22 on a MacBook Air M3; Intel Macs untested). All three
read the same `profiles/*.psd1`. The Linux laptop this repo is developed on is the workbench and test
machine. It also runs other remote workloads: install nothing system-wide, touch only this repo.

## Files

| Path | What it is |
| --- | --- |
| `omen-audit.ps1` | Windows entry point: options, mode, then runs the parts in `windows/`. Modes: full (default), `-Only <checks>`, `-Quick`, `-Monitor`, `-Stress`, `-GpuTest` (the last three combine), `-Interactive`. Every run writes a PDF report |
| `windows/*.ps1`, `windows/checks/*.ps1` | The Windows kit split by job: one file per check area plus helpers. Map: `windows/README.md` |
| `profiles/*.psd1` | Expected specs per laptop model, read with `Import-PowerShellDataFile` |
| `docs/*.md` | Docs: guide, checks, profiles, trust, omen-day. GitHub shows them; the site renders the same files |
| `docs/index.html`, `docs.html`, `site.css`, `.nojekyll` | The website. Static, hosted from `docs/` (GitHub Pages or Cloudflare Pages) once Sankalp gives a subdomain |
| `docs/SHA256SUMS.txt`, `tools/update-hashes.sh` | Published fingerprints. Re-run the tool before every commit that changes a script or profile |
| `linux-live-audit.sh` | Linux audit (installed or live USB), profile-aware. `DOA_DEV=1` skips the root check for testing without sudo |
| `mac-audit.sh` | macOS audit. Activation Lock (checked against Find My of the signed-in Apple ID), MDM/DEP, SIP, Gatekeeper, panics, shutdown causes, battery (Apple's own maximum capacity), charger |
| `lib/common.sh` | Shared by the Linux and macOS scripts (bash 3.2): profile reading, results, HTML report, manifest |
| `docs/site.js`, `docs/docs.js`, `docs/favicon.svg` | Page scripts (kept out of the HTML so the CSP allows no inline code) and the plain favicon |
| `deploy/Dockerfile`, `deploy/nginx.conf`, `.dockerignore` | The website image: unprivileged nginx on 8080, `/healthz`, strict CSP, GET/HEAD only. Builds for arm64 without emulation |
| `deploy/MYPROD.md` | Myprod handoff manifest and the operator's registration steps |
| `.github/workflows/site.yml` | Smoke test, multi-platform GHCR publish by digest, then Myprod image endpoint once `MYPROD_DEPLOY_TOKEN` exists |
| `docs/fonts/` | IBM Plex Sans and Mono (woff2, OFL), self-hosted so the site makes no outside requests |

## How omen-audit.ps1 works

- **Structure (since 2026-11-22):** `omen-audit.ps1` dot-sources `windows/core.ps1` and `profile.ps1`, then
  the mode's files. The full audit runs `windows/checks/<name>.ps1` from the fixed list `$FullChecks`, each
  inside its own try/catch, so one crash no longer stops the rest. All files share the script scope.
- **Profiles:** the script loads every `profiles/*.psd1` file and matches each one's `Detect` regex against
  "model board ID". With no match it runs in **generic mode** (WARN "not recognised"): specs are listed, not
  compared, and every health, tamper and prior-use check still runs. `-Laptop <name>` forces a profile,
  and `-Laptop generic` forces generic mode. Every spec check is guarded by `Test-Spec '<key>'`.
- **Checks:** identity, serial against the invoice (asks once), CPU, GPU and VRAM, display (resolution,
  refresh, panel code), RAM and upgrade room, SSD (NVMe health log through IOCTL, uncached speed test),
  battery, Secure Boot and keys, BIOS passwords and HP BIOS settings, kernel and boot integrity (boot flags,
  HVCI, running driver signatures), activation, company or MDM enrollment, devices and PCIe link widths,
  event logs (incl. SSD resets 129/153, CPU limited 37, LiveKernelReports).
- **Load:** `-Stress` = verified CPU and RAM load (C# in `windows/stress.ps1`, gpu-burn principle: fixed
  calculations compared with a reference). `-GpuTest` = memtest_vulkan v0.5.0, pinned by SHA-256, run as
  `memtest_vulkan.exe 1` (unattended mode found in its source; device 1 = the dedicated GPU), log parsed.
- **Hands-on:** `-Interactive` = screen colours, key map with chatter detection, touchpad, speakers
  L/R/sweep, microphone (MCI record, deleted after), webcam, USB ports with uncached speed, other ports.
- **Report:** `DOA_report_<mode>_<stamp>.pdf` is printed from HTML by headless Edge, with the `.html` kept as
  a fallback. It includes the SHA-256 of every kit file (`kit_files.csv`), a 16-character kit fingerprint,
  and a WARN if any file differs from the bundled `docs/SHA256SUMS.txt`.
- **Constraints:** every file must stay pure ASCII (Windows PowerShell 5.1), C# must compile as C# 5.
  Nothing gets installed; `-GpuTest` downloads one pinned file into the kit's `tools` folder.

## Product direction

Sankalp may turn this into a product: a self-serve laptop check for owners and buyers, OS neutral, with a
site on his subdomain. It stays local-first. Seller certification was discussed and set aside for now.

**Name:** SecondTrust (decided 2026-11-19; script and folder names stay omen-* until the OMEN DOA window ends).

**Open decisions (his):** license, subdomain, code signing
certificate.

**Hosting:** on Myprod (Sankalp's Nomad pool on Oracle ARM64; docs in github.com/blackdragoon26/Myprod). This
repo is the "project agent" side only: build, publish, handoff. Registration and deploy are the operator's
(Sankalp's) dashboard actions. Proposed app `secondtrust-site` at `secondtrust.sankalpjha.dev`. Steps: deploy/MYPROD.md.

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
- `linux-live-audit.sh` (profile-aware rewrite) verified with sudo on the ASUS, 2026-11-19.

- **Third Windows run on the ASUS (2026-11-19):** all five modes ran with the profile files: full (serial PASS
  via `-InvoiceSerial`), `-Laptop omen` (10 FAIL, 8 WARN: swapped-machine detection works), `-Laptop generic`,
  `-Quick`, `-Monitor`. The reports' script hash `cfaa5f48...` matched commit 6d1fe68. Fixed after it: the
  monitor now keeps Windows awake (SetThreadExecutionState) and reports gaps (a 60 min run slept after 25 min),
  checking Kernel-Power 42/107 to tell sleep from a possible freeze; no empty GPU fields in the progress line
  without NVIDIA; FAIL Model shows the expected value; empty product number reads "(none stored)".

- **Split and new checks (2026-11-22), from research on gpu-burn, memtest_vulkan, LaptopInspector
  (github.com/tyrmoga/hwcheck), Notebookcheck's Transcend 16 review and forum threads.** Verified in a
  throwaway `mcr.microsoft.com/powershell` container (image removed after): all files parse, all C#
  compiles as C# 5, the stress engine ran with 0 false errors and caught an injected RAM bit flip and wrong
  CPU answers, the tone generator and the memtest_vulkan log parser work. **Not yet run on Windows.**
  Also fixed: NUL characters in hardware_inventory.csv (empty monitor names, TPM version). Site body text
  is now Plex Sans Medium (500) at 17 px with darker grey text.

- **First real Mac run (2026-11-22, MacBook Air M3, macOS 26.4.1):** worked, 0 FAIL, 4 WARN, but took
  almost 6 minutes (the 30-day `log show` search, which found no shutdown causes on Apple silicon). Fixed
  after it: the search now filters on the kernel process first; battery leads with Apple's own maximum
  capacity (85%, the raw gauge said 79%); charger reported; Activation Lock PASSes when Find My is on for
  the signed-in Apple ID (masked in the report); tidier GPU and MDM text; new `macbook-air-m3` profile.
- **Reports and cleanup (2026-11-22):** every OS writes `reports/<computer>_<mode>_<time>/` inside the kit
  (Linux and macOS used to write `linux-audit-*` / `mac-audit-*` into the current folder). Reports written
  under sudo are chowned back to the user. `-Cleanup` / `--cleanup` moves reports to
  `~/SecondTrust-reports` and deletes the kit and its temp files; it refuses a git checkout or an
  unexpected folder name (tested on Linux, including the refusal). The Windows setup block deletes its zip;
  Edge's print profile is removed after each report.
  `sudo bash linux-live-audit.sh --remove-tools` removes only the packages `--install` added (read from
  `/var/log/apt/history.log*`, asks first). Every cleanup command, with by-hand fallbacks: guide.md#clean-up.
  The docs site now supports section links (`docs.html#guide/clean-up`), same heading ids as GitHub.

- **Site (2026-11-22):** the landing page cycles through the checks a few at a time under a scan line
  (reads `docs/checks.md`; hover pauses, click skips); Checks is out of the navbar. The guide asks which
  system first and shows only that one (or the full guide); the checks page is a tour, one topic per slide.
  The live dot background (`docs/bg.js`) runs on every page and glows while scrolling. Body text is
  regular weight again.

## To do

1. **Before the OMEN arrives (about 2026-11-26):**
   - On the ASUS in Windows, paste the Step 1 block to update, then run the split kit for the first time:
     - `.\omen-audit.ps1`: every check component, the new SSD speed, PCIe, kernel and panel checks
     - `.\omen-audit.ps1 -Stress -Minutes 5`: the verified load (expect 0 wrong results)
     - `.\omen-audit.ps1 -GpuTest -Minutes 6`: memtest_vulkan on the Radeon Vega (download, hash, run, parse)
     - `.\omen-audit.ps1 -Interactive`: every hands-on test, especially the key map and USB speeds
     - `.\omen-audit.ps1 -Only storage,kernel` and `-Quick`
   - DONE 2026-11-19: Linux script verified with sudo on the ASUS: profile recognised, serial PASS via
     `--serial`, RAM layout and speed PASS, SSD 19,282 h / 72.2 TB / wear 100% (WARN), battery 60% (WARN),
     0 FAIL; HTML report valid, manifest verifies.
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
