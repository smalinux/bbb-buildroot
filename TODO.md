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

## Workflow Improvements (Beyond Packages)

These are build system, boot, and development workflow enhancements that
make the edit→build→test cycle faster — the biggest productivity wins.

### Fast Kernel Deploy (no OTA)

Full RAUC OTA takes minutes. For kernel-only changes, a direct deploy
is 10-20x faster.

- [x] **`make kernel-deploy BOARD=<ip>`** — implemented in
  `scripts/kernel-deploy.sh`: linux-rebuild, scp zImage + DTB + full
  /lib/modules tree to the active slot, depmod, reboot. Skips rootfs
  rebuild, genimage, RAUC bundle, and rauc install. See
  `doc/kernel-deploy.md`. Module-only `rmmod`/`insmod` path is still
  handled by `scripts/deploy-kmod.sh`.
- [x] **`make module-deploy BOARD=<ip>`** — push just `*.ko` files and
  run `depmod -a` on target, no reboot needed

### TFTP + NFS Boot (Zero-Flash Development)

The fastest possible kernel iteration: no SD card writes at all.

- [ ] **TFTP kernel loading** — U-Boot loads zImage + DTB from host
  via TFTP instead of from SD card. Edit `boot.cmd` to add a
  `tftp-boot` path that tries network first, falls back to SD card.
  - Requires: host TFTP server (tftpd-hpa), U-Boot network configured
  - Kernel iteration becomes: recompile → copy to /tftpboot → reboot BBB
- [ ] **NFS rootfs** — mount rootfs over NFS from the host machine.
  Eliminates SD card writes entirely during development.
  - Requires: host NFS server, kernel `CONFIG_ROOT_NFS=y`,
    `CONFIG_NFS_V4=y`, U-Boot bootargs `root=/dev/nfs nfsroot=...`
  - Changes to rootfs are instant — no rebuild, no deploy, no reboot
  - Add `nfs-boot.cmd` as alternative boot script
- [ ] **`make nfsroot`** — Makefile target to export `output/target/`
  via NFS for direct BBB boot (add docs for host NFS setup)

### Host Build Acceleration

- [x] **ccache** — `BR2_CCACHE=y` — cache compilation results.
  Massive speedup for incremental kernel rebuilds after `make clean`.
  First build is same speed, subsequent rebuilds 2-5x faster.
- [ ] **per-package directories** — `BR2_PER_PACKAGE_DIRECTORIES=y` —
  enables parallel package builds. Reduces full rebuild time on
  multi-core hosts. Skipped for now: buildroot's per-package directory
  support is not mature enough — skeleton-init-systemd breaks on
  incremental rebuilds (stale symlinks in per-package target dirs).

### SSH Key Authentication

- [ ] **SSH key login** — install host's `~/.ssh/id_*.pub` into the
  rootfs overlay at `/root/.ssh/authorized_keys`. Eliminates
  `sshpass` dependency and password prompts everywhere.
  - Update `scripts/deploy.sh` to use key auth instead of sshpass
  - Update all `make *-deploy` targets to use key auth
  - Still keep a root password for serial console access

### Serial Console Workflow

- [ ] **Host-side serial logging script** — a script that connects
  to BBB's serial console (via USB-to-serial adapter) and logs
  output to a file with timestamps. Essential for:
  - Capturing kernel panics and oops (SSH is dead by then)
  - Watching U-Boot boot slot selection
  - Debugging early boot issues before network is up
  - Tool: `picocom` or `screen` on host + `tee` to logfile
- [ ] **Kernel `earlycon`** — add `earlycon=ttyS0,115200` to
  bootargs in `boot.cmd` for output before the regular console
  driver loads. Critical for debugging early crashes.

### Device Tree Overlay Workflow

- [ ] **Runtime overlay loading** — enable `CONFIG_OF_OVERLAY=y` in
  linux.fragment, install `dtc` on target. Allows loading `.dtbo`
  files at runtime via configfs without rebooting:
  ```
  mkdir /sys/kernel/config/device-tree/overlays/my-overlay
  cat my-overlay.dtbo > /sys/kernel/config/device-tree/overlays/my-overlay/dtbo
  ```
  - Add `make dtbo-deploy BOARD=<ip>` to push compiled overlays
  - Useful for testing cape/peripheral bindings without reboot

