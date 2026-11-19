#!/usr/bin/env bash
# Laptop audit for Linux: an installed system or a live USB (outside the laptop's own OS, so that OS
# cannot influence it). Identity and specs against the laptop's profile, SSD health and prior use,
# firmware security, kernel hardware errors, battery wear, optional verified stress test.
#
# Usage:
#   sudo bash linux-live-audit.sh                   # audit
#   sudo bash linux-live-audit.sh --install         # apt-install the tools it uses first (Debian/Ubuntu)
#   sudo bash linux-live-audit.sh --stress          # also a 15 min CPU + memory stress test with verification
#   sudo bash linux-live-audit.sh --laptop omen     # force a profile (or --laptop generic)
#   sudo bash linux-live-audit.sh --serial 5CD123   # compare the serial with your invoice
#
# Output: ./linux-audit-<timestamp>/ with SUMMARY.txt, an HTML report and MANIFEST.sha256.
# On a live USB, copy that folder somewhere before you reboot: a live session forgets everything.

set -u
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$KIT/lib/common.sh"

INSTALL=0; STRESS=0; LAPTOP=auto; INVOICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --stress)  STRESS=1 ;;
    --laptop)  LAPTOP="${2:-}"; shift ;;
    --serial)  INVOICE="${2:-}"; shift ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done

# DOA_DEV=1 skips the root check, to test the script's logic without sudo (most checks then read less)
if [ "$(id -u)" -ne 0 ] && [ "${DOA_DEV:-0}" != 1 ]; then
  echo "Run with sudo."; exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$(pwd)/linux-audit-$STAMP"
mkdir -p "$OUT"
SUMMARY="$OUT/SUMMARY.txt"
: > "$SUMMARY"
SSD_HOURS_WARN=100

if [ "$INSTALL" -eq 1 ]; then
  if have apt-get; then
    add-apt-repository -y universe >/dev/null 2>&1 || true
    apt-get update -qq
    apt-get install -y -qq dmidecode pciutils usbutils nvme-cli smartmontools fwupd \
      lm-sensors stress-ng bolt mokutil >/dev/null
  else
    echo "--install only knows apt-get. Install with your package manager: dmidecode pciutils usbutils"
    echo "nvme-cli smartmontools fwupd lm-sensors stress-ng mokutil"
  fi
fi

dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null; }

# ---------- profile ----------
product="$(dmi product_name)"; board="$(dmi board_name)"; vendor="$(dmi sys_vendor)"
pick_profile "$product $board" "$LAPTOP"
report_profile_line

# ---------- identity ----------
sku="$(dmi product_sku)"; serial="$(dmi product_serial)"
if [ -n "$INVOICE" ] && [ -n "$serial" ]; then
  if [ "$(printf '%s' "$INVOICE" | tr '[:lower:]' '[:upper:]')" = "$(printf '%s' "$serial" | tr '[:lower:]' '[:upper:]')" ]; then
    result PASS "Serial number" "$serial matches the invoice"
  else result FAIL "Serial number" "firmware says '$serial', the invoice says '$INVOICE'"; fi
else
  result INFO "Serial number" "${serial:-(needs sudo)} (not compared: pass --serial from the invoice)"
fi
result INFO "BIOS" "$(dmi bios_version) ($(dmi bios_date))"
if ! spec_has ProductNumber; then result INFO "Product number" "'$sku'"
elif [ -z "$(spec ProductNumber)" ]; then result INFO "Product number" "this model's firmware stores none"
elif printf '%s' "$sku" | grep -qi -- "$(spec ProductNumber)"; then result PASS "Product number" "$sku"
else result FAIL "Product number" "got '$sku', expected $(spec ProductNumber)"; fi
if ! spec_has Model; then result INFO "Model" "$vendor $product"
elif printf '%s' "$product" | grep -qiE -- "$(spec Model)"; then result PASS "Model" "$product"
else result FAIL "Model" "got '$product', expected $(spec Model)"; fi
if ! spec_has BoardId; then result INFO "Board ID" "$board"
elif [ "$board" = "$(spec BoardId)" ]; then result PASS "Board ID" "$board"
else result WARN "Board ID" "got '$board', expected $(spec BoardId). Ask the maker or the seller why it differs"; fi
have dmidecode && save dmidecode.txt dmidecode

