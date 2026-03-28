# Firmware Images

Firmware images are not included in this repository due to their size. Download them from the official sources below.

## Stock Firmware (Rabbit OS v0.8.293)

**Download:** [rabbit-hmi-oss/firmware v0.8.293](https://github.com/rabbit-hmi-oss/firmware/releases/download/v0.8.293/rabbit_OS_v0.8.293.zip)

**Size:** ~922 MB (ZIP)

**Required files after extraction:**
| File | Size | Purpose |
|------|------|---------|
| `boot.img` | 32 MB | Stock kernel (required for fastbootd support) |
| `super.img` | ~2 GB | Stock super partition (Android sparse format) |
| `vbmeta.img` | 4 KB | Verified boot metadata |
| `vbmeta_system.img` | 4 KB | System verified boot metadata |
| `vbmeta_vendor.img` | 4 KB | Vendor verified boot metadata |

## CipherOS

**Download:** [CipherOS for Rabbit R1](https://cipheros.com/) (device codename: `cipher_r1`)

**Direct build directory:** [SourceForge CipherOS-7/r1](https://sourceforge.net/projects/cipheros/files/CipherOS-7/r1/)

**Known newer build:** `CipherOS-7.0-ALHENA-cipher_r1-20250623-0753-BETA-OFFICIAL-VANILLA` (reported to include side-button fixes)

**Required files:**
| File | Size | Purpose |
|------|------|---------|
| `system.img` | ~1.4 GB | CipherOS system image |
| `system_ext.img` | ~534 MB | System extensions |
| `product.img` | ~389 MB | Product overlay |
| `vendor.img` | ~353 MB | Vendor HAL |

## Checksums

See `checksums.sha256` for SHA256 checksums of known-good images.

To verify:

```bash
sha256sum -c checksums.sha256
```
