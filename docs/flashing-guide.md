# Flashing CipherOS on Rabbit R1

This guide walks through flashing [CipherOS](https://cipheros.com/) (Android 16) onto a Rabbit R1. The procedure uses MediaTek's preloader serial interface to enter fastboot mode, then flashes via standard `fastboot` commands.

> **Important**: This process will erase all data on the device. The R1 can always be restored to stock firmware -- see [Restoring Stock Firmware](#restoring-stock-firmware).

## Prerequisites

### Hardware
- Rabbit R1
- USB-C data cable
- Linux host with USB access (tested on Proxmox/Debian)

### Software

Install these on your Linux host:

```bash
# Android platform tools (fastboot + adb)
apt install android-tools-adb android-tools-fastboot
# or: https://developer.android.com/tools/releases/platform-tools

# Python 3 + pyserial (for mtkbootcmd.py)
apt install python3 python3-pip
pip3 install pyserial

# Clone r1_escape (for mtkbootcmd.py)
git clone https://github.com/RabbitHoleEscapeR1/r1_escape.git
```

### Firmware Images

**Stock Firmware (required):**
Download `rabbit_OS_v0.8.293.zip` from [rabbit-hmi-oss/firmware](https://github.com/rabbit-hmi-oss/firmware/releases/download/v0.8.293/rabbit_OS_v0.8.293.zip) and extract it. You need:
- `boot.img` -- Stock kernel (required for fastbootd support)
- `super.img` -- Stock super partition (clean partition base)
- `vbmeta.img`, `vbmeta_system.img`, `vbmeta_vendor.img`

> If your device is on a newer build than v0.8.293 — most are — take a raw dump before
> flashing, so you can get back to what you actually had. See
> [Backing Up a Rabbit R1](device-dump.md).

**CipherOS (required):**
Download CipherOS for the Rabbit R1 (`cipher_r1`). You need:
- `system.img`, `system_ext.img`, `product.img`, `vendor.img`
- `vbmeta.img`, `vbmeta_system.img`, `vbmeta_vendor.img`

### Kernel Module Setup

The `cdc_acm` kernel module is needed for `mtkbootcmd.py` but conflicts with `adb`. You'll toggle it during the process.

```bash
# Check if cdc_acm is blacklisted
cat /etc/modprobe.d/blacklist-cdc_acm.conf 2>/dev/null

# If blacklisted, temporarily enable it:
mv /etc/modprobe.d/blacklist-cdc_acm.conf /etc/modprobe.d/blacklist-cdc_acm.conf.disabled
modprobe cdc_acm
```

## Understanding the R1 Boot Chain

```
MediaTek Preloader (ROM) → LK Bootloader → Linux Kernel → Android Init
                ↓                ↓
        mtkbootcmd.py      Fastboot Mode
        sends FASTBOOT     (can flash partitions)
                              ↓
                         fastbootd (userspace)
                         (can flash logical partitions
                          inside super)
```

The R1 has **no volume buttons**, so the standard Android method of holding Volume Down + Power to enter fastboot doesn't work. Instead, we use `mtkbootcmd.py` from the [r1_escape](https://github.com/RabbitHoleEscapeR1/r1_escape) project, which sends a `FASTBOOT` command via USB serial to the MediaTek preloader before it hands off to the bootloader.

**Two-stage fastboot:**
1. **Bootloader fastboot** (LK level) -- Can flash physical partitions like `boot_a`, `vbmeta_a`
2. **Userspace fastbootd** -- Can flash logical partitions inside `super` (system, vendor, product, system_ext)

CipherOS's boot.img does **not** support fastbootd. That's why we use the **stock boot.img** -- it provides fastbootd support for flashing the CipherOS logical partitions.

## Flashing Procedure

### Step 1: Enter Fastboot Mode

```bash
# Enable cdc_acm (required for mtkbootcmd.py)
modprobe cdc_acm

# Power off the R1 completely
# (hold power button until screen goes dark, or use the reset pin near the SIM slot)

# Run mtkbootcmd.py -- it will wait for the device
python3 r1_escape/mtkbootcmd.py FASTBOOT

# NOW plug in the powered-off R1 via USB-C
# The preloader will send "READY", the script sends "FASTBOOT"
# You should see: "Sent boot mode command: FASTBOOT"
```

Verify fastboot mode:
```bash
fastboot devices
# Should show: <serial>    fastboot
```

### Step 2: Flash Stock Boot Image

The stock boot.img provides fastbootd support, which we need to flash logical partitions.

```bash
fastboot flash boot_a /path/to/stock_firmware/boot.img
fastboot flash boot_b /path/to/stock_firmware/boot.img
```

### Step 3: Disable Verified Boot

Flash vbmeta with verification disabled to all 6 slots:

```bash
fastboot --disable-verity --disable-verification flash vbmeta_a /path/to/stock_firmware/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_b /path/to/stock_firmware/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system_a /path/to/stock_firmware/vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_system_b /path/to/stock_firmware/vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor_a /path/to/stock_firmware/vbmeta_vendor.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor_b /path/to/stock_firmware/vbmeta_vendor.img
```

### Step 4: Reboot to Fastbootd

```bash
fastboot reboot fastboot
```

Wait for the device to reboot into userspace fastbootd. Verify:
```bash
fastboot getvar is-userspace
# Should show: is-userspace: yes
```

### Step 5: Flash Stock Super Partition

This creates a clean partition layout as a base:

```bash
fastboot flash super /path/to/stock_firmware/super.img
```

This takes ~100 seconds for the 2GB sparse image.

### Step 6: Flash Vbmeta in Fastbootd

```bash
fastboot --disable-verity --disable-verification flash vbmeta_system_a /path/to/stock_firmware/vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor_a /path/to/stock_firmware/vbmeta_vendor.img
```

### Step 7: Verify Stock Boot (Optional but Recommended)

At this point, you can verify the stock firmware boots correctly:

```bash
fastboot reboot
```

The R1 should boot to the RabbitOS setup screen. If it does, you know the base is solid. Power off the device and continue.

### Step 8: Re-enter Fastboot Mode

Repeat Step 1 to re-enter fastboot via `mtkbootcmd.py`.

### Step 9: Flash Boot and Vbmeta Again

```bash
fastboot flash boot_a /path/to/stock_firmware/boot.img
fastboot flash boot_b /path/to/stock_firmware/boot.img

fastboot --disable-verity --disable-verification flash vbmeta_a /path/to/stock_firmware/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_b /path/to/stock_firmware/vbmeta.img
```

### Step 10: Reboot to Fastbootd

```bash
fastboot reboot fastboot
```

### Step 11: Create system_ext Partition

The stock R1 layout doesn't have a `system_ext` partition, but CipherOS needs one:

```bash
fastboot create-logical-partition system_ext_a 559304704
```

### Step 12: Flash CipherOS Partitions

```bash
fastboot flash system_a /path/to/cipheros/system.img
fastboot flash system_ext_a /path/to/cipheros/system_ext.img
fastboot flash product_a /path/to/cipheros/product.img
fastboot flash vendor_a /path/to/cipheros/vendor.img
```

### Step 13: Erase Userdata

```bash
fastboot erase userdata
```

### Step 14: Reboot

```bash
fastboot reboot
```

The device will show an "orange state" warning briefly (this is normal -- it indicates the bootloader is unlocked), then boot into CipherOS.

### Step 15: Configure ADB Access

On the host, disable `cdc_acm` so `adb` can connect:

```bash
rmmod cdc_acm

# Re-enable the blacklist to persist across reboots
mv /etc/modprobe.d/blacklist-cdc_acm.conf.disabled /etc/modprobe.d/blacklist-cdc_acm.conf

# Verify ADB connection
adb devices
```

### Step 16: Post-Install Setup

```bash
# Wake the screen (it may appear off due to sleep)
adb shell input keyevent KEYCODE_WAKEUP

# Set display density for R1's small screen
adb shell wm density 190
```

You should now see the CipherOS home screen on the R1.

## Restoring Stock Firmware

The R1 can always be restored to stock RabbitOS:

1. Enter fastboot mode via `mtkbootcmd.py` (Step 1 above)
2. Flash stock boot.img to both slots (Step 2)
3. Flash vbmeta with `--disable-verity --disable-verification` (Step 3)
4. Reboot to fastbootd (Step 4)
5. Flash stock super.img (Step 5)
6. Erase userdata: `fastboot erase userdata`
7. Reboot: `fastboot reboot`

Stock firmware v0.8.293 is available at [rabbit-hmi-oss/firmware](https://github.com/rabbit-hmi-oss/firmware/releases).

> **This is a downgrade on most devices.** v0.8.293 (May 2025) is the newest *published*
> release, but production units ship much newer builds — the test unit for this project
> was on `rabbit_OS_v2.3.1_20260910192308` (Android 13, built 2026-09-10). There is no
> download for that build, so restoring from the ZIP throws it away. Dump the device
> first if you want to keep it: see [Backing Up a Rabbit R1](device-dump.md).

### Restoring from a dump instead

A raw dump restores the exact build, including the COW snapshot state:

```bash
for f in firmware/device-dump/*.bin; do
  n=$(basename "$f" .bin)
  case "$n" in gpt|gpt_backup) continue;; esac
  mtk w "$n" "$f"
done
```

or in a single mtkclient session: `mtk wl firmware/device-dump`.

Raw writes are safe here because the bytes are the original ones — the "mtkclient
corrupts super" failure documented in [Failed Approaches](failed-approaches.md) comes
from writing a *different* image with a hand-built LP header, not from writing a dump
back.

## Final Configuration

| Setting | Value |
|---------|-------|
| ROM | CipherOS (cipher_r1-userdebug) |
| Android Version | 16 |
| Build | BP2A.250605.031.A2 |
| Architecture | arm64-v8a |
| SDK Level | 36 |
| Display Density | 190 |
| Active Slot | a |
| Boot Image | Stock v0.8.293 (for fastbootd support) |
| System/Vendor/Product | CipherOS |
