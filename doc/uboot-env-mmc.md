# U-Boot Environment: FAT to Raw MMC Migration

## Problem

RAUC uses `fw_printenv`/`fw_setenv` (from libubootenv) to read and write
U-Boot environment variables (`BOOT_ORDER`, `BOOT_A_LEFT`, `BOOT_B_LEFT`)
for A/B slot management. These tools require `/etc/fw_env.config` to point
to the environment's storage location.

The stock `am335x_evm` U-Boot defconfig stores the environment in a FAT
file (`uboot.env` on the boot partition):

```
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_INTERFACE="mmc"
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
CONFIG_ENV_FAT_FILE="uboot.env"
```

The standard `fw_env.config` format only supports raw block devices with
byte offsets — it cannot access files on a mounted filesystem. This causes
`fw_printenv` to fail with:

```
Cannot read environment, using default
Cannot read default environment from file
```

Which in turn causes RAUC installation to fail when it tries to mark slots.

## Solution

A U-Boot config fragment (`board/bbb/uboot.fragment`) switches the
environment storage from FAT to raw MMC:

```
CONFIG_ENV_IS_IN_FAT=n
CONFIG_ENV_IS_IN_MMC=y
CONFIG_SYS_MMC_ENV_DEV=0
CONFIG_ENV_OFFSET=0x200000
```

This stores the environment at a fixed offset on the raw MMC device
(`/dev/mmcblk0`), which `fw_printenv`/`fw_setenv` can access directly.

The `fw_env.config` on the target matches:

```
/dev/mmcblk0    0x200000    0x20000
```

## Offset choice and SD card layout

The first 4MB of the SD card is reserved as a pre-partition gap
(`genimage.cfg` sets `offset = 4M` on the boot partition). This gap contains:

```
0x000000           MBR (partition table)
0x000200-0x060000  MLO/SPL raw copies (AM335x ROM loads from here)
0x060000-0x1E0000  u-boot.img raw copy (~1.5MB, SPL fallback)
0x200000-0x220000  U-Boot environment (128KB) <-- our env
0x220000-0x400000  free space
0x400000+          boot FAT partition (32MB)
```

The env at `0x200000` (2MB) is safely past u-boot.img and well before the
boot partition.

**Previous broken offsets**:
- `0x260000` — was inside the boot FAT partition when it started at sector 1,
  corrupting kernel/DTB on `saveenv`.
- `0x80000` — overlapped with the u-boot.img raw binary (which starts at
  sector 0x300 = byte 0x60000 and spans ~1.5MB to 0x1E0000). Writing env
  here corrupted u-boot.img, causing an SPL boot loop.

The size `0x20000` (128KB) matches `CONFIG_ENV_SIZE=0x20000` in the
U-Boot config.

## Rebuild

After adding the fragment, rebuild U-Boot and reflash:

```
make uboot-rebuild all
```

Then flash the new `sdcard.img` to the SD card. The first `saveenv` from
U-Boot will create the environment at the raw offset.

## Verification

After booting the new image, test from the board:

```sh
fw_printenv
fw_setenv test_var hello
fw_printenv test_var
```

If these commands work without errors, RAUC slot management will work too.
