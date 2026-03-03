#!/usr/bin/env bash
set -euo pipefail

# Restore stock Rabbit OS firmware
# Requires device to be in fastboot mode (use fastboot-entry.sh first)
#
# Usage:
#   ./flash-stock.sh --stock-dir /path/to/stock_firmware
#   ./flash-stock.sh --stock-dir /path/to/stock --dry-run

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[!]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[STEP $1]${NC} $2"; }

STOCK_DIR=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Restore stock RabbitOS firmware on a Rabbit R1 in fastboot mode.

Options:
  --stock-dir DIR    Path to extracted stock firmware (v0.8.293)
  --dry-run          Show commands without executing
  -h, --help         Show this help

Example:
  ./fastboot-entry.sh
  ./flash-stock.sh --stock-dir /root/stock_firmware
EOF
    exit 1
}

run() {
    if $DRY_RUN; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} $*"
    else
        "$@"
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --stock-dir) STOCK_DIR="$2"; shift 2 ;;
            --dry-run)   DRY_RUN=true; shift ;;
            -h|--help)   usage ;;
            *)           error "Unknown option: $1"; usage ;;
        esac
    done

    if [ -z "$STOCK_DIR" ]; then
        error "--stock-dir is required"
        usage
    fi
}

main() {
    parse_args "$@"

    echo "========================================="
    echo "  Restore Stock RabbitOS"
    echo "========================================="
    echo ""

    if ! fastboot devices 2>/dev/null | grep -q fastboot; then
        error "No fastboot device detected. Run fastboot-entry.sh first."
        exit 1
    fi

    step 1 "Flashing stock boot.img"
    run fastboot flash boot_a "$STOCK_DIR/boot.img"
    run fastboot flash boot_b "$STOCK_DIR/boot.img"

    step 2 "Disabling verified boot"
    run fastboot --disable-verity --disable-verification flash vbmeta_a "$STOCK_DIR/vbmeta.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_b "$STOCK_DIR/vbmeta.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_system_a "$STOCK_DIR/vbmeta_system.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_system_b "$STOCK_DIR/vbmeta_system.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_vendor_a "$STOCK_DIR/vbmeta_vendor.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_vendor_b "$STOCK_DIR/vbmeta_vendor.img"

    step 3 "Rebooting to fastbootd"
    run fastboot reboot fastboot
    if ! $DRY_RUN; then
        info "Waiting for fastbootd..."
        sleep 15
    fi

    step 4 "Flashing stock super.img (~100 seconds)"
    run fastboot flash super "$STOCK_DIR/super.img"

    step 5 "Erasing userdata"
    run fastboot erase userdata

    step 6 "Rebooting"
    run fastboot reboot

    echo ""
    info "Stock firmware restored!"
    echo "The R1 should boot to the RabbitOS setup screen."
}

main "$@"
