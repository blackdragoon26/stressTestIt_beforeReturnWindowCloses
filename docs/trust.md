# Trust and privacy

You are asked to paste a command into an administrator or `sudo` terminal. Be careful with that request:
it is also how malware spreads. Here is exactly what this kit does, and how to check it yourself.

## What it does

- **Reads only.** It reads hardware information, firmware settings, logs and drive health. It does not
  change settings. It writes its own report folder, plus temporary files (on Windows, Edge's print
  profile and the compiled helpers below, in `%TEMP%`).
- **Leaves nothing behind when you ask.** Reports go to `reports` in the kit folder. When you are done,
  `-Cleanup` (Windows) or `--cleanup` (Linux, macOS) moves them to `SecondTrust-reports` in your home folder
  and deletes the kit and its temporary files. It never deletes a git checkout. The Windows setup block
  deletes its downloaded zip straight away, and Edge's print profile is removed after every report.
  On Linux, `--remove-tools` removes exactly the packages `--install` added, read from apt's own history.
  Every command: [Clean up](guide.md#clean-up).
- **Test files, deleted after.** The SSD speed check writes one 1 GB file to `%TEMP%` and the USB port test
  one 256 MB file to your stick; both are deleted straight after. Nothing else on the stick is touched.
- **Installs nothing unless you ask.** Only the Linux `--install` option installs packages, through your
  package manager, and it says which ones.
- **One download, only with `-GpuTest`.** The GPU memory test uses memtest_vulkan v0.5.0 (open source, zlib
  license) from its author's GitHub release. The kit saves it in its own `tools` folder and runs it only if
  its SHA-256 is exactly `09e67704210762ae8d8ad70fe6d71275eefbe815cc2c0658cd5afc8e231d0df6`, the value
  GitHub publishes for that file. Otherwise it deletes the file and stops.
- **Your voice is not kept.** The microphone test records 4 seconds, plays them back and deletes the
  recording. Only the peak level goes in the report.
- **Nothing leaves your machine.** No telemetry, no uploads, no accounts. The report stays in its folder
  until you share it yourself.
- **Root or admin, and why.** Serial numbers, RAM module details, the SSD's health log, firmware passwords
  and the system event log are only readable with admin rights.
- **Windows helpers.** Microsoft Edge prints the HTML report to PDF. Four small pieces of C#, visible in
  the scripts, are compiled when needed:
  - `windows/nvme.ps1` asks Windows for the SSD's health log. It opens a handle to the drive and sends one
    query (`IOCTL_STORAGE_QUERY_PROPERTY`). Windows requires read and write access on that handle, but the
    query only reads, and nothing is written to the drive.
  - `windows/diskspeed.ps1` writes and reads its test file with the Windows file cache bypassed, so the
    speed is the drive's own.
  - `windows/stress.ps1` runs the verified load in memory. Nothing is written to disk.
  - `windows/interactive.ps1` plays the test tones, records the microphone test and tells the left and right
    Shift, Ctrl and Alt keys apart.
- **Open source, in small parts.** Every line is in this repository. On Windows, `omen-audit.ps1` only
  starts things; each check is its own short file in `windows/` (the map is in `windows/README.md`). Linux
  and macOS have one script each, plus `lib/common.sh`, which they share.

## Check the download

Compare every file's fingerprint with the published list,
[SHA256SUMS.txt](https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/blob/main/docs/SHA256SUMS.txt),
also served at `https://secondtrust.sankalpjha.dev/SHA256SUMS.txt`. In the kit folder:

```powershell
$sums = (Invoke-WebRequest https://secondtrust.sankalpjha.dev/SHA256SUMS.txt -UseBasicParsing).Content -split "`n" | Where-Object { $_ -match '^[0-9a-f]{64}  ' }
$bad = @(foreach ($l in $sums) { $h, $f = $l -split '  ', 2; $f = $f.Trim(); if ((Get-FileHash $f).Hash.ToLower() -ne $h) { $f } })
if ($bad.Count) { "DIFFERENT: $($bad -join ', ')" } else { "All $($sums.Count) files match" }
```

```bash
cd ~/stressTestIt_beforeReturnWindowCloses-main
curl -fsSL https://secondtrust.sankalpjha.dev/SHA256SUMS.txt | grep -v '^#' | sha256sum -c -        # Linux
curl -fsSL https://secondtrust.sankalpjha.dev/SHA256SUMS.txt | grep -v '^#' | shasum -a 256 -c -    # macOS
```

Every Windows run also checks itself against the copy of the list that came with the download, records
the SHA-256 of each file it ran in `kit_files.csv`, and puts one short kit fingerprint in the report.

## What a report contains

Reports hold personal and identifying data. Look before you share:

- Serial numbers (laptop, board, RAM, SSD, battery) and network MAC addresses
- Local account names
- The list of installed software and startup items

## Limits

- **It is evidence, not a guarantee.** It reports what the firmware and the operating system say. A
  determined seller with access to the machine could alter what it sees.
- **Some faults only show physically.** `-Interactive` walks you through the screen, keys, touchpad,
  speakers, microphone, webcam and ports, but the verdict is yours. Coil whine, hinge play and chassis
  damage are for your eyes and ears.
- **An in-Windows memory test cannot reach all RAM.** `-Stress` tests half the free memory while Windows
  runs. MemTest86+ from a USB stick tests all of it.
- **The macOS script has run on one Mac so far** (MacBook Air M3). Intel Macs are untested.
- **Not yet code-signed.** Windows may warn about an unsigned script. A signing certificate is planned.