### Kernel Debug Features (linux.fragment additions)

- [ ] **Dynamic debug** — `CONFIG_DYNAMIC_DEBUG=y` — enable/disable
  pr_debug() messages at runtime per-file/function/line without
  recompiling. Zero overhead when disabled.
  ```
  echo 'file drivers/i2c/* +p' > /sys/kernel/debug/dynamic_debug/control
  ```
- [ ] **Kernel memory debugging** — for catching memory bugs during
  driver development:
  ```
  CONFIG_KASAN=y              # Kernel Address Sanitizer (catches OOB, UAF)
  CONFIG_DEBUG_KMEMLEAK=y     # detect kernel memory leaks
  CONFIG_DEBUG_SLAB=y         # slab corruption detection
  ```
  Note: KASAN has ~2x memory overhead, enable only when debugging
- [ ] **Lock debugging** — for catching concurrency bugs:
  ```
  CONFIG_PROVE_LOCKING=y      # lockdep — detect deadlocks
  CONFIG_DEBUG_LOCK_ALLOC=y   # detect incorrect lock usage
  CONFIG_DEBUG_MUTEXES=y
  CONFIG_DEBUG_SPINLOCK=y
  ```
- [ ] **Kernel crash / hang diagnostics**:
  ```
  CONFIG_MAGIC_SYSRQ=y        # SysRq key for emergency debug
  CONFIG_SOFTLOCKUP_DETECTOR=y # detect hung CPUs
  CONFIG_DETECT_HUNG_TASK=y    # detect hung processes
  CONFIG_PANIC_ON_OOPS=y       # reboot on kernel oops (with pstore)
  ```
- [ ] **pstore / ramoops** — persist last kernel log across reboots
  so panics are recoverable. Already have `BR2_PACKAGE_SYSTEMD_PSTORE=y`.
  Add:
  ```
  CONFIG_PSTORE=y
  CONFIG_PSTORE_RAM=y
  CONFIG_PSTORE_CONSOLE=y
  CONFIG_PSTORE_PMSG=y
  ```
  Plus reserve RAM region in device tree for the pstore backend.

### Build System Improvements

- [ ] **`make flash DISK=/dev/sdX`** — Makefile target to flash
  `sdcard.img` directly to an SD card. Safer than raw `dd` (adds
  confirmation prompt, validates target is removable media).
- [ ] **Bundle versioning from git** — auto-set `BUNDLE_VERSION` in
  `post-image.sh` from `git describe --tags` instead of hardcoded
  `0.1.0`. Makes OTA bundles traceable to source commits.
- [ ] **Build timestamp + git hash in `/etc/os-release`** — stamp
  each rootfs with build metadata so you can `cat /etc/os-release`
  on the BBB and know exactly what build is running.
- [ ] **Parallel build CI** — GitHub Actions or local CI that builds
  the image on push and runs `rauc info` to verify the bundle.
  Catches defconfig breakage early.

### Testing Improvements

- [ ] **labgrid test for kernel module load** — test that loads a
  sample `.ko` module, verifies `lsmod` output, unloads it.
  Catches broken module build/install.
- [ ] **labgrid test for TFTP/NFS boot** — verify the board boots
  correctly from network when the TFTP/NFS workflow is set up.
- [ ] **labgrid test for device tree overlay** — load a test `.dtbo`,
  verify it appears in `/proc/device-tree`, unload it.
- [ ] **labgrid test for perf/ftrace** — verify `perf stat ls` and
  `trace-cmd record -e sched_switch` produce output. Catches
  missing kernel config options.
- [ ] **Automated boot time measurement** — labgrid test that parses
  `systemd-analyze` output and fails if boot takes longer than a
  threshold. Prevents accidental boot time regressions.

### Rootfs Size Optimization

- [ ] **Strip unneeded locales** — `BR2_ENABLE_LOCALE_PURGE=y` —
  remove unused locale data, saves 5-10 MB.
