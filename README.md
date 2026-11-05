# FOXXD A67L Gen2 Rooting Toolkit

Read-only diagnostics, backup and Magisk-readiness validation for the
**FOXXD A67L Gen2** running Android 16 (`Android16_Foxxd_A67L_3G_V1.0_260530`).

> **This tool does not unlock, erase or flash anything.** Flashing is hard-locked
> in this release. It exists to answer one question safely: *which partition
> holds the ramdisk on my build, and is my bootloader even unlockable?*

## Features

- ADB device detection and authorization check
- Full property / build fingerprint dump with expected-build validation
- Partition layout probe (`boot` vs `init_boot` vs recovery-ramdisk)
- Bootloader + verified-boot state interpretation
- Package inventory, settings snapshot and logcat capture
- SHA-256 hashing of every artifact written to the report directory
- Machine-readable JSON report alongside human-readable log
- No network calls, no telemetry, no bundled binaries

## Requirements

- Windows 11 (Windows 10 1809+ also works), PowerShell 5.1+
- [Android Platform-Tools](https://developer.android.com/tools/releases/platform-tools)
  for Windows (not bundled — Google's licence forbids redistribution)
- USB debugging enabled on the phone

## Quick start

```powershell
git clone https://github.com/<you>/FOXXD-A67L-Gen2-Toolkit.git
cd FOXXD-A67L-Gen2-Toolkit

# Drop platform-tools here:
#   tools\adb.exe, tools\fastboot.exe, tools\*.dll ...

powershell -ExecutionPolicy Bypass -File .\src\A67L-Gen2-Toolkit.ps1
```

Menu:

1. Run device diagnostics + backup
2. Show Magisk readiness checklist
3. Quit

Non-interactive:

```powershell
.\src\A67L-Gen2-Toolkit.ps1 -Diagnostics
```

Output goes to `reports\<timestamp>\` (`report.json`, `report.txt`, `logcat.txt`,
`packages.txt`, `SHA256SUMS.txt`).

## Build the distributable ZIP

```powershell
.\build\Build-Zip.ps1
# -> dist\FOXXD-A67L-Gen2-Toolkit-v1.0.0.zip
```

## Status

| Stage | State |
|---|---|
| Diagnostics | Working |
| Backup / report | Working |
| Bootloader unlock | **Locked** — manual, wipes device |
| Image patching | Manual (Magisk app) |
| Flashing | **Locked** — requires verified layout |

Magisk target: **v31.1** (Android 16 QPR2 sepolicy + Zygisk support).

## Legal

For devices you own. Rooting voids warranties and may trip verified boot.
You are responsible for your hardware. MIT licensed.
