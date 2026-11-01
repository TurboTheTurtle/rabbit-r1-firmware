# Backing Up a Rabbit R1

Take a full dump before flashing anything. The official release archive is **not** a
complete backup, and on this hardware it is frequently **older** than what the device
is running.

## Why the release archive is not enough

1. **Official releases stop at v0.8.293 (May 2025).** The test unit for this project
   shipped with `rabbit_OS_v2.3.1_20260910192308` (Android 13, SDK 33, built
   2026-09-10) — roughly 16 months newer than the newest published release. Flashing
   v0.8.293 is a *downgrade*, and there is nothing to download that matches what was
   on the device.

2. **OTA updates use virtual A/B snapshots.** The `super` partition on an updated
   device carries `system_a-cow`, `vendor_a-cow` and `product_a-cow` extents alongside
   `system_a`/`vendor_a`/`product_a`. The live system is the base partition merged with
   its COW overlay. Extracting `system_a` on its own gives you the **pre-OTA** system,
   not what boots.

3. **Calibration and identity partitions never ship in a release.** `nvram`, `nvdata`,
   `nvcfg`, `proinfo`, `protect1`, `protect2`, `seccfg`, `para`, `frp` and `otp` are
   per-device. A normal restore leaves them alone, but a botched flash or a
   `fastboot erase` can take them with it — and they are not recoverable from a ZIP.

## Requirements

```bash
# mtkclient (MediaTek DA protocol; works over the preloader USB interface)
pip install pyserial
pip install --ignore-requires-python git+https://github.com/bkerler/mtkclient.git
```

`--ignore-requires-python` is needed on Python 3.13+ because mtkclient pins an older
supported range.

**macOS:** mtkclient imports `mfusepy` unconditionally for an optional FUSE mount. The
real module raises `OSError("Unable to find libfuse")` when libfuse is absent, and
mtkclient's `except ImportError` guard does not catch it, so the whole CLI dies. Put the
stub in `scripts/mfusepy_stub/` first on `PYTHONPATH` (the dump script does this
automatically).

**Linux:** works as-is; no stub needed.

**Windows:** mtkclient works, but the preloader driver must be installed
(`MediaTek-Preloader_USB_VCOM_drivers-signed.zip` from the rabbit-hmi-oss releases).

## Procedure

The MediaTek preloader only exposes its serial interface for a moment at power-on, so
the timing matters: start the tool first, then power the device on.

```bash
# 1. Power the R1 off completely (hold power, or use the reset pin by the SIM slot).

# 2. Start the dump. It will sit waiting for the preloader.
scripts/dump-stock.sh --critical

# 3. Plug the R1 in / press power. The tool sees the preloader and reads the partitions.
#    The device reboots itself when the session ends.
```

For an arbitrary list of partitions:

```bash
scripts/dump-stock.sh boot_a,boot_b,init_boot_a,init_boot_b,vbmeta_a,super
```

Each partition is written as `<name>.bin` in `firmware/device-dump/`, and the script
prints a size and SHA-256 for every one.

A full dump (everything except `userdata`) is about **8.9 GB**, most of it `super`
(8,792,064,000 bytes). Expect roughly 15 MB/s over USB — around ten minutes.

## Partitions worth dumping

| Partition | Size | Why |
|-----------|------|-----|
| `super` | 8.79 GB | Everything Android-side, including the COW overlays |
| `boot_a`, `boot_b` | 32 MB each | Kernel + ramdisk per slot |
| `init_boot_a/b` | 8 MB each | Android 13+ generic ramdisk (Magisk target) |
| `vendor_boot_a/b` | 64 MB each | Vendor ramdisk |
| `vbmeta`, `vbmeta_system`, `vbmeta_vendor` (a+b) | 8–16 MB | Verified-boot metadata; needed to restore a bootable device |
| `dtbo_a/b`, `lk_a/b`, `tee_a/b` | 8 MB / 1 MB / 5 MB | Device tree overlay, bootloader, trusted execution |
| `md1img_a/b` | 100 MB | Modem firmware |
| `gz_a/b`, `scp_a/b`, `sspm_a/b`, `spmfw_a/b` | 1–16 MB | MediaTek coprocessor firmware |
| `nvram`, `nvdata`, `nvcfg` | 64/64/32 MB | Radio calibration, IMEI, MAC addresses |
| `protect1`, `protect2` | 8 / 11 MB | DRM keys |
| `proinfo` | 3 MB | Product identity |
| `seccfg` | 8 MB | Bootloader lock state |
| `para`, `boot_para` | 512 KB / 1 MB | Boot control block and A/B slot state |
| `frp` | 1 MB | Factory reset protection |
| `otp` | 43 MB | One-time-programmable fuse state (read-only) |

`userdata` is deliberately skipped — it is 110 GB, changes constantly, and every
flashing procedure erases it anyway.

## Verify the dump

```bash
cd firmware/device-dump
sha256sum -c MANIFEST.sha256      # or: shasum -a 256 -c MANIFEST.sha256
```

The script also writes `gpt.bin`; `scripts/lpinfo.py` can turn it into a readable
partition table, or just parse `super` directly:

```bash
scripts/lpinfo.py firmware/device-dump/super.bin
```

```
LP metadata: v10.2 flags=0x1
groups: default, main_a, cow
  product_a      179.0 MiB  offset 0x100000
  system_a      1498.5 MiB  offset 0xb400000
  vendor_a       337.8 MiB  offset 0x69c00000
  product_a-cow  103.8 MiB  offset 0x7f7be000
  system_a-cow   759.4 MiB  offset 0x85f8e000
  vendor_a-cow   167.1 MiB  offset 0xb56f0000
```

`lpinfo.py` reads the LP metadata header directly, so it works on macOS without
`lpunpack` (which is Linux-only).

## Restoring from a dump

```bash
for f in firmware/device-dump/*.bin; do
  n=$(basename "$f" .bin)
  case "$n" in gpt|gpt_backup) continue;; esac
  mtk w "$n" "$f"
done
```

Or in one session: `mtk wl firmware/device-dump`.

Raw writes are safe **when the bytes are the original ones**. The well-known "mtkclient
corrupts super" failure comes from writing a *different* image (e.g. a CipherOS logical
partition) with a hand-built LP header — see [Failed Approaches](failed-approaches.md).
Restoring the dump byte-for-byte does not have that problem, because the LP metadata in
it is the original.

## Gotchas

- **Use `mtk r`, not `mtk rl`.** `da_read` logs a failed partition and continues;
  `da_rl` raises and kills the whole run. Long reads over USB occasionally glitch, and
  losing 8 GB of progress is worse than losing one partition.
- **`otp` is one-time-programmable.** Reading is fine; writing is a no-op at best.
- **A rooted device has modified slot A images.** If Magisk is installed, `boot_a` and
  `vbmeta_a` differ from stock; slot B is usually untouched. Do not treat a dumped
  `boot_a` as the pristine image for that build.
- **ADB does not work on stock firmware.** `tech.rabbit.judy` force-disables it, and the
  USB gadget only exposes HID + WebUSB (`0e8d:2304`). A dump is often the only way to
  get files off the device.
- **`cdc_acm` on Linux** is needed for the preloader serial and conflicts with `adb`; see
  [`scripts/toggle-cdc-acm.sh`](../scripts/toggle-cdc-acm.sh).