- [ ] **Strip kernel modules** — `BR2_LINUX_KERNEL_INSTALL_TARGET=y`
  with `INSTALL_MOD_STRIP=1` — strip debug symbols from `.ko` files
  on target while keeping full symbols on host for debugging.
- [ ] **Review enabled systemd features** — disable unused systemd
  components (hostnamed, vconsole, timedated if using timesyncd
  only) to reduce footprint.

---

## Driver Development & Device Bring-Up

Tools, kernel configs, and workflow items specifically for writing drivers,
porting WiFi/BT chips, bringing up new peripherals, and debugging hardware.

### Wireless / Network Driver Bring-Up

- [ ] **wireless-tools + iw** — `BR2_PACKAGE_IW=y`,
  `BR2_PACKAGE_WIRELESS_TOOLS=y` — scan, connect, monitor WiFi.
  `iw` is the modern nl80211 tool; `iwconfig`/`iwlist` from
  wireless-tools still needed for some legacy/WEXT drivers.
- [ ] **wpa_supplicant** — `BR2_PACKAGE_WPA_SUPPLICANT=y` — WPA/WPA2
  authentication. Essential for testing any WiFi chip you bring up.
  Enable dbus + nl80211 driver.
- [ ] **hostapd** — `BR2_PACKAGE_HOSTAPD=y` — run BBB as a WiFi AP.
  Tests the AP/mesh mode paths of your WiFi driver.
- [ ] **bluez5_utils** — `BR2_PACKAGE_BLUEZ5_UTILS=y` — Bluetooth
  stack + tools (`bluetoothctl`, `hciconfig`, `hcitool`, `btmon`).
  Required for any BT/BLE chip bring-up.
- [ ] **linux-firmware** — `BR2_PACKAGE_LINUX_FIRMWARE=y` — binary
  firmware blobs for WiFi/BT chips (ath9k, ath10k, rtl8xxxu,
  brcmfmac, iwlwifi, etc). Select only the ones you need to keep
  rootfs small. Without this, most WiFi chips won't initialize.
- [ ] **USB WiFi adapter support** — kernel configs:
  ```
  CONFIG_USB_NET_DRIVERS=y      # USB network device support
  CONFIG_CFG80211=y             # wireless core (nl80211)
  CONFIG_MAC80211=y             # mac80211 stack (most WiFi drivers need this)
  CONFIG_RFKILL=y               # RF kill switch support
  ```
- [ ] **tcpdump** — `BR2_PACKAGE_TCPDUMP=y` — capture packets on
  any interface. Essential for debugging WiFi data path issues,
  DHCP failures, and protocol-level driver bugs.
- [ ] **ethtool** — `BR2_PACKAGE_ETHTOOL=y` — query/set NIC driver
  and hardware settings: link status, ring buffers, offloads,
  register dumps. Works for both Ethernet and WiFi drivers.

### USB Subsystem & Driver Development

- [ ] **usbutils** — `BR2_PACKAGE_USBUTILS=y` — `lsusb` for USB
  device enumeration. First tool you reach for when plugging in
  a new USB device. Shows VID:PID, descriptors, speed, endpoints.
- [ ] **usbip** — USB/IP for forwarding USB devices over network.
  Useful for developing USB drivers when the device is physically
  connected to another machine.
- [ ] **USB gadget support** — kernel configs for BBB's USB gadget
  port (USB0). BBB can act as a USB device:
  ```
  CONFIG_USB_GADGET=y
  CONFIG_USB_MUSB_HDRC=y        # BBB's USB controller (Mentor Graphics)
  CONFIG_USB_MUSB_DSPS=y
  CONFIG_USB_CONFIGFS=y         # configfs-based gadget composition
  CONFIG_USB_CONFIGFS_SERIAL=y  # USB serial gadget (console over USB)
  CONFIG_USB_CONFIGFS_ECM=y     # USB Ethernet gadget
  CONFIG_USB_CONFIGFS_MASS_STORAGE=y
  ```
  Useful for: USB serial console (no FTDI cable needed), USB
  Ethernet (second network path), USB mass storage emulation.

