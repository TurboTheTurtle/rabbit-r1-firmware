# Firmware Images

Firmware images are not included in this repository due to their size. Download them from the official sources below.

## Stock Firmware (Rabbit OS v0.8.293)

**Download:** [rabbit-hmi-oss/firmware v0.8.293](https://github.com/rabbit-hmi-oss/firmware/releases/download/v0.8.293/rabbit_OS_v0.8.293.zip)

**Size:** ~922 MB (ZIP)

**Required files after extraction:**
| File | Size | Purpose |
|------|------|---------|
| `boot.img` | 32 MB | Stock kernel (required for fastbootd support) |
| `super.img` | ~2 GB | Stock super partition (Android sparse format) |
| `vbmeta.img` | 4 KB | Verified boot metadata |
| `vbmeta_system.img` | 4 KB | System verified boot metadata |
| `vbmeta_vendor.img` | 4 KB | Vendor verified boot metadata |

## Stock Firmware (Rabbit OS v2.3.1 and newer)

**Download:** none — there is no published release for these builds.

The newest archive on [rabbit-hmi-oss/firmware](https://github.com/rabbit-hmi-oss/firmware/releases)
is v0.8.293 from May 2025. Devices in the field run much newer software: the test unit for
this project reported `rabbit_OS_v2.3.1_20260910192308`, Android 13 (SDK 33), built
2026-09-10. Flashing v0.8.293 onto such a device is a **downgrade**.

The only way to keep that build is to dump it from the device itself — see
[Backing Up a Rabbit R1](../docs/device-dump.md).

**Files produced by a dump:**

| File | Size | Purpose |
|------|------|---------|
| `boot_a.bin`, `boot_b.bin` | 32 MB each | Kernel + ramdisk. On a rooted device slot A carries the Magisk patch |
| `init_boot_a/b.bin` | 8 MB each | Android 13+ generic ramdisk |
| `vendor_boot_a/b.bin` | 64 MB each | Vendor ramdisk |
| `super.bin` | 8.79 GB | Raw dynamic-partition container, including live COW overlays |
| `vbmeta*_a/b.bin` | 8–16 MB | Verified-boot metadata per slot |
| `dtbo_a/b.bin`, `lk_a/b.bin`, `tee_a/b.bin` | 8 MB / 1 MB / 5 MB | Device tree, bootloader, TEE |
| `md1img_a/b.bin` | 100 MB each | Modem firmware |
| `gz/scp/sspm/spmfw_a/b.bin` | 1–16 MB | MediaTek coprocessor firmware |

`super.bin` is too large for git; the repository stores checksums only.

## CipherOS

**Download:** [CipherOS for Rabbit R1](https://cipheros.com/) (device codename: `cipher_r1`)

**Required files:**
| File | Size | Purpose |
|------|------|---------|
| `system.img` | ~1.4 GB | CipherOS system image |
| `system_ext.img` | ~534 MB | System extensions |
| `product.img` | ~389 MB | Product overlay |
| `vendor.img` | ~353 MB | Vendor HAL |

## Checksums

| File | Covers |
|------|--------|
| `checksums.sha256` | Stock v0.8.293 release images and CipherOS images |
| `checksums-stock-v2.3.1.sha256` | Boot-chain and `super` images from the v2.3.1 device dump |

To verify a downloaded release:
```bash
sha256sum -c checksums.sha256
```

To verify your own dump, run it from inside the dump directory:
```bash
cd firmware/device-dump
sha256sum -c ../checksums-stock-v2.3.1.sha256
```
