# BeagleBone Black Buildroot

Linux system image for the BeagleBone Black with OTA updates via [RAUC](https://rauc.io/).

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

### Generating an update bundle

```
make bundle
```

This produces `output/images/update.raucb`.

### Applying an update

Copy the bundle to the board and install with RAUC:

```
scp output/images/update.raucb root@<beaglebone-ip>:/tmp/
ssh root@<beaglebone-ip> rauc install /tmp/update.raucb
ssh root@<beaglebone-ip> reboot
```

Or use the deploy script:

```
./deploy.sh <beaglebone-ip>
```

On successful boot, the new slot is marked as good. If the new image fails to boot 3 times, U-Boot rolls back automatically.

### Version bumping

Edit the `--bundle-version` argument in `board/bbb/post-image.sh`, then rebuild with `make bundle`.

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
│   ├── boot.cmd                # U-Boot A/B boot script (RAUC bootchooser)
│   ├── genimage.cfg            # A/B partition layout
│   ├── post-build.sh           # rootfs post-build hooks
│   ├── post-image.sh           # image generation + RAUC bundle packaging
│   ├── system.conf             # RAUC system configuration
│   ├── rauc-keys/              # development signing keys
│   │   ├── development-1.cert.pem
│   │   └── development-1.key.pem
│   └── rootfs-overlay/
│       └── etc/
│           └── fw_env.config   # U-Boot env access config
├── doc/
│   └── ota-implementation.md   # detailed OTA design document
├── buildroot/                  # buildroot submodule
└── output/                     # build output (gitignored)
```