### Firmware Loading & Management

- [ ] **Firmware loading infrastructure** — kernel configs:
  ```
  CONFIG_FW_LOADER=y
  CONFIG_FW_LOADER_USER_HELPER=y       # fallback to userspace loading
  CONFIG_FW_LOADER_COMPRESS=y          # support compressed firmware
  CONFIG_EXTRA_FIRMWARE_DIR="/lib/firmware"
  ```
- [ ] **mdev or udev firmware rules** — systemd-udevd handles this,
  but verify firmware loading works: `dmesg | grep firmware` after
  plugging a device. If firmware fails to load, check
  `/lib/firmware/` paths match what the driver requests.
- [ ] **Custom firmware directory in rootfs overlay** — add
  `board/bbb/rootfs-overlay/lib/firmware/` for any proprietary
  firmware blobs your chips need that aren't in linux-firmware.

### Device Tree Authoring & Debugging

- [ ] **dtc on target** — already in the package list, but critical
  for driver bring-up: decompile the live device tree to verify
  your bindings are correct:
  ```
  dtc -I fs /sys/firmware/devicetree/base
  ```
- [ ] **CONFIG_OF_UNITTEST=y** — kernel device tree unit tests.
  Run at boot to verify DT overlay infrastructure works.
- [ ] **CONFIG_OF_DYNAMIC=y** — required for runtime DT node
  add/remove. Needed for overlay workflow.
- [ ] **Device tree debugging via debugfs**:
  ```
  CONFIG_DEBUG_FS=y               # mount debugfs (many subsystems expose info here)
  ```
  Access live DT state at `/sys/kernel/debug/device-tree/`,
  regulator state at `/sys/kernel/debug/regulator/`,
  clock tree at `/sys/kernel/debug/clk/`,
  pin control at `/sys/kernel/debug/pinctrl/`,
  GPIO state at `/sys/kernel/debug/gpio`.

### Bus & Subsystem Debugging

- [ ] **devmem2 or memtool** — read/write hardware registers directly.
  Essential for checking if a peripheral is responding at all
  before writing a proper driver. BBB's AM335x TRM has register
  maps for every peripheral.
- [ ] **regmap debugfs** — `CONFIG_REGMAP=y` + `CONFIG_DEBUG_FS=y` —
  exposes I2C/SPI device register maps at
  `/sys/kernel/debug/regmap/<device>/registers`. Lets you read
  all registers of an I2C/SPI chip without writing any code.
- [ ] **i2c-tools on steroids** — beyond basic `i2cdetect`:
  - `i2ctransfer` — raw I2C message sending (combined transactions)
  - `i2c-stub` kernel module — fake I2C devices for driver testing
    without real hardware: `CONFIG_I2C_STUB=m`
- [ ] **spidev + spi-tools** — `CONFIG_SPI_SPIDEV=y` — expose SPI
  bus to userspace via `/dev/spidevX.Y`. Lets you talk to SPI
  devices from userspace scripts before writing a kernel driver.
- [ ] **PWM sysfs** — `CONFIG_PWM_SYSFS=y` — control PWM outputs
  from userspace. BBB has EHRPWM and ECAP PWM peripherals.
- [ ] **IIO (Industrial I/O)** — `BR2_PACKAGE_LINUX_TOOLS_IIO=y` +
  kernel `CONFIG_IIO=y` — for ADC, DAC, accelerometer, gyroscope
  drivers. BBB has a built-in 12-bit ADC (AM335x TSCADC).

### Power Management & Clock Debugging

- [ ] **PM debugging** — kernel configs for debugging suspend/resume
  and runtime PM in drivers:
  ```
  CONFIG_PM_DEBUG=y              # /sys/power/pm_debug_messages
  CONFIG_PM_ADVANCED_DEBUG=y     # detailed PM state in sysfs
  CONFIG_PM_SLEEP_DEBUG=y        # debug suspend/resume timing
  CONFIG_PM_TRACE=y              # trace PM events via RTC
  ```
