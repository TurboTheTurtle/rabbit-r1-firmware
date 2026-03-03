# Contributing

Contributions are welcome! Whether it's improving documentation, fixing scripts, or building out the OpenClaw client app.

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Make your changes
4. Test thoroughly (especially flash scripts -- use `--dry-run` first!)
5. Submit a pull request

## Areas Where Help is Needed

- **Testing on different host systems** -- The flashing scripts have been tested on Proxmox/Debian. Reports from Ubuntu, Fedora, Arch, etc. are welcome.
- **OpenClaw client app development** -- Kotlin/Jetpack Compose Android development
- **Documentation improvements** -- Clearer instructions, screenshots, diagrams
- **CipherOS configuration** -- Optimizing Android 16 settings for the R1's hardware

## Guidelines

- Keep flash scripts POSIX-compatible where possible
- Use `set -euo pipefail` in bash scripts
- Test destructive operations with `--dry-run` before running on real hardware
- Document any new partition offsets or hardware findings in `docs/hardware-reference.md`

## Reporting Issues

If you bricked your R1, don't panic! The device can almost always be recovered via `mtkbootcmd.py` and fastboot. Include in your issue:

- Host OS and kernel version
- `mtkclient` version
- `fastboot --version` output
- Exact commands run and their output
- USB device IDs (`lsusb` output when device is connected)
