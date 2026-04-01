# OTA Update Implementation for BeagleBone Black

This document describes the full implementation of over-the-air (OTA) updates
using RAUC with an A/B partition scheme on the BeagleBone Black.

## Table of Contents

1. [Design Decisions](#design-decisions)
2. [Partition Layout](#partition-layout)
3. [U-Boot Boot Script](#u-boot-boot-script)
4. [RAUC Integration](#rauc-integration)
5. [Build System Changes](#build-system-changes)
6. [Update Flow](#update-flow)
7. [Rollback Mechanism](#rollback-mechanism)
8. [File-by-File Reference](#file-by-file-reference)

---

## Design Decisions

### Why RAUC?

Several OTA solutions exist for embedded Linux (Mender, RAUC, SWUpdate, raw scripts).
RAUC was chosen because:

- It is already packaged in buildroot (`BR2_PACKAGE_RAUC` and `BR2_PACKAGE_HOST_RAUC`),
  so no external tooling or custom package recipes are needed.
- It uses cryptographically signed bundles (X.509), ensuring only authorized
  updates can be installed.
- It integrates directly with U-Boot environment via a well-defined bootchooser
  protocol (`BOOT_ORDER`, `BOOT_A_LEFT`, `BOOT_B_LEFT`).
- It supports A/B (dual-slot) rootfs updates out of the box.
- Bundle creation is handled by `host-rauc` at build time, with a simple manifest format.
- It is actively maintained by Pengutronix and widely used in production embedded systems.

### Why A/B partitions?

The A/B (dual-slot) scheme means there are two root filesystem partitions on the
SD card. The running system occupies one slot; updates are written to the other.
This provides:

- **Atomic updates**: The switch from old to new happens by changing U-Boot
  bootchooser environment variables. Either the old image boots or the new one
  does. There is no half-written state.
- **Automatic rollback**: If the new image fails to boot, U-Boot detects this
  via boot attempt counters and reverts to the previous working slot.
- **Zero downtime risk**: The running system is never modified during an update.
  If power is lost during the update write, the old system still boots fine.

The tradeoff is disk space: two 512MB rootfs partitions instead of one. On a
typical 4GB+ SD card this is acceptable.

### Why not systemd?

The stock beaglebone_defconfig uses BusyBox init (sysvinit-style), not systemd.
RAUC supports both. Switching to systemd would be a large change with no
benefit for OTA specifically, so we kept sysvinit. Without systemd, RAUC runs
on-demand (invoked via `rauc install`) rather than as a persistent daemon.

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
- `boot.scr` — compiled U-Boot boot script with A/B bootchooser logic

### rootfs-a (p2, ext4, 512MB) and rootfs-b (p3, ext4, 512MB)

Two identical root filesystem slots. On a fresh flash, both contain the
same image. After the first OTA update, one will be newer than the other.

RAUC maps these as `rootfs.0` (slot A, partition 2) and `rootfs.1` (slot B,
partition 3) in `system.conf`.

### data (p4, ext4, 128MB)

Persistent data partition. This is never overwritten by OTA updates. Use it for
application data, logs, configuration, or anything that must survive updates.

---

## U-Boot Boot Script

Defined in `board/bbb/boot.cmd`, compiled to `boot.scr` by `post-image.sh`.

### Boot script logic (RAUC bootchooser protocol)

RAUC uses a standardized set of U-Boot environment variables:

| Variable     | Example    | Purpose                                     |
|-------------|------------|---------------------------------------------|
| `BOOT_ORDER` | `"A B"`    | Slot priority order (first slot tried first) |
| `BOOT_A_LEFT` | `3`       | Remaining boot attempts for slot A           |
| `BOOT_B_LEFT` | `3`       | Remaining boot attempts for slot B           |

```
1. Set defaults if variables are missing:
   BOOT_ORDER="A B", BOOT_A_LEFT=3, BOOT_B_LEFT=3

2. Iterate through BOOT_ORDER:
   - For each slot, check if attempts remain (BOOT_x_LEFT > 0)
   - Select the first slot with attempts remaining
   - Decrement its attempt counter
   - Map slot to partition: A -> p2, B -> p3

3. If no slot has attempts left, reset everything to defaults

4. Save environment (persists counters across reset)

5. Set kernel bootargs with root=/dev/mmcblk0p${root_part}
   and rauc.slot=${boot_slot} (so userspace knows which slot booted)

6. Load kernel and DTB from the boot (FAT) partition

7. Boot the kernel
```

### Why boot.scr instead of uEnv.txt?

The stock beaglebone setup uses `uEnv.txt`. However, uEnv.txt has limited support
for conditional logic. The bootchooser protocol requires iterating through slots,
checking counters, and conditionally decrementing — operations that need a proper
U-Boot script.

---

## RAUC Integration

### System configuration: `board/bbb/system.conf`

Installed to `/etc/rauc/system.conf` on the target. This tells RAUC about:

- **compatible**: `beaglebone-black` — bundles must declare the same compatible
  string or RAUC rejects them.
- **bootloader**: `uboot` — RAUC uses fw_setenv/fw_printenv to interact with
  U-Boot environment for slot switching.
- **keyring**: `/etc/rauc/keyring.pem` — the CA certificate used to verify
  bundle signatures. Only bundles signed by a key trusted by this CA can be
  installed.
- **Slot definitions**: `rootfs.0` maps to `/dev/mmcblk0p2` (bootname `A`),
  `rootfs.1` maps to `/dev/mmcblk0p3` (bootname `B`).

### Signing keys: `board/bbb/rauc-keys/`

RAUC requires all bundles to be cryptographically signed. The project includes
a development keypair:

- `development-1.cert.pem` — self-signed X.509 certificate (also used as keyring
  on the target)
- `development-1.key.pem` — private key used to sign bundles at build time

**For production**: Replace with a proper PKI. The keyring on the target should
be the CA certificate, and bundles should be signed by a key issued by that CA.
Never ship the signing private key on the target.

### Bundle manifest

Created dynamically by `post-image.sh`. The manifest (`manifest.raucm`) declares:

```ini
[update]
compatible=beaglebone-black
version=0.1.0

[image.rootfs]
filename=rootfs.ext4
type=ext4
```

RAUC automatically determines which slot to write to based on the current boot
state — it writes to the inactive slot.

### fw_env.config: `board/bbb/rootfs-overlay/etc/fw_env.config`

Tells libubootenv (and the `fw_printenv`/`fw_setenv` userspace tools) where
U-Boot's environment is stored on disk:

```
/dev/mmcblk0    0x260000    0x20000
```

- `/dev/mmcblk0` — the raw SD card block device
- `0x260000` — byte offset where U-Boot stores its environment
- `0x20000` — environment size (128KB)

The offset must match the U-Boot binary's compiled-in `CONFIG_ENV_OFFSET`.

---

## Build System Changes

### defconfig changes

The following buildroot options were changed for the RAUC migration:

| Option | Why |
|--------|-----|
| `BR2_PACKAGE_RAUC=y` | The RAUC update client |
| `BR2_PACKAGE_RAUC_NETWORK=y` | Network support for fetching bundles |
| `BR2_PACKAGE_HOST_RAUC=y` | Host tool to create signed bundles in post-image.sh |
| `BR2_PACKAGE_OPENSSL=y` | Dependency of RAUC for bundle signature verification |
| `BR2_PACKAGE_SQUASHFS=y` | Runtime dependency of RAUC |
| `BR2_PACKAGE_LIBUBOOTENV=y` | U-Boot environment access from userspace (already present) |

Removed: `BR2_PACKAGE_SWUPDATE`, `BR2_PACKAGE_SWUPDATE_CONFIG`,
`BR2_PACKAGE_SWUPDATE_WEBSERVER`, `BR2_PACKAGE_SWUPDATE_INSTALL_WEBSITE`.

### post-build.sh

Runs after buildroot constructs the root filesystem. Our script:

1. Installs `system.conf` to `/etc/rauc/system.conf` in the target rootfs.
2. Installs the keyring certificate to `/etc/rauc/keyring.pem`.
3. Installs `fw_env.config` for U-Boot environment access.
4. Creates `/etc/init.d/S99rauc-mark-good` — a sysvinit script that runs
   at the end of boot. It calls `rauc status mark-good` which tells RAUC
   to confirm the current slot as bootable (restoring its boot attempts).

### post-image.sh

Runs after all images are built. It:

1. **Compiles boot.scr**: Runs `mkimage` to compile `boot.cmd` into `boot.scr`.
2. **Generates sdcard.img**: Calls `genimage.sh` with our A/B partition layout.
3. **Generates update.raucb**: Creates a RAUC bundle by writing a manifest,
   linking the rootfs image, and running `host-rauc bundle` with the development
   signing key.

---

## Update Flow

### First boot (fresh SD card flash)

```
1. AM335x ROM loads MLO (SPL) from boot partition
2. SPL loads u-boot.img
3. U-Boot loads boot.scr from boot partition
4. boot.scr: BOOT_ORDER unset, defaults to "A B"
5. Slot A selected, BOOT_A_LEFT decremented to 2
6. Kernel boots with root=/dev/mmcblk0p2 (rootfs-a)
7. S99rauc-mark-good runs, calls rauc status mark-good
   (BOOT_A_LEFT restored to 3)
```

### Applying an update

```
1. User builds new firmware: make bundle
2. User copies bundle to board: scp update.raucb root@<ip>:/tmp/
3. User installs: ssh root@<ip> rauc install /tmp/update.raucb
4. RAUC verifies bundle signature against /etc/rauc/keyring.pem
5. RAUC checks compatible string matches "beaglebone-black"
6. RAUC determines inactive slot (e.g., slot B if running from A)
7. RAUC writes rootfs.ext4 to /dev/mmcblk0p3
8. RAUC sets BOOT_ORDER="B A", BOOT_B_LEFT=3
9. User reboots the board
```

### First boot after update

```
1. U-Boot loads boot.scr
2. boot.scr reads BOOT_ORDER="B A"
3. Tries slot B first, BOOT_B_LEFT=3 > 0, selects it
4. Decrements BOOT_B_LEFT to 2, saves env
5. Boots with root=/dev/mmcblk0p3 (rootfs-b, the new image)
6. System starts normally
7. S99rauc-mark-good calls rauc status mark-good
8. RAUC restores BOOT_B_LEFT to 3 (slot confirmed good)
9. Update is now confirmed
```

### Rollback scenario

```
1. Update was applied, BOOT_ORDER="B A", BOOT_B_LEFT=3
2. New image has a bug that causes a kernel panic or boot loop
3. Boot attempt 1: BOOT_B_LEFT decremented to 2, kernel panics
4. Boot attempt 2: BOOT_B_LEFT decremented to 1, same failure
5. Boot attempt 3: BOOT_B_LEFT decremented to 0, same failure
6. Boot attempt 4: BOOT_B_LEFT is 0, slot B skipped
7. Slot A tried next: BOOT_A_LEFT=3 > 0, selected
8. BOOT_A_LEFT decremented to 2, boots from partition 2
9. S99rauc-mark-good confirms slot A, restores BOOT_A_LEFT to 3
10. System is back to the old working firmware
```

---

## File-by-File Reference

| File | Purpose |
|------|---------|
| `board/bbb/genimage.cfg` | Defines the SD card partition layout: boot + rootfsA + rootfsB + data |
| `board/bbb/boot.cmd` | U-Boot script source with RAUC bootchooser A/B selection and rollback logic |
| `board/bbb/system.conf` | RAUC system configuration: slot definitions, bootloader backend, keyring path |
| `board/bbb/rauc-keys/development-1.cert.pem` | Development X.509 certificate (used as bundle signing cert and target keyring) |
| `board/bbb/rauc-keys/development-1.key.pem` | Development private key for signing bundles |
| `board/bbb/post-build.sh` | Installs RAUC config, keyring, and boot-confirm init script into target rootfs |
| `board/bbb/post-image.sh` | Compiles boot.scr, generates sdcard.img, creates signed RAUC bundle |
| `board/bbb/rootfs-overlay/etc/fw_env.config` | Tells libubootenv where U-Boot environment lives on the MMC (offset 0x260000) |
| `defconfig` | Buildroot configuration with RAUC and all dependencies enabled |
| `Makefile` | Top-level wrapper with `make bundle` target and auto-save on config targets |
| `external.desc` | BR2_EXTERNAL tree descriptor (name: BBB) |
| `deploy.sh` | Build + upload bundle via SCP + install with rauc + reboot |