- [ ] **Clock framework debugging**:
  ```
  CONFIG_COMMON_CLK_DEBUG=y      # expose clock tree in debugfs
  ```
  View the full clock tree: `cat /sys/kernel/debug/clk/clk_summary`
  Critical for bring-up — if your peripheral's clock isn't enabled,
  register reads return all-zeros or bus errors.
- [ ] **Regulator framework debugging**:
  ```
  CONFIG_REGULATOR_DEBUG=y       # verbose regulator messages in dmesg
  ```
  `/sys/kernel/debug/regulator/` shows voltage, enable state,
  consumer list for each regulator. Essential when your device
  doesn't power on.

### DMA & Interrupt Debugging

- [ ] **DMA debug** — `CONFIG_DMA_API_DEBUG=y` — catches DMA mapping
  errors (wrong direction, missing unmap, mapping leak). Critical
  for network and storage driver development.
- [ ] **IRQ debugging**:
  ```
  CONFIG_GENERIC_IRQ_DEBUGFS=y   # /sys/kernel/debug/irq/
  ```
  Shows IRQ affinity, count, handler, type. Check
  `/proc/interrupts` to verify your driver's IRQ is firing.

### Driver Testing Frameworks

- [ ] **configfs gadget testing** — compose USB gadgets from shell
  scripts to test USB host-side drivers on another machine, or
  test gadget-side driver changes.
- [ ] **GPIO mockup** — `CONFIG_GPIO_MOCKUP=m` — fake GPIO controller
  for testing GPIO consumer drivers without real hardware.
- [ ] **IIO dummy driver** — `CONFIG_IIO_DUMMY=m` — fake IIO device
  for testing IIO subsystem integration.
- [ ] **Virtual CAN** — `CONFIG_CAN_VCAN=m` — loopback CAN interface
  for testing CAN drivers without real hardware:
  `ip link add dev vcan0 type vcan`

### Kernel Coding & Submission Workflow

- [ ] **checkpatch.pl on host** — run `scripts/checkpatch.pl` from
  your linux source tree before submitting patches. Catches style
  violations that maintainers will reject.
- [ ] **coccinelle (spatch)** — semantic patching tool. Some
  maintainers require coccinelle scripts for API migrations.
  Run on host: `make coccicheck M=drivers/your_driver/`
- [ ] **sparse** — `BR2_PACKAGE_HOST_SPARSE=y` — static analysis
  for the kernel. Catches `__user`/`__iomem` pointer misuse,
  endianness bugs, locking errors. Run: `make C=1 M=drivers/your_driver/`
- [ ] **kerneldoc validation** — `make W=1` to catch documentation
  warnings. Maintainers increasingly require kerneldoc for
  exported functions.

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
BR2_CCACHE=y                         # compilation cache (huge speedup)
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

### Phase 4: Fast Iteration Workflow
The biggest productivity multipliers:

```
1. SSH key auth (eliminate sshpass)
2. make kernel-deploy / module-deploy targets
3. Kernel debug configs (dynamic debug, magic sysrq, lockdep)
4. TFTP boot for zero-flash kernel iteration
5. NFS root for zero-flash rootfs iteration
6. Device tree overlay workflow
7. Bundle versioning from git describe
8. Build metadata in /etc/os-release
```

### Phase 5: Driver & Device Bring-Up
For writing and debugging drivers:

