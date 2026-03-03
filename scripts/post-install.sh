#!/usr/bin/env bash
set -euo pipefail

# Post-install setup for CipherOS on Rabbit R1
# Run this after flashing CipherOS and rebooting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[!]${NC} $*" >&2; }

# Ensure cdc_acm is disabled for adb
setup_adb() {
    info "Configuring ADB access..."

    if lsmod | grep -q cdc_acm; then
        rmmod cdc_acm
        info "  Unloaded cdc_acm"
    fi

    # Wait for adb
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if adb devices 2>/dev/null | grep -q device$; then
            info "  ADB connected"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    error "ADB device not detected within ${timeout}s"
    return 1
}

# Wake screen and configure display
setup_display() {
    info "Configuring display..."
    adb shell input keyevent KEYCODE_WAKEUP
    sleep 1
    adb shell wm density 190
    info "  Density set to 190"
}

# Show device info
show_info() {
    echo ""
    info "Device Information:"
    echo "  Build:    $(adb shell getprop ro.build.display.id)"
    echo "  Android:  $(adb shell getprop ro.build.version.release)"
    echo "  SDK:      $(adb shell getprop ro.build.version.sdk)"
    echo "  Arch:     $(adb shell getprop ro.product.cpu.abi)"
    echo "  Device:   $(adb shell getprop ro.product.device)"
}

main() {
    echo "========================================="
    echo "  R1 CipherOS Post-Install Setup"
    echo "========================================="
    echo ""

    setup_adb
    setup_display
    show_info

    echo ""
    info "Post-install complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Connect to WiFi via Settings on the R1"
    echo "  2. Install Tailscale: adb install tailscale.apk"
    echo "  3. Install OpenClaw client app"
}

main "$@"
