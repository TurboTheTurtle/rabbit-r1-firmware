#!/usr/bin/env bash
# Dump partitions from a Rabbit R1 through the MediaTek preloader (mtkclient).
#
# Usage:
#   scripts/dump-stock.sh --critical          # boot chain + calibration + super
#   scripts/dump-stock.sh boot_a,super        # named partitions
#   scripts/dump-stock.sh --all-but-userdata  # everything except userdata
#
# The R1 must be POWERED OFF and then plugged in (or powered on while plugged in) so
# the preloader appears; mtkclient waits for it. The device reboots when the session
# ends, so a dump is one power-cycle per session — keep the list in a single call.
#
# Environment:
#   MTK=/path/to/mtk     override the mtkclient entry point (default: mtk on PATH)
#   OUT=/path/to/dir     override the output directory (default: firmware/device-dump)
#
# macOS note: mtkclient imports mfusepy unconditionally for an optional FUSE mount.
# Without libfuse that import raises OSError, which escapes mtkclient's
# `except ImportError` guard and kills the CLI. scripts/mfusepy_stub/ is put first on
# PYTHONPATH to satisfy the import; Linux does not need it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/firmware/device-dump}"
MTK="${MTK:-mtk}"

STUB="$ROOT/scripts/mfusepy_stub"
if [ -d "$STUB" ]; then
    export PYTHONPATH="$STUB${PYTHONPATH:+:$PYTHONPATH}"
fi

CRITICAL="boot_a,boot_b,init_boot_a,init_boot_b,vendor_boot_a,vendor_boot_b,dtbo_a,lk_a,lk_b,tee_a,vbmeta_a,vbmeta_b,vbmeta_system_a,vbmeta_system_b,vbmeta_vendor_a,vbmeta_vendor_b,md1img_a,md1img_b,gz_a,gz_b,scp_a,scp_b,sspm_a,sspm_b,spmfw_a,spmfw_b,nvram,nvdata,nvcfg,protect1,protect2,proinfo,seccfg,para,boot_para,frp,super"

mkdir -p "$OUT"

if ! command -v "$MTK" >/dev/null 2>&1; then
    echo "error: '$MTK' not found. Install mtkclient or set MTK=/path/to/mtk" >&2
    exit 1
fi

case "${1:-}" in
    --critical)
        PARTS="$CRITICAL"
        ;;
    --all-but-userdata)
        echo "[*] dumping everything except userdata into $OUT"
        "$MTK" rl "$OUT" --skip userdata 2>&1 | tr '\r' '\n' | grep -vE '^Progress|^Done|^ *$'
        exit 0
        ;;
    "")
        echo "usage: $0 <partition[,partition...]> | --critical | --all-but-userdata" >&2
        exit 1
        ;;
    *)
        PARTS="$1"
        ;;
esac

FILES=""
IFS=',' read -r -a names <<< "$PARTS"
for n in "${names[@]}"; do
    FILES="${FILES:+$FILES,}$OUT/$n.bin"
done

echo "[*] dumping ${#names[@]} partition(s) into $OUT"
# `mtk r` (da_read) logs a failed partition and continues; `mtk rl` (da_rl) raises and
# aborts the whole run. Long reads over USB occasionally glitch, so prefer `r`.
"$MTK" r "$PARTS" "$FILES" 2>&1 | tr '\r' '\n' | grep -vE '^Progress|^Done|^ *$'

echo
echo "[*] results:"
for n in "${names[@]}"; do
    f="$OUT/$n.bin"
    if [ -s "$f" ]; then
        printf '  %-22s %12s  %s\n' "$n" "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")" \
            "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$f" | cut -d' ' -f1)"
    else
        printf '  %-22s %12s  MISSING/EMPTY\n' "$n" "-"
    fi
done

echo
echo "[*] write a manifest with:"
echo "    cd $OUT && sha256sum *.bin > MANIFEST.sha256"
