#!/usr/bin/env bash
set -euo pipefail

# Flash CipherOS onto Rabbit R1
# Requires device to already be in fastboot mode (use fastboot-entry.sh first)
#
# Usage:
#   ./flash-cipheros.sh --stock-dir /path/to/stock_firmware --cipheros-dir /path/to/cipheros/images
#   ./flash-cipheros.sh --stock-dir /path/to/stock --cipheros-dir /path/to/cipheros --dry-run

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
CIPHEROS_DIR=""
DRY_RUN=false
SKIP_STOCK_VERIFY=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Flash CipherOS onto a Rabbit R1 that is already in fastboot mode.

Options:
  --stock-dir DIR       Path to extracted stock firmware (v0.8.293)
  --cipheros-dir DIR    Path to CipherOS images
  --dry-run             Show commands without executing
  --skip-stock-verify   Skip the stock boot verification step
  -h, --help            Show this help

Prerequisites:
  - Device must be in fastboot mode (run fastboot-entry.sh first)
  - Stock firmware v0.8.293 extracted
  - CipherOS images downloaded

Example:
  ./fastboot-entry.sh
  ./flash-cipheros.sh --stock-dir /root/stock_firmware --cipheros-dir /root/cipheros/images
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
            --stock-dir)    STOCK_DIR="$2"; shift 2 ;;
            --cipheros-dir) CIPHEROS_DIR="$2"; shift 2 ;;
            --dry-run)      DRY_RUN=true; shift ;;
            --skip-stock-verify) SKIP_STOCK_VERIFY=true; shift ;;
            -h|--help)      usage ;;
            *)              error "Unknown option: $1"; usage ;;
        esac
    done

    if [ -z "$STOCK_DIR" ] || [ -z "$CIPHEROS_DIR" ]; then
        error "Both --stock-dir and --cipheros-dir are required"
        usage
    fi
}

check_files() {
    local missing=false

    for f in boot.img super.img vbmeta.img vbmeta_system.img vbmeta_vendor.img; do
        if [ ! -f "$STOCK_DIR/$f" ]; then
            error "Missing stock file: $STOCK_DIR/$f"
            missing=true
        fi
    done

    for f in system.img system_ext.img product.img vendor.img; do
        if [ ! -f "$CIPHEROS_DIR/$f" ]; then
            error "Missing CipherOS file: $CIPHEROS_DIR/$f"
            missing=true
        fi
    done

    if $missing; then
        exit 1
    fi
}

check_fastboot() {
    if ! fastboot devices 2>/dev/null | grep -q fastboot; then
        error "No fastboot device detected"
        echo "  Run fastboot-entry.sh first to enter fastboot mode"
        exit 1
    fi
    info "Fastboot device detected"
}

wait_for_fastbootd() {
    info "Waiting for fastbootd..."
    local timeout=60
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if fastboot getvar is-userspace 2>&1 | grep -q "yes"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    error "Timed out waiting for fastbootd"
    return 1
}

