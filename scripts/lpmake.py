#!/usr/bin/env python3
"""Build a super.img (LP metadata + logical partitions) without lpmake.

lpmake is Linux-only and not packaged on macOS, but the metadata format is
simple enough to emit directly: geometry block, metadata header, and the
partition/extent/group/block-device tables, all with the SHA-256 checksums
liblp expects.

Usage:
    lpmake.py --output super.img --device-size 8792064000 \
        system_a=1400053760:firmware/cipheros/images/system.img \
        system_ext_a=559304704:firmware/cipheros/images/system_ext.img

Layout reference: system/core/fs_mgr/liblp/metadata_format.h
"""
import argparse
import hashlib
import os
import struct
import sys

RESERVED = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
METADATA_MAX_SIZE = 65536
METADATA_SLOTS = 3
LOGICAL_BLOCK_SIZE = 4096
HEADER_SIZE = 256
HEADER_FLAGS = 0x1  # LP_HEADER_FLAG_VIRTUAL_AB_DEVICE, same as stock
ALIGN = 1 << 20
SECTOR = 512


def pad(data, size):
    return data + b"\x00" * (size - len(data))


def build_geometry(device_size):
    body = struct.pack("<II", GEOMETRY_MAGIC, 52)
    tail = struct.pack("<III", METADATA_MAX_SIZE, METADATA_SLOTS, LOGICAL_BLOCK_SIZE)
    checksum = hashlib.sha256(body + b"\x00" * 32 + tail).digest()
    return body + checksum + tail


def build_metadata(parts, group_name, device_size):
    """parts: list of (name, size, offset). Returns header+tables bytes."""
    part_entries = b""
    extent_entries = b""
    for index, (name, size, offset) in enumerate(parts):
        sectors = size // SECTOR
        part_entries += struct.pack(
            "<36sIIII",
            name.encode(),
            0x1,          # LP_PARTITION_ATTR_READONLY
            index,        # first_extent_index
            1,            # num_extents
            0,            # group_index
        )
        extent_entries += struct.pack(
            "<QIQI",
            sectors,
            0,            # LP_TARGET_TYPE_LINEAR
            offset // SECTOR,
            0,            # target_source (block device 0)
        )
    group_size = sum(p[1] for p in parts)
    group_entries = struct.pack("<36sIQ", group_name.encode(), 0, group_size)
    bdev_entries = struct.pack(
        "<QIIQ36sI",
        ALIGN // SECTOR,                   # first_logical_sector: 1 MiB
        512,                               # alignment
        0,                                 # alignment_offset
        device_size,
        b"super",
        0x2,
    )

    tables = part_entries + extent_entries + group_entries + bdev_entries
    offsets = []
    cursor = 0
    for blob in (part_entries, extent_entries, group_entries, bdev_entries):
        offsets.append(cursor)
        cursor += len(blob)

    descriptors = b""
    for offset, blob, entry_size in (
        (offsets[0], part_entries, 52),
        (offsets[1], extent_entries, 24),
        (offsets[2], group_entries, 48),
        (offsets[3], bdev_entries, 64),
    ):
        descriptors += struct.pack("<III", offset, len(blob) // entry_size, entry_size)

    header = struct.pack("<IHHI", HEADER_MAGIC, 10, 2, HEADER_SIZE)
    header += b"\x00" * 32
    header += struct.pack("<I", len(tables))
    header += hashlib.sha256(tables).digest()
    header += descriptors
    header += struct.pack("<I", HEADER_FLAGS)
    header = pad(header, HEADER_SIZE)
    header = header[:12] + hashlib.sha256(header).digest() + header[44:]
    return header + tables


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    ap.add_argument("--device-size", type=int, default=8792064000)
    ap.add_argument("--group", default="main_a")
    ap.add_argument("partitions", nargs="+", help="name=size:path")
    args = ap.parse_args()

    parsed = []
    for spec in args.partitions:
        name, rest = spec.split("=", 1)
        size_s, path = rest.split(":", 1)
        size = int(size_s)
        if os.path.getsize(path) != size:
            raise SystemExit(f"{path}: expected {size} bytes, found {os.path.getsize(path)}")
        parsed.append((name, size, path))

    # Assign extents sequentially, 1 MiB aligned, starting after the metadata region.
    parts = []
    cursor = max(ALIGN, ((RESERVED + 2 * 4096 + METADATA_SLOTS * METADATA_MAX_SIZE + ALIGN - 1) // ALIGN) * ALIGN)
    for name, size, path in parsed:
        cursor = ((cursor + ALIGN - 1) // ALIGN) * ALIGN
        parts.append((name, size, cursor))
        cursor += size
    image_size = ((cursor + ALIGN - 1) // ALIGN) * ALIGN

    metadata = build_metadata(parts, args.group, args.device_size)
    geometry = build_geometry(args.device_size)

    with open(args.output, "wb") as out:
        out.truncate(image_size)
        out.seek(RESERVED)
        out.write(geometry)
        out.write(geometry)          # backup geometry
        for slot in range(METADATA_SLOTS):
            out.seek(RESERVED + 2 * 4096 + slot * METADATA_MAX_SIZE)
            out.write(metadata)
        for name, size, offset, (_, _, path) in zip(
            [p[0] for p in parts], [p[1] for p in parts], [p[2] for p in parts], parsed
        ):
            print(f"  {name:<16} {size/1048576:8.1f} MiB at 0x{offset:x}", flush=True)
            out.seek(offset)
            with open(path, "rb") as src:
                remaining = size
                while remaining:
                    chunk = src.read(min(remaining, 64 << 20))
                    if not chunk:
                        raise SystemExit(f"{path}: short read")
                    out.write(chunk)
                    remaining -= len(chunk)

    print(f"wrote {args.output}: {image_size} bytes ({image_size/1073741824:.2f} GiB)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
