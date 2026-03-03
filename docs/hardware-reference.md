# Rabbit R1 Hardware Reference

## Specifications

| Component | Details |
|-----------|---------|
| SoC | MediaTek MT6765 / Helio P35 |
| CPU | 4x Cortex-A53 2.3GHz + 4x Cortex-A53 1.8GHz |
| RAM | 4GB |
| Storage | 128GB eMMC |
| Display | 2.88" touchscreen |
| Camera | Rotating camera module |
| Connectivity | WiFi, Bluetooth, LTE (SIM slot) |
| USB | USB-C (data + charging) |
| Battery | Internal, non-removable |

## Buttons and Controls

```
┌─────────────────────┐
│                     │
│    ┌───────────┐    │
│    │           │    │
│    │  Display  │    │
│    │  2.88"    │    │
│    │           │    │
│    └───────────┘    │
│                     │  ← Scroll Wheel (right side, NOT clickable)
│                     │
│    [  PTT/Power  ]  │  ← PTT button = Power button (single button)
│                     │
└─────────────────────┘
      ↑ USB-C port

Reset pin: near SIM slot (use SIM ejector tool)
SIM slot: nano-SIM for LTE
```

**Important notes:**
- **No volume buttons** -- This is the critical hardware limitation. Android's standard fastboot entry (Volume Down + Power) is impossible.
- **PTT button IS the power button** -- Same physical button serves both functions. Short press = PTT (in stock firmware), long press = power off.
- **Scroll wheel** -- Rotates but does not click/press. Sends scroll input events.
- **Reset pin** -- Small hole near the SIM slot. Insert a SIM ejector tool to force reset.

## USB Device IDs

| Mode | VID:PID | Description |
|------|---------|-------------|
| Preloader | `0e8d:2000` | MediaTek preloader mode (seen during boot) |
| Fastboot (bootloader) | `0e8d:201c` | LK fastboot mode |
| ADB | Various | Standard Android ADB interface |

## MediaTek Boot Chain

```
Power On
  → Preloader (MediaTek ROM, VID 0e8d:2000)
    → Reads FASTBOOT command via serial (mtkbootcmd.py)
    → LK Bootloader (Little Kernel)
      → Checks dm-verity
      → Checks boot verification state
      → Loads kernel from boot_a/boot_b
        → Linux Kernel
          → Android Init
            → fastbootd (if BCB says "boot-fastboot")
```

## GPT Partition Layout

Key partitions and their byte offsets on the eMMC:

| Partition | Offset | Size | Notes |
|-----------|--------|------|-------|
| `para` | 0x108000 | 512KB | A/B slot info at offset 0x800 (slot_a active). Also serves as misc/BCB partition |
| `lk_a` | 0x18f00000 | 1MB | LK bootloader slot A |
| `boot_a` | 0x19000000 | 32MB | Kernel + ramdisk slot A |
| `vendor_boot_a` | 0x1B000000 | 32MB | Vendor boot slot A |
| `lk_b` | 0x29700000 | 1MB | LK bootloader slot B |
| `boot_b` | 0x29800000 | 32MB | Kernel + ramdisk slot B |
| `super` | 0x31000000 | ~8.19 GiB | Dynamic partitions container |
| `userdata` | 0x23F000000 | Remaining | User data |

### Super Partition (Dynamic Partitions)

The `super` partition contains logical partitions managed by Android's dynamic partitions system:

**Stock layout:**
- `system_a` -- Main Android system
- `vendor_a` -- Vendor HAL and firmware
- `product_a` -- Product-specific apps and overlays

**CipherOS layout** (after flashing):
- `system_a` -- CipherOS system (~1.4GB)
- `system_ext_a` -- System extensions (~534MB, must be created manually)
- `vendor_a` -- Vendor HAL (~353MB)
- `product_a` -- Product overlay (~389MB)

### LpMetadata Format (Super Partition Header)

The super partition header uses Android's LpMetadata format:

| Field | Value (Stock R1) |
|-------|-----------------|
| Block device entry size | 64 bytes |
| First sector | 2048 |
| Alignment | 512 |
| Super size | 8,792,064,000 bytes |
| Geometry magic | 0x616c4467 |
| Max metadata size | 65,536 |
| Metadata slots | 3 |
| Block size | 4,096 |
| Header magic | 0x414c5030 |
| Header version | 10.2 |
| Header size | 256 |
| Flags | 0x1 (Virtual A/B) |
| Partition attributes | 0x00000005 (READONLY + SLOT_SUFFIXED) |

## LK Bootloader Analysis

The LK (Little Kernel) bootloader has been extensively analyzed during the development of this project. Key findings:

| Symbol | Address (offset from base 0x48000000) | Function |
|--------|---------------------------------------|----------|
| `mt_power_off` | 0x78b0 | System shutdown function |
| dm-verity handler | 0x51730 | Verification check (shutdown at 0x517c0) |
| Orange State display | 0x3d550 | Shows "orange state" with 5s sleep |
| Boot verification | 0x51b8c | Boot state verification (called from 0x1da1a) |
| Boot path shutdown | 0x1d68c | Shutdown triggered by boot state check |

See [Failed Approaches](failed-approaches.md) for detailed analysis of LK patching attempts.
