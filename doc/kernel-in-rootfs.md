# Kernel and DTB in Rootfs for OTA Updates

## Problem

Previously, the Linux kernel (`zImage`) and device tree blobs (`am335x-*.dtb`)
lived on the shared FAT boot partition (p1). The RAUC A/B update only replaced
the rootfs on p2/p3, meaning OTA updates could not include kernel or DTB
changes. A kernel bug fix or DTB change required reflashing the entire SD card.

## Solution

Move the kernel and DTBs into the root filesystem at `/boot/`, so they are
included in every RAUC update bundle.

### Changes

1. **`defconfig`**: Enable `BR2_LINUX_KERNEL_INSTALL_TARGET=y`. This tells
   buildroot to install `zImage` and all DTBs into `$(TARGET_DIR)/boot/`
   during the kernel build, so they end up inside `rootfs.ext4`.

2. **`board/bbb/boot.cmd`**: Load kernel and DTB from the active rootfs
   partition instead of the FAT boot partition:
   ```
   # Before (FAT boot partition)
   load mmc 0:1 ${kernel_addr_r} zImage
   load mmc 0:1 ${fdt_addr_r} am335x-boneblack.dtb

   # After (active rootfs partition)
   load mmc 0:${root_part} ${kernel_addr_r} boot/zImage
   load mmc 0:${root_part} ${fdt_addr_r} boot/am335x-boneblack.dtb
   ```

3. **`board/bbb/genimage.cfg`**: Remove kernel and DTB files from the FAT
   boot partition. It now only contains `MLO`, `u-boot.img`, and `boot.scr`.
   Shrink the boot partition from 32MB to 16MB since it holds much less.

### What lives where now

| Partition | Contents | Updated by |
|-----------|----------|-----------|
| p1 (boot FAT, 16MB) | MLO, u-boot.img, boot.scr | SD card reflash only |
| p2/p3 (rootfs ext4, 512MB) | Full rootfs + `/boot/zImage` + `/boot/*.dtb` | RAUC OTA |

### RAUC bundle

No changes needed to the RAUC manifest or bundle creation. The kernel and
DTBs are part of `rootfs.ext4`, which is already the bundle payload. Any
`make bundle` now automatically includes the current kernel build.

## Trade-offs

- **Pro**: Kernel updates are now atomic and roll-backable via RAUC A/B.
- **Pro**: No more version skew between kernel and rootfs after OTA.
- **Con**: U-Boot must read from ext4 instead of FAT. U-Boot's ext4 driver
  is read-only and well-tested, so this is not a practical concern.
- **Con**: The boot partition can no longer be updated via OTA. But it only
  contains the bootloader (MLO + u-boot.img) and boot script, which rarely
  change. Bootloader updates still require a full reflash.
