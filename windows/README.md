# The Windows kit, file by file

`omen-audit.ps1` in the folder above only starts things: it reads the options, picks the mode, and runs the
files below. Each file does one job and can be read on its own. All of them are pure ASCII, for Windows
PowerShell 5.1.

| File | Job |
| --- | --- |
| `core.ps1` | Shared helpers: recording a result, saving raw output, small conversions, the kit's own fingerprints |
| `profile.ps1` | Recognises the laptop and loads what it should have from `..\profiles` |
| `nvme.ps1` | Reads the SSD's NVMe health log (power-on hours, TB written, wear) straight from the drive |
| `diskspeed.ps1` | Uncached sequential speed test, used for the SSD and the USB ports |
| `events.ps1` | The event log check: hardware errors, crashes, SSD resets, hangs, devices with errors |
| `monitor.ps1` | The sensor log for `-Monitor`, `-Stress` and `-GpuTest`, and its verdicts |
| `stress.ps1` | The verified CPU and RAM load for `-Stress` |
| `gpumemtest.ps1` | Fetches, checks and runs memtest_vulkan for `-GpuTest` |
| `interactive.ps1` | The hands-on tests for `-Interactive` |
| `report.ps1` | SUMMARY.txt, the HTML and PDF report, and MANIFEST.sha256 |
| `checks\*.ps1` | The full audit, one area per file, run in the order listed in `omen-audit.ps1` |

## How the parts fit

- Every file is dot-sourced from `omen-audit.ps1`, so they share one scope: a check can read what an
  earlier one found, and every result goes into the same list for the report.
- Each check runs inside its own error guard. If one crashes, the report says which one and why, and the
  rest still run. Before the split, one crash stopped every check after it.
- The order and the list of checks are fixed in `omen-audit.ps1`, not read from the folder, so a file left
  over from an older download never runs. A missing file stops the run with a clear message.
- `-Only storage,battery` runs single checks again without the whole audit.

## Adding a check

1. Write `checks\<name>.ps1`: start with `Section '<Title>'`, record each result with
   `Add-Result 'PASS|WARN|FAIL|INFO' '<Check>' '<detail>'`, and save raw output with `Save-Text`.
   Read expected values with `Test-Spec '<Key>'` and `$Expect.<Key>`, so it works in generic mode.
2. Add `<name>` to `$FullChecks` in `omen-audit.ps1`, where it should run.
3. Add a row to `docs/checks.md`, run `tools/update-hashes.sh`, and test it on a real machine.
