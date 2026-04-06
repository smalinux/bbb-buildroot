# Initramfs — Early Userspace for Recovery and Overlayfs

## What

A minimal initramfs (~1-2 MB) that runs before the real rootfs is
mounted.  It provides two features:

1. **Recovery shell** — a busybox shell for emergency repair when the
   rootfs is corrupt or unbootable.
2. **Overlayfs root** — mount the rootfs read-only with a writable
   overlay, keeping the rootfs pristine for OTA.

Without either flag on the kernel cmdline, the initramfs just mounts
the rootfs normally and hands off to systemd — sub-second overhead.

## How It Works

### Boot Flow

```
U-Boot (boot.cmd)
  ├── loads zImage + DTB + initramfs.uImage from /boot/
  └── bootz with initrd
        │
        ▼
Kernel unpacks initramfs, runs /init
  ├── mounts proc, sys, devtmpfs
  ├── parses cmdline: root=, bbb.recovery, bbb.overlayfs
  │
  ├── [bbb.recovery]  → drop to busybox shell
  │                      user types 'exit' → continue boot
  │
  ├── [bbb.overlayfs] → mount rootfs read-only
  │                      mount /data overlay (persistent)
  │                      create overlayfs union
  │
  └── [normal]         → mount rootfs read-write
        │
        ▼
switch_root → /sbin/init (systemd)
```

### Backward Compatibility

If `initramfs.uImage` is missing (e.g. old rootfs from before this
feature), `boot.cmd` falls back to booting without an initrd — the
`bootz ... - ...` syntax.  No breakage.

## Usage

### Normal Boot (default)

No changes needed.  The initramfs adds sub-second overhead.

### Recovery Mode

Add `bbb.recovery` to the kernel cmdline.  From the running board:

```bash
# Set recovery flag and reboot
fw_setenv optargs bbb.recovery
reboot
```

On the serial console, you'll get a busybox shell with basic tools
(mount, ls, cp, vi, ip, etc.).  The rootfs is NOT mounted — you can
mount it manually, fsck it, edit files, then type `exit` to continue
normal boot.

To clear the flag after recovery:

```bash
fw_setenv optargs
```

**Note**: recovery mode requires serial console access — the network
stack isn't started in the initramfs.

### Overlayfs Root

Add `bbb.overlayfs` to the kernel cmdline:

```bash
fw_setenv optargs bbb.overlayfs
reboot
```

The rootfs partition is mounted read-only.  All writes go to a
writable overlay backed by the `/data` partition (`/dev/mmcblk0p4`).
This means:

- The rootfs stays pristine — RAUC OTA diffs are exact
- Runtime changes (logs, config edits) go to `/data/overlay/`
- You can "factory reset" runtime changes: `rm -rf /data/overlay/*`

If the data partition is unavailable, the overlay falls back to tmpfs
(changes lost on reboot).

To return to normal read-write rootfs:

```bash
fw_setenv optargs
reboot
```

## What's in the Initramfs

The initramfs is intentionally minimal:

| Component | Purpose |
|---|---|
| `/init` | Shell script — entry point |
| `/bin/busybox` | All-in-one userspace (from the buildroot target) |
| `/bin/sh`, `/bin/mount`, ... | Symlinks to busybox applets |
| `/lib/libc*`, `/lib/ld-*` | Shared libraries (if busybox is dynamically linked) |
| `/dev/`, `/proc/`, `/sys/` | Mount points for virtual filesystems |
| `/mnt/root`, `/mnt/lower`, `/mnt/data` | Mount points for rootfs assembly |

## Files

| File | Purpose |
|---|---|
| `board/bbb/initramfs/init` | Init script (parsed cmdline, mounts rootfs, switch_root) |
| `board/bbb/mkinitrfs.sh` | Build script — creates cpio.gz, wraps as U-Boot ramdisk |
| `board/bbb/post-build.sh` | Calls mkinitrfs.sh during build |
| `board/bbb/boot.cmd` | U-Boot script — loads initramfs.uImage alongside kernel |
| `board/bbb/linux.fragment` | Kernel config: BLK_DEV_INITRD, OVERLAY_FS |

## Kernel Config (linux.fragment)

```
CONFIG_BLK_DEV_INITRD=y    # accept external initrd from bootloader
CONFIG_RD_GZIP=y            # decompress gzipped cpio
CONFIG_OVERLAY_FS=y          # overlayfs filesystem support
```

## Build Details

The initramfs is built during `post-build.sh` (after packages are
installed, before filesystem images are created).  The `mkinitrfs.sh`
script:

1. Creates a minimal directory tree in a temp dir
2. Copies busybox + its shared libraries from `output/target/`
3. Creates symlinks for needed busybox applets
4. Installs the `/init` script
5. Packs everything as `cpio -H newc | gzip`
6. Wraps with `mkimage -T ramdisk` for U-Boot
7. Installs to `${TARGET_DIR}/boot/initramfs.uImage`

The result is included in `rootfs.ext4` and updated via RAUC OTA
alongside the kernel and DTB.

## Kernel Deploy

`make kernel-deploy` automatically pushes `initramfs.uImage` to the
board alongside zImage and DTB (if the file exists).

## Verifying on the Board

Confirm the initramfs was loaded and used during boot:

```bash
# Should show "Trying to unpack rootfs image as initramfs..." and
# "initramfs: root=/dev/mmcblk0pN fstype=ext4"
dmesg | grep initramfs
```

## Testing

```bash
pytest tests/test_initramfs.py --lg-env tests/env.yaml -v
```

Tests verify the initramfs file exists, is a reasonable size, the
kernel has initrd support, and overlayfs works.

## Troubleshooting

**Board doesn't boot with initramfs**:
Check that U-Boot's `ramdisk_addr_r` is set.  On AM335x it should
default to `0x88080000`.  Verify: `printenv ramdisk_addr_r` in U-Boot.

**Recovery shell has no /dev/mmcblk0pN**:
Wait a moment — the MMC controller may not be initialized yet.
Try `sleep 2` then `ls /dev/mmcblk0*`.

**Overlayfs "wrong fs type" error**:
Verify `CONFIG_OVERLAY_FS=y` in the kernel config.  Check with
`zcat /proc/config.gz | grep OVERLAY` on the board.