```
# Packages
BR2_PACKAGE_IW=y                     # WiFi scanning/config
BR2_PACKAGE_WPA_SUPPLICANT=y         # WPA authentication
BR2_PACKAGE_WIRELESS_TOOLS=y         # iwconfig, iwlist
BR2_PACKAGE_LINUX_FIRMWARE=y         # WiFi/BT firmware blobs
BR2_PACKAGE_BLUEZ5_UTILS=y           # Bluetooth stack + tools
BR2_PACKAGE_USBUTILS=y              # lsusb
BR2_PACKAGE_ETHTOOL=y               # NIC driver debugging
BR2_PACKAGE_TCPDUMP=y               # packet capture
BR2_PACKAGE_LINUX_TOOLS_IIO=y       # ADC/sensor tools

# Kernel configs
CONFIG_CFG80211=y                    # wireless core
CONFIG_MAC80211=y                    # WiFi stack
CONFIG_USB_GADGET=y                  # USB device mode
CONFIG_DEBUG_FS=y                    # debugfs (clk, regulator, pinctrl)
CONFIG_REGMAP=y                      # register map debugging
CONFIG_DMA_API_DEBUG=y               # catch DMA mapping bugs
CONFIG_PM_DEBUG=y                    # suspend/resume debugging
CONFIG_COMMON_CLK_DEBUG=y            # clock tree visibility
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
# Dynamic debug — toggle pr_debug() at runtime without recompiling
CONFIG_DYNAMIC_DEBUG=y
# Device tree overlays — runtime overlay loading via configfs
CONFIG_OF_OVERLAY=y
CONFIG_OF_CONFIGFS=y
# NFS root — boot rootfs from host NFS server
CONFIG_ROOT_NFS=y
CONFIG_NFS_V4=y
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y
# Crash diagnostics
CONFIG_MAGIC_SYSRQ=y
CONFIG_SOFTLOCKUP_DETECTOR=y
CONFIG_DETECT_HUNG_TASK=y
# pstore — persist kernel log across reboots
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y
CONFIG_PSTORE_CONSOLE=y
```

For driver development, add:

```
# debugfs — exposes clk, regulator, pinctrl, regmap, GPIO, IRQ state
CONFIG_DEBUG_FS=y
# Wireless stack (WiFi driver bring-up)
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_RFKILL=y
# USB gadget (BBB as USB device — serial console, Ethernet, mass storage)
CONFIG_USB_GADGET=y
CONFIG_USB_MUSB_HDRC=y
CONFIG_USB_MUSB_DSPS=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_SERIAL=y
CONFIG_USB_CONFIGFS_ECM=y
# IIO — ADC, DAC, sensors (BBB has AM335x 12-bit ADC)
CONFIG_IIO=y
# SPI userspace access
CONFIG_SPI_SPIDEV=y
# PWM control from userspace
CONFIG_PWM_SYSFS=y
# DMA error detection
CONFIG_DMA_API_DEBUG=y
# Clock framework debugging
CONFIG_COMMON_CLK_DEBUG=y
# PM debugging — suspend/resume, runtime PM
CONFIG_PM_DEBUG=y
CONFIG_PM_ADVANCED_DEBUG=y
# IRQ debugging
CONFIG_GENERIC_IRQ_DEBUGFS=y
# Device tree runtime modifications
CONFIG_OF_DYNAMIC=y
```

Optional (enable when actively debugging memory/locking bugs):

```
# Memory debugging (significant overhead — enable only when needed)
CONFIG_KASAN=y
CONFIG_DEBUG_KMEMLEAK=y
# Lock debugging
CONFIG_PROVE_LOCKING=y
CONFIG_DEBUG_LOCK_ALLOC=y
CONFIG_DEBUG_MUTEXES=y
CONFIG_DEBUG_SPINLOCK=y
```

Optional (mock hardware for testing drivers without real devices):

```
CONFIG_I2C_STUB=m              # fake I2C devices
CONFIG_GPIO_MOCKUP=m           # fake GPIO controller
CONFIG_IIO_DUMMY=m             # fake IIO device
CONFIG_CAN_VCAN=m              # loopback CAN interface
```

---

## Impact on Rootfs Size

Current rootfs: ~256 MB partition (512 MB per slot in genimage.cfg).

| Phase | Estimated addition |
|---|---|
| Phase 1 | ~15-20 MB |
| Phase 2 | ~25-35 MB |
| Phase 3 | ~20-30 MB |
| Phase 5 (drivers) | ~30-50 MB (depends on firmware blobs) |
| **Total** | **~90-135 MB** |

Fits comfortably in the 512 MB rootfs partition. WiFi firmware blobs
can be large (ath10k firmware alone is ~5 MB) — select only the chips
you're actually working with via `BR2_PACKAGE_LINUX_FIRMWARE_*`.
