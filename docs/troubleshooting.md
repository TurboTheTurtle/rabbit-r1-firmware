# Troubleshooting

## Common Issues

### ADB can't see the device

**Symptom:** `adb devices` shows nothing, even though the device is plugged in and booted.

**Cause:** The `cdc_acm` kernel module is loaded and grabbing the USB device before adb can.

**Fix:**

```bash
rmmod cdc_acm
# Verify
adb devices
```

To make this persist across reboots, ensure cdc_acm is blacklisted:

```bash
echo "blacklist cdc_acm" > /etc/modprobe.d/blacklist-cdc_acm.conf
```

### mtkbootcmd.py times out / doesn't detect device

**Symptom:** `mtkbootcmd.py` sits waiting and never sees "READY" from the preloader.

**Common causes:**

1. **cdc_acm not loaded** -- mtkbootcmd.py needs the serial device, which requires cdc_acm:

    ```bash
    modprobe cdc_acm
    ```

2. **Device is still powered on** -- The device must be completely powered off before plugging in. The preloader only runs during initial power-on.
    - Use the reset pin (near SIM slot) with a SIM ejector tool
    - Or hold the power button until the screen goes completely dark

3. **Device was plugged in before running the script** -- The script must be running BEFORE you plug in the device. The preloader window is brief.

4. **USB cable is charge-only** -- Use a data-capable USB-C cable.

### r1_escape unlock/entry fails on newest OTA firmware

**Symptom:** `r1_escape`-based unlock or fastboot entry attempts fail on devices that were fully updated via OTA.

**Possible cause:** Newer RabbitOS OTA builds may change preloader/bootloader behavior in ways that break older `r1_escape` workflows.

**What to try:**

1. Confirm your current stock build/version and record it in your notes
2. Test with a known working backup/base image from the `r1_escape` community
3. Re-run `mtkbootcmd.py`/fastboot flow from that known-good base

This is currently anecdotal; if you can reproduce, include versions and logs when reporting issues.

### Stuck on "orange state" screen

**Symptom:** After flashing CipherOS, the device shows an "orange state" warning and appears stuck.

**Explanation:** The orange state warning is normal on devices with an unlocked bootloader and disabled vbmeta verification. The device IS booting -- it's just showing this warning before continuing.

**What to do:**

1. Wait 5-10 seconds for it to continue booting
2. If the screen goes dark, the device may have booted but gone to sleep:
    ```bash
    rmmod cdc_acm
    adb shell input keyevent KEYCODE_WAKEUP
    ```
3. Set the display density:
    ```bash
    adb shell wm density 190
    ```

### fastbootd not entering (after flashing CipherOS boot.img)

**Symptom:** `fastboot reboot fastboot` causes the device to reboot through preloader but never enters fastbootd.

**Cause:** CipherOS's boot.img does NOT support fastbootd. Only the stock boot.img supports it.

**Fix:** Always use the stock boot.img (from v0.8.293 firmware) when you need fastbootd access. Flash stock boot.img first, reboot to fastbootd, then flash CipherOS partitions.

### "system_ext_a" partition not found

**Symptom:** `fastboot flash system_ext_a` fails with partition not found.

**Cause:** The stock R1 partition layout doesn't include `system_ext`. CipherOS needs it.

**Fix:** Create the partition in fastbootd before flashing:

```bash
fastboot create-logical-partition system_ext_a 559304704
```

### Rapid USB cycling / error -71

**Symptom:** The device rapidly connects and disconnects from USB, with `dmesg` showing `error -71` (protocol error).

**Cause:** The kernel is loading but crashing immediately. This often happens with an incompatible boot.img or corrupted super partition.

**Fix:**

1. Wait for the cycling to slow down or stop
2. Use `mtkbootcmd.py` to re-enter fastboot
3. Re-flash from scratch following the full [Flashing Guide](flashing-guide.md)

### "wipe task partition not found: userdata" in fastbootd

**Symptom:** `fastboot -w` fails in fastbootd mode.

**Cause:** Fastbootd (userspace) can only see logical partitions inside super, not physical partitions like userdata.

**Fix:** Use `fastboot erase userdata` instead, or switch back to bootloader fastboot for the wipe:

```bash
fastboot reboot bootloader
fastboot erase userdata
```

### Device won't power on after failed flash

**Symptom:** Device appears completely dead -- no USB, no screen, no response to power button.

**Fix:**

1. Use the reset pin near the SIM slot (insert SIM ejector tool)
2. Wait 30 seconds
3. Plug in USB-C while running `mtkbootcmd.py` -- the preloader should still respond
4. If the preloader responds, enter fastboot and re-flash stock firmware

The MediaTek preloader is in ROM and cannot be bricked through software. As long as the hardware is functional, the device can always be recovered.

## Diagnostic Commands

```bash
# Check what the device is doing
adb shell dumpsys wifi | grep "Wi-Fi is"
adb shell getprop ro.build.display.id
adb shell getprop ro.product.cpu.abi
adb shell dumpsys power | grep mWakefulness

# Check USB device IDs
lsusb | grep -i mediatek
# 0e8d:2000 = preloader
# 0e8d:201c = fastboot

# Check kernel module state
lsmod | grep cdc_acm

# Monitor USB events
dmesg -w | grep -i usb
```
