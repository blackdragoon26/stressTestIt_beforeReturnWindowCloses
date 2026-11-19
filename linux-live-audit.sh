#!/usr/bin/env bash
# OMEN Transcend 16 (834T6PA) DOA audit from an Ubuntu 24.04 live USB.
# A second opinion from outside Windows: identity, PCI devices, SSD health,
# firmware security (fwupd HSI), kernel hardware errors, battery wear.
#
# Usage (from the live session, with internet):
#   sudo bash linux-live-audit.sh            # audit only
#   sudo bash linux-live-audit.sh --install  # apt-install missing tools first
#   sudo bash linux-live-audit.sh --stress   # also run a 15 min stress-ng with verification
#
# Output: ./linux-audit-<timestamp>/ with SUMMARY.txt and MANIFEST.sha256.
# Copy that folder to a second USB stick or upload it before rebooting:
# a live session forgets everything on shutdown.

set -u

# Expected values for the HP OMEN Transcend 16-u0005TX. Override for other machines, e.g.
#   sudo EXPECT_SKU=XYZ EXPECT_BOARD=1234 EXPECT_CPU=5800H EXPECT_THREADS=16 bash linux-live-audit.sh
EXPECT_SKU="${EXPECT_SKU:-834T6PA}"
EXPECT_BOARD="${EXPECT_BOARD:-8BB3}"
EXPECT_CPU="${EXPECT_CPU:-13700HX}"
EXPECT_THREADS="${EXPECT_THREADS:-24}"
EXPECT_GPU_REGEX="${EXPECT_GPU_REGEX:-RTX 4070|AD106M}"
SSD_HOURS_WARN="${SSD_HOURS_WARN:-100}"

INSTALL=0
STRESS=0
for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    --stress)  STRESS=1 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo."; exit 1
fi

OUT="$(pwd)/linux-audit-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
SUMMARY="$OUT/SUMMARY.txt"
: > "$SUMMARY"

result() {  # level check detail
  printf '%-5s %s : %s\n' "$1" "$2" "$3" | tee -a "$SUMMARY"
}
save() {    # file command...
  local f="$1"; shift
  { echo "\$ $*"; "$@"; } > "$OUT/$f" 2>&1
}
have() { command -v "$1" >/dev/null 2>&1; }

if [ "$INSTALL" -eq 1 ]; then
  add-apt-repository -y universe >/dev/null 2>&1 || true
  apt-get update -qq
  apt-get install -y -qq dmidecode pciutils usbutils nvme-cli smartmontools fwupd \
    lm-sensors stress-ng bolt mokutil >/dev/null
fi

# ---------- identity ----------
sku=$(cat /sys/class/dmi/id/product_sku 2>/dev/null)
board=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
serial=$(cat /sys/class/dmi/id/product_serial 2>/dev/null)
biosver=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
biosdate=$(cat /sys/class/dmi/id/bios_date 2>/dev/null)

result INFO "Product" "$product"
result INFO "Serial number" "$serial  <- must match box, sticker, invoice and the Windows report"
result INFO "BIOS" "$biosver ($biosdate)"
if [[ "$sku" == *"$EXPECT_SKU"* ]]; then result PASS "Product number" "$sku"; else result FAIL "Product number" "got '${sku:-(empty: firmware does not expose a SKU)}', expected $EXPECT_SKU"; fi
if [ "$board" = "$EXPECT_BOARD" ]; then result PASS "Board ID" "$board"; else result WARN "Board ID" "got '$board', expected $EXPECT_BOARD"; fi
have dmidecode && save dmidecode.txt dmidecode

# ---------- CPU ----------
cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')
threads=$(nproc --all)
save lscpu.txt lscpu
if [[ "$cpu" == *"$EXPECT_CPU"* ]] && [ "$threads" -eq "$EXPECT_THREADS" ]; then
  result PASS "CPU" "$cpu, $threads threads"
else
  result FAIL "CPU" "got '$cpu' with $threads threads, expected $EXPECT_CPU with $EXPECT_THREADS"
fi

# ---------- PCI / USB / Thunderbolt ----------
if have lspci; then
  save lspci.txt lspci -nnk
  if lspci | grep -qiE "$EXPECT_GPU_REGEX"; then result PASS "GPU on PCI bus" "$(lspci | grep -iE "$EXPECT_GPU_REGEX" | head -1 | cut -d: -f3-)"
  else result FAIL "GPU on PCI bus" "no device matching '$EXPECT_GPU_REGEX'. Found: $(lspci | grep -iE 'VGA|3D|Display' | cut -d: -f3- | tr '\n' ';')"; fi
  lspci | grep -qi 'network\|wireless' && result INFO "Wi-Fi/Ethernet" "$(lspci | grep -i 'network\|ethernet' | cut -d: -f3- | tr '\n' ';')"