main() {
    parse_args "$@"

    echo "========================================="
    echo "  CipherOS Flash for Rabbit R1"
    echo "========================================="
    echo ""
    echo "Stock firmware:  $STOCK_DIR"
    echo "CipherOS images: $CIPHEROS_DIR"
    $DRY_RUN && echo -e "${YELLOW}*** DRY RUN MODE ***${NC}"
    echo ""

    check_files
    check_fastboot

    echo ""
    warn "This will ERASE ALL DATA on the R1."
    if ! $DRY_RUN; then
        read -p "Continue? [y/N] " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Aborted."
            exit 0
        fi
    fi
    echo ""

    # Phase 1: Flash stock boot + vbmeta in bootloader fastboot
    step 1 "Flashing stock boot.img to both slots"
    run fastboot flash boot_a "$STOCK_DIR/boot.img"
    run fastboot flash boot_b "$STOCK_DIR/boot.img"

    step 2 "Disabling verified boot (all 6 vbmeta slots)"
    run fastboot --disable-verity --disable-verification flash vbmeta_a "$STOCK_DIR/vbmeta.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_b "$STOCK_DIR/vbmeta.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_system_a "$STOCK_DIR/vbmeta_system.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_system_b "$STOCK_DIR/vbmeta_system.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_vendor_a "$STOCK_DIR/vbmeta_vendor.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_vendor_b "$STOCK_DIR/vbmeta_vendor.img"

    step 3 "Rebooting to fastbootd (userspace)"
    run fastboot reboot fastboot
    if ! $DRY_RUN; then
        wait_for_fastbootd
    fi

    step 4 "Flashing stock super.img (clean partition base)"
    info "This takes ~100 seconds for the 2GB sparse image..."
    run fastboot flash super "$STOCK_DIR/super.img"

    step 5 "Flashing vbmeta in fastbootd"
    run fastboot --disable-verity --disable-verification flash vbmeta_system_a "$STOCK_DIR/vbmeta_system.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_vendor_a "$STOCK_DIR/vbmeta_vendor.img"

    # Phase 2: Verify stock boot (optional)
    if ! $SKIP_STOCK_VERIFY; then
        echo ""
        step 6 "Verifying stock firmware boots correctly"
        warn "The R1 will reboot to stock RabbitOS."
        warn "Verify it reaches the setup screen, then power it off."
        if ! $DRY_RUN; then
            read -p "Press Enter to reboot to stock (or Ctrl+C to skip)..."
            fastboot reboot
            echo ""
            warn "After verifying stock boots, power off the R1 and re-enter fastboot."
            warn "Run: ./fastboot-entry.sh"
            read -p "Press Enter when back in fastboot mode..."
            check_fastboot
        fi
    fi

    # Phase 3: Flash CipherOS
    step 7 "Flashing stock boot.img again"
    run fastboot flash boot_a "$STOCK_DIR/boot.img"
    run fastboot flash boot_b "$STOCK_DIR/boot.img"

    step 8 "Disabling verified boot"
    run fastboot --disable-verity --disable-verification flash vbmeta_a "$STOCK_DIR/vbmeta.img"
    run fastboot --disable-verity --disable-verification flash vbmeta_b "$STOCK_DIR/vbmeta.img"

    step 9 "Rebooting to fastbootd"
    run fastboot reboot fastboot
    if ! $DRY_RUN; then
        wait_for_fastbootd
    fi

    step 10 "Creating system_ext_a partition"
    run fastboot create-logical-partition system_ext_a 559304704

    step 11 "Flashing CipherOS partitions"
    info "Flashing system.img (~1.4GB)..."
    run fastboot flash system_a "$CIPHEROS_DIR/system.img"
    info "Flashing system_ext.img (~534MB)..."
    run fastboot flash system_ext_a "$CIPHEROS_DIR/system_ext.img"
    info "Flashing product.img (~389MB)..."
    run fastboot flash product_a "$CIPHEROS_DIR/product.img"
    info "Flashing vendor.img (~353MB)..."
    run fastboot flash vendor_a "$CIPHEROS_DIR/vendor.img"

    step 12 "Erasing userdata"
    run fastboot erase userdata

    step 13 "Rebooting"
    run fastboot reboot

    echo ""
    echo "========================================="
    info "Flash complete!"
    echo "========================================="
    echo ""
    echo "The R1 will show an 'orange state' warning (normal for unlocked bootloader),"
    echo "then boot into CipherOS."
    echo ""
    echo "After boot, run these commands:"
    echo "  rmmod cdc_acm                                 # Enable adb access"
    echo "  adb shell input keyevent KEYCODE_WAKEUP       # Wake screen"
    echo "  adb shell wm density 190                      # Set display density"
    echo ""
    echo "Or run: ./post-install.sh"
}

main "$@"
