#!/usr/bin/env python3
"""Convert a raw super image into an Android sparse image with bounded chunks.

MTK's LK fastboot fails with "sparse image write failure" when handed a single
enormous DONT_CARE chunk (fastboot resparses a raw image into one 6 GB
don't-care run for the unused tail of the partition). Splitting every run into
chunks of at most MAX_CHUNK_BLKS keeps each write small enough for LK.

The image is extended to the full partition size, mirroring the stock super
image layout (total_blks == partition size, trailing zeros as DONT_CARE).

Usage:
    mksparse.py --input super.img --output super.sparse.img \
        --partition-size 8792064000
"""
import argparse
import struct
import sys

BLK = 4096
SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_DONT_CARE = 0xCAC3
MAX_CHUNK_BLKS = 8192  # 32 MiB per chunk


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--partition-size", type=int, default=8792064000)
    args = ap.parse_args()

    if args.partition_size % BLK:
        raise SystemExit("partition size must be a multiple of 4096")

    with open(args.input, "rb") as src:
        data = src.read()
    if len(data) % BLK:
        data += b"\x00" * (BLK - len(data) % BLK)
    if len(data) > args.partition_size:
        raise SystemExit(f"image {len(data)} exceeds partition {args.partition_size}")

    image_blocks = len(data) // BLK
    total_blocks = args.partition_size // BLK

    chunks = []

    def add(kind, blocks, payload=b""):
        # Split a run into MAX_CHUNK_BLKS pieces.
        while blocks:
            n = min(blocks, MAX_CHUNK_BLKS)
            if kind == CHUNK_RAW:
                chunk = payload[: n * BLK]
                payload = payload[n * BLK :]
            else:
                chunk = b""
            chunks.append((kind, n, chunk))
            blocks -= n

    # Walk the image, grouping zero and non-zero runs.
    run_start = 0
    run_zero = data[0:BLK] == b"\x00" * BLK
    for i in range(1, image_blocks + 1):
        if i == image_blocks:
            zero = None
        else:
            zero = data[i * BLK : (i + 1) * BLK] == b"\x00" * BLK
        if i < image_blocks and zero == run_zero:
            continue
        length = i - run_start
        if run_zero:
            add(CHUNK_DONT_CARE, length)
        else:
            add(CHUNK_RAW, length, data[run_start * BLK : i * BLK])
        run_start = i
        run_zero = zero

    if total_blocks > image_blocks:
        add(CHUNK_DONT_CARE, total_blocks - image_blocks)

    header = struct.pack(
        "<IHHHHIIII",
        SPARSE_MAGIC,
        1,  # major
        0,  # minor
        28,  # file header size
        12,  # chunk header size
        BLK,
        total_blocks,
        len(chunks),
        0,  # checksum
    )

    with open(args.output, "wb") as out:
        out.write(header)
        for kind, blocks, payload in chunks:
            out.write(struct.pack("<HHII", kind, 0, blocks, 12 + len(payload)))
            out.write(payload)

    covered = sum(c[1] for c in chunks)
    print(
        f"{args.output}: {total_blocks} blocks, {len(chunks)} chunks, "
        f"covered {covered} (expected {total_blocks})",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