# ---------- CPU ----------
cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
threads="$(nproc --all)"
cps="$(lscpu | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,"",$2); print $2}')"
sockets="$(lscpu | awk -F: '/^Socket\(s\)/ {gsub(/ /,"",$2); print $2}')"
cores=$(( ${cps:-0} * ${sockets:-1} ))
save lscpu.txt lscpu
if ! spec_has Cpu; then result INFO "CPU model" "$cpu"
elif printf '%s' "$cpu" | grep -qiE -- "$(spec Cpu)"; then result PASS "CPU model" "$cpu"
else result FAIL "CPU model" "got '$cpu', expected $(spec Cpu)"; fi
if ! spec_has Cores; then result INFO "CPU cores/threads" "${cores}C / ${threads}T"
elif [ "$cores" = "$(spec Cores)" ] && [ "$threads" = "$(spec Threads)" ]; then result PASS "CPU cores/threads" "${cores}C / ${threads}T"
else result FAIL "CPU cores/threads" "got ${cores}C / ${threads}T, expected $(spec Cores)C / $(spec Threads)T"; fi

# ---------- GPU, PCI, USB, Thunderbolt ----------
if have lspci; then
  save lspci.txt lspci -nnk
  gpus="$(lspci | grep -iE 'VGA|3D|Display' | cut -d: -f3- | sed 's/^ //')"
  if ! spec_has Gpu; then result INFO "GPU" "$(printf '%s' "$gpus" | tr '\n' ';')"
  elif printf '%s' "$gpus" | grep -qiE -- "$(spec Gpu)"; then result PASS "GPU" "$(printf '%s' "$gpus" | grep -iE -- "$(spec Gpu)" | head -1)"
  else result FAIL "GPU" "no GPU matching '$(spec Gpu)'. Found: $(printf '%s' "$gpus" | tr '\n' ';')"; fi
  net="$(lspci | grep -iE 'network|ethernet|wireless' | cut -d: -f3- | sed 's/^ //' | tr '\n' ';')"
  [ -n "$net" ] && result INFO "Wi-Fi / Ethernet" "$net"
fi
if have nvidia-smi && [ "$(spec GpuVramGB)" != "0" ]; then
  save nvidia-smi.txt nvidia-smi
  mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9')"
  if [ -n "$mib" ]; then
    vram=$(( (mib + 512) / 1024 ))
    if ! spec_has GpuVramGB; then result INFO "GPU memory" "$vram GB"
    elif [ "$vram" = "$(spec GpuVramGB)" ]; then result PASS "GPU memory" "$vram GB"
    else result FAIL "GPU memory" "$vram GB, expected $(spec GpuVramGB) GB"; fi
  fi
fi
have lsusb && save lsusb.txt lsusb -tv
have boltctl && save thunderbolt.txt boltctl list

# ---------- display ----------
# The first mode the panel lists is its native resolution
for c in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-*; do
  [ -f "$c/modes" ] || continue
  native="$(head -1 "$c/modes")"
  [ -n "$native" ] || continue
  if ! spec_has Display; then result INFO "Display resolution" "$native"
  elif [ "$native" = "$(spec Display)" ]; then result PASS "Display resolution" "$native"
  else result FAIL "Display resolution" "panel reports $native, expected $(spec Display). Replaced panel?"; fi
  result INFO "Display refresh" "not readable here: check the highest refresh rate in Settings, Displays"
  break
done

