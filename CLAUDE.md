# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Embedded Linux build system for BeagleBone Black using Buildroot with RAUC OTA (A/B partition scheme). The project wraps buildroot as a git submodule and uses `BR2_EXTERNAL` to keep board customizations outside the buildroot tree.

## Build Commands

```bash
make                    # full build (sdcard.img + update.raucb)
make menuconfig         # configure buildroot (auto-saves defconfig on close)
make linux-menuconfig   # configure Linux kernel (auto-saves defconfig)
make uboot-menuconfig   # configure U-Boot (auto-saves defconfig)
make bundle             # build + generate RAUC OTA bundle
make clean              # clean build output
./scripts/deploy.sh <board-ip>  # build, upload .raucb via SSH, install with rauc, reboot
```

## Architecture

**BR2_EXTERNAL mechanism**: The project root is a buildroot external tree (`external.desc` name: `BBB`). The Makefile passes `BR2_EXTERNAL=$(CURDIR)` to all buildroot invocations. All paths in `defconfig` use `$(BR2_EXTERNAL_BBB_PATH)/board/bbb/...` so buildroot resolves them to absolute paths. Plain relative paths like `board/bbb/...` will fail because buildroot resolves them relative to its own source tree.

**A/B OTA update flow**:
- SD card has 4 partitions: boot (FAT) + rootfsA (ext4) + rootfsB (ext4) + data (ext4)
- `board/bbb/boot.cmd` is the U-Boot script that selects active slot via RAUC bootchooser env vars (`BOOT_ORDER`, `BOOT_A_LEFT`, `BOOT_B_LEFT`)
- RAUC installs the bundle to the inactive slot, updates `BOOT_ORDER` to prefer the new slot
- On successful boot, `rauc-mark-good.service` systemd unit calls `rauc status mark-good`
- After 3 failed boots (attempts decremented per boot), U-Boot falls back to the other slot

**Key config files**:
- `defconfig` — full buildroot .config (tracked in git, `output/` is gitignored)
- `board/bbb/system.conf` — RAUC system configuration (slot definitions, bootloader backend, keyring)
- `board/bbb/rauc-keys/` — development signing keypair for RAUC bundles
- `board/bbb/rootfs-overlay/etc/fw_env.config` — U-Boot env location on MMC (offset 0x200000)

**Build flow**: `post-build.sh` installs RAUC system.conf, keyring cert, and systemd service units (ntpd, rauc-mark-good) into rootfs. `post-image.sh` compiles `boot.scr`, runs `genimage.sh` for sdcard.img, creates a signed RAUC bundle using `host-rauc`.

## Important Constraints

- The `defconfig` is a full `.config`, not a minimal defconfig. The Makefile copies it directly and runs `olddefconfig`.
- When adding board files referenced by defconfig, paths must use `$(BR2_EXTERNAL_BBB_PATH)/` prefix.
- RAUC bundles must be signed. Development keys are in `board/bbb/rauc-keys/`. For production, use a proper PKI.
- `fw_env.config` offset (0x200000) must match U-Boot's compiled `CONFIG_ENV_OFFSET`. The env lives in the pre-partition gap (0-4MB). genimage.cfg sets boot partition at 4MB offset to leave room for raw U-Boot binaries + env.
- Bundle version is set in `board/bbb/post-image.sh` via `BUNDLE_VERSION` variable.

## Workflow Rules

- **Document every step**: For each new feature or configuration step, create a dedicated documentation file under `doc/` explaining what was done and how it works. Each doc should be self-contained and cover the what, why, and how.
- **Update the changelog**: Always add a one-liner entry to `CHANGELOG.md` under the `[Unreleased]` section for every change made to the project.
- **Write tests for every feature**: When adding or changing a feature, write a labgrid-based integration test under `tests/` that verifies the feature works on the real hardware. Tests run via pytest against the BeagleBone Black (slave) from the host (master). See `tests/README.md` for setup and `tests/conftest.py` for fixtures.
- **Comment non-obvious logic**: When writing Makefile tricks, shell scripts, or any logic that isn't immediately obvious, add comments explaining *what* it does and *why*. This project is maintained by a single developer — if the logic can't be understood at a glance six months later, it needs a comment.

## Testing

```bash
# Setup (one-time)
python3 -m venv tests/.venv
source tests/.venv/bin/activate
pip install -r tests/requirements.txt

# Run all tests against the BBB
pytest tests/ --lg-env tests/env.yaml

# Run a specific test file
pytest tests/test_systemd.py --lg-env tests/env.yaml -v
```

Tests use [labgrid](https://labgrid.readthedocs.io/) to SSH into the BBB and verify system-level features (systemd services, RAUC slots, partitions, etc.).
