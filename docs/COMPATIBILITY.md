# Compatibility notes

Target: FOXXD A67L Gen2, Android 16, build `Android16_Foxxd_A67L_3G_V1.0_260530`.

## Verified

- Magisk v31.1 is current stable and supports Android 16 QPR2 sepolicy and Zygisk.
- Latest stable prior: v30.7 (first stable with A16 QPR2 sepolicy support).

## Not verified

- Whether this Gen2 build places the ramdisk in `boot` or `init_boot`
  (diagnostics resolve this per device).
- Whether the Unisoc bootloader accepts `fastboot flashing unlock` without a
  vendor auth file.
- Magisk functionality on this specific OEM firmware.
- Availability of a downloadable stock firmware package for restore.

## Prior art caution

Older A67L rooting write-ups target Android 14 / SC9863A and do not apply to
Gen2 Android 16 firmware. Separate Gen2 projects using KernelSU Next exist;
that is evidence of development activity only, not Magisk compatibility.

## Gate before flashing

1. Partition list captured in `report.json`.
2. `bootloaderState` == `unlocked`.
3. Stock image for the exact build on disk with recorded SHA-256.
4. Patched image created by the Magisk app from that stock image.