# ---------- memory ----------
if have dmidecode && [ "$(id -u)" -eq 0 ]; then
  dmidecode -t memory > "$OUT/memory.txt" 2>&1
  mods=$(grep -cE '^[[:space:]]+Size: [0-9]+ (GB|MB)' "$OUT/memory.txt")
  total=$(awk '/^[[:space:]]+Size: [0-9]+ GB/ {s+=$2} /^[[:space:]]+Size: [0-9]+ MB/ {s+=$2/1024} END {printf "%d", s}' "$OUT/memory.txt")
  parts=$(grep -E '^[[:space:]]+Part Number:' "$OUT/memory.txt" | grep -v 'Not Specified' | sed 's/^[[:space:]]*Part Number:[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
  nparts=$(printf '%s\n' "$parts" | grep -c .)
  mts=$(grep -E '^[[:space:]]+Configured Memory Speed: [0-9]+' "$OUT/memory.txt" | awk '{print $4}' | sort -n | head -1)
  if ! spec_has RamModules; then result INFO "RAM layout" "$mods modules, $total GB"
  elif [ "$mods" = "$(spec RamModules)" ] && [ "$total" = "$(spec RamGB)" ]; then result PASS "RAM layout" "$mods modules, $total GB"
  else result FAIL "RAM layout" "$mods modules, $total GB (expected $(spec RamModules) modules, $(spec RamGB) GB)"; fi
  if [ "$nparts" -le 1 ]; then result PASS "RAM matched pair" "$parts"
  elif ! spec_has RamMatched; then result INFO "RAM matched pair" "different part numbers ($(printf '%s' "$parts" | tr '\n' '/')). Normal if one module is soldered"
  elif [ "$(spec RamMatched)" = '$false' ]; then result PASS "RAM matched pair" "different part numbers, normal for this model: one soldered, one in the slot"
  else result WARN "RAM matched pair" "different part numbers: $(printf '%s' "$parts" | tr '\n' '/'). Could mean a swapped module"; fi
  if ! spec_has RamMinMTs; then result INFO "RAM speed" "${mts:-?} MT/s"
  elif [ "${mts:-0}" -ge "$(spec RamMinMTs)" ]; then result PASS "RAM speed" "$mts MT/s"
  else result WARN "RAM speed" "${mts:-?} MT/s, expected at least $(spec RamMinMTs). Slower or mismatched module?"; fi
  slots=$(grep -m1 'Number Of Devices:' "$OUT/memory.txt" | awk '{print $NF}')
  maxcap=$(grep -m1 'Maximum Capacity:' "$OUT/memory.txt" | cut -d: -f2- | xargs)
  empty=$(grep -cE '^[[:space:]]+Size: No Module Installed' "$OUT/memory.txt")
  result INFO "RAM upgrade room" "${slots:-?} slot(s), $mods filled, $empty empty, firmware max ${maxcap:-?}"
else
  result INFO "RAM" "$(awk '/MemTotal/ {printf "%.1f GB visible to Linux", $2/1048576}' /proc/meminfo). Module details need sudo and dmidecode"
fi

# ---------- SSD ----------
sizes=""
for dev in /dev/nvme[0-9]n1 /dev/sd[a-z]; do
  [ -b "$dev" ] || continue
  [ "$(cat "/sys/block/$(basename "$dev")/removable" 2>/dev/null)" = 1 ] && continue
  case "$(readlink -f "/sys/block/$(basename "$dev")")" in */usb*) continue ;; esac   # skip USB sticks
  gb=$(( $(cat "/sys/block/$(basename "$dev")/size") * 512 / 1000000000 ))
  sizes="$sizes $gb"
  if have smartctl; then
    save "smart_$(basename "$dev").txt" smartctl -x "$dev"
    f="$OUT/smart_$(basename "$dev").txt"
    model=$(grep -m1 -E 'Model Number|Device Model' "$f" | cut -d: -f2- | xargs)
    hours=$(grep -m1 'Power On Hours' "$f" | cut -d: -f2- | xargs)
    written=$(grep -m1 'Data Units Written' "$f" | cut -d: -f2- | xargs)
    used=$(grep -m1 'Percentage Used' "$f" | cut -d: -f2- | xargs)
    unsafe=$(grep -m1 'Unsafe Shutdowns' "$f" | cut -d: -f2- | xargs)
    media=$(grep -m1 'Media and Data Integrity Errors' "$f" | cut -d: -f2- | xargs)
    health=$(grep -m1 'SMART overall-health' "$f" | cut -d: -f2- | xargs)
    lvl=PASS; note=""
    if [ -z "${health:-}" ]; then
      result WARN "SSD health $dev" "could not read the drive's SMART data (run with sudo). Power-on hours are the best proof of prior use"
      continue
    fi
    [ "$health" != "PASSED" ] && lvl=FAIL
    [ "${media:-0}" != "0" ] && lvl=FAIL
    hrs_num=$(printf '%s' "${hours:-}" | tr -dc '0-9')
    if [ "$lvl" = PASS ]; then
      if [ -z "$hrs_num" ]; then lvl=WARN; note=". Power-on hours not readable: check them with another tool"
      elif [ "$hrs_num" -gt "$SSD_HOURS_WARN" ]; then lvl=WARN; note=" (heavy prior use?)"; fi
    fi
    result "$lvl" "SSD health $dev" "$model, health ${health:-?}, power-on ${hours:-?} h, written ${written:-?}, wear ${used:-?}, media errors ${media:-?}, unsafe shutdowns ${unsafe:-?}$note"
  else
    result WARN "SSD health $dev" "smartctl missing: run again with --install to read power-on hours, the best proof of prior use"
  fi
