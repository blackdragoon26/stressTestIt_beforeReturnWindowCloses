#!/bin/bash
# Laptop audit for macOS. First run on a real Mac 2026-11-22 (MacBook Air M3, macOS 26.4.1); Intel Macs are
# still untested. Report problems on GitHub.
# Identity and specs against the Mac's profile, SSD health, battery wear, Activation Lock, company
# (MDM / DEP) enrollment, System Integrity Protection, Gatekeeper, FileVault, kernel panics and
# shutdown causes from the last 30 days.
#
# Usage:
#   bash mac-audit.sh                      # audit (some checks read more with sudo)
#   sudo bash mac-audit.sh                 # adds the firmware password check (Intel Macs)
#   bash mac-audit.sh --serial C02XXXXXX   # compare the serial with your invoice
#   bash mac-audit.sh --laptop generic     # force a profile, or generic mode
#   bash mac-audit.sh --cleanup            # keep the reports in ~/SecondTrust-reports, remove the kit
#
# Output: reports/<computer>_full_<time>/ in the kit folder, with SUMMARY.txt, an HTML report and MANIFEST.sha256.
# Bash 3.2 compatible (the version macOS ships).

set -u
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$KIT/lib/common.sh"

LAPTOP=auto; INVOICE=""; CLEANUP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --laptop) LAPTOP="${2:-}"; shift ;;
    --serial) INVOICE="${2:-}"; shift ;;
    --cleanup) CLEANUP=1 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done
