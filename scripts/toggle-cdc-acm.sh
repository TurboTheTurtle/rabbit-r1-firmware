#!/usr/bin/env bash
set -euo pipefail

# Toggle cdc_acm kernel module on/off
# cdc_acm must be ENABLED for mtkbootcmd.py (serial access)
# cdc_acm must be DISABLED for adb (it grabs the USB device)

BLACKLIST_FILE="/etc/modprobe.d/blacklist-cdc_acm.conf"
BLACKLIST_DISABLED="${BLACKLIST_FILE}.disabled"
LSMOD_BIN=""
MODPROBE_BIN=""
RMMOD_BIN=""

resolve_bin() {
    local name="$1"
    shift

    if command -v "$name" &>/dev/null; then
        command -v "$name"
        return 0
    fi

    for candidate in "$@"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

init_paths() {
    if ! LSMOD_BIN="$(resolve_bin lsmod /sbin/lsmod /usr/sbin/lsmod)"; then
        echo "[!] lsmod not found" >&2
        exit 1
    fi

    if ! MODPROBE_BIN="$(resolve_bin modprobe /sbin/modprobe /usr/sbin/modprobe)"; then
        echo "[!] modprobe not found" >&2
        exit 1
    fi

    if ! RMMOD_BIN="$(resolve_bin rmmod /sbin/rmmod /usr/sbin/rmmod)"; then
        echo "[!] rmmod not found" >&2
        exit 1
    fi
}

usage() {
    echo "Usage: $0 <enable|disable|status>"
    echo ""
    echo "  enable   - Load cdc_acm module (for mtkbootcmd.py)"
    echo "  disable  - Unload cdc_acm module (for adb)"
    echo "  status   - Show current state"
    exit 1
}

status() {
    if "$LSMOD_BIN" | grep -q cdc_acm; then
        echo "cdc_acm: LOADED"
    else
        echo "cdc_acm: NOT LOADED"
    fi

    if [ -f "$BLACKLIST_FILE" ]; then
        echo "Blacklist: ACTIVE (will stay unloaded after reboot)"
    elif [ -f "$BLACKLIST_DISABLED" ]; then
        echo "Blacklist: DISABLED (will load after reboot)"
    else
        echo "Blacklist: NOT CONFIGURED"
    fi
}

enable_cdc_acm() {
    echo "[*] Enabling cdc_acm..."

    # Move blacklist file aside if it exists
    if [ -f "$BLACKLIST_FILE" ]; then
        mv "$BLACKLIST_FILE" "$BLACKLIST_DISABLED"
        echo "    Blacklist disabled"
    fi

    # Load module
    if ! "$LSMOD_BIN" | grep -q cdc_acm; then
        "$MODPROBE_BIN" cdc_acm
        echo "    Module loaded"
    else
        echo "    Module already loaded"
    fi

    echo "[+] cdc_acm enabled (ready for mtkbootcmd.py)"
}

disable_cdc_acm() {
    echo "[*] Disabling cdc_acm..."

    # Unload module
    if "$LSMOD_BIN" | grep -q cdc_acm; then
        "$RMMOD_BIN" cdc_acm
        echo "    Module unloaded"
    else
        echo "    Module not loaded"
    fi

    # Re-enable blacklist
    if [ -f "$BLACKLIST_DISABLED" ]; then
        mv "$BLACKLIST_DISABLED" "$BLACKLIST_FILE"
        echo "    Blacklist re-enabled"
    elif [ ! -f "$BLACKLIST_FILE" ]; then
        echo "blacklist cdc_acm" > "$BLACKLIST_FILE"
        echo "    Blacklist created"
    fi

    echo "[+] cdc_acm disabled (ready for adb)"
}

if [ $# -ne 1 ]; then
    usage
fi

init_paths

case "$1" in
    enable)  enable_cdc_acm ;;
    disable) disable_cdc_acm ;;
    status)  status ;;
    *)       usage ;;
esac
