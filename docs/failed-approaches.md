# Failed Approaches: LK Bootloader Patching

This document records the approaches that **did not work** for getting CipherOS to boot on the Rabbit R1. They are preserved here as institutional knowledge for anyone working on MediaTek devices or the R1 specifically.

**TL;DR**: We tried patching the LK (Little Kernel) bootloader to bypass dm-verity and boot verification shutdowns, and used `mtkclient` to write partition images directly. All approaches failed. The correct method is to use `fastbootd` (via `mtkbootcmd.py` -> fastboot -> fastbootd), which handles dynamic partition metadata automatically.

## Background

The original plan was to:
1. Use `mtkclient` (MediaTek USB exploit tool) to write CipherOS images directly to the eMMC
2. Patch the LK bootloader to bypass dm-verity and boot verification checks that prevent unsigned OS from booting

This approach seemed simpler than fastboot since `mtkclient` gives raw block-level access. It turned out to be fundamentally flawed.

## Approach 1: Raw Partition Writes via mtkclient

**What we did:** Used `mtkclient` to write CipherOS system.img, vendor.img, product.img, and system_ext.img directly to byte offsets within the super partition. Also wrote a custom LpMetadata header (`super_header_v3.bin`) with correct 64-byte block device entries.

**What happened:** The kernel couldn't find or mount the partitions from super. Various LpMetadata header formats were tried (v1, v2, v3), eventually getting the format correct (64-byte bdev entries, align=512, flags=0x1), but the kernel still failed to mount.

**Why it failed:** Raw partition writes bypass the dynamic partitions metadata management layer. Even with a correctly formatted LpMetadata header, the extent tables, group configurations, and partition layout need to be internally consistent. `fastbootd` handles this automatically, which is why it works.

**Lesson:** Don't try to outsmart Android's dynamic partitions system by writing raw bytes. Use `fastbootd`.

## Approach 2: LK Bootloader Patching v2

**What we did:** Disassembled the LK bootloader (Thumb-mode ARM, 309K lines) and identified the dm-verity handler at offset 0x51730. The handler calls `mt_power_off` at offset 0x517c0 to shut down the device when verification fails. We NOPed the `BL mt_power_off` instruction at 0x517c0.

**Patch:** Replace `BL 0x78b0` at offset 0x517c0 with `NOP; NOP` (0xBF00BF00 in Thumb)

**What happened:** Device still shut down. The dm-verity path was bypassed, but there was a second shutdown path.

**Lesson:** The LK has multiple verification paths. Patching one is insufficient.

## Approach 3: LK Bootloader Patching v3

**What we did:** NOPed ALL 4 calls to `mt_power_off` found in the binary.

**What happened:** Device rebooted in a fast loop instead of shutting down cleanly. The reboot loop was faster than the previous shutdown behavior, suggesting we got past the verification but something else went wrong.

**Lesson:** NOPing all shutdown calls causes callers to fall through into subsequent code paths that weren't designed to execute after a failed check.

## Approach 4: LK Bootloader Patching v4

**What we did:** Targeted only 2 specific shutdown calls:
1. 0x517c0 -- dm-verity handler shutdown
2. 0x1d68c -- Boot path verification shutdown

These were identified as the two critical shutdown paths through control flow analysis:
- 0x517c0 triggers when dm-verity fails
- 0x1d68c triggers when boot state value is 8 or 9 AND a secondary check at 0x7938 returns 0

**What happened:** Still boot-looped, though behavior was slightly different (slower cycling). The LK appeared to pass through to kernel loading, but the kernel failed to boot properly.

**Lesson:** Even with the correct shutdown paths identified, the underlying issue was likely the super partition metadata, not LK itself.

## Approach 5: LK Bootloader Patching v5

**What we did:** NOPed all 6 distinct calls to `mt_power_off` in the entire binary, covering every possible code path that could trigger a shutdown.

**What happened:** Same boot loop behavior as v3/v4.

**Lesson:** The problem was never purely about LK shutdown paths.

## Approach 6: LK Bootloader Patching v6

**What we did:** Instead of NOPing individual calls, patched `mt_power_off` itself to immediately return:

```
Address 0x78b0: BX LR (0x4770) + NOP (0x00BF)
```

This catches ALL callers (including any indirect calls through function pointers).

**What happened:** Rapid USB cycling with `error -71` (USB protocol error). The device cycled much faster than before, suggesting the kernel was loading but crashing almost immediately. Battery drained rapidly.

**Lesson:** Making `mt_power_off` a no-op causes callers to continue execution in undefined states. Functions that call shutdown expect the device to stop; when it doesn't, they fall through into random code, causing WDT (watchdog timer) resets.

## Approach 7: BCB "boot-fastboot" via Para Partition

**What we did:** Wrote a BCB (Bootloader Control Block) with "boot-fastboot" command to the `para` partition at offset 0x108000, hoping the LK would read it and enter fastboot mode.

**What happened:** Device rapidly cycled and died. The BCB was never read.

**Why it failed:** The "boot-fastboot" BCB command is read by Android init (kernel level), NOT by LK. If the kernel can't boot (which was our problem), the BCB is never read. This is a chicken-and-egg problem.

**Lesson:** BCB commands require a booting kernel. To enter fastboot on a boot-looping device, use the preloader-level serial command (mtkbootcmd.py).

## The Correct Approach

After all these failed attempts, the solution was:

1. **Use `mtkbootcmd.py`** to send a FASTBOOT command to the MediaTek preloader via USB serial. This enters fastboot at the LK level, before any verification checks run.

2. **Use `fastbootd`** (userspace fastboot) to flash logical partitions. Fastbootd properly manages the LpMetadata, extent tables, and partition layout inside the super partition.

3. **Keep the stock boot.img** -- CipherOS's boot.img doesn't support fastbootd. The stock kernel is compatible with CipherOS's system/vendor/product images.

4. **Disable vbmeta verification** -- Rather than patching LK to bypass checks, simply flash vbmeta with `--disable-verity --disable-verification` flags.

See the [Flashing Guide](flashing-guide.md) for the working procedure.

## Tools Used

| Tool | Purpose | Notes |
|------|---------|-------|
| `mtkclient` | Raw eMMC read/write via MediaTek USB exploit | Works for reading/backing up, but raw writes to super are unreliable |
| ARM Thumb disassembler | LK binary analysis | Used to trace shutdown call paths |
| `mtkbootcmd.py` | Enter fastboot via preloader serial | The key tool that made the working approach possible |
| `fastboot` | Standard Android flashing | Used for both bootloader fastboot and fastbootd |
