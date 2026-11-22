# How to run it

Pick your operating system. Each one downloads the kit, unpacks it, and runs the audit. Nothing is uploaded,
and nothing is installed unless you ask for it.

| System | Script | Report | Status |
| --- | --- | --- | --- |
| Windows 10 and 11 | `omen-audit.ps1` | PDF and HTML | Tested |
| Linux (installed or live USB) | `linux-live-audit.sh` | HTML | Tested |
| macOS | `mac-audit.sh` | HTML | Tested on one Mac (MacBook Air M3); Intel Macs untested |

Want to check the download first? See [Trust](trust.md).

## Windows

Press `Win + X`, click **Terminal (Admin)** (or **Windows PowerShell (Admin)**), then **Yes**. Paste this
and press Enter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Invoke-WebRequest https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.zip -OutFile $env:TEMP\omen-kit.zip -UseBasicParsing
Expand-Archive $env:TEMP\omen-kit.zip -DestinationPath C:\omen-kit -Force; Remove-Item $env:TEMP\omen-kit.zip
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
.\omen-audit.ps1
```

The first line allows scripts in this window only; it resets when the window closes. The audit asks once
for the serial number on your invoice and compares it with the BIOS. Press Enter to skip.

| Command | When |
| --- | --- |
| `.\omen-audit.ps1` | The full audit, the day the laptop arrives, before you install anything |
| `.\omen-audit.ps1 -Interactive` | Hands-on tests: screen, every key, touchpad, speakers, microphone, webcam, every port |
| `.\omen-audit.ps1 -Stress -Minutes 30` | Full CPU and RAM load where every result is checked, with the sensor log |
| `.\omen-audit.ps1 -GpuTest -Minutes 10` | Checks every byte of the GPU's memory, with the sensor log |
| `.\omen-audit.ps1 -Monitor -Minutes 60` | Sensor log only, while you run a game or another stress tool |
| `.\omen-audit.ps1 -Quick` | Every evening while you use it hard |
| `.\omen-audit.ps1 -Only storage,battery` | Run some checks again (names in [Checks](checks.md)) |
| `.\omen-audit.ps1 -InvoiceSerial 5CD1234XYZ` | Pass the serial instead of typing it |
| `.\omen-audit.ps1 -Laptop omen` | Force a profile (see below) |

Reports land in `C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main\reports`, one folder per run. Pasting the
block again updates the kit and keeps the reports. In a new window later, you only need the first and fourth
lines.

When you are done, one command keeps your reports and removes the rest: see [Clean up](#clean-up) below.

**Load tests that check their own answers.** A laptop can survive hours of load and still compute wrong
answers. That is a fault you can return it for, and a plain busy loop never notices. `-Stress` loads every
CPU thread and half the free RAM with fixed calculations and compares every result with the right one,
the way [gpu-burn](https://github.com/wilicc/gpu-burn) checks GPUs. `-GpuTest` does the same for the
GPU's memory with [memtest_vulkan](https://github.com/GpuZelenograd/memtest_vulkan), which the kit
downloads once and checks against its published fingerprint. Run both together for a whole-system test:
`.\omen-audit.ps1 -Stress -GpuTest -Minutes 60`.

All three load modes log, every 2 seconds, CPU and GPU clocks, load, temperatures, GPU power and slowdown
reasons, the GPU's PCIe link, and the battery's power flow. At the end they flag wrong results, GPU
dropouts, hardware slowdowns, low sustained GPU power, a charger that cannot keep up, and any crash during
the test. Press `Q` to stop early. Windows does not report fan speed or CPU package power: keep HWiNFO64
logging alongside for those.

## Linux

Open a terminal. Paste this and press Enter:

```bash
(curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz || wget -qO- https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz) | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
sudo bash linux-live-audit.sh --install
```

| Option | What it does |
| --- | --- |
| `--install` | Installs the tools it reads with (smartmontools, dmidecode, fwupd, stress-ng, and others). Debian and Ubuntu only; elsewhere, install them yourself |
| `--stress` | Adds a 15 minute CPU and memory stress test that verifies every result |
| `--serial 5CD1234XYZ` | Compares the firmware serial with your invoice |
| `--laptop omen` | Forces a profile, or `--laptop generic` |

Reports land in `reports` inside the kit folder, one folder per run, owned by you even though the audit ran
with `sudo`. It needs `sudo` to read the serial, the RAM modules and the SSD's health. When you are done:
[Clean up](#clean-up).

**Checking a Windows laptop from outside Windows:** boot Ubuntu from a USB stick ("Try Ubuntu"), connect to
Wi-Fi, and run the same three lines. Windows cannot influence anything this sees. Copy the report folder to
another stick before you reboot: a live session forgets everything.

## macOS

Open Terminal. Paste this and press Enter:

```bash
curl -fsSL https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/archive/refs/heads/main.tar.gz | tar -xz -C ~
cd ~/stressTestIt_beforeReturnWindowCloses-main
bash mac-audit.sh
```

| Option | What it does |
| --- | --- |
| `--serial C02XXXXXXX` | Compares the serial with your invoice |
| `--laptop generic` | Forces a profile or generic mode |
| run with `sudo` | Adds the firmware password check on Intel Macs |

Reports land in `reports` inside the kit folder, one folder per run. A run takes a few minutes, most of
it reading 30 days of shutdown history.

For SSD power-on hours, the best proof of prior use, install smartmontools first
(`brew install smartmontools`). Without it the report shows the drive's SMART status only.

The macOS script has run on one Mac so far (MacBook Air M3, macOS 26). If anything looks wrong, especially
on an Intel Mac, open an issue with the report.

## Every command, ready to copy

One block per command, each with its own Copy button. Run them inside the kit folder from the steps above.

### Windows (admin PowerShell)

Open the kit folder in a new window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main
```

