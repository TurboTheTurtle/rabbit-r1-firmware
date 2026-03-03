# CipherOS Findings on Rabbit R1

This document records what works and what doesn't when running [CipherOS](https://cipheros.com/) (Android 16) on the Rabbit R1. These findings may apply to other custom ROMs targeting the MT6765 platform.

## Environment

| Property | Value |
|----------|-------|
| ROM | CipherOS (cipher_r1-userdebug) |
| Android Version | 16 (SDK 36) |
| Build | BP2A.250605.031.A2 |
| Architecture | arm64-v8a |
| Kernel | Stock v0.8.293 (CipherOS kernel lacks fastbootd) |
| Display Density | 190 (set via `adb shell wm density 190`) |

## What Works

- **WiFi** — connects and works normally
- **Bluetooth** — pairs and connects
- **Touchscreen** — full multi-touch support
- **Display** — 480x640, works at density 190
- **Camera** — captures photos and video
- **USB** — ADB over USB works (after disabling `cdc_acm`)
- **Scroll wheel** — sends `KEY_UP` (0x67) and `KEY_DOWN` (0x6c) via `/dev/input/event2` (`och1970_holl_key`). Maps to `DPAD_UP`/`DPAD_DOWN` in Android. Works for list scrolling and navigation.
- **Audio** — speaker and microphone functional
- **Vosk speech recognition** — offline STT works (with crash prevention, see below)
- **TTS engines** — RHVoice, Android TTS, and cloud TTS providers work

## What Doesn't Work

### Side Button (PTT/Power) — BROKEN

**Symptom:** The side button produces absolutely zero kernel events on CipherOS. No key events, no input events, no interrupts.

**Investigation:**

1. `getevent -l` shows nothing when the button is pressed (stock firmware shows `KEY_POWER` events)

2. Checked `/proc/interrupts` for `mtk-kpd`:
   ```
   # Before pressing button:
   mtk-kpd: 38 interrupts
   # After pressing button many times:
   mtk-kpd: 38 interrupts (unchanged — zero new interrupts)
   ```
   The 38 interrupts are all from boot time. No new interrupts are generated on press.

3. The kernel driver is loaded:
   ```
   # /dev/input/event0 exists (mtk-kpd)
   # Driver shows in /proc/interrupts
   ```

4. GPIO state doesn't change on press:
   ```bash
   # Checked all GPIOs before and after press — no changes
   cat /sys/kernel/debug/gpio
   ```

5. On stock firmware (same hardware), the button generates `POWER` key events via both:
   - `/dev/input/event0` (mtk-kpd) — `KEY_POWER` (0x74)
   - `/dev/input/event1` (mtk-pmic-keys) — `KEY_POWER` (0x74)

**Root cause:** The CipherOS kernel is missing the correct GPIO/PMIC key configuration for the R1's side button. The `mtk-kpd` driver is loaded but not configured to monitor the correct GPIO pin or PMIC key register. The stock kernel (MT6765 with Rabbit's device tree) has this configured correctly.

**Workaround:** None found. The button is physically connected to the MT6357 PMIC (as confirmed by `mtk-pmic-keys` working on stock), which suggests the PMIC key configuration in the CipherOS device tree is incomplete or wrong.

**Impact:** Push-to-talk requires software activation (auto-listen, wake word, or touch) instead of the physical button.

## Vosk Speech Recognition — Crash After ~25s of Silence

**Symptom:** When using Vosk (offline speech recognition) for continuous listening, the native library crashes after approximately 25 seconds of silence with:

```
VoskAPI: Assertion failed: (-min <= tolerance * max)
```

The crash occurs in `sp-matrix.cc:62` within the i-vector extractor. This is a `SIGABRT` that cannot be caught from Java/Kotlin.

**Root cause:** Long continuous silence causes a degenerate matrix in Vosk's i-vector computation. The i-vector extractor expects some speech signal variance; pure silence produces near-zero variance matrices that fail the assertion.

**Fix:** Implement a silence timeout in the recognition service. After 4 seconds of no partial results (indicating silence), stop the recognizer cleanly and return `ERROR_SPEECH_TIMEOUT`. The calling code can then restart recognition for a new session.

```kotlin
// In the recognition thread:
var lastSpeechActivityMs = System.currentTimeMillis()

// When partial results arrive:
if (partial != lastPartial && partial.isNotBlank()) {
    lastSpeechActivityMs = System.currentTimeMillis()
}

// After each audio processing cycle:
if (System.currentTimeMillis() - lastSpeechActivityMs > 4000L) {
    isListening = false
    callback.error(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
    return@Thread
}
```

This prevents the crash entirely. The 4-second timeout is well within the safe window (~25s) and keeps sessions responsive.

## Input Device Map (via getevent)

| Device | Driver | Events | Status on CipherOS |
|--------|--------|--------|--------------------|
| event0 | mtk-kpd | `KEY_VOLUMEDOWN`, `KEY_POWER` | **Broken** — zero interrupts on press |
| event1 | mtk-pmic-keys | `KEY_POWER` | **Broken** — driver not present on CipherOS |
| event2 | och1970_holl_key | `KEY_UP`, `KEY_DOWN` | **Working** — scroll wheel |
| event3 | mtk-tpd | Touch (480x640, 2-point multitouch) | **Working** — touchscreen |
| event4 | mt63xx-accdet | `KEY_VOLUMEUP`, `KEY_VOLUMEDOWN`, `KEY_PLAYPAUSE`, `KEY_VOICECOMMAND` | Present but untested (headset jack) |

## Super Partition Layout After CipherOS Flash

```
system_a     — CipherOS system (~1.4 GB)
system_ext_a — CipherOS system extensions (~534 MB, must be created manually)
vendor_a     — CipherOS vendor HAL (~353 MB)
product_a    — CipherOS product overlay (~389 MB)
```

Note: `system_ext` does not exist in the stock partition layout. It must be created before flashing CipherOS:
```bash
fastboot create-logical-partition system_ext_a 559304704
```
