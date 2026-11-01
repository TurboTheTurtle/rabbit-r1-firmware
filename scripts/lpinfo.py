#!/usr/bin/env python3
"""Minimal reader for Android dynamic-partition (LP) metadata inside a super image.

Prints the partition/extent/group tables without needing lpunpack (which is a
Linux-only tool). Useful on macOS for inspecting super.bin dumps and for
computing where a logical partition actually lives.

Usage:
    scripts/lpinfo.py <super.img>            # print layout
    scripts/lpinfo.py <super.img> --json     # machine-readable

Layout reference: system/core/fs_mgr/liblp/metadata_format.h
  header at LP_PARTITION_RESERVED_BYTES (4096)
  magic 0x414C5030, then table descriptors for partitions/extents/groups/block_devices.
"""
import json
import struct
import sys

RESERVED = 4096
MAGIC = 0x414C5030


def read_tables(buf, base):
    (magic, major, minor, header_size) = struct.unpack_from("<IHHI", buf, base)
    if magic != MAGIC:
        raise SystemExit(f"bad LP magic at {base}: {magic:#x}")
    tables_size = struct.unpack_from("<I", buf, base + 8 + 32 + 4)[0]
    off = base + 8 + 32 + 4 + 4 + 32
    parts, exts, groups, bdevs = (struct.unpack_from("<III", buf, off + 12 * i) for i in range(4))
    flags = struct.unpack_from("<I", buf, off + 48)[0]
    return {
        "magic": hex(magic), "major": major, "minor": minor,
        "header_size": header_size, "tables_size": tables_size, "flags": flags,
        "tables": {"partitions": parts, "extents": exts, "groups": groups, "block_devices": bdevs},
    }


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    as_json = "--json" in sys.argv

    with open(path, "rb") as f:
        f.seek(0)
        head = f.read(1 << 20)
        base = head.find(b"\x30\x50\x4c\x41")  # 0x414c5030 header magic
        if base < 0:
            raise SystemExit("no LP metadata header found in the first 1 MiB")
        hdr = read_tables(head, base)

        # The metadata "primary" copy lives right after the header region.
        t = hdr["tables"]
        # table offsets are relative to the start of the tables region
        tables_base = base + hdr["header_size"]
        f.seek(tables_base)
        tables = f.read(hdr["tables_size"])

        def entries(desc, fmt, names):
            off, num, esize = desc
            out = []
            for i in range(num):
                vals = struct.unpack_from(fmt, tables, off + i * esize)
                out.append(dict(zip(names, vals)))
            return out

        parts = entries(t["partitions"], "<36sIIII", ["name", "attributes", "first_extent", "num_extents", "group_index"])
        exts = entries(t["extents"], "<QIQI", ["num_sectors", "target_type", "target_data", "target_source"])
        groups = entries(t["groups"], "<36sIQ", ["name", "flags", "max_size"])
        bdevs = entries(t["block_devices"], "<QIIQ", ["first_logical_sector", "alignment", "alignment_offset", "size"])

    for p in parts:
        p["name"] = p["name"].rstrip(b"\x00").decode()
        p["extent_list"] = []
        for e in exts[p["first_extent"]:p["first_extent"] + p["num_extents"]]:
            p["extent_list"].append({
                "sectors": e["num_sectors"],
                "byte_offset": e["target_data"] * 512,
                "byte_length": e["num_sectors"] * 512,
            })
    for g in groups:
        g["name"] = g["name"].rstrip(b"\x00").decode()

    if as_json:
        print(json.dumps({"header": hdr, "partitions": parts, "groups": groups, "block_devices": bdevs}, indent=2))
        return

    print(f"LP metadata: v{hdr['major']}.{hdr['minor']} flags={hdr['flags']:#x}")
    print(f"block devices: {len(bdevs)}")
    for b in bdevs:
        print(f"  first_logical_sector={b['first_logical_sector']} size={b['size']} "
              f"alignment={b['alignment']} offset={b['alignment_offset']}")
    print(f"groups: {[g['name'] for g in groups]}")
    print(f"partitions ({len(parts)}):")
    for p in parts:
        total = sum(e["byte_length"] for e in p["extent_list"])
        print(f"  {p['name']:<18} attrs={p['attributes']:#x} extents={p['num_extents']} "
              f"size={total} ({total / 1024 / 1024:.1f} MiB)")
        for e in p["extent_list"]:
            print(f"      offset={e['byte_offset']:#x} len={e['byte_length']:#x}")


if __name__ == "__main__":
    main()
