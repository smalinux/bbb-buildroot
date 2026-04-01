# TODO: Essential Kernel Development Stack for BBB

Packages and features to enable for a comfortable Linux kernel development
environment on the BeagleBone Black.

## Legend

- `[x]` — already enabled
- `[ ]` — not yet enabled, should add
- `[-]` — skip (not needed or too heavy for BBB)

---

## Core Build & Boot

- [x] Buildroot — build system
- [x] U-Boot — bootloader + fw_printenv/fw_setenv
- [x] systemd — init system
- [x] RAUC — A/B OTA with signed bundles and automatic rollback
- [x] BusyBox — fallback shell/tools
- [ ] initramfs — early userspace (for recovery, overlayfs root)
- [ ] watchdog daemon — hardware watchdog, auto-recovery on hang

## Kernel Development

- [x] kmod — modprobe, lsmod, insmod, rmmod
- [x] strace — syscall tracing
- [x] host-dtc — device tree compiler (host side)
- [ ] dtc (target) — compile/decompile .dts overlays live on BBB
- [ ] linux kernel headers — for out-of-tree module builds on target
- [ ] perf (BR2_LINUX_TOOLS_PERF) — kernel profiling and tracing
- [ ] gdb + gdbserver — userspace + kernel debugging
- [ ] trace-cmd — ftrace frontend for kernel tracing
- [ ] ltrace — library call tracing
- [-] valgrind — too heavy for ARM Cortex-A8, limited usefulness
- [-] crash/kdump — overkill for dev board, use KGDB instead
- [-] lttng — complex setup, trace-cmd + ftrace is sufficient

## Networking & Remote Access

- [x] Dropbear SSH — remote access
- [x] systemd-networkd — network config (DHCP on end0)
- [x] systemd-resolved — DNS resolution
- [ ] iproute2 — ip, ss, tc commands (much better than busybox ip)
- [ ] rsync — fast incremental file sync from host
- [ ] curl — pull files, test HTTP endpoints, manual OTA
- [ ] avahi-daemon — mDNS (reach BBB as beaglebone.local)
- [-] OpenSSH — Dropbear is sufficient for embedded
- [-] nftables/iptables — not needed for dev board on local network

## Hardware Access

- [ ] libgpiod + gpiotools — modern GPIO access (replaces sysfs GPIO)
- [ ] i2c-tools — i2cdetect, i2cdump, i2cset
- [ ] spi-tools — SPI bus diagnostics
- [ ] can-utils — CAN bus tools (candump, cansend)
- [ ] evtest — input device testing
- [ ] memtool — direct memory/register read-write

## Storage & Filesystem

- [x] util-linux — mount, lsblk, blkid, fdisk, losetup
- [ ] e2fsprogs — mkfs.ext4, fsck, resize2fs
- [ ] dosfstools — FAT partition tools (U-Boot boot partition)
- [-] mtd-utils — BBB uses eMMC/SD, not raw NAND
- [-] f2fs-tools — ext4 is fine for SD/eMMC
- [-] overlayfs — useful but complex, not essential right now

## System Monitoring

- [x] htop — interactive process viewer
- [ ] procps-ng — top, ps, vmstat, free, uptime (better than busybox)
- [ ] sysstat — iostat, mpstat, sar for performance analysis
- [ ] logrotate — prevent journal/logs from filling /data

## Developer Convenience

- [ ] tmux — persistent terminal sessions over SSH
- [ ] nano — simple on-device editing (lighter than vim)
- [ ] bash + bash-completion — proper shell experience
- [-] vim — nano is enough for quick edits on target
- [-] git — version tracking belongs on host, not target
- [-] python3 — adds ~20 MB, use host for scripting
- [-] minicom/picocom — serial monitoring is done from host side

---

## Priority Order

### Phase 1: Essentials (add now)
These are the most impactful for daily kernel development:

```
BR2_PACKAGE_DTC=y                    # device tree compiler on target
BR2_PACKAGE_IPROUTE2=y               # ip, ss, tc (replaces busybox ip)
BR2_PACKAGE_E2FSPROGS=y              # fsck, mkfs.ext4
BR2_PACKAGE_DOSFSTOOLS=y             # FAT tools for boot partition
BR2_PACKAGE_LIBGPIOD=y               # modern GPIO access
BR2_PACKAGE_LIBGPIOD_TOOLS=y
BR2_PACKAGE_I2C_TOOLS=y              # I2C bus debugging
BR2_PACKAGE_PROCPS_NG=y              # proper ps, top, free, vmstat
BR2_PACKAGE_RSYNC=y                  # fast file sync from host
BR2_PACKAGE_CURL=y                   # HTTP client
BR2_PACKAGE_NANO=y                   # on-target editing
```

### Phase 2: Debugging & Profiling
For deeper kernel work:

```
BR2_LINUX_KERNEL_HEADERS_AS_KERNEL=y # kernel headers on target
BR2_PACKAGE_LINUX_TOOLS_PERF=y       # kernel profiling
BR2_PACKAGE_GDB=y                    # debugger
BR2_PACKAGE_GDBSERVER=y              # remote debugging from host
BR2_PACKAGE_TRACE_CMD=y              # ftrace frontend
BR2_PACKAGE_LTRACE=y                 # library call tracing
```

### Phase 3: Comfort & Infrastructure
Nice-to-haves for longer dev sessions:

```
BR2_PACKAGE_TMUX=y                   # persistent SSH sessions
BR2_PACKAGE_BASH=y                   # proper shell
BR2_PACKAGE_BASH_COMPLETION=y
BR2_PACKAGE_AVAHI_DAEMON=y           # beaglebone.local mDNS
BR2_PACKAGE_SYSSTAT=y                # iostat, mpstat
BR2_PACKAGE_LOGROTATE=y              # log rotation
BR2_PACKAGE_WATCHDOG=y               # hardware watchdog daemon
BR2_PACKAGE_SPI_TOOLS=y              # SPI debugging
BR2_PACKAGE_CAN_UTILS=y              # CAN bus tools
BR2_PACKAGE_EVTEST=y                 # input device testing
BR2_PACKAGE_MEMTOOL=y                # register read/write
```

---

## Kernel Config Additions (linux.fragment)

For ftrace and perf support, add to `board/bbb/linux.fragment`:

```
# ftrace — expose via /sys/kernel/debug/tracing
CONFIG_FTRACE=y
CONFIG_FUNCTION_TRACER=y
CONFIG_FUNCTION_GRAPH_TRACER=y
CONFIG_STACK_TRACER=y
CONFIG_DYNAMIC_FTRACE=y
# perf events
CONFIG_PERF_EVENTS=y
CONFIG_HW_PERF_EVENTS=y
# KGDB for live kernel debugging over serial
CONFIG_KGDB=y
CONFIG_KGDB_SERIAL_CONSOLE=y
```

---

## Impact on Rootfs Size

Current rootfs: ~256 MB partition.

| Phase | Estimated addition |
|---|---|
| Phase 1 | ~15-20 MB |
| Phase 2 | ~25-35 MB |
| Phase 3 | ~20-30 MB |
| **Total** | **~60-85 MB** |

Fits comfortably in the 256 MB rootfs partition.
