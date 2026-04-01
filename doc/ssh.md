# Enabling SSH on BeagleBone Black

This document describes how to enable SSH access on the BeagleBone Black
Buildroot system using Dropbear (lightweight SSH server).

## Table of Contents

1. [Overview](#overview)
2. [Configuration](#configuration)
3. [Build](#build)
4. [Flashing](#flashing)
5. [First SSH Connection](#first-ssh-connection)
6. [Key-based Authentication](#key-based-authentication)
7. [Tips](#tips)

---

## Overview

Dropbear is a lightweight SSH server and client designed for embedded systems.
It has a much smaller footprint than OpenSSH (~110KB vs ~1MB), making it the
preferred choice for resource-constrained devices like the BeagleBone Black.

---

## Configuration

### Using menuconfig

Start from the existing defconfig and enable Dropbear:

```bash
make menuconfig
```

Navigate to the following options:

```
Target packages  --->
    Networking applications  --->
        [*] dropbear
```

Also ensure these system options are set:

```
System configuration  --->
    (root) Root password                          # set a root password
    Network interface to configure through DHCP   # eth0
```

### Key config options

| Config option | Value | Purpose |
|---|---|---|
| `BR2_PACKAGE_DROPBEAR=y` | enabled | Dropbear SSH server |
| `BR2_TARGET_GENERIC_ROOT_PASSWD="root"` | set a password | Root login password for SSH |
| `BR2_SYSTEM_DHCP="eth0"` | eth0 | DHCP on eth0 (required for network access) |

### Optional: OpenSSH instead of Dropbear

If you need full OpenSSH compatibility (e.g., for SFTP subsystem or advanced
options), you can use OpenSSH instead:

```
# In menuconfig:
Target packages  --->
    Networking applications  --->
        [ ] dropbear            # disable Dropbear
        [*] openssh             # enable OpenSSH
```

This is generally not recommended for embedded use due to the larger binary
size and higher memory usage.

### Minimal config fragment

You can apply these settings as a Kconfig fragment:

```bash
# Save as bbb_ssh_fragment.config, then merge:
# support/kconfig/merge_config.sh .config bbb_ssh_fragment.config

BR2_PACKAGE_DROPBEAR=y
BR2_SYSTEM_DHCP="eth0"
BR2_TARGET_GENERIC_ROOT_PASSWD="yourpassword"
BR2_TARGET_ROOTFS_EXT2_4=y
```

---

## Build

```bash
make -j$(nproc)
```

Output files in `output/images/`:

| File | Purpose |
|---|---|
| `MLO` | First-stage bootloader |
| `u-boot.img` | U-Boot |
| `zImage` | Kernel |
| `am335x-boneblack.dtb` | Device tree |
| `rootfs.ext4` | Root filesystem |
| `sdcard.img` | Complete SD card image |

---

## Flashing

Flash the built image to an SD card:

```bash
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=4M status=progress
sync
```

Boot the BeagleBone Black from the SD card by holding the **S2 button** while
powering on.

---

## First SSH Connection

Once the board boots and obtains an IP via DHCP:

```bash
ssh root@<beaglebone-ip>
# password: whatever you set in BR2_TARGET_GENERIC_ROOT_PASSWD
```

To find the board's IP address, check your DHCP server/router's client list,
or connect via serial console and run `ip addr show eth0`.

---

## Key-based Authentication

For passwordless SSH login, place your public key in the rootfs overlay:

```bash
mkdir -p board/bbb/rootfs-overlay/root/.ssh
cp ~/.ssh/id_rsa.pub board/bbb/rootfs-overlay/root/.ssh/authorized_keys
chmod 700 board/bbb/rootfs-overlay/root/.ssh
chmod 600 board/bbb/rootfs-overlay/root/.ssh/authorized_keys
```

The rootfs overlay (`BR2_ROOTFS_OVERLAY`) is already configured in the
defconfig to use `$(BR2_EXTERNAL_BBB_PATH)/board/bbb/rootfs-overlay`, so these
files will be included in the next build automatically.

---

## Tips

- **Dropbear vs OpenSSH**: Dropbear is strongly preferred for embedded systems
  due to its small footprint. Only use OpenSSH if you need features Dropbear
  doesn't provide.
- **SSH client on device**: Add `BR2_PACKAGE_DROPBEAR_CLIENT=y` if you need
  the `dbclient` SSH client on the BeagleBone itself.
- **Boot order**: Dropbear starts after the network is up. The init script
  order is `S40network` (brings up eth0) before Dropbear's init script.
- **Firewall**: By default there is no firewall configured, so SSH (port 22)
  is accessible as soon as the network is up.
- **Root password security**: Change the default root password to something
  strong before deploying to production. Consider disabling password auth
  entirely and using key-based auth only.
