# OTA Update Implementation for BeagleBone Black

This document describes the full implementation of over-the-air (OTA) updates
using SWUpdate with an A/B partition scheme on the BeagleBone Black.

## Table of Contents

1. [Design Decisions](#design-decisions)
2. [Partition Layout](#partition-layout)
3. [U-Boot Boot Script](#u-boot-boot-script)
4. [SWUpdate Integration](#swupdate-integration)
5. [Build System Changes](#build-system-changes)
6. [Update Flow](#update-flow)
7. [Rollback Mechanism](#rollback-mechanism)
8. [File-by-File Reference](#file-by-file-reference)

---

## Design Decisions

### Why SWUpdate?

Several OTA solutions exist for embedded Linux (Mender, RAUC, SWUpdate, raw scripts).
SWUpdate was chosen because:

- It is already packaged in buildroot (`BR2_PACKAGE_SWUPDATE`), so no external
  tooling or custom package recipes are needed.
- It has a built-in web server (Mongoose) that provides a browser-based UI for
  uploading updates. No cloud infrastructure required.
- It integrates directly with U-Boot environment via libubootenv, which is the
  bootloader already used by the BeagleBone Black.
- It supports A/B (dual-copy) rootfs updates out of the box through its
  sw-description format.
- It is widely used in production embedded systems and actively maintained.

### Why A/B partitions?

The A/B (dual-copy) scheme means there are two root filesystem partitions on the
SD card. The running system occupies one partition; updates are written to the
other. This provides:

- **Atomic updates**: The switch from old to new happens by changing a single
  U-Boot environment variable (`root_part`). Either the old image boots or the
  new one does. There is no half-written state.
- **Automatic rollback**: If the new image fails to boot, U-Boot detects this
  via a boot counter and reverts to the previous working partition.
- **Zero downtime risk**: The running system is never modified during an update.
  If power is lost during the update write, the old system still boots fine.

The tradeoff is disk space: two 512MB rootfs partitions instead of one. On a
typical 4GB+ SD card this is acceptable.

### Why not systemd?

The stock beaglebone_defconfig uses BusyBox init (sysvinit-style), not systemd.
SWUpdate supports both. Switching to systemd would be a large change with no
benefit for OTA specifically, so we kept sysvinit. SWUpdate starts via the
`S80swupdate` init script provided by the buildroot package.

---

## Partition Layout

Defined in `board/bbb/genimage.cfg`.

```
+--------+------------+------------+--------+
|  boot  |  rootfs-a  |  rootfs-b  |  data  |
|  FAT   |   ext4     |   ext4     |  ext4  |
|  32MB  |   512MB    |   512MB    | 128MB  |
|  p1    |   p2       |   p3       |  p4    |
+--------+------------+------------+--------+
```

### boot (p1, FAT, 32MB)

Contains everything needed for U-Boot to load the kernel:

- `MLO` — U-Boot SPL (first-stage bootloader, loaded by the AM335x ROM)
- `u-boot.img` — U-Boot proper (second-stage bootloader)
- `zImage` — Linux kernel
- `am335x-boneblack.dtb` (and other DTB variants) — device tree blobs
- `boot.scr` — compiled U-Boot boot script with A/B logic

The boot partition is 32MB (doubled from the stock 16MB) to accommodate the
boot.scr and leave headroom.

This partition is shared between both A and B configurations. Kernel updates
require a separate mechanism (or can be included in the rootfs and loaded
from there in a more advanced setup).

### rootfs-a (p2, ext4, 512MB) and rootfs-b (p3, ext4, 512MB)

Two identical root filesystem partitions. On a fresh flash, both contain the
same image. After the first OTA update, one will be newer than the other.

U-Boot decides which to boot based on the `root_part` environment variable:
- `root_part=2` boots rootfs-a (`/dev/mmcblk0p2`)
- `root_part=3` boots rootfs-b (`/dev/mmcblk0p3`)

### data (p4, ext4, 128MB)

Persistent data partition. This is never overwritten by OTA updates. Use it for
application data, logs, configuration, or anything that must survive updates.

It can be mounted at boot by adding an fstab entry (not done by default — the
user should mount it where their application needs it).

### Why this layout?

The stock beaglebone genimage.cfg has only two partitions (boot + rootfs). We
added a second rootfs for A/B and a data partition for persistence. The partition
types are MBR (0xC for FAT, 0x83 for Linux), matching the stock layout. GPT
could be used but MBR is simpler and the AM335x ROM expects it.

---

## U-Boot Boot Script

Defined in `board/bbb/boot.cmd`, compiled to `boot.scr` by `post-image.sh`.

### Why boot.scr instead of uEnv.txt?

The stock beaglebone setup uses `uEnv.txt`, which sets U-Boot environment
variables and runs a simple boot command. However, uEnv.txt has limited support
for conditional logic. The A/B boot requires:

- Reading `root_part` to select the active partition
- Incrementing `bootcount` when `upgrade_available` is set
- Comparing `bootcount` against `bootlimit` for rollback
- Saving the environment after modifications

This requires `if/then`, `setexpr`, and `saveenv` — operations that are more
naturally expressed in a U-Boot script (boot.cmd compiled to boot.scr) than in
uEnv.txt variable assignments.

U-Boot on AM335x loads boot.scr automatically from the FAT partition if present.

### Boot script logic

```
1. Set defaults if variables are missing:
   root_part=2, bootlimit=3, bootcount=0, upgrade_available=0

2. If upgrade_available == 1:
   a. Increment bootcount
   b. Save environment (persists bootcount across reset)
   c. If bootcount > bootlimit:
      - Swap root_part (2 -> 3 or 3 -> 2)
      - Clear upgrade_available and bootcount
      - Save environment
      - (This is the rollback)

3. Set kernel bootargs with root=/dev/mmcblk0p${root_part}

4. Load kernel and DTB from the boot (FAT) partition

5. Boot the kernel
```

### Environment variables

These live in U-Boot's persistent environment storage (raw MMC at offset
0x260000, configured in `fw_env.config`):

| Variable           | Values   | Purpose                                      |
|--------------------|----------|----------------------------------------------|
| `root_part`        | 2 or 3   | Which rootfs partition to boot               |
| `upgrade_available`| 0 or 1   | Whether a new update is pending confirmation  |
| `bootcount`        | 0-N      | How many times we've booted since the update  |
| `bootlimit`        | 3        | Max boot attempts before rollback             |

---

## SWUpdate Integration

### Build configuration: `board/bbb/swupdate.config`

This is the kconfig file that controls how the SWUpdate binary is compiled.
Key choices:

- **CONFIG_UBOOT=y**: Enables the U-Boot bootloader handler. This allows
  SWUpdate to modify U-Boot environment variables (root_part, upgrade_available)
  after writing an update. Without this, SWUpdate could write the image but
  couldn't tell U-Boot to boot it.

- **CONFIG_UBOOT_FWENV="/etc/fw_env.config"**: Tells libubootenv where to find
  the U-Boot environment on disk. This file maps to the raw MMC offset where
  U-Boot stores its env.

- **CONFIG_RAW=y**: Enables the "raw" image handler. This writes a filesystem
  image (rootfs.ext4) directly to a block device (/dev/mmcblk0pN). This is the
  simplest handler — it does a raw dd-style write.

- **CONFIG_BOOTLOADERHANDLER=y**: Enables the bootloader environment handler.
  This is what processes the `bootenv` sections in sw-description to set U-Boot
  variables.

- **CONFIG_SHELLSCRIPTHANDLER=y**: Enables running shell scripts as part of an
  update. Not used in the base implementation but useful for custom pre/post
  update hooks.

- **CONFIG_WEBSERVER=y, CONFIG_MONGOOSE=y**: Enables the embedded Mongoose web
  server on port 8080. This provides a drag-and-drop browser UI for uploading
  .swu files.

- **CONFIG_BOOTLOADER_NONE is not set**: The default swupdate.config sets
  CONFIG_BOOTLOADER_NONE=y which disables all bootloader integration. We
  explicitly unset this and enable CONFIG_UBOOT instead.

### Runtime configuration: `board/bbb/swupdate.cfg`

Libconfig-format file installed to `/etc/swupdate.cfg`. Sets:

- `verbose = true` and `loglevel = 5` for debugging during development.
  Reduce loglevel in production.
- Hardware compatibility identifier `"beaglebone-black"` version `"1.0"`.
  The `hardware-compatibility` list in sw-description must include this
  version, or SWUpdate will reject the update.

### Image descriptor: `board/bbb/sw-description`

This is the metadata file inside every .swu package. SWUpdate reads it to
determine what to install and where. Key structure:

```
software = {
    version = "@@SWU_VERSION@@";
    hardware-compatibility: [ "1.0" ];
    beaglebone-black = {
        stable = {
            copy1: { ... write to p2, set root_part=2 ... };
            copy2: { ... write to p3, set root_part=3 ... };
        };
    };
};
```

**How SWUpdate picks copy1 vs copy2**: SWUpdate reads the current `root_part`
from U-Boot env. If the system is running from partition 2 (copy1), SWUpdate
selects copy2 (writes to partition 3) and vice versa. This is automatic — the
`copy1`/`copy2` naming convention is recognized by SWUpdate.

**Version gating**: The `version` field is compared against `/etc/sw-versions`
on the target. By default, SWUpdate will not install an older or equal version.
This prevents accidental downgrades.

**@@SWU_VERSION@@**: This placeholder is replaced by `post-image.sh` at build
time with the value passed via `--swu-version`.

Each copy section contains:
- An `images` entry that writes `rootfs.ext4` as a raw image to the target
  partition device.
- A `bootenv` entry that sets `root_part` to the target partition number,
  `upgrade_available` to `1`, and resets `bootcount` to `0`.

### fw_env.config: `board/bbb/rootfs-overlay/etc/fw_env.config`

Tells libubootenv (and the `fw_printenv`/`fw_setenv` userspace tools) where
U-Boot's environment is stored on disk:

```
/dev/mmcblk0    0x260000    0x20000
```

- `/dev/mmcblk0` — the raw SD card block device
- `0x260000` — byte offset where U-Boot stores its environment (this is the
  standard offset for AM335x U-Boot builds)
- `0x20000` — environment size (128KB)

If this offset is wrong, SWUpdate will fail to read/write U-Boot variables and
the A/B switching will not work. The offset must match the U-Boot binary's
compiled-in `CONFIG_ENV_OFFSET`. For the stock `am335x_evm` defconfig in
U-Boot 2026.01, 0x260000 is correct.

### sw-versions: `board/bbb/rootfs-overlay/etc/sw-versions`

A simple text file listing installed software versions:

```
beaglebone-black 0.1.0
```

SWUpdate reads this at startup. When an update arrives, SWUpdate compares the
incoming sw-description version against this file to decide whether to proceed.
The format is: `<component-name> <version>` one per line.

---

## Build System Changes

### BR2_EXTERNAL

Buildroot resolves all paths in defconfig relative to its own source tree. Since
our board files live outside buildroot (in the project root), paths like
`board/bbb/swupdate.config` would resolve to `buildroot/board/bbb/...` which
doesn't exist.

The standard buildroot solution is `BR2_EXTERNAL` — a mechanism for keeping
board customizations outside the buildroot tree. We set this up with:

- `external.desc` — declares the external tree name (`BBB`) and description
- `external.mk` — empty, required by buildroot
- `Config.in` — empty, required by buildroot

The Makefile passes `BR2_EXTERNAL=$(CURDIR)` to all buildroot invocations. This
makes buildroot set `BR2_EXTERNAL_BBB_PATH=/absolute/path/to/project`, which we
use in defconfig paths like `$(BR2_EXTERNAL_BBB_PATH)/board/bbb/swupdate.config`.

### defconfig changes

The following buildroot options were enabled in the defconfig:

| Option | Why |
|--------|-----|
| `BR2_PACKAGE_SWUPDATE=y` | The OTA update daemon |
| `BR2_PACKAGE_SWUPDATE_CONFIG="$(BR2_EXTERNAL_BBB_PATH)/board/bbb/swupdate.config"` | Custom build config with U-Boot handler |
| `BR2_PACKAGE_SWUPDATE_WEBSERVER=y` | Web UI for uploading updates |
| `BR2_PACKAGE_SWUPDATE_INSTALL_WEBSITE=y` | Default web UI files |
| `BR2_PACKAGE_JSON_C=y` | Mandatory dependency of SWUpdate |
| `BR2_PACKAGE_LIBUBOOTENV=y` | U-Boot environment access from userspace |
| `BR2_PACKAGE_LIBYAML=y` | Dependency of libubootenv |
| `BR2_PACKAGE_ZLIB=y` | Dependency of libubootenv and compression |
| `BR2_PACKAGE_LIBCONFIG=y` | Config file parser for swupdate.cfg |
| `BR2_PACKAGE_HOST_UBOOT_TOOLS=y` | Provides `mkimage` on the host to compile boot.cmd to boot.scr |
| `BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_BBB_PATH)/board/bbb/rootfs-overlay"` | Install fw_env.config and sw-versions into rootfs |
| `BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_BBB_PATH)/board/bbb/post-build.sh"` | Custom post-build (replaces stock beaglebone script) |
| `BR2_ROOTFS_POST_IMAGE_SCRIPT="$(BR2_EXTERNAL_BBB_PATH)/board/bbb/post-image.sh"` | Custom post-image (replaces genimage.sh wrapper) |
| `BR2_ROOTFS_POST_IMAGE_SCRIPT_ARGS="--swu-version 0.1.0"` | SWU version passed to post-image.sh |

### post-build.sh

Runs after buildroot constructs the root filesystem but before it is packed
into an image. Our script:

1. Installs `swupdate.cfg` to `/etc/swupdate.cfg` in the target rootfs.
2. Creates `/etc/init.d/S99swupdate-confirm` — a sysvinit script that runs
   at the end of boot. It checks if `upgrade_available=1` in U-Boot env,
   and if so, sets it to 0 and resets bootcount. This "confirms" a successful
   boot, preventing rollback on the next reboot.

Why S99? It runs last, after all other services have started. If any critical
service fails to start (and the system reboots or hangs), the confirm script
never runs, bootcount keeps incrementing, and U-Boot will eventually roll back.

### post-image.sh

Runs after all images (rootfs.ext4, zImage, etc.) are built. It:

1. **Compiles boot.scr**: Runs `mkimage` (from host-uboot-tools) to compile
   `board/bbb/boot.cmd` into `boot.scr` in the images directory.

2. **Generates sdcard.img**: Calls buildroot's `genimage.sh` helper with our
   custom `genimage.cfg` to assemble the full SD card image with A/B partitions.

3. **Generates update.swu**: Creates a CPIO archive containing `sw-description`
   (with version substituted) and `rootfs.ext4`. The sw-description MUST be the
   first file in the archive — SWUpdate requires this. The archive uses CRC
   format (`cpio -H crc`).

### Makefile changes

Added to the top-level Makefile wrapper:

- `linux-menuconfig`, `uboot-menuconfig`, `busybox-menuconfig` to the list
  of config targets that auto-save defconfig.
- `make swu` target as a convenience alias that builds and reminds the user
  where the output files are.
- Updated `make help` to list OTA-related targets.

---

## Update Flow

### First boot (fresh SD card flash)

```
1. AM335x ROM loads MLO (SPL) from boot partition
2. SPL loads u-boot.img
3. U-Boot loads boot.scr from boot partition
4. boot.scr: root_part is unset, defaults to 2
5. Kernel boots with root=/dev/mmcblk0p2 (rootfs-a)
6. S80swupdate starts SWUpdate daemon (web UI on port 8080)
7. S99swupdate-confirm runs, but upgrade_available=0, so nothing happens
```

### Applying an update

```
1. User builds new firmware: make swu
2. User opens http://<board-ip>:8080 in browser
3. User uploads update.swu
4. SWUpdate reads sw-description:
   - Checks hardware-compatibility matches "1.0"
   - Checks version is newer than /etc/sw-versions
   - Current root_part=2, so selects copy2 (target: partition 3)
5. SWUpdate writes rootfs.ext4 to /dev/mmcblk0p3 (raw handler)
6. SWUpdate sets U-Boot env: root_part=3, upgrade_available=1, bootcount=0
7. User reboots the board
```

### First boot after update

```
1. U-Boot loads boot.scr
2. boot.scr sees upgrade_available=1
3. Increments bootcount to 1, saves env
4. bootcount (1) <= bootlimit (3), so proceeds normally
5. Boots with root=/dev/mmcblk0p3 (rootfs-b, the new image)
6. System starts normally
7. S99swupdate-confirm sees upgrade_available=1
8. Sets upgrade_available=0, bootcount=0 in U-Boot env
9. Update is now confirmed. Next reboot will boot partition 3 with no
   bootcount logic.
```

### Rollback scenario

```
1. Update was applied, root_part=3, upgrade_available=1
2. New image has a bug that causes a kernel panic or boot loop
3. Boot attempt 1: bootcount incremented to 1, kernel panics, board resets
4. Boot attempt 2: bootcount incremented to 2, same failure
5. Boot attempt 3: bootcount incremented to 3, same failure
6. Boot attempt 4: bootcount would be 4 > bootlimit (3)
7. boot.scr: "Boot limit reached! Rolling back..."
8. Swaps root_part back to 2, clears upgrade_available and bootcount
9. Saves env
10. Boots from partition 2 (the previous known-good image)
11. System is back to the old working firmware
```

---

## File-by-File Reference

| File | Purpose |
|------|---------|
| `board/bbb/genimage.cfg` | Defines the SD card partition layout: boot + rootfsA + rootfsB + data |
| `board/bbb/boot.cmd` | U-Boot script source with A/B selection and bootcount rollback logic |
| `board/bbb/swupdate.config` | Kconfig file controlling how SWUpdate is compiled (enables U-Boot handler, raw handler, web server) |
| `board/bbb/swupdate.cfg` | Runtime config installed to /etc/swupdate.cfg (hardware identity, log level) |
| `board/bbb/sw-description` | Template for .swu package metadata (copy1/copy2 definitions, version placeholder) |
| `board/bbb/post-build.sh` | Installs swupdate.cfg and creates the boot-confirm init script in the target rootfs |
| `board/bbb/post-image.sh` | Compiles boot.scr, generates sdcard.img, packages update.swu |
| `board/bbb/rootfs-overlay/etc/fw_env.config` | Tells libubootenv where U-Boot environment lives on the MMC (offset 0x260000) |
| `board/bbb/rootfs-overlay/etc/sw-versions` | Records installed software version for SWUpdate version comparison |
| `defconfig` | Buildroot configuration with SWUpdate and all dependencies enabled |
| `Makefile` | Top-level wrapper with `make swu` target and auto-save on config targets |
| `external.desc` | BR2_EXTERNAL tree descriptor (name: BBB) |
| `external.mk` | BR2_EXTERNAL makefile (empty, required by buildroot) |
| `Config.in` | BR2_EXTERNAL Kconfig (empty, required by buildroot) |
