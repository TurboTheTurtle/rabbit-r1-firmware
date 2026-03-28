#!/usr/bin/env bash
set -euo pipefail

# Enter fastboot mode on the Rabbit R1
# Uses mtkbootcmd.py to send FASTBOOT command via serial to MediaTek preloader
#
# Prerequisites:
#   - r1_escape repo cloned (for mtkbootcmd.py)
#   - pyserial installed: pip3 install pyserial
#   - cdc_acm kernel module available
#   - R1 must be POWERED OFF and DISCONNECTED

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R1_ESCAPE_DIR="${R1_ESCAPE_DIR:-/root/r1_escape}"
MTKBOOTCMD="${R1_ESCAPE_DIR}/mtkbootcmd.py"
MODPROBE_BIN=""
LSMOD_BIN=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[!]${NC} $*" >&2; }

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

# Check prerequisites
check_prereqs() {
    if [ ! -f "$MTKBOOTCMD" ]; then
        error "mtkbootcmd.py not found at: $MTKBOOTCMD"
        echo "  Set R1_ESCAPE_DIR to your r1_escape clone path, for example:"
        echo "    export R1_ESCAPE_DIR=$HOME/r1_escape"
        echo "  Clone if needed: git clone https://github.com/RabbitHoleEscapeR1/r1_escape.git"
        exit 1
    fi

    if ! MODPROBE_BIN="$(resolve_bin modprobe /sbin/modprobe /usr/sbin/modprobe)"; then
        error "modprobe not found"
        exit 1
    fi

    if ! LSMOD_BIN="$(resolve_bin lsmod /sbin/lsmod /usr/sbin/lsmod)"; then
        error "lsmod not found"
        exit 1
    fi

    if ! python3 -c "import serial" 2>/dev/null; then
        error "pyserial not installed"
        echo "  Install: pip3 install pyserial"
        exit 1
    fi

    if ! command -v fastboot &>/dev/null; then
        error "fastboot not found"
        echo "  Install: apt install android-tools-fastboot"
        exit 1
    fi
}

# Enable cdc_acm for serial access
enable_serial() {
    info "Enabling cdc_acm module..."

    if [ -f /etc/modprobe.d/blacklist-cdc_acm.conf ]; then
        mv /etc/modprobe.d/blacklist-cdc_acm.conf /etc/modprobe.d/blacklist-cdc_acm.conf.disabled
    fi

    if ! "$LSMOD_BIN" | grep -q cdc_acm; then
        "$MODPROBE_BIN" cdc_acm
    fi
}

# Wait for fastboot device
wait_for_fastboot() {
    info "Waiting for fastboot device..."
    local timeout=30
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if fastboot devices 2>/dev/null | grep -q fastboot; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

main() {
    echo "========================================="
    echo "  Rabbit R1 Fastboot Entry"
    echo "========================================="
    echo ""

    check_prereqs
    enable_serial

    echo ""
    warn "Make sure the R1 is POWERED OFF and DISCONNECTED from USB"
    echo ""
    read -p "Press Enter when ready, then plug in the R1..."
    echo ""

    info "Running mtkbootcmd.py FASTBOOT..."
    python3 "$MTKBOOTCMD" FASTBOOT

    echo ""

    if wait_for_fastboot; then
        info "Fastboot device detected!"
        fastboot devices
        echo ""
        info "You can now run fastboot commands."
        info "To enter fastbootd (for logical partitions): fastboot reboot fastboot"
    else
        error "Fastboot device not detected within 30 seconds"
        echo "  Check USB connection and try again"
        exit 1
    fi
}

main "$@"