[ "$(uname -s)" = Darwin ] || { echo "This script is for macOS. On Linux use linux-live-audit.sh, on Windows omen-audit.ps1."; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
if [ "$CLEANUP" -eq 1 ]; then kit_cleanup; exit 0; fi
report_dir full
SSD_HOURS_WARN=100
ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1

sp() { system_profiler "$@" 2>/dev/null; }
field() {  # file "Label" -> value after "Label: " (first match)
  sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -1
}
iokey() {  # ioreg key from the battery -> number
  ioreg -rn AppleSmartBattery 2>/dev/null | sed -n "s/.*\"$1\" = \([0-9][0-9]*\).*/\1/p" | head -1
}

echo "Reading the hardware (about a minute)..."
sp SPHardwareDataType > "$OUT/hardware.txt"
model_name="$(field "$OUT/hardware.txt" "Model Name")"
model_id="$(field "$OUT/hardware.txt" "Model Identifier")"
chip="$(field "$OUT/hardware.txt" "Chip")"; [ -n "$chip" ] || chip="$(field "$OUT/hardware.txt" "Processor Name")"
memory="$(field "$OUT/hardware.txt" "Memory")"
serial="$(field "$OUT/hardware.txt" "Serial Number (system)")"
activation="$(field "$OUT/hardware.txt" "Activation Lock Status")"

# ---------- profile ----------
pick_profile "$model_id $model_name" "$LAPTOP"
report_profile_line

# ---------- identity ----------
if [ -n "$INVOICE" ]; then
  if [ "$(printf '%s' "$INVOICE" | tr '[:lower:]' '[:upper:]')" = "$(printf '%s' "$serial" | tr '[:lower:]' '[:upper:]')" ]; then
    result PASS "Serial number" "$serial matches the invoice"
  else result FAIL "Serial number" "the Mac says '$serial', the invoice says '$INVOICE'"; fi
else
  result INFO "Serial number" "$serial (not compared: pass --serial from the invoice). Also check it at checkcoverage.apple.com"
fi
result INFO "macOS" "$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
if ! spec_has Model; then result INFO "Model" "$model_name ($model_id)"
elif printf '%s %s' "$model_name" "$model_id" | grep -qiE -- "$(spec Model)"; then result PASS "Model" "$model_name ($model_id)"
else result FAIL "Model" "got '$model_name ($model_id)', expected $(spec Model)"; fi

# ---------- CPU, memory, GPU ----------
cores="$(sysctl -n hw.physicalcpu 2>/dev/null)"; threads="$(sysctl -n hw.logicalcpu 2>/dev/null)"
if ! spec_has Cpu; then result INFO "CPU" "$chip"
elif printf '%s' "$chip" | grep -qiE -- "$(spec Cpu)"; then result PASS "CPU" "$chip"
else result FAIL "CPU" "got '$chip', expected $(spec Cpu)"; fi
if ! spec_has Cores; then result INFO "CPU cores/threads" "${cores}C / ${threads}T"
elif [ "$cores" = "$(spec Cores)" ] && [ "$threads" = "$(spec Threads)" ]; then result PASS "CPU cores/threads" "${cores}C / ${threads}T"
else result FAIL "CPU cores/threads" "got ${cores}C / ${threads}T, expected $(spec Cores)C / $(spec Threads)T"; fi
memgb="$(printf '%s' "$memory" | awk '{print $1}')"
if ! spec_has RamGB; then result INFO "Memory" "$memory"
elif [ "$memgb" = "$(spec RamGB)" ]; then result PASS "Memory" "$memory"
else result FAIL "Memory" "got $memory, expected $(spec RamGB) GB"; fi

sp SPDisplaysDataType > "$OUT/displays.txt"
gpus="$(sed -n 's/^[[:space:]]*Chipset Model:[[:space:]]*//p' "$OUT/displays.txt" | paste -sd, - | sed 's/,/, /g')"
if ! spec_has Gpu; then result INFO "GPU" "$gpus"
elif printf '%s' "$gpus" | grep -qiE -- "$(spec Gpu)"; then result PASS "GPU" "$gpus"
else result FAIL "GPU" "got '$gpus', expected $(spec Gpu)"; fi

# Built-in panel: the first "Resolution" after a built-in display line
res="$(awk '/Display Type: Built-[Ii]n|Connection Type: Internal/ {b=1} b && /Resolution:/ {sub(/.*Resolution: */, ""); print; exit}' "$OUT/displays.txt" \
  | awk '{print $1 "x" $3}')"
if [ -n "$res" ]; then
  if ! spec_has Display; then result INFO "Display resolution" "$res"
  elif [ "$res" = "$(spec Display)" ]; then result PASS "Display resolution" "$res"
  else result FAIL "Display resolution" "panel reports $res, expected $(spec Display). Replaced panel?"; fi
fi

# ---------- storage ----------
diskutil info disk0 > "$OUT/disk0.txt" 2>&1
smart_status="$(field "$OUT/disk0.txt" "SMART Status")"
bytes="$(sed -n 's/.*Disk Size:.*(\([0-9][0-9]*\) Bytes).*/\1/p' "$OUT/disk0.txt" | head -1)"
gb=""; [ -n "$bytes" ] && gb=$(( bytes / 1000000000 ))
if have smartctl; then
  save smart_disk0.txt smartctl -a disk0
  f="$OUT/smart_disk0.txt"
  hours=$(grep -m1 'Power On Hours' "$f" | cut -d: -f2- | xargs)
  written=$(grep -m1 'Data Units Written' "$f" | cut -d: -f2- | xargs)
  used=$(grep -m1 'Percentage Used' "$f" | cut -d: -f2- | xargs)
  media=$(grep -m1 'Media and Data Integrity Errors' "$f" | cut -d: -f2- | xargs)
  hrs_num=$(printf '%s' "${hours:-}" | tr -dc '0-9')
  lvl=PASS; note=""
  { [ "$smart_status" != "Verified" ] || [ "${media:-0}" != "0" ]; } && lvl=FAIL
  if [ "$lvl" = PASS ]; then
    if [ -z "$hrs_num" ]; then lvl=WARN; note=". Power-on hours not readable"
    elif [ "$hrs_num" -gt "$SSD_HOURS_WARN" ]; then lvl=WARN; note=" (heavy prior use?)"; fi
  fi
  result "$lvl" "SSD health" "SMART ${smart_status:-?}, power-on ${hours:-?} h, written ${written:-?}, wear ${used:-?}, media errors ${media:-?}$note"
else
  if [ "$smart_status" = "Verified" ]; then lvl=WARN; else lvl=FAIL; fi
  result "$lvl" "SSD health" "SMART ${smart_status:-?}. Power-on hours, the best proof of prior use, need smartmontools: brew install smartmontools, then run again"
fi
if [ -n "$gb" ]; then
  if ! spec_has SsdGB; then result INFO "SSD size" "$gb GB"
  else
    want="$(spec SsdGB)"
    if [ $(( gb * 10 )) -ge $(( want * 9 )) ] && [ $(( gb * 10 )) -le $(( want * 11 )) ]; then result PASS "SSD size" "$gb GB"
    else result FAIL "SSD size" "found $gb GB, expected about $want GB"; fi
  fi
fi

# ---------- battery ----------
cycles="$(iokey CycleCount)"; design="$(iokey DesignCapacity)"; rawmax="$(iokey AppleRawMaxCapacity)"
[ -n "$rawmax" ] || rawmax="$(iokey NominalChargeCapacity)"
ioreg -rn AppleSmartBattery > "$OUT/battery_ioreg.txt" 2>&1
sp SPPowerDataType > "$OUT/power.txt"
# Apple's own "Maximum Capacity" (System Settings, Battery) is what Apple service goes by; the raw
# gauge reading is lower on some Macs (seen on a MacBook Air M3: Apple 85%, raw 3623 / 4563 mAh = 79%)
applemax="$(field "$OUT/power.txt" "Maximum Capacity" | tr -dc '0-9')"
condition="$(field "$OUT/power.txt" "Condition")"
raw=""; [ -n "$design" ] && [ -n "$rawmax" ] && [ "$design" -gt 0 ] && raw="raw gauge $rawmax / $design mAh = $(( 100 * rawmax / design ))%"
pct="$applemax"; [ -n "$pct" ] || { [ -n "$raw" ] && pct=$(( 100 * rawmax / design )); }
if [ -n "$pct" ]; then
  lvl=PASS; { [ "$pct" -lt 95 ] || [ "${cycles:-0}" -gt 10 ]; } && lvl=WARN
  src="Apple reports $pct% maximum capacity"; [ -n "$applemax" ] || src="$pct% of design"
  result "$lvl" "Battery" "$src, cycles ${cycles:-?}, condition ${condition:-?}${raw:+ ($raw)}"
elif [ -n "$cycles" ]; then
  result INFO "Battery" "cycles $cycles, condition ${condition:-?}"
fi
charger="$(field "$OUT/power.txt" "Name")"; watts="$(field "$OUT/power.txt" "Wattage (W)")"
if [ -n "$charger" ]; then result INFO "Charger" "$charger${watts:+, $watts W} (connected during the run)"
else result INFO "Charger" "none connected during the run"; fi

# ---------- tampering and ownership ----------
# Activation Lock is on whenever Find My Mac is. If Find My is on for the Apple ID signed in here, it is
# that account's lock; if not, it belongs to someone else (a previous owner).
findmy=""; acct=""
mma="$(defaults read "$(user_home)/Library/Preferences/MobileMeAccounts" Accounts 2>/dev/null)"
if [ -n "$mma" ]; then
  printf '%s' "$mma" | awk 'BEGIN { RS = "}" } /FIND_MY_MAC/ && /Enabled = 1/ { f = 1 } END { exit !f }' && findmy=1
  acct="$(printf '%s' "$mma" | sed -n 's/^[[:space:]]*AccountID = "\{0,1\}\([^";]*\)"\{0,1\};.*/\1/p' | head -1)"
  # Shown masked in the report: j***@icloud.com
  [ -n "$acct" ] && acct="$(printf '%s' "$acct" | sed -E 's/^(.)[^@]*@/\1***@/')"
fi
case "$activation" in
  Disabled) result PASS "Activation Lock" "disabled" ;;
  Enabled)
    if [ -n "$findmy" ]; then result PASS "Activation Lock" "on, through Find My of the Apple ID signed in here (${acct:-this user}). If that is not your account, ask the seller to remove the Mac from it"
    else result WARN "Activation Lock" "on, but Find My is not on for an Apple ID signed in here: it may be a previous owner's lock, and the Mac can be locked remotely. Ask the seller to remove it from their account"; fi ;;
  *)        result INFO "Activation Lock" "not reported on this model. Check System Settings, your name, Find My" ;;