done
sizes="${sizes# }"
if [ -n "$sizes" ]; then
  if ! spec_has SsdGB; then result INFO "SSD size" "$sizes GB"
  else
    want="$(spec SsdGB)"; ok=""
    for s in $sizes; do [ $(( s * 10 )) -ge $(( want * 9 )) ] && [ $(( s * 10 )) -le $(( want * 11 )) ] && ok="$s"; done
    if [ -n "$ok" ]; then result PASS "SSD size" "$ok GB"; else result FAIL "SSD size" "found $sizes GB, expected about $want GB. Swapped drive?"; fi
  fi
fi
have nvme && save nvme_list.txt nvme list

# ---------- firmware security ----------
if have fwupdmgr; then
  save fwupd_security.txt fwupdmgr security --force --no-unreported-check
  hsi=$(grep -m1 -o 'HSI:[0-9!]*' "$OUT/fwupd_security.txt")
  result INFO "fwupd HSI" "${hsi:-see fwupd_security.txt} (look for red items under Firmware / Boot protections)"
  save fwupd_devices.txt fwupdmgr get-devices --no-unreported-check
fi
if have mokutil; then
  sb=$(mokutil --sb-state 2>&1 | head -1)
  if echo "$sb" | grep -qi enabled; then result PASS "Secure Boot" "$sb"; else result FAIL "Secure Boot" "$sb"; fi
  # The Platform Key (PK) is the root of Secure Boot. It should belong to the laptop maker.
  # "DO NOT TRUST" / "DO NOT SHIP" means a leaked test key (PKfail, 2024): anyone can sign boot code.
  { echo "== PK =="; mokutil --pk; echo; echo "== KEK =="; mokutil --kek; } > "$OUT/secureboot_keys.txt" 2>&1
  pk=$(mokutil --pk 2>/dev/null | grep -m1 'Subject:' | sed 's/^[[:space:]]*Subject:[[:space:]]*//')
  pkwant="$(spec Pk)"; [ -n "$pkwant" ] || pkwant="$(printf '%s' "$vendor" | awk '{print $1}')"
  if grep -qiE 'DO NOT (TRUST|SHIP)' "$OUT/secureboot_keys.txt"; then
    result FAIL "Secure Boot keys" "test key found (PKfail), see secureboot_keys.txt"
  elif [ -z "$pk" ]; then
    result WARN "Secure Boot keys" "no Platform Key readable (setup mode or keys cleared), see secureboot_keys.txt"
  elif [ -n "$pkwant" ] && printf '%s' "$pk" | grep -qiE -- "$pkwant"; then
    result PASS "Secure Boot keys" "PK: $pk"
  else
    result WARN "Secure Boot keys" "PK: $pk does not name the maker ($pkwant). Custom keys? Check the firmware settings"
  fi
fi
if [ -d /sys/firmware/efi ]; then result PASS "Boot mode" "UEFI"; else result FAIL "Boot mode" "legacy BIOS"; fi

