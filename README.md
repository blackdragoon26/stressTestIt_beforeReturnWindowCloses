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

Every run makes a folder `reports\<PC>_<mode>_<date_time>\` with `SUMMARY.txt`, the raw files, and
`MANIFEST.sha256` (fingerprints that prove the files were not edited later).

## Before the laptop arrives

1. Copy this whole folder to a USB stick. Run the script from the stick, not from `C:`.
   The reports then land on the stick and survive the Windows reinstall on day 1.
2. Put the portable test tools from the runbook on the same stick (HWiNFO64, OCCT, CPU-Z, GPU-Z,
   CrystalDiskInfo, CrystalDiskMark).

## Step 1: open PowerShell as administrator (every time)

1. Plug in the USB stick.
2. Press `Win + X`, then click **Terminal (Admin)** (or **Windows PowerShell (Admin)**). Click **Yes**.
3. Go to the stick. If the stick is drive `E:` and the folder is `omen-kit`:

        cd E:\omen-kit

4. Allow scripts for this window only (it resets when the window closes):

        Set-ExecutionPolicy -Scope Process Bypass -Force

## Step 2: day 1, full audit on the system exactly as delivered

Do this before you install, update or sign in to anything:

    .\omen-audit.ps1

It takes a few minutes (msinfo32 is the slow part). It changes nothing on the laptop. It checks:

- Identity: product number 834T6PA, model, board ID 8BB3, serial number, BIOS version
- Genuine parts: CPU i7-13700HX with 16 cores and 24 threads, RTX 4070, 2 matched RAM modules, RAM slots
- Prior use: SSD power-on hours and errors, battery health and cycle count
- Tampering: Secure Boot on, Secure Boot keys are HP's (FAIL on leaked test keys), no BIOS password set
  by someone else, TPM, boot entries, Windows OEM key and activation, company or MDM enrollment, admin accounts
- Errors: devices with driver errors, WHEA hardware errors, crashes and GPU driver resets in the last 30 days

Upload the report folder to Drive the same day.

## Step 3: after the clean reinstall

After the Windows reinstall (HP Cloud Recovery Tool) and the HP and NVIDIA drivers, run the full audit again:

    .\omen-audit.ps1

Keep both reports. The second one also reads the RTX 4070 power limit through nvidia-smi.

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

## Testing on a different laptop

Every expected value is a parameter. Example for the ASUS VivoBook X515DA used to develop this kit:

    .\omen-audit.ps1 -ExpectProductNumber X515DA -ExpectModel VivoBook -ExpectBoardId X515DA `
        -ExpectCpu 3500U -ExpectCores 4 -ExpectThreads 8 -ExpectGpu Radeon `
        -ExpectRamModules 2 -ExpectRamGB 8 -ExpectPk ASUS

## Expected values for this unit

| Item | Expected |
| --- | --- |
| Product number | 834T6PA#ACJ |
| Board ID | 8BB3 |
| CPU | i7-13700HX, 16 cores, 24 threads |
| GPU | RTX 4070 Laptop, 8 GB, about 130 W max |
| RAM | 2 x 8 GB DDR5-4800, matched part numbers |
| Battery | full charge at least 95% of design, single-digit cycles |
| Sustained (LaptopMedia) | GPU about 2280 MHz at 109 W after 30 min gaming, CPU P-cores about 3.0 GHz at 82 C |

## Optional: linux-live-audit.sh

A second opinion from outside Windows, booted from an Ubuntu USB stick. Not needed for the normal plan:

    sudo bash linux-live-audit.sh --install            # identity, SSD, firmware security, kernel errors
    sudo bash linux-live-audit.sh --install --stress   # plus a 15 min stress-ng with verification
