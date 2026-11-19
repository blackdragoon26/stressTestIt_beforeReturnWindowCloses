# Trust and privacy

You are asked to paste a command into an administrator PowerShell. Be careful with that request: it is
also how malware spreads. Here is exactly what this kit does, and how to check it yourself.

## What it does

- **Reads only.** It reads hardware information, firmware settings, event logs and drive health. It does
  not change settings or install software. It writes its own `reports` folder, plus temporary files in
  `%TEMP%` (Edge's print profile and the compiled helper below).
- **Nothing leaves your machine.** No telemetry, no uploads, no accounts. The report stays in `reports`
  until you share it yourself.
- **Two built-in helpers.** Microsoft Edge prints the HTML report to PDF. A small piece of C#, visible in
  the script, is compiled to ask Windows for the SSD's health log. It opens a handle to the drive and
  sends one query (`IOCTL_STORAGE_QUERY_PROPERTY`). Windows requires read and write access on that handle,
  but the query only reads, and nothing is written to the drive.
- **Open source.** Every line is in this repository. `omen-audit.ps1` is one file you can read top to
  bottom.

## Check the download

Compare the file's fingerprint with the published one before running it:

```powershell
(Get-FileHash C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main\omen-audit.ps1).Hash
```

The result must match the `omen-audit.ps1` line in
[SHA256SUMS.txt](https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/blob/main/docs/SHA256SUMS.txt)
(Windows prints it in capitals, the file lists it in lower case: the letters are the same). Every report
also records the SHA-256 of the script that produced it.

## What a report contains

Reports hold personal and identifying data. Look before you share:

- Serial numbers (laptop, board, RAM, SSD, battery) and network MAC addresses
- Local account names
- The list of installed software and startup items

## Limits

- **It is evidence, not a guarantee.** It reports what the firmware and Windows say. A determined seller
  with access to the machine could alter what it sees.
- **Some faults only show physically:** dead pixels, keyboard keys, ports, speakers, coil whine. The guide
  lists hands-on tests for those.
- **Not yet code-signed.** Windows may warn about an unsigned script. A signing certificate is planned.
