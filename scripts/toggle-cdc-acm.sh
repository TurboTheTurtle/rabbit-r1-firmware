#!/usr/bin/env bash
set -euo pipefail

# Toggle cdc_acm kernel module on/off
# cdc_acm must be ENABLED for mtkbootcmd.py (serial access)
# cdc_acm must be DISABLED for adb (it grabs the USB device)

BLACKLIST_FILE="/etc/modprobe.d/blacklist-cdc_acm.conf"
BLACKLIST_DISABLED="${BLACKLIST_FILE}.disabled"

usage() {
    echo "Usage: $0 <enable|disable|status>"
    echo ""
    echo "  enable   - Load cdc_acm module (for mtkbootcmd.py)"
    echo "  disable  - Unload cdc_acm module (for adb)"
    echo "  status   - Show current state"
    exit 1
}

status() {
    if lsmod | grep -q cdc_acm; then
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
    if ! lsmod | grep -q cdc_acm; then
        modprobe cdc_acm
        echo "    Module loaded"
    else
        echo "    Module already loaded"
    fi

    echo "[+] cdc_acm enabled (ready for mtkbootcmd.py)"
}

disable_cdc_acm() {
    echo "[*] Disabling cdc_acm..."

    # Unload module
    if lsmod | grep -q cdc_acm; then
        rmmod cdc_acm
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

case "$1" in
    enable)  enable_cdc_acm ;;
    disable) disable_cdc_acm ;;
    status)  status ;;
    *)       usage ;;
esac
