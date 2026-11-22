# How to run it

Pick your system. Everything for it is in one place: setup, every command, and cleanup. Nothing is
uploaded, and nothing is installed unless you ask for it. Want to check the download first? See
[Trust](trust.md).

## Windows

Windows 10 and 11. Tested. The report is a PDF.

### Set up and run

Press `Win + X`, click **Terminal (Admin)** (or **Windows PowerShell (Admin)**), then **Yes**. Paste this
and press Enter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Invoke-WebRequest https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.zip -OutFile $env:TEMP\omen-kit.zip -UseBasicParsing
Expand-Archive $env:TEMP\omen-kit.zip -DestinationPath C:\omen-kit -Force; Remove-Item $env:TEMP\omen-kit.zip
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
.\omen-audit.ps1
```

The first line allows scripts in this window only. The audit asks once for the serial number on your
invoice and compares it with the BIOS; press Enter to skip. Reports land in `reports` inside the kit
folder, one folder per run. Pasting the block again updates the kit and keeps the reports.

### Every command

In a new admin window later, open the kit folder first:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
```

Full audit, with the invoice serial and a known profile (a wrong model then FAILs):

```powershell
.\omen-audit.ps1 -Laptop omen -InvoiceSerial PASTE-SERIAL-HERE
```

Hands-on tests: screen, every key, touchpad, speakers, microphone, webcam, every port:

```powershell
.\omen-audit.ps1 -Interactive
```

Verified CPU and RAM load, 30 minutes (press Q to stop early):

```powershell
.\omen-audit.ps1 -Stress -Minutes 30
```

GPU memory test, 10 minutes (at least 6):

```powershell
.\omen-audit.ps1 -GpuTest -Minutes 10
```

Everything at once, 1 hour:

```powershell
.\omen-audit.ps1 -Stress -GpuTest -Minutes 60
```

Sensor log only, while a game or OCCT runs in another window:

```powershell
.\omen-audit.ps1 -Monitor -Minutes 60
```

Every evening while you use it hard (new errors since the last check):

```powershell
.\omen-audit.ps1 -Quick
```

Some checks again, without the whole audit (names in [Checks](checks.md)):

```powershell
.\omen-audit.ps1 -Only storage,battery,devices
```

Generic mode, no spec comparison:

```powershell
.\omen-audit.ps1 -Laptop generic
```

### Load tests that check their answers

