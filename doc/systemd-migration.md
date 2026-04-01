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

### 3. Init scripts → systemd services (`board/bbb/post-build.sh`)

#### ntpd.service (was S49ntp)

```ini
[Unit]
Description=NTP time sync (BusyBox ntpd)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=-/usr/sbin/ntpd -q -p pool.ntp.org
ExecStart=/usr/sbin/ntpd -p pool.ntp.org
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

- `ExecStartPre` does a one-shot sync (the `-` prefix means failure is not fatal)
- `ExecStart` runs ntpd as a daemon for ongoing sync
- `After=network-online.target` ensures network is up first

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

### 4. Existing services (no changes needed)

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
journalctl -u ntpd            # NTP service logs
journalctl -u rauc-mark-good  # RAUC mark-good logs
```

### Manage services

```bash
systemctl start ntpd          # start a service
systemctl stop ntpd           # stop a service
systemctl restart ntpd        # restart a service
systemctl enable ntpd         # enable at boot
systemctl disable ntpd        # disable at boot
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
- **BusyBox is still installed**: BusyBox provides many utilities (ntpd, shell,
  coreutils). systemd replaces only init and device management.
- **Future improvements**: Consider enabling `systemd-timesyncd` (replaces
  busybox ntpd), `systemd-networkd` (replaces ifupdown), and
  `systemd-resolved` (local DNS cache) for a more integrated setup.
- **RAUC D-Bus**: With systemd, you can enable `BR2_PACKAGE_RAUC_DBUS=y` to
  allow D-Bus based RAUC control (useful for hawkBit integration or custom
  update UIs).