esac
profiles status -type enrollment > "$OUT/mdm_enrollment.txt" 2>&1
dep="$(sed -n 's/.*Enrolled via DEP:[[:space:]]*//p' "$OUT/mdm_enrollment.txt" | head -1)"
mdm="$(sed -n 's/.*MDM enrollment:[[:space:]]*//p' "$OUT/mdm_enrollment.txt" | head -1)"
if grep -qiE '(DEP|MDM enrollment).*: *Yes' "$OUT/mdm_enrollment.txt"; then
  result FAIL "MDM enrollment" "enrolled (DEP: ${dep:-?}, MDM: ${mdm:-?}). A company can lock or wipe this Mac, and DEP re-enrolls it even after a reset"
else
  result PASS "MDM enrollment" "not enrolled (DEP: ${dep:-?}, MDM: ${mdm:-?})"
fi
profiles list > "$OUT/config_profiles.txt" 2>&1
sip="$(csrutil status 2>&1)"
if printf '%s' "$sip" | grep -q 'enabled\.'; then result PASS "System Integrity Protection" "enabled"
else result FAIL "System Integrity Protection" "$sip"; fi
gk="$(spctl --status 2>&1)"
if printf '%s' "$gk" | grep -q 'assessments enabled'; then result PASS "Gatekeeper" "enabled"
else result WARN "Gatekeeper" "$gk"; fi
result INFO "FileVault" "$(fdesetup status 2>&1 | head -1)"
if have firmwarepasswd; then
  if [ "$ROOT" -eq 1 ]; then
    fw="$(firmwarepasswd -check 2>&1)"
    if printf '%s' "$fw" | grep -q 'Yes'; then result FAIL "Firmware password" "set. Ask the seller to remove it"
    else result PASS "Firmware password" "none"; fi
  else
    result INFO "Firmware password" "run with sudo to check (Intel Macs)"
  fi
