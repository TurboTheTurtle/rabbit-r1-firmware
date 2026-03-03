# Rabbit R1 Firmware Guide

Guides, scripts, and technical documentation for flashing custom firmware on the [Rabbit R1](https://www.rabbit.tech/r1). Includes a complete [CipherOS](https://cipheros.com/) (Android 16) flashing procedure, stock firmware restoration, hardware reference, and detailed notes on what worked and what didn't.

## What's in This Repo

| Directory | Contents |
|-----------|----------|
| [`docs/`](docs/) | Flashing guides, hardware reference, troubleshooting, CipherOS findings |
| [`scripts/`](scripts/) | Automation scripts for fastboot entry and flashing |
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
2. **[Hardware Reference](docs/hardware-reference.md)** — SoC, buttons, USB IDs, partition layout, LK bootloader analysis
3. **[Troubleshooting](docs/troubleshooting.md)** — Common issues and fixes
4. **[Failed Approaches](docs/failed-approaches.md)** — 7 LK bootloader patching attempts (and why they all failed)
5. **[CipherOS Findings](docs/cipheros-findings.md)** — What works and what doesn't on CipherOS

## Key Findings

### What Works
- CipherOS (Android 16, SDK 36) boots and runs on the R1
- WiFi, Bluetooth, touchscreen, display, USB, camera
- Scroll wheel sends `KEY_UP`/`KEY_DOWN` (DPAD navigation)
- ADB over USB (must toggle `cdc_acm` kernel module)
- Tailscale VPN connectivity

### What Doesn't Work on CipherOS
- **Side button produces zero interrupts** — the `mtk-kpd` kernel driver in CipherOS's kernel does not generate any events on button press. Stock kernel works fine. This appears to be a missing GPIO/PMIC configuration in the CipherOS device tree. See [CipherOS Findings](docs/cipheros-findings.md) for details.

### Critical Gotchas
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

## Prerequisites

```bash
# Android platform tools
apt install android-tools-adb android-tools-fastboot

# Python + pyserial (for mtkbootcmd.py)
pip3 install pyserial

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