A laptop can survive hours of load and still compute wrong answers, and a plain busy loop never notices.
`-Stress` repeats fixed calculations on every CPU thread and half the free RAM and compares every result
with the right one, the way [gpu-burn](https://github.com/wilicc/gpu-burn) checks GPUs. `-GpuTest` does
the same for video memory with [memtest_vulkan](https://github.com/GpuZelenograd/memtest_vulkan), which
the kit downloads once and checks against its published fingerprint.

Every 2 seconds the load modes log clocks, load, temperatures, GPU power and slowdowns, the GPU's PCIe
link and the battery's power flow. They keep the laptop awake. Playing a video is not a load test: the
graphics chip decodes it and the CPU stays idle. For fan speed and CPU package power, keep HWiNFO64
logging alongside.

### Check the download

Every kit file against the published fingerprints ([Trust](trust.md) explains this):

```powershell
$sums = (Invoke-WebRequest https://secondtrust.sankalpjha.dev/SHA256SUMS.txt -UseBasicParsing).Content -split "`n" | Where-Object { $_ -match '^[0-9a-f]{64}  ' }
$bad = @(foreach ($l in $sums) { $h, $f = $l -split '  ', 2; $f = $f.Trim(); if ((Get-FileHash $f).Hash.ToLower() -ne $h) { $f } })
if ($bad.Count) { "DIFFERENT: $($bad -join ', ')" } else { "All $($sums.Count) files match" }
```

### Clean up

When you are done, inside the kit folder. Reports move to `C:\Users\<you>\SecondTrust-reports`, then the
kit, `C:\omen-kit` and the kit's temporary files are deleted. The kit installs nothing, so there is nothing
else to undo.

```powershell
.\omen-audit.ps1 -Cleanup
```

By hand, if the kit folder is already gone or broken:

```powershell
cd $env:USERPROFILE
$kit = 'C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main'
New-Item -ItemType Directory "$env:USERPROFILE\SecondTrust-reports" -Force | Out-Null
if (Test-Path "$kit\reports") { Get-ChildItem "$kit\reports" | Move-Item -Destination "$env:USERPROFILE\SecondTrust-reports" -Force }
Remove-Item C:\omen-kit, $env:TEMP\omen-kit.zip, $env:TEMP\omen-audit-edge, $env:TEMP\secondtrust_* -Recurse -Force -ErrorAction SilentlyContinue
```

Reports hold serial numbers and account names. Once you no longer need the evidence:

```powershell
Remove-Item $env:USERPROFILE\SecondTrust-reports -Recurse -Force
```

## Linux

An installed system or a live USB. Tested. The report is an HTML page.

### Set up and run

Open a terminal. Paste this and press Enter:

```bash
(curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz || wget -qO- https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz) | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
sudo bash linux-live-audit.sh --install
```

`--install` adds the tools it reads with (Debian and Ubuntu; elsewhere install smartmontools, dmidecode,
fwupd, stress-ng yourself). It needs `sudo` to read the serial, the RAM modules and the SSD's health.
Reports land in `reports` inside the kit folder, owned by you.

**Checking a Windows laptop from outside Windows:** boot Ubuntu from a USB stick ("Try Ubuntu"), connect
to Wi-Fi and run the same three lines. Windows cannot influence anything this sees. Copy the reports to
another stick before you reboot: a live session forgets everything.

### Every command

Inside `~/stressTestIt_beforeReturnWindowCloses-main`. Full audit plus a 15 minute stress test that
verifies every result:

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

Check the download against the published fingerprints:

```bash
curl -fsSL https://secondtrust.sankalpjha.dev/SHA256SUMS.txt | grep -v '^#' | sha256sum -c -
```

### Clean up

If you used `--install`, remove the tools first. It reads apt's own history, removes only what `--install`
added, and asks before removing:

```bash
sudo bash linux-live-audit.sh --remove-tools
```

Then keep the reports in `~/SecondTrust-reports` and remove the kit:

```bash
bash linux-live-audit.sh --cleanup
```

By hand, if the kit folder is already broken:

```bash
cd ~ && mkdir -p ~/SecondTrust-reports
sudo chown -R "$USER" ~/stressTestIt_beforeReturnWindowCloses-main
mv ~/stressTestIt_beforeReturnWindowCloses-main/reports/* ~/SecondTrust-reports/ 2>/dev/null
rm -rf ~/stressTestIt_beforeReturnWindowCloses-main
```

Once you no longer need the evidence:

```bash
rm -rf ~/SecondTrust-reports
```

## macOS

Tested on one Mac so far (MacBook Air M3); Intel Macs untested. The report is an HTML page.

### Set up and run

Open Terminal. Paste this and press Enter:

```bash
curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
bash mac-audit.sh
```

A run takes a few minutes, most of it reading 30 days of shutdown history. Reports land in `reports`
inside the kit folder. For SSD power-on hours, the best proof of prior use, install smartmontools first
(`brew install smartmontools`). If anything looks wrong, open an issue with the report.

### Every command

Inside `~/stressTestIt_beforeReturnWindowCloses-main`. With the invoice serial, plus the firmware password
check on Intel Macs:

```bash
sudo bash mac-audit.sh --serial PASTE-SERIAL-HERE
```

Generic mode:

```bash
bash mac-audit.sh --laptop generic
```

Check the download against the published fingerprints:

```bash
curl -fsSL https://secondtrust.sankalpjha.dev/SHA256SUMS.txt | grep -v '^#' | shasum -a 256 -c -
```

### Clean up

Keep the reports in `~/SecondTrust-reports` and remove the kit:

```bash
bash mac-audit.sh --cleanup
```

If you installed smartmontools only for this:

```bash
brew uninstall smartmontools
```

By hand, if the kit folder is already broken (this also keeps reports from older versions of the kit):

```bash
cd ~ && mkdir -p ~/SecondTrust-reports
mv ~/stressTestIt_beforeReturnWindowCloses-main/reports/* ~/stressTestIt_beforeReturnWindowCloses-main/mac-audit-* ~/SecondTrust-reports/ 2>/dev/null
rm -rf ~/stressTestIt_beforeReturnWindowCloses-main
```

Once you no longer need the evidence:

```bash
rm -rf ~/SecondTrust-reports
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

Each script recognises the laptop from its model name and board ID (on a Mac, its model identifier) and
says which profile it picked. With no match it runs in **generic mode**: specs are listed, not compared,
and every health, tamper and prior-use check still runs. Force a profile when you know what you paid for,
so a swapped model FAILs instead of quietly running in generic mode. Supported laptops and how to add one:
[Profiles](profiles.md).
