#!/usr/bin/env bash
# Writes docs/SHA256SUMS.txt: the fingerprints people compare their download against.
# Run it before every commit that changes a script or a profile.
set -euo pipefail
cd "$(dirname "$0")/.."
{
  echo "# SHA-256 of every file the kit runs. On Windows: (Get-FileHash .\\omen-audit.ps1).Hash"
  sha256sum omen-audit.ps1 linux-live-audit.sh profiles/*.psd1
} > docs/SHA256SUMS.txt
cat docs/SHA256SUMS.txt