fi
have lsusb && save lsusb.txt lsusb -tv
have boltctl && save thunderbolt.txt boltctl list

# ---------- memory ----------
if have dmidecode; then
  dmidecode -t memory > "$OUT/memory.txt" 2>&1
  mods=$(grep -cE '^\s+Size: [0-9]+ (GB|MB)' "$OUT/memory.txt")
  parts=$(grep -E '^\s+Part Number:' "$OUT/memory.txt" | grep -v 'Not Specified' | sort -u | wc -l)
  result INFO "RAM" "$mods module(s); $(grep -E '^\s+(Manufacturer|Part Number|Configured Memory Speed):' "$OUT/memory.txt" | grep -v Unknown | sort -u | sed 's/^\s*//' | tr '\n' ';')"
  [ "$parts" -gt 1 ] && result WARN "RAM matched pair" "different part numbers found"
fi

# ---------- SSD ----------
if have smartctl; then
  for dev in /dev/nvme[0-9]; do
    [ -e "$dev" ] || continue
    save "smart_$(basename "$dev").txt" smartctl -x "$dev"
    f="$OUT/smart_$(basename "$dev").txt"
    model=$(grep -m1 'Model Number' "$f" | cut -d: -f2- | xargs)
    hours=$(grep -m1 'Power On Hours' "$f" | cut -d: -f2- | xargs)
    written=$(grep -m1 'Data Units Written' "$f" | cut -d: -f2- | xargs)
    media=$(grep -m1 'Media and Data Integrity Errors' "$f" | cut -d: -f2- | xargs)
    health=$(grep -m1 'SMART overall-health' "$f" | cut -d: -f2- | xargs)
    lvl=PASS
    [ "${health:-}" != "PASSED" ] && lvl=FAIL
    [ "${media:-0}" != "0" ] && lvl=FAIL
    hrs_num=$(echo "${hours:-0}" | tr -dc '0-9')
    if [ "$lvl" = PASS ] && [ "${hrs_num:-0}" -gt "$SSD_HOURS_WARN" ]; then lvl=WARN; health="$health (heavy prior use?)"; fi
    result "$lvl" "SSD $dev" "$model, health $health, power-on $hours h, written $written, media errors $media"
  done
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
fi
[ -d /sys/firmware/efi ] && result PASS "Boot mode" "UEFI" || result FAIL "Boot mode" "legacy BIOS"

# ---------- kernel hardware errors ----------
journalctl -k -b --no-pager > "$OUT/kernel.log" 2>&1
# Core errors (CPU machine checks, PCIe AER, NVMe, GPU) are DOA evidence: FAIL.
# Bluetooth / Wi-Fi firmware errors come from the radio card's own firmware, often after
# suspend or while pairing, and usually recover by themselves: WARN, then test the radio by hand.
radio_re='bluetooth: hci[0-9]+: (hardware error|.*exception)|iwlwifi.*(microcode sw error|firmware error|fw error)'
hw=$(grep -iE 'mce|machine check|hardware error|pcie bus error|aer:|nvme.*(timeout|reset)|i915.*(hang|error)|nouveau.*(fault|error)' "$OUT/kernel.log" \
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
    lvl=PASS; [ "$pct" -lt 95 ] && lvl=WARN
    result "$lvl" "Battery $(basename "$b")" "$pct% of design, cycles ${cycles:-?}"
  fi
done

# ---------- sensors ----------
if have sensors; then sensors-detect --auto >/dev/null 2>&1; save sensors_idle.txt sensors; fi

# ---------- optional stress ----------
if [ "$STRESS" -eq 1 ] && have stress-ng; then
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
fi

# ---------- manifest ----------
fails=$(grep -c '^FAIL' "$SUMMARY"); warns=$(grep -c '^WARN' "$SUMMARY")
{ echo; echo "Totals: $fails FAIL, $warns WARN"; echo "Run at: $(date -Is)"; } >> "$SUMMARY"
( cd "$OUT" && find . -maxdepth 1 -type f ! -name MANIFEST.sha256 -printf '%f\0' | sort -z | xargs -0 sha256sum > MANIFEST.sha256 )
echo
echo "$fails FAIL, $warns WARN. Report folder: $OUT"
echo "Copy it off the live session before you reboot."
