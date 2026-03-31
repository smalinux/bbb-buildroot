# BeagleBone Black Buildroot

Linux system image for the BeagleBone Black, built with [Buildroot](https://buildroot.org/).

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

## Usage

All standard buildroot targets work from the project root:

```
make                 # build the system image
make menuconfig      # configure (auto-saves defconfig on close)
make linux-menuconfig # configure the Linux kernel
make clean           # clean build output
make help            # list available commands
```

Config targets (`menuconfig`, `nconfig`, `xconfig`, `gconfig`) automatically save `defconfig` when you close them.

## Flash to SD Card

```
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=1M status=progress
sync
```

Replace `/dev/sdX` with your actual SD card device (check with `lsblk`).

## Project Structure

```
├── Makefile        # wrapper around buildroot
├── defconfig       # board configuration (tracked in git)
├── buildroot/      # buildroot submodule
└── output/         # build output (gitignored)
```