Full audit:

```powershell
.\omen-audit.ps1
```

Full audit with the invoice serial, comparing against a known profile:

```powershell
.\omen-audit.ps1 -Laptop omen -InvoiceSerial PASTE-SERIAL-HERE
```

Generic mode (no spec comparison, every other check):

```powershell
.\omen-audit.ps1 -Laptop generic
```

Hands-on tests (pick some or all from the menu it shows):

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

Playing a video, even 4K gameplay, is not a load test: the graphics chip decodes it and the CPU stays mostly
idle. The load modes keep the laptop awake while they run. If the lid is closed anyway, the report shows
the gap and whether the laptop slept.

Some checks again, without the whole audit:

```powershell
.\omen-audit.ps1 -Only storage,battery,devices
```

Evening check (new errors since the last one):

```powershell
.\omen-audit.ps1 -Quick
```

Check every kit file against the published fingerprints ([Trust](trust.md) explains this):

```powershell
$sums = (Invoke-WebRequest https://secondtrust.sankalpjha.dev/SHA256SUMS.txt -UseBasicParsing).Content -split "`n" | Where-Object { $_ -match '^[0-9a-f]{64}  ' }
$bad = @(foreach ($l in $sums) { $h, $f = $l -split '  ', 2; $f = $f.Trim(); if ((Get-FileHash $f).Hash.ToLower() -ne $h) { $f } })
if ($bad.Count) { "DIFFERENT: $($bad -join ', ')" } else { "All $($sums.Count) files match" }
```

### Linux (terminal, inside `~/stressTestIt_beforeReturnWindowCloses-main`)

Full audit, installing the tools it needs first:

```bash
sudo bash linux-live-audit.sh --install
```

Full audit plus the 15 minute verified stress test:

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

Fingerprints:

```bash
sha256sum linux-live-audit.sh lib/common.sh
```


### macOS (Terminal, inside `~/stressTestIt_beforeReturnWindowCloses-main`)

Full audit:

```bash
bash mac-audit.sh
```

With the firmware password check (Intel Macs) and the invoice serial:

```bash
sudo bash mac-audit.sh --serial PASTE-SERIAL-HERE
```

Generic mode:

```bash
bash mac-audit.sh --laptop generic
```

Fingerprints:

```bash
shasum -a 256 mac-audit.sh lib/common.sh
```


## Clean up

When you are done with the kit: after the return window, or after checking a laptop you are buying. Your
reports are kept; everything else the kit put on the computer goes.

### Windows

In an admin PowerShell, inside the kit folder:

```powershell
.\omen-audit.ps1 -Cleanup
```

It moves every report to `C:\Users\<you>\SecondTrust-reports`, then deletes `C:\omen-kit` (with the GPU
test's download, which lives inside it) and the kit's temporary files in `%TEMP%`. There is nothing else to
undo: the kit installs nothing, and `Set-ExecutionPolicy -Scope Process` ends when the window closes.

If the kit folder is already gone or broken, the same by hand, in any admin PowerShell:

```powershell
cd $env:USERPROFILE
$kit = 'C:\omen-kit\stressTestIt_beforeReturnWindowCloses-main'
New-Item -ItemType Directory "$env:USERPROFILE\SecondTrust-reports" -Force | Out-Null
if (Test-Path "$kit\reports") { Get-ChildItem "$kit\reports" | Move-Item -Destination "$env:USERPROFILE\SecondTrust-reports" -Force }
Remove-Item C:\omen-kit, $env:TEMP\omen-kit.zip, $env:TEMP\omen-audit-edge, $env:TEMP\secondtrust_* -Recurse -Force -ErrorAction SilentlyContinue
```

### Linux

If you used `--install`, remove the tools first. It reads apt's own history and removes only the packages
`--install` added; anything you already had stays. It shows the list and asks before removing:

```bash
cd ~/stressTestIt_beforeReturnWindowCloses-main
sudo bash linux-live-audit.sh --remove-tools
```

Then keep the reports in `~/SecondTrust-reports` and remove the kit:

```bash
cd ~/stressTestIt_beforeReturnWindowCloses-main
bash linux-live-audit.sh --cleanup
```

By hand, if the kit folder is already broken:

```bash
cd ~ && mkdir -p ~/SecondTrust-reports
sudo chown -R "$USER" ~/stressTestIt_beforeReturnWindowCloses-main
mv ~/stressTestIt_beforeReturnWindowCloses-main/reports/* ~/SecondTrust-reports/ 2>/dev/null
rm -rf ~/stressTestIt_beforeReturnWindowCloses-main
```

On a live USB there is nothing to clean up: the session forgets everything when it shuts down. Copy the
reports to another stick first.

### macOS

```bash
cd ~/stressTestIt_beforeReturnWindowCloses-main
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

### Removing the reports too

Reports hold serial numbers, MAC addresses and account names. Delete them only when you no longer need the
evidence, for example once the return window has closed.

```powershell
Remove-Item $env:USERPROFILE\SecondTrust-reports -Recurse -Force
```

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

All three scripts read the same profiles from the `profiles` folder. Each script recognises the laptop from
its model name and board ID (on a Mac, its model identifier) and says which profile it picked.

| Situation | Result |
| --- | --- |
| A profile matches | Every spec is compared: FAIL or WARN on any difference |
| No profile matches | **Generic mode.** Specs are listed, not compared. All health, tamper and prior-use checks still run |
| You force a profile | That profile is used even if the laptop does not look like it |

Force the profile when you know what you paid for. A swapped or wrong model then FAILs instead of quietly
running in generic mode. Supported laptops and how to add one: [Profiles](profiles.md).
