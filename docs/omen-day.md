# OMEN day: a worked example

The exact sequence for the laptop this kit was built for: an open-box HP OMEN Transcend 16-u0005TX
(834T6PA) with a short dead-on-arrival (DOA) replacement window. Use it as a template for any laptop.

## This week, before it arrives

- [ ] Get the DOA window (15 or 30 days) from the seller **in writing**. Day 0 is the delivery date on the
      invoice or courier slip.
- [ ] Make a MemTest86+ USB stick (any stick of 1 GB or more; it gets erased). Download it from
      [memtest.org](https://www.memtest.org/). Write it with [Rufus](https://rufus.ie/) on Windows, or
      on Linux with `sudo dd if=<image> of=/dev/sdX bs=4M status=progress`, after checking `sdX` with
      `lsblk`. A wrong `sdX` erases the wrong disk.
- [ ] Bookmark the portable tools. Download them only **after** the first audit in Step 2:

| Tool | For | Link |
| --- | --- | --- |
| HWiNFO64 (portable) | Sensor logging: fans, CPU power | [hwinfo.com](https://www.hwinfo.com/download/) |
| OCCT | CPU, RAM, GPU and power stress with error detection | [ocbase.com](https://www.ocbase.com/) |
| CPU-Z, GPU-Z | Second opinion on identity | [cpuid.com](https://www.cpuid.com/softwares/cpu-z.html), [techpowerup.com](https://www.techpowerup.com/gpuz/) |
| CrystalDiskInfo, CrystalDiskMark | SSD health and speed | [crystalmark.info](https://crystalmark.info/en/) |
| Cinebench 2024 | Sustained CPU load | [maxon.net](https://www.maxon.net/en/cinebench) |
| Unigine Superposition | Sustained GPU load | [benchmark.unigine.com](https://benchmark.unigine.com/superposition) |
| OBS Studio | Screen recording for evidence | [obsproject.com](https://obsproject.com/) |
| iperf3 | Wi-Fi and Ethernet speed | [iperf.fr](https://iperf.fr/) |

- [ ] Charge your phone and clear space: you will film the whole unboxing in one take.

## Day 0: unboxing

1. Start filming before you cut the tape. Film the courier label and all six sides of the box.
2. Unbox on camera. Film the charger's label (model and wattage) and the bottom sticker. Read out the
   serial number and the product number. The product number must be **834T6PA#ACJ**.
3. Under bright light, look for opened or scratched bottom screws, gaps along the panel, dents, shiny keys,
   and bent pins in any port.
4. First boot: tap `Esc`, then `F10` for BIOS setup. Film the system information page: serial, product
   number, BIOS version, CPU, memory.

## Day 1, step 1: the audit, before anything else

Finish Windows setup, connect to Wi-Fi, then open an admin PowerShell and paste the Step 1 block from the
[guide](guide.md). Then run the audit with the profile forced and the invoice serial:

```powershell
.\omen-audit.ps1 -Laptop omen -InvoiceSerial <serial from the invoice>
```

`-Laptop omen` makes a wrong or swapped model FAIL instead of falling back to generic mode.

**What a genuine, lightly used unit looks like:**

- PASS for serial, product number, model, board ID, CPU (16 cores, 24 threads), RTX 4070 with 8 GB,
  2560x1600 at 240 Hz, 2 matched RAM modules, a 1 TB SSD, Secure Boot with HP's keys, no BIOS password,
  no company enrollment, webcam, Wi-Fi and Bluetooth.
- SSD: a few dozen power-on hours at most and well under 1 TB written. Hundreds of hours means weeks of use.
- Battery: at least 95% of design capacity and single-digit cycles.
- Event logs: anything dated before delivery happened at the previous owner or the refurbisher. Record it.

**Upload the whole `reports` folder to Google Drive now.** The reinstall in step 3 erases it.

## Day 1, step 2: HP's own hardware test

Power on, tap `Esc`, then `F2`: HP PC Hardware Diagnostics UEFI. Run the Extensive Test (1 to 2 hours).
Photograph the result. HP support asks for its failure ID before anything else.

## Day 1, step 3: clean reinstall, then audit again

1. Run a Microsoft Defender Offline scan.
2. Update the BIOS from HP's site.
3. Reinstall Windows with the HP Cloud Recovery Tool.
4. Install drivers from HP Support Assistant and NVIDIA, and OMEN Gaming Hub.
5. Paste the Step 1 block again (the reinstall erased the kit) and run the full audit again. Keep both
   reports.

## Days 2 to 4: stress tests

In Performance mode, on the HP charger, on a hard flat surface. For **every** test, open a second admin
window and log it:

```powershell
.\omen-audit.ps1 -Monitor -Minutes 60
```

| Test | Tool | Pass |
| --- | --- | --- |
| RAM, outside Windows | MemTest86+ USB, 4 passes overnight | 0 errors |
| CPU | OCCT CPU, 1 hour | 0 errors, no WHEA |
| GPU | OCCT 3D Adaptive with error detection, 1 hour | 0 errors |
| Whole system | OCCT Power, 1 hour | No shutdown, no driver reset |
| Sustained | Cinebench 2024 30 min loop, Superposition 30 min | Last score within about 5% of the first |
| Real games | Your heaviest games, 2 hours each | No crash, no GPU dropout |

The monitor WARNs if the GPU sustains under 95 W at full load. LaptopMedia measured this model at about
109 W and 2280 MHz after 30 minutes.

## Every evening until the window closes

```powershell
.\omen-audit.ps1 -Quick
```

Anything new (a hardware error, a crash, a GPU that vanished) is a FAIL. Email the seller the same day with
the PDF, the video, the serial number and the invoice number.
