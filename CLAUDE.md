# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Embedded Linux build system for BeagleBone Black using Buildroot with SWUpdate OTA (A/B partition scheme). The project wraps buildroot as a git submodule and uses `BR2_EXTERNAL` to keep board customizations outside the buildroot tree.

## Build Commands

```bash
make                    # full build (sdcard.img + update.swu)
make menuconfig         # configure buildroot (auto-saves defconfig on close)
make linux-menuconfig   # configure Linux kernel (auto-saves defconfig)
make uboot-menuconfig   # configure U-Boot (auto-saves defconfig)
make swu                # build + generate OTA update package
make clean              # clean build output
./deploy.sh <board-ip>  # build, upload .swu via SWUpdate web UI, reboot board
```

## Architecture

**BR2_EXTERNAL mechanism**: The project root is a buildroot external tree (`external.desc` name: `BBB`). The Makefile passes `BR2_EXTERNAL=$(CURDIR)` to all buildroot invocations. All paths in `defconfig` use `$(BR2_EXTERNAL_BBB_PATH)/board/bbb/...` so buildroot resolves them to absolute paths. Plain relative paths like `board/bbb/...` will fail because buildroot resolves them relative to its own source tree.

**A/B OTA update flow**:
- SD card has 4 partitions: boot (FAT) + rootfsA (ext4) + rootfsB (ext4) + data (ext4)
- `board/bbb/boot.cmd` is the U-Boot script that selects active partition via `root_part` env var
- SWUpdate writes to the inactive partition, flips `root_part`, sets `upgrade_available=1`
- On successful boot, `S99swupdate-confirm` init script clears `upgrade_available`
- After 3 failed boots (`bootlimit`), U-Boot rolls back to previous partition

**Key config files**:
- `defconfig` — full buildroot .config (tracked in git, `output/` is gitignored)
- `board/bbb/swupdate.config` — kconfig for SWUpdate build (U-Boot handler, raw handler, web server)
- `board/bbb/sw-description` — SWUpdate image descriptor with `@@SWU_VERSION@@` placeholder
- `board/bbb/rootfs-overlay/etc/fw_env.config` — U-Boot env location on MMC (offset 0x260000)

**Build flow**: `post-build.sh` installs runtime configs + boot-confirm script into rootfs. `post-image.sh` compiles `boot.scr`, runs `genimage.sh` for sdcard.img, packages `update.swu` (cpio archive with sw-description first).

## Important Constraints

- The `defconfig` is a full `.config`, not a minimal defconfig. The Makefile copies it directly and runs `olddefconfig`.
- When adding board files referenced by defconfig, paths must use `$(BR2_EXTERNAL_BBB_PATH)/` prefix.
- The `.swu` cpio archive requires `sw-description` as the first file — ordering matters.
- `fw_env.config` offset (0x260000) must match U-Boot's compiled `CONFIG_ENV_OFFSET` for am335x_evm.
- Version in `board/bbb/sw-description` and `board/bbb/rootfs-overlay/etc/sw-versions` must be bumped before each OTA update — SWUpdate rejects equal/older versions.