fi

# ---------- stability ----------
panics="$(find /Library/Logs/DiagnosticReports -name '*panic*' -mtime -30 2>/dev/null)"
if [ -n "$panics" ]; then
  printf '%s\n' "$panics" > "$OUT/panics.txt"
  result FAIL "Kernel panics" "$(printf '%s\n' "$panics" | grep -c .) in the last 30 days, see panics.txt"
else
  result PASS "Kernel panics" "none in the last 30 days"
fi
echo "Reading 30 days of shutdown history (up to a few minutes)..."
# Only the kernel's messages: filtering on the process first is much faster than searching every message
log show --last 30d --style syslog --predicate 'process == "kernel" AND eventMessage CONTAINS "Previous shutdown cause"' > "$OUT/shutdown_causes.txt" 2>&1
# 5 = normal shutdown. 3 = held power button. Anything else (negative numbers especially) is a fault:
# overheating, power loss, a watchdog reset.
causes="$(sed -n 's/.*Previous shutdown cause: *\(-*[0-9][0-9]*\).*/\1/p' "$OUT/shutdown_causes.txt" | sort | uniq -c | awk '{printf "cause %s x%s, ", $2, $1}')"
bad="$(sed -n 's/.*Previous shutdown cause: *\(-*[0-9][0-9]*\).*/\1/p' "$OUT/shutdown_causes.txt" | grep -vxE '5|3' | grep -c .)"
if [ "${bad:-0}" -gt 0 ]; then result FAIL "Abnormal shutdowns" "$bad in the last 30 days (${causes%, }). See shutdown_causes.txt"
elif [ -n "$causes" ]; then result PASS "Abnormal shutdowns" "none (${causes%, })"
else result INFO "Abnormal shutdowns" "none recorded in the unified log (Apple silicon Macs often log no shutdown cause; the kernel panic check above still covers crashes)"; fi

# ---------- devices and inventory ----------
sp SPCameraDataType > "$OUT/camera.txt"
if grep -q 'Model ID\|Unique ID' "$OUT/camera.txt"; then result PASS "Webcam" "$(sed -n '3p' "$OUT/camera.txt" | sed 's/^[[:space:]]*//; s/:$//')"
else result FAIL "Webcam" "no camera found"; fi
sp SPMemoryDataType SPStorageDataType SPNVMeDataType SPAirPortDataType SPBluetoothDataType SPUSBDataType SPThunderboltDataType > "$OUT/hardware_inventory.txt"
result INFO "Hardware inventory" "saved hardware_inventory.txt"

write_report full
