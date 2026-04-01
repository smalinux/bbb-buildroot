# Migration from BusyBox Init to systemd

## What

Replaced BusyBox init + mdev with systemd as the init system and device
manager. Converted all SysV init scripts to systemd service units.

## Why

systemd provides:
- Proper service dependency management and parallel startup
- Built-in journal logging (`journalctl`)
- Native D-Bus integration (useful for RAUC's D-Bus API)
- Socket activation, watchdog timers, cgroups isolation
- Standard service management (`systemctl start/stop/status`)

## Prerequisites (already met)

| Requirement | Status |
|---|---|
| glibc toolchain | Bootlin armv7-eabihf-glibc-stable |
| `BR2_USE_WCHAR=y` | Already enabled |
| `BR2_ENABLE_LOCALE=y` | Already enabled |
| `BR2_TOOLCHAIN_HAS_THREADS=y` | Already enabled |
| `BR2_PACKAGE_KMOD=y` | Already enabled |

## Changes Made

### 1. Buildroot config (`defconfig`)

```
BR2_INIT_SYSTEMD=y
```

This automatically pulls in systemd, util-linux, and switches the device
manager from mdev to systemd-udevd. The old `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_MDEV`
is no longer set — systemd handles `/dev` population via udev rules.

### 2. Kernel config (`board/bbb/linux.fragment`)

Added mandatory kernel options for systemd:

```
CONFIG_CGROUPS=y           # control groups (process isolation)
CONFIG_INOTIFY_USER=y      # filesystem event monitoring
CONFIG_SIGNALFD=y          # signal handling via file descriptors
CONFIG_TIMERFD=y           # timer file descriptors
CONFIG_EPOLL=y             # efficient I/O event notification
CONFIG_UNIX=y              # Unix domain sockets
CONFIG_FHANDLE=y           # file handle syscalls
CONFIG_DEVTMPFS=y          # automatic /dev population
CONFIG_DEVTMPFS_MOUNT=y    # mount devtmpfs at boot
CONFIG_TMPFS=y             # tmpfs for /tmp, /run
CONFIG_TMPFS_POSIX_ACL=y   # ACL support on tmpfs
CONFIG_SECCOMP=y           # syscall filtering (recommended)
CONFIG_UEVENT_HELPER_PATH=""  # disable legacy hotplug
```

Most of these are likely already enabled in `omap2plus_defconfig`, but the
fragment ensures they're set regardless.

### 3. Network configuration (`board/bbb/post-build.sh`)

The BBB ethernet interface `end0` is configured via systemd-networkd:

```ini
# /usr/lib/systemd/network/20-wired.network
[Match]
Name=end0

[Network]
DHCP=yes

[DHCPv4]
UseDNS=yes
UseNTP=yes
```

Without this file, systemd-networkd starts but has no interfaces to manage,
resulting in no network connectivity.

### 4. NTP time sync

systemd-timesyncd handles NTP natively — no custom ntpd service is needed.
It starts automatically as `systemd-timesyncd.service` and uses NTP servers
provided by DHCP (via `UseDNS=yes` in the `.network` file) or the compiled-in
fallback servers.

### 5. Init scripts → systemd services (`board/bbb/post-build.sh`)

#### rauc-mark-good.service (was S99rauc-mark-good)

```ini
[Unit]
Description=Mark current RAUC slot as good
After=multi-user.target
ConditionPathIsReadWrite=/dev/mmcblk0

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'fw_printenv BOOT_ORDER 2>/dev/null && rauc status mark-good'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

- Runs once after the system reaches multi-user target
- `ConditionPathIsReadWrite` skips if MMC is not available
- `RemainAfterExit=yes` keeps the unit in "active" state after completion

### 6. Existing services (no changes needed)

- **Dropbear SSH**: Buildroot's dropbear package already includes a systemd
  service unit (`dropbear.service`). It will be used automatically.
- **fstab mounts**: systemd reads `/etc/fstab` and creates mount units
  automatically (`data.mount` for `/data`).

## Usage

### Check system status after boot

```bash
systemctl status              # overall system state
systemctl list-units          # all loaded units
systemctl list-units --failed # any failed services
journalctl -b                 # full boot log
journalctl -u systemd-timesyncd  # NTP time sync logs
journalctl -u rauc-mark-good    # RAUC mark-good logs
journalctl -u systemd-networkd  # Network config logs
```

### Manage services

```bash
systemctl start dropbear      # start a service
systemctl stop dropbear       # stop a service
systemctl restart dropbear    # restart a service
systemctl enable dropbear     # enable at boot
systemctl disable dropbear    # disable at boot
```

### Debug boot issues

```bash
systemd-analyze                # boot time breakdown
systemd-analyze blame          # time per service
systemd-analyze critical-chain # critical path
```

## Notes

- **Rootfs size increase**: systemd adds ~30-50 MB to the rootfs. The 256 MB
  partition has enough room.
- **BusyBox is still installed**: BusyBox provides many utilities (shell,
  coreutils). systemd replaces init, device management, NTP, and networking.
- **systemd-timesyncd** handles NTP natively, replacing busybox ntpd.
- **systemd-networkd** manages ethernet via `/usr/lib/systemd/network/20-wired.network`.
- **systemd-resolved** provides DNS resolution (started automatically).
- **RAUC D-Bus**: With systemd, you can enable `BR2_PACKAGE_RAUC_DBUS=y` to
  allow D-Bus based RAUC control (useful for hawkBit integration or custom
  update UIs).
