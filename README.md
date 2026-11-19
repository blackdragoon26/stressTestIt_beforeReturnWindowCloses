# OMEN Transcend 16 DOA kit

A Windows script that finds faults in a new or open-box HP OMEN Transcend 16 (16-u0005TX, 834T6PA)
inside the dead-on-arrival (DOA) return window, and saves evidence for the claim.

Full plan (day by day, which stress tools, pass criteria, results log): the
"OMEN Transcend 16 DOA Test Runbook" doc. This README is how to run the script.

## Reading the results

| Label | Meaning | What you do |
| --- | --- | --- |
| FAIL | DOA evidence | Screenshot it, record it, email the seller the same day |
| WARN | Needs a look by hand | Check it, write down what you found |
| PASS | As expected | Nothing |
| INFO | A value to record | Copy it into the results log |

Every run makes a folder `reports\<PC>_<mode>_<date_time>\` with:

- `DOA_report_<mode>_<date_time>.pdf`: **the file to share.** All results, the expected values, every part
  with its exact model and serial (CPU, GPU, RAM, SSD, panel, battery, Wi-Fi, Bluetooth, camera, audio,
  touchpad, USB and Thunderbolt), sensor charts from `-Monitor`, the raw outputs, and any script errors at
  the end so a person or another agent can review it. It is made even if a check crashes or the laptop is
  not recognised. Microsoft Edge (built into Windows) prints it; if that fails, the same report is there as
  `.html` to open and print.
- `SUMMARY.txt`, the raw files, and `MANIFEST.sha256` (fingerprints that prove no file was edited later).

## Get the kit onto the laptop (no Git needed)

1. Open this repo's page on GitHub in the browser. Click **Code**, then **Download ZIP**.
2. In Downloads, right-click the ZIP and choose **Extract All**.

Do not install Git or anything else before Step 2: the first report should show the laptop as delivered.
Portable versions of the runbook tools (HWiNFO64, OCCT, CPU-Z, GPU-Z, CrystalDiskInfo, CrystalDiskMark)
are fine: they run without installing.

## Step 1: open PowerShell as administrator (every time)

1. Press `Win + X`, then click **Terminal (Admin)** (or **Windows PowerShell (Admin)**). Click **Yes**.
2. Go to the kit folder. This finds it inside Downloads, wherever Extract All put it:

        cd (Get-ChildItem $HOME\Downloads -Recurse -Filter omen-audit.ps1 | Select-Object -First 1).DirectoryName

3. Allow scripts for this window only (it resets when the window closes). This also lifts the
   "downloaded from the internet" block Windows puts on the file:

        Set-ExecutionPolicy -Scope Process Bypass -Force

## Step 2: day 1, full audit on the system exactly as delivered

Do this before you install, update or sign in to anything:

    .\omen-audit.ps1

It first asks for the serial number printed on the invoice: type it and press Enter. It compares it
with the serial in the BIOS itself. Then it runs on its own for a few minutes (msinfo32 is the slow part)
and changes nothing on the laptop.

It knows what this laptop is supposed to have (table at the bottom) and flags every difference itself:

- Identity: product number 834T6PA, model, board ID 8BB3, serial number against the invoice, BIOS version
- Genuine parts: CPU i7-13700HX with 16 cores and 24 threads, RTX 4070 with 8 GB, 16 GB RAM in 2 matched
  modules at 4800 MT/s or faster, 1 TB SSD, 2560x1600 240 Hz panel, 97 Wh battery, webcam, Wi-Fi, Bluetooth
- Prior use: SSD power-on hours and errors, battery health and cycle count
- Tampering: Secure Boot on, Secure Boot keys are HP's (FAIL on leaked test keys), no BIOS password set
  by someone else, TPM, boot entries, Windows OEM key and activation, company or MDM enrollment, admin accounts
- Errors: devices with driver errors, WHEA hardware errors, crashes and GPU driver resets in the last 30 days

**Upload the `reports` folder to Google Drive now, before Step 3.** The reinstall erases the whole drive,
and this report is your only record of the laptop as the seller delivered it.

## Step 3: after the clean reinstall

The reinstall wiped the kit too. Download the ZIP again (or install Git now and `git clone`, it no longer matters).

After the Windows reinstall (HP Cloud Recovery Tool) and the HP and NVIDIA drivers, run the full audit again:

    .\omen-audit.ps1

Keep both reports. The second one also checks the GPU memory (8 GB) through nvidia-smi, which comes
with the NVIDIA driver.

## Step 4: during every stress test, log the sensors

Open a **second** admin PowerShell window (Step 1 again) and start the monitor, then start the stress test
(OCCT, Cinebench loop, a game) in the other window:

    .\omen-audit.ps1 -Monitor -Minutes 60

- Set `-Minutes` to the length of the test. Press `Q` to stop early.
- Every 2 seconds it writes `sensors.csv`: CPU load, CPU clock, CPU firmware limit, board temperature,
  GPU temperature, GPU power, GPU clocks, GPU load, GPU slowdown reasons, charger on or off.
- At the end it flags:
  - FAIL: the GPU stopped answering (GPU dropout), or a crash, WHEA error or driver reset happened during the test
  - WARN: GPU hardware slowdown (thermal or power brake), GPU at 87 C or above, sustained GPU power
    under 95 W at full load (this model does about 109 W), samples taken on battery
- Fan speed and CPU package power are not available from Windows itself. Keep HWiNFO64 logging to CSV
  next to it for those, as the runbook says.

Run on the HP charger, in Performance mode in OMEN Gaming Hub, on a hard flat surface.

## Step 5: every evening during the soak

    .\omen-audit.ps1 -Quick

Lists anything new since the last quick run: WHEA hardware errors, unexpected shutdowns, blue screens,
NVIDIA driver resets, disk errors, devices with errors, and whether the RTX 4070 is still present.
Takes a few seconds.

## Which laptop it checks against

Nothing to set. The script reads the laptop's model name and board ID and picks the matching profile.
The first line of every report says which one it picked. It knows two laptops:

- **omen**: the HP OMEN Transcend 16-u0005TX, the real target
- **asus**: the ASUS VivoBook 15 X515DA used to test this kit. On that laptop, expect real WARNs for
  the old SSD (19,000+ hours) and the worn battery (about 60%, 1,800+ cycles), and PASS for the rest

A laptop it does not recognise is checked against the OMEN, so a wrong or swapped machine fails loudly.
To force a profile: `.\omen-audit.ps1 -Laptop omen`. To skip the serial question: `-InvoiceSerial <serial>`.

## Expected values (omen profile)

| Item | Expected | On mismatch |
| --- | --- | --- |
| Product number | 834T6PA (box says 834T6PA#ACJ) | FAIL |
| Model / board ID | Transcend / 8BB3 | FAIL / WARN |
| CPU | i7-13700HX, 16 cores, 24 threads | FAIL |
| GPU | RTX 4070 Laptop, 8 GB | FAIL |
| RAM | 2 x 8 GB, matched part numbers, at least 4800 MT/s | FAIL / WARN / WARN |
| SSD | about 1 TB (900 to 1100 GB) | FAIL |
| Display | 2560x1600, 240 Hz | FAIL / WARN |
| Battery | designed for about 97 Wh; full charge at least 95% of design; under 10 cycles | WARN |
| Secure Boot key | HP's | WARN (FAIL if a leaked test key) |
| Webcam, Wi-Fi, Bluetooth | present and working | FAIL |
| Sustained (LaptopMedia) | GPU about 2280 MHz at 109 W after 30 min gaming, CPU P-cores about 3.0 GHz at 82 C | -Monitor WARN under 95 W |

The battery is only a WARN because spec listings disagree (one says 45 Wh, reviews of this model say 97 Wh).
If it fires, ask HP support which battery your serial number shipped with. Do not open the laptop to look.

## Optional: linux-live-audit.sh

A second opinion from outside Windows, booted from an Ubuntu USB stick. Not needed for the normal plan:

    sudo bash linux-live-audit.sh --install            # identity, SSD, firmware security, kernel errors
    sudo bash linux-live-audit.sh --install --stress   # plus a 15 min stress-ng with verification
