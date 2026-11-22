# Shared by linux-live-audit.sh and mac-audit.sh. Bash 3.2 compatible (macOS ships 3.2).
# Reads the same profiles/*.psd1 files as omen-audit.ps1 and writes the same kind of report.

# ---------- results ----------
result() {  # level check detail
  printf '%-5s %s : %s\n' "$1" "$2" "$3" | tee -a "$SUMMARY"
}
save() {    # file command...
  local f="$1"; shift
  { echo "\$ $*"; "$@"; } > "$OUT/$f" 2>&1
}
have() { command -v "$1" >/dev/null 2>&1; }

# ---------- profiles ----------
# A profile is a PowerShell data file. Only simple "Key = value" lines are read here, which is all the
# spec keys use. Quotes and trailing comments are stripped.
prof_get() {  # file key -> value
  sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$1" | head -1 \
    | sed -E "s/[[:space:]]+#.*$//; s/[[:space:]]+$//; s/^'(.*)'$/\1/; s/^\"(.*)\"$/\1/"
}
prof_has() {  # file key -> true if the profile defines the key
  [ -n "${1:-}" ] && grep -qE "^[[:space:]]*$2[[:space:]]*=" "$1"
}

# pick_profile "<machine id>" "<requested name or auto>"
# Sets PROFILE (file path, empty in generic mode), PROFILE_NAME and HOW.
pick_profile() {
  local id="$1" want="$2" f
  PROFILE=""; PROFILE_NAME="Generic (no profile for this laptop: specs are listed, not compared)"; HOW=""
  if [ "$want" = "generic" ]; then HOW="chosen with --laptop"; return 0; fi
  if [ "$want" != "auto" ]; then
    f="$KIT/profiles/$want.psd1"
    if [ ! -f "$f" ]; then echo "No profile '$want'. Available: $(ls "$KIT/profiles" 2>/dev/null | sed 's/\.psd1$//' | tr '\n' ' ')generic"; exit 1; fi
    PROFILE="$f"; PROFILE_NAME="$(prof_get "$f" Name)"; HOW="chosen with --laptop"; return 0
  fi
  for f in "$KIT"/profiles/*.psd1; do
    [ -f "$f" ] || continue
    local d; d="$(prof_get "$f" Detect)"
    if [ -n "$d" ] && printf '%s' "$id" | grep -qiE "$d"; then
      PROFILE="$f"; PROFILE_NAME="$(prof_get "$f" Name)"; HOW="recognised from '$id'"; return 0
    fi
  done
  HOW="not recognised ('$id')"
}
spec()     { [ -n "$PROFILE" ] && prof_get "$PROFILE" "$1"; }
spec_has() { [ -n "$PROFILE" ] && prof_has "$PROFILE" "$1"; }

report_profile_line() {
  if [ -z "$PROFILE" ] && [ "${HOW#not recognised}" != "$HOW" ]; then
    result WARN "Laptop profile" "$HOW. Specs are listed, not compared. All health, tamper and prior-use checks still run. To compare, add a profile (docs/profiles.md) or force one with --laptop"
  else
    result INFO "Laptop profile" "$PROFILE_NAME, $HOW"
  fi
  local me; me="$(shasum -a 256 "$0" 2>/dev/null || sha256sum "$0" 2>/dev/null)"
  result INFO "Script version" "sha256 ${me%% *}"
}

# ---------- where reports go, and cleaning up ----------
# Every run writes reports/<computer>_<mode>_<time>/ inside the kit folder, like the Windows kit.
report_dir() {  # report_dir <mode> -> sets OUT and SUMMARY
  OUT="$KIT/reports/$(hostname -s 2>/dev/null || echo laptop)_${1}_$STAMP"
  mkdir -p "$OUT"
  SUMMARY="$OUT/SUMMARY.txt"
  : > "$SUMMARY"
}

# The home folder of the person running the kit, also under sudo
user_home() {
  if [ -n "${SUDO_USER:-}" ]; then eval echo "~$SUDO_USER"; else echo "$HOME"; fi
}

# Files written under sudo belong to root; give them back, so you can open, move and delete them
give_back() {
  [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ] && chown -R "$SUDO_USER" "$@" 2>/dev/null
  return 0
}

# --cleanup: keep the reports, remove everything else the kit put on this computer.
# Reports move to ~/SecondTrust-reports, then the kit folder is deleted. A git checkout (a developer's
# copy) is never deleted, and neither is a folder that does not look like the kit.
kit_cleanup() {
  local dest n old
  dest="$(user_home)/SecondTrust-reports"
  # Reports from older versions of the kit sit loose in the kit folder: keep those too
  for old in "$KIT"/mac-audit-[0-9]* "$KIT"/linux-audit-[0-9]*; do
    [ -d "$old" ] || continue
    mkdir -p "$KIT/reports" && mv "$old" "$KIT/reports/"
  done
  if [ -d "$KIT/reports" ] && [ -n "$(ls -A "$KIT/reports" 2>/dev/null)" ]; then
    mkdir -p "$dest"
    mv "$KIT/reports/"* "$dest/" && give_back "$dest"
    n=$(ls -1 "$dest" | grep -c .)
    echo "Reports kept: $dest ($n folder(s))"
  else
    echo "No reports to keep."
  fi
  if [ -d "$KIT/.git" ]; then echo "$KIT is a git checkout: not deleting it."; return 0; fi
  if [ ! -f "$KIT/lib/common.sh" ] || [ ! -f "$KIT/omen-audit.ps1" ]; then echo "$KIT does not look like the kit: not deleting it."; return 0; fi
  case "$(basename "$KIT")" in stressTestIt_beforeReturnWindowCloses*) ;; *) echo "Unexpected folder name $KIT: not deleting it."; return 0 ;; esac
  cd / && rm -rf "$KIT" && echo "Removed the kit: $KIT. Nothing else was left behind."
}

# ---------- report ----------
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# write_report <mode>: an HTML report beside SUMMARY.txt, then the SHA-256 manifest of every file.
write_report() {
  local mode="$1" fails warns html f level check detail
  fails=$(grep -c '^FAIL' "$SUMMARY"); warns=$(grep -c '^WARN' "$SUMMARY")
  { echo; echo "Totals: $fails FAIL, $warns WARN"; echo "Run at: $(date '+%Y-%m-%dT%H:%M:%S%z')"; } >> "$SUMMARY"
  html="$OUT/DOA_report_${mode}_${STAMP}.html"
  {
    cat <<'EOF'
<!doctype html><html><head><meta charset="utf-8"><title>SecondTrust report</title><style>
body{font:13px/1.5 system-ui,Arial,sans-serif;color:#111;margin:24px;max-width:1100px}
h1{font-size:20px;margin:0 0 6px}h2{font-size:15px;margin:22px 0 6px;border-bottom:1px solid #ccc}
table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:3px 6px;text-align:left;vertical-align:top}
.FAIL{background:#ffd7d7}.WARN{background:#fff3c4}.PASS{background:#dff5df}
pre{font-size:11px;white-space:pre-wrap;word-wrap:break-word;background:#fafafa;border:1px solid #ddd;padding:6px}
.box{padding:6px;border:1px solid #999;margin:8px 0;font-size:14px}
</style></head><body>
EOF
    echo "<h1>SecondTrust report ($mode, $(uname -s))</h1>"
    echo "<div>Run at $(date '+%Y-%m-%d %H:%M:%S %z'). Profile: $(printf '%s' "$PROFILE_NAME, $HOW" | html_escape).</div>"
    if [ "$fails" -gt 0 ]; then level=FAIL; elif [ "$warns" -gt 0 ]; then level=WARN; else level=PASS; fi
    echo "<div class=\"box $level\"><b>$fails FAIL, $warns WARN.</b> FAIL = evidence of a fault, swap or tampering. WARN = check by hand. Print this page to PDF from your browser to share it.</div>"
    echo "<h2>Results</h2><table><tr><th>Result</th><th>Check</th><th>Detail</th></tr>"
    grep -E '^(PASS|WARN|FAIL|INFO) ' "$SUMMARY" | while IFS= read -r line; do
      level="${line%% *}"; rest="${line#* }"; rest="${rest#"${rest%%[![:space:]]*}"}"
      check="${rest%% : *}"; detail="${rest#* : }"
      printf '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td></tr>\n' "$level" "$level" \
        "$(printf '%s' "$check" | html_escape)" "$(printf '%s' "$detail" | html_escape)"
    done
    echo "</table>"
    if [ -n "$PROFILE" ]; then
      echo "<h2>Expected values ($(basename "$PROFILE"))</h2><pre>"; html_escape < "$PROFILE"; echo "</pre>"
    fi
    for f in "$OUT"/*; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in SUMMARY.txt|MANIFEST.sha256|DOA_report_*|*.log) continue ;; esac
      echo "<h2>$(basename "$f" | html_escape)</h2><pre>"; head -c 60000 "$f" | html_escape; echo "</pre>"
    done
    echo "</body></html>"
  } > "$html"
  ( cd "$OUT" && for f in *; do [ -f "$f" ] && [ "$f" != MANIFEST.sha256 ] && { shasum -a 256 "$f" 2>/dev/null || sha256sum "$f"; }; done > MANIFEST.sha256 )
  give_back "$KIT/reports"
  echo
  echo "$fails FAIL, $warns WARN. Report: $html"
  echo "When you are done with the kit: bash $(basename "$0") --cleanup (keeps the reports, removes the rest)"
}
