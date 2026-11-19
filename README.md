# OMEN Transcend 16 DOA kit

Full plan: the "OMEN Transcend 16 DOA Test Runbook" doc.

## Windows: omen-audit.ps1

Open PowerShell as administrator in this folder:

    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\omen-audit.ps1          # full audit: day 1, before installing anything, then again after the clean reinstall
    .\omen-audit.ps1 -Quick   # every evening during the soak: new WHEA, crashes, GPU driver resets, device errors

Each run creates reports\<PC>_<mode>_<timestamp>\ with SUMMARY.txt and MANIFEST.sha256.
Upload the folder to Drive the same day.

FAIL = DOA evidence. WARN = check by hand and record it. INFO = record it in the results log.

Before the clean reinstall, the script runs on the system exactly as delivered and does not change anything.
Optional extras it uses if present: nvidia-smi (comes with the NVIDIA driver) and smartctl (smartmontools for Windows).

## Linux live USB: linux-live-audit.sh

Boot Ubuntu 24.04 from USB (F9 boot menu), choose "Try Ubuntu", connect to Wi-Fi, then:

    sudo bash linux-live-audit.sh --install            # identity, SSD, firmware security, kernel errors
    sudo bash linux-live-audit.sh --install --stress   # plus a 15 min stress-ng with verification

Copy the linux-audit-<timestamp> folder to another USB stick before rebooting.

## Expected values for this unit

| Item | Expected |
| --- | --- |
| Product number | 834T6PA#ACJ |
| Board ID | 8BB3 |
| CPU | i7-13700HX, 16 cores, 24 threads |
| GPU | RTX 4070 Laptop, 8 GB, about 130W max |
| RAM | 2 x 8 GB DDR5-4800, matched part numbers |
| Battery | full charge at least 95% of design, single-digit cycles |
