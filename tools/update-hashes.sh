#!/usr/bin/env bash
# Writes docs/SHA256SUMS.txt: the fingerprints people compare their download against.
# Every Windows run also compares itself with this list and records the result in its report.
# Run it before every commit that changes a script or a profile.
set -euo pipefail
cd "$(dirname "$0")/.."
{
  echo "# SHA-256 of every file the kit runs. Check them all at once: see docs/trust.md"
  sha256sum omen-audit.ps1 windows/*.ps1 windows/checks/*.ps1 linux-live-audit.sh mac-audit.sh lib/common.sh profiles/*.psd1
} > docs/SHA256SUMS.txt
cat docs/SHA256SUMS.txt
