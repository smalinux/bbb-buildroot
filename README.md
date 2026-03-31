# BeagleBone Black Buildroot

Linux system image for the BeagleBone Black with OTA updates via [SWUpdate](https://sbabic.github.io/swupdate/).

## Prerequisites

- Linux host (Ubuntu/Debian/Fedora)
- Build dependencies:
  ```
  # Debian/Ubuntu
  sudo apt install build-essential git wget cpio unzip rsync bc libncurses-dev
  ```

## Build

```
git clone --recurse-submodules <repo-url>
cd bbb-buildroot
make
```

Output images are placed in `output/images/`.

## Flash to SD Card

```
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=1M status=progress
sync
```

Replace `/dev/sdX` with your actual SD card device (check with `lsblk`).

## OTA Updates

The system uses an A/B partition scheme with automatic rollback:

```
SD card layout:
  p1: boot    (FAT, 32MB)  - U-Boot, kernel, DTB, boot.scr
  p2: rootfsA (ext4, 512MB) - root filesystem A
  p3: rootfsB (ext4, 512MB) - root filesystem B
  p4: data    (ext4, 128MB) - persistent storage
```

### Generating an update package

```
make swu
```

This produces `output/images/update.swu`.

### Applying an update

SWUpdate runs a web UI on port 8080. From any machine on the same network:

1. Open `http://<beaglebone-ip>:8080` in a browser
2. Upload `update.swu`
3. The board installs to the inactive partition and reboots

On successful boot, the new partition is confirmed. If the new image fails to boot 3 times, U-Boot rolls back automatically.

### Version bumping

Edit the version in `board/bbb/sw-description` and `board/bbb/rootfs-overlay/etc/sw-versions`, then rebuild with `make swu`.

## Customization

```
make menuconfig          # buildroot config (auto-saves defconfig)
make linux-menuconfig    # Linux kernel config
make uboot-menuconfig    # U-Boot config
make help                # list all targets
```

## Project Structure

```
├── Makefile                    # wrapper around buildroot
├── defconfig                   # board configuration (tracked in git)
├── external.desc               # BR2_EXTERNAL tree descriptor
├── external.mk                 # BR2_EXTERNAL makefile (empty)
├── Config.in                   # BR2_EXTERNAL kconfig (empty)
├── board/bbb/
│   ├── boot.cmd                # U-Boot A/B boot script
│   ├── genimage.cfg            # A/B partition layout
│   ├── post-build.sh           # rootfs post-build hooks
│   ├── post-image.sh           # image generation + .swu packaging
│   ├── sw-description          # SWUpdate image descriptor
│   ├── swupdate.cfg            # SWUpdate runtime config
│   ├── swupdate.config         # SWUpdate build config
│   └── rootfs-overlay/
│       └── etc/
│           ├── fw_env.config   # U-Boot env access config
│           └── sw-versions     # installed software version
├── doc/
│   └── ota-implementation.md   # detailed OTA design document
├── buildroot/                  # buildroot submodule
└── output/                     # build output (gitignored)
```
