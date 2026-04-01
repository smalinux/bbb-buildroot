# BeagleBone Black Buildroot

Linux system image for the BeagleBone Black with OTA updates via [RAUC](https://rauc.io/).

## Prerequisites

- Linux host (Ubuntu/Debian/Fedora)
- Build dependencies:
  ```
  # Debian/Ubuntu
  sudo apt install build-essential git wget cpio unzip rsync bc libncurses-dev sshpass
  ```

## Build

```
git clone --recurse-submodules <repo-url>
cd bbb-buildroot
make
```

The first build compiles the entire toolchain, kernel, U-Boot, and all packages from source. Subsequent builds are incremental and much faster.

Output images are placed in `output/images/`:
- `sdcard.img` — full SD card image (boot + rootfsA + rootfsB + data)
- `update.raucb` — signed RAUC bundle for OTA updates

## Make Targets

| Target | What it does | When to use |
|--------|-------------|-------------|
| `make` | Incremental build | Day-to-day builds after code/config changes |
| `make menuconfig` | Configure buildroot (auto-saves defconfig) | Add/remove packages, change system settings |
| `make linux-menuconfig` | Configure Linux kernel (auto-saves defconfig) | Enable kernel drivers/features |
| `make uboot-menuconfig` | Configure U-Boot (auto-saves defconfig) | Change bootloader settings |
| `make busybox-menuconfig` | Configure BusyBox (auto-saves defconfig) | Enable/disable BusyBox applets |
| `make bundle` | Build + generate RAUC OTA bundle | Same as `make`, with output paths printed |
| `make rebuild` | Wipe rootfs + rebuild (no recompile) | After disabling packages |
| `make clean` | Full clean (deletes everything in output/) | Nuclear option — recompiles from scratch |
| `make help` | List available targets | |

All standard buildroot targets (e.g., `make busybox-rebuild`, `make linux-dirclean`) are passed through to buildroot.

## Common Workflows

### First build

```
make
```

Takes a while (toolchain + all packages compiled from source). After this, incremental builds are fast.

### Add or enable a package

```
make menuconfig          # enable the package, save, exit
make                     # incremental build — only compiles the new package
```

### Disable or remove a package

Buildroot's incremental build never removes files from the rootfs. Disabled packages stay in `output/target/` until you wipe it:

```
make menuconfig          # disable the package, save, exit
make rebuild             # wipes output/target/, reinstalls all packages, rebuilds images
```

`make rebuild` does **not** recompile anything — packages are already built. It only re-runs the install step for each enabled package into a fresh target directory. This takes minutes, not hours.

### Change kernel config

```
make linux-menuconfig    # change options, save, exit
make                     # recompiles kernel with new config
```

For targeted changes, you can also edit `board/bbb/linux.fragment` directly and run:

```
make linux-dirclean && make
```

### Change U-Boot config

```
make uboot-menuconfig    # change options, save, exit
make                     # recompiles U-Boot with new config
```

Or edit `board/bbb/uboot.fragment` directly and run:

```
make uboot-dirclean && make
```

### Rebuild a single package

```
make <package>-rebuild         # recompile + reinstall one package
make <package>-dirclean && make  # full clean rebuild of one package
```

### Start from scratch

```
make clean               # deletes output/ entirely
make                     # full rebuild — takes a long time
```

Only use this as a last resort when incremental builds produce broken results.

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
  p1: boot    (FAT, 16MB)  - U-Boot, boot.scr (bootloader only)
  p2: rootfsA (ext4, 512MB) - root filesystem A + kernel + DTBs
  p3: rootfsB (ext4, 512MB) - root filesystem B + kernel + DTBs
  p4: data    (ext4, 128MB) - persistent storage
```

### Deploy an update

The deploy script builds, uploads via SCP, installs with RAUC, and reboots:

```
./deploy.sh <beaglebone-ip>
```

Default root password is `root`. Override with `BOARD_PASS=secret ./deploy.sh <ip>`.

### Manual update

```
make bundle
scp -O output/images/update.raucb root@<beaglebone-ip>:/tmp/
ssh root@<beaglebone-ip> rauc install /tmp/update.raucb
ssh root@<beaglebone-ip> reboot
```

On successful boot, the new slot is marked as good. If the new image fails to boot 3 times, U-Boot rolls back automatically.

### Version bumping

Edit `BUNDLE_VERSION` in `board/bbb/post-image.sh`, then rebuild with `make bundle`.

## Project Structure

```
├── Makefile                    # wrapper around buildroot
├── defconfig                   # board configuration (tracked in git)
├── external.desc               # BR2_EXTERNAL tree descriptor
├── external.mk                 # BR2_EXTERNAL makefile (empty)
├── Config.in                   # BR2_EXTERNAL kconfig (empty)
├── board/bbb/
│   ├── boot.cmd                # U-Boot A/B boot script (RAUC bootchooser)
│   ├── busybox.fragment        # BusyBox config additions (ntpd)
│   ├── linux.fragment          # kernel config additions (SquashFS)
│   ├── uboot.fragment          # U-Boot config additions (raw MMC env, setexpr)
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
├── deploy.sh                   # build + upload + install OTA bundle
├── doc/                        # documentation
├── buildroot/                  # buildroot submodule
└── output/                     # build output (gitignored)
```