# ---------- kernel hardware errors ----------
journalctl -k -b --no-pager > "$OUT/kernel.log" 2>&1
# Core errors (CPU machine checks, PCIe AER, NVMe, GPU) are evidence of a fault: FAIL.
# Bluetooth / Wi-Fi firmware errors come from the radio card's own firmware, often after
# suspend or while pairing, and usually recover by themselves: WARN, then test the radio by hand.
radio_re='bluetooth: hci[0-9]+: (hardware error|.*exception)|iwlwifi.*(microcode sw error|firmware error|fw error)'
hw=$(grep -iE 'mce|machine check|hardware error|pcie bus error|aer:|nvme.*(timeout|reset)|i915.*(hang|error)|nouveau.*(fault|error)|amdgpu.*(ring .* timeout|gpu reset)' "$OUT/kernel.log" \
  | grep -viE 'aer: .*enabled|mce: (cpu supports|using) [0-9]+ mce banks|thermal monitoring enabled|in-kernel mce decoding enabled' \
  | grep -viE "$radio_re")
radio=$(grep -iE "$radio_re" "$OUT/kernel.log")
if [ -z "$hw" ]; then result PASS "Kernel hardware errors" "none this boot"
else echo "$hw" > "$OUT/kernel_hw_errors.txt"; result FAIL "Kernel hardware errors" "$(echo "$hw" | wc -l) line(s), see kernel_hw_errors.txt"; fi
if [ -n "$radio" ]; then
  echo "$radio" > "$OUT/kernel_radio_errors.txt"
  result WARN "Radio firmware errors" "$(echo "$radio" | wc -l) line(s), see kernel_radio_errors.txt. Pair a Bluetooth device and use Wi-Fi to confirm they work"
fi

# ---------- battery ----------
for b in /sys/class/power_supply/BAT*; do
  [ -d "$b" ] || continue
  full=$(cat "$b/energy_full" 2>/dev/null || cat "$b/charge_full" 2>/dev/null)
  design=$(cat "$b/energy_full_design" 2>/dev/null || cat "$b/charge_full_design" 2>/dev/null)
  cycles=$(cat "$b/cycle_count" 2>/dev/null)
  if [ -n "${full:-}" ] && [ -n "${design:-}" ] && [ "$design" -gt 0 ]; then
    pct=$(( 100 * full / design ))
    lvl=PASS; { [ "$pct" -lt 95 ] || [ "${cycles:-0}" -gt 10 ]; } && lvl=WARN
    result "$lvl" "Battery $(basename "$b")" "$pct% of design, cycles ${cycles:-?}"
  fi
  if [ -f "$b/energy_full_design" ]; then
    wh10=$(( $(cat "$b/energy_full_design") / 100000 ))     # tenths of a Wh
    whtxt="$(( wh10 / 10 )).$(( wh10 % 10 )) Wh"
    if ! spec_has BatteryWh; then result INFO "Battery model" "designed for $whtxt"
    else
      want10=$(( $(spec BatteryWh) * 10 ))
      if [ "$wh10" -ge $(( want10 * 9 / 10 )) ] && [ "$wh10" -le $(( want10 * 11 / 10 )) ]; then result PASS "Battery model" "designed for $whtxt"
      else result WARN "Battery model" "designed for $whtxt, expected about $(spec BatteryWh) Wh. Replaced battery?"; fi
    fi
  fi
done

# ---------- sensors ----------
if have sensors; then sensors-detect --auto >/dev/null 2>&1; save sensors_idle.txt sensors; fi

# ---------- optional stress ----------
if [ "$STRESS" -eq 1 ]; then
  if have stress-ng; then
    echo "Running 15 min stress-ng (CPU + memory with verification)..."
    stress-ng --cpu 0 --cpu-method all --vm 2 --vm-bytes 70% --verify --timeout 15m --metrics-brief \
      > "$OUT/stress-ng.txt" 2>&1
    rc=$?
    have sensors && save sensors_after_stress.txt sensors
    # stress-ng exits 0 on success. A clean run still prints "failed: 0" and "metrics untrustworthy: 0",
    # so only non-zero counts count. Verification errors print "fail:" lines.
    if [ $rc -eq 0 ] && ! grep -qE 'failed: [1-9]|fail: |verify.*(fail|error)|untrustworthy: [1-9]' "$OUT/stress-ng.txt"; then
      result PASS "stress-ng 15 min" "no failures, verification clean"
    else
      result FAIL "stress-ng 15 min" "exit $rc, see stress-ng.txt"
    fi
  else
    result WARN "stress-ng 15 min" "stress-ng missing: run again with --install"
  fi
fi

write_report full
echo "On a live USB, copy the folder somewhere before you reboot."
