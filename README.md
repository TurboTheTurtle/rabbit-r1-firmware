# Rabbit R1 Firmware Guide

Guides, scripts, and technical documentation for flashing custom firmware on the [Rabbit R1](https://www.rabbit.tech/r1). Includes a complete [CipherOS](https://cipheros.com/) (Android 16) flashing procedure, stock firmware restoration, hardware reference, and detailed notes on what worked and what didn't.

## What's in This Repo

| Directory | Contents |
|-----------|----------|
| [`docs/`](docs/) | Flashing guides, hardware reference, troubleshooting, CipherOS findings, backup procedure |
| [`scripts/`](scripts/) | Automation scripts for fastboot entry, flashing, and dumping |
| [`firmware/`](firmware/) | Download links and SHA-256 checksums for firmware images |

## Hardware

- **SoC**: MediaTek MT6765 / Helio P35
- **RAM**: 4 GB
- **Storage**: 128 GB eMMC
- **Display**: 2.88" touchscreen (480x640)
- **No volume buttons** — fastboot entry requires [`mtkbootcmd.py`](https://github.com/RabbitHoleEscapeR1/r1_escape) via MediaTek preloader serial interface
- **Side button** = PTT + Power (single button, same physical key)
- **Scroll wheel** = rotates only, does not click

## Quick Start

1. **[Flashing Guide](docs/flashing-guide.md)** — Step-by-step CipherOS installation and stock restore
2. **[Backing Up a Rabbit R1](docs/device-dump.md)** — Full partition dump before you flash; the only way to keep a newer build
3. **[Hardware Reference](docs/hardware-reference.md)** — SoC, buttons, USB IDs, partition layout, firmware versions, LK bootloader analysis
4. **[Troubleshooting](docs/troubleshooting.md)** — Common issues and fixes
5. **[Failed Approaches](docs/failed-approaches.md)** — 7 LK bootloader patching attempts (and why they all failed)
6. **[CipherOS Findings](docs/cipheros-findings.md)** — What works and what doesn't on CipherOS

## Key Findings

### Firmware Versions
- **Published releases stop at v0.8.293.** Production units run much newer software — the
  unit used for this project reported `rabbit_OS_v2.3.1_20260910192308`, Android 13 (SDK 33),
  built 2026-09-10. Rabbit publishes nothing for that build, so restoring "stock" from the
  ZIP downgrades the device. A community dump is available in the
  [stock-v2.3.1 release](https://github.com/TurboTheTurtle/rabbit-r1-firmware/releases/tag/stock-v2.3.1).
- **OTA updates use virtual A/B COW overlays.** On an updated device, `super` contains
  `system_a-cow`, `vendor_a-cow` and `product_a-cow` extents next to the base partitions.
  Extracting `system_a` alone gives the **pre-OTA** system, not what boots.
- **The release ZIP omits per-device partitions** (`nvram`, `nvdata`, `nvcfg`, `proinfo`,
  `protect1/2`, `seccfg`, `para`, `frp`, `otp`). Those hold radio calibration, IMEI, MAC
  addresses and DRM keys, and are not recoverable from a download.

### What Works
- CipherOS (Android 16, SDK 36) boots and runs on the R1
- WiFi, Bluetooth, touchscreen, display, USB, camera
- Scroll wheel sends `KEY_UP`/`KEY_DOWN` (DPAD navigation)
- ADB over USB (must toggle `cdc_acm` kernel module)
- Tailscale VPN connectivity

### What Doesn't Work on CipherOS
- **Side button produces zero interrupts** — the `mtk-kpd` kernel driver in CipherOS's kernel does not generate any events on button press. Stock kernel works fine. This appears to be a missing GPIO/PMIC configuration in the CipherOS device tree. See [CipherOS Findings](docs/cipheros-findings.md) for details.

### Critical Gotchas
- **Back up before you flash** → the newest published release is v0.8.293 (May 2025), but production units ship much newer builds. A full dump is the only way to keep what the device actually runs. See [Backing Up a Rabbit R1](docs/device-dump.md).
- **No volume buttons** → can't enter fastboot the Android way. Must use `mtkbootcmd.py` to send FASTBOOT command via preloader serial.
- **CipherOS boot.img doesn't support fastbootd** → must use stock boot.img (v0.8.293) even when running CipherOS.
- **`cdc_acm` conflicts with `adb`** → must toggle the kernel module: enable for `mtkbootcmd.py`, disable for `adb`.
- **`system_ext` doesn't exist in stock layout** → must create via `fastboot create-logical-partition` before flashing CipherOS.
- **Raw `mtkclient` writes to super don't work** → dynamic partition metadata gets corrupted. Must use `fastbootd` for logical partitions. See [Failed Approaches](docs/failed-approaches.md).
- **LK bootloader patching is a dead end** → we tried 7 different approaches to patch the Little Kernel bootloader to bypass dm-verity. All failed. The correct approach is disabling vbmeta verification via fastboot flags.

## Scripts

| Script | Purpose |
|--------|---------|
| [`fastboot-entry.sh`](scripts/fastboot-entry.sh) | Enter fastboot mode via preloader serial (`mtkbootcmd.py`) |
| [`flash-cipheros.sh`](scripts/flash-cipheros.sh) | Flash CipherOS (multi-phase fastboot + fastbootd) |
| [`flash-stock.sh`](scripts/flash-stock.sh) | Restore stock RabbitOS firmware |
| [`toggle-cdc-acm.sh`](scripts/toggle-cdc-acm.sh) | Toggle `cdc_acm` kernel module for serial vs adb |
| [`post-install.sh`](scripts/post-install.sh) | Post-boot configuration (density, wake, etc.) |
| [`dump-stock.sh`](scripts/dump-stock.sh) | Dump partitions via mtkclient before flashing (boot chain, calibration, super) |
| [`lpinfo.py`](scripts/lpinfo.py) | Read dynamic-partition (LP) metadata from a `super` image without `lpunpack` |
| [`lpmake.py`](scripts/lpmake.py) | Build a `super` image with LP metadata and logical partitions, without `lpmake` |
| [`mksparse.py`](scripts/mksparse.py) | Convert a raw `super` image to a chunk-bounded Android sparse image (MTK LK rejects multi-GB chunks) |

## Prerequisites

```bash
# Android platform tools
apt install android-tools-adb android-tools-fastboot

# Python + pyserial (for mtkbootcmd.py)
pip3 install pyserial

# mtkclient (for dumping partitions)
pip install --ignore-requires-python git+https://github.com/bkerler/mtkclient.git

# Clone r1_escape (for mtkbootcmd.py)
git clone https://github.com/RabbitHoleEscapeR1/r1_escape.git
```

## Related Projects

- [r1_escape](https://github.com/RabbitHoleEscapeR1/r1_escape) — R1 unlocking/flashing tools (we use `mtkbootcmd.py`)
- [rabbit-hmi-oss/firmware](https://github.com/rabbit-hmi-oss/firmware) — Official stock firmware releases
- [CipherOS](https://cipheros.com/) — Custom Android 16 ROM
- [Pinball3D/Rabbit-R1](https://github.com/Pinball3D/Rabbit-R1) — Launcher reverse engineering

## License

[Apache License 2.0](LICENSE)
