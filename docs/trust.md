# Trust and privacy

You are asked to paste a command into an administrator or `sudo` terminal. Be careful with that request:
it is also how malware spreads. Here is exactly what this kit does, and how to check it yourself.

## What it does

- **Reads only.** It reads hardware information, firmware settings, logs and drive health. It does not
  change settings. It writes its own report folder, plus temporary files (on Windows, Edge's print
  profile and the compiled helper below, in `%TEMP%`).
- **Installs nothing unless you ask.** Only the Linux `--install` option installs packages, through your
  package manager, and it says which ones.
- **Nothing leaves your machine.** No telemetry, no uploads, no accounts. The report stays in its folder
  until you share it yourself.
- **Root or admin, and why.** Serial numbers, RAM module details, the SSD's health log, firmware passwords
  and the system event log are only readable with admin rights.
- **Windows helpers.** Microsoft Edge prints the HTML report to PDF. A small piece of C#, visible in the
  script, is compiled to ask Windows for the SSD's health log. It opens a handle to the drive and sends one
  query (`IOCTL_STORAGE_QUERY_PROPERTY`). Windows requires read and write access on that handle, but the
  query only reads, and nothing is written to the drive.
- **Open source.** Every line is in this repository. Each script is one file you can read top to bottom,
  plus `lib/common.sh`, shared by the Linux and macOS scripts.

## Check the download

Compare each file's fingerprint with the published one before running it. The result must match the
file's line in
[SHA256SUMS.txt](https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/blob/main/docs/SHA256SUMS.txt).

```powershell
(Get-FileHash C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main\omen-audit.ps1).Hash
```

```bash
cd ~/stressTestIt_beforeReturnWindowCloses-main
sha256sum linux-live-audit.sh lib/common.sh     # Linux
shasum -a 256 mac-audit.sh lib/common.sh        # macOS
```

Windows prints the fingerprint in capitals and the file lists it in lower case: the letters are the same.
Every report also records the SHA-256 of the script that produced it.

## What a report contains

Reports hold personal and identifying data. Look before you share:

- Serial numbers (laptop, board, RAM, SSD, battery) and network MAC addresses
- Local account names
- The list of installed software and startup items

## Limits

- **It is evidence, not a guarantee.** It reports what the firmware and the operating system say. A
  determined seller with access to the machine could alter what it sees.
- **Some faults only show physically:** dead pixels, keyboard keys, ports, speakers, coil whine. Test
  those by hand.
- **The macOS script is experimental.** It was written without a Mac to test on.
- **Not yet code-signed.** Windows may warn about an unsigned script. A signing certificate is planned.
