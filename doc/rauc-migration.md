# Migration from SWUpdate to RAUC

This document describes the migration from SWUpdate to RAUC as the OTA update
framework for the BeagleBone Black build.

## What Changed

### Removed (SWUpdate)

- `board/bbb/swupdate.config` — SWUpdate kconfig build configuration
- `board/bbb/swupdate.cfg` — SWUpdate runtime configuration
- `board/bbb/sw-description` — SWUpdate image descriptor (copy1/copy2 format)
- `board/bbb/rootfs-overlay/etc/sw-versions` — version tracking file for SWUpdate
- `patches/swupdate/` — mongoose upload fix patch
- `doc/swupdate-integration.md` — SWUpdate troubleshooting guide
- defconfig entries: `BR2_PACKAGE_SWUPDATE`, `BR2_PACKAGE_SWUPDATE_CONFIG`,
  `BR2_PACKAGE_SWUPDATE_WEBSERVER`, `BR2_PACKAGE_SWUPDATE_INSTALL_WEBSITE`

### Added (RAUC)

- `board/bbb/system.conf` — RAUC system configuration defining A/B slots,
  U-Boot bootloader backend, and keyring path
- `board/bbb/rauc-keys/` — development X.509 keypair for signing bundles
- defconfig entries: `BR2_PACKAGE_RAUC`, `BR2_PACKAGE_RAUC_NETWORK`,
  `BR2_PACKAGE_HOST_RAUC`, `BR2_PACKAGE_OPENSSL`, `BR2_PACKAGE_SQUASHFS`

### Modified

- `board/bbb/boot.cmd` — switched from `root_part`/`upgrade_available`/`bootcount`
  variables to RAUC bootchooser protocol (`BOOT_ORDER`/`BOOT_A_LEFT`/`BOOT_B_LEFT`)
- `board/bbb/post-build.sh` — installs RAUC system.conf and keyring instead of
  swupdate.cfg; creates `S99rauc-mark-good` instead of `S99swupdate-confirm`
- `board/bbb/post-image.sh` — generates signed `.raucb` bundle with host-rauc
  instead of `.swu` cpio archive
- `deploy.sh` — uses SCP + `rauc install` via SSH instead of curl upload to
  SWUpdate web UI on port 8080
- `Makefile` — `make bundle` replaces `make swu`
- `defconfig` — `--bundle-version` replaces `--swu-version` in post-image args

## Why RAUC over SWUpdate

1. **Mandatory bundle signing** — RAUC bundles are cryptographically signed with
   X.509 certificates. The target verifies signatures before installing. SWUpdate
   supports signing but does not require it.

2. **Simpler slot management** — RAUC's bootchooser protocol uses a clear
   priority + attempt-counter model (`BOOT_ORDER`, `BOOT_x_LEFT`). SWUpdate's
   copy1/copy2 model requires more configuration in the image descriptor.

3. **No persistent daemon needed** — RAUC can run on-demand (`rauc install`)
   without a continuously running daemon. SWUpdate requires S80swupdate running
   at all times to serve its web UI.

4. **Host-side tooling** — `host-rauc` creates bundles at build time with a
   simple manifest format. SWUpdate requires manual cpio archive assembly with
   strict file ordering (sw-description must be first).

## How It Works

See `doc/ota-implementation.md` for the full technical description of the
RAUC-based A/B update flow, boot script logic, and rollback mechanism.
