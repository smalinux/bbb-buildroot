# BeagleBone Black Buildroot

Linux system image for the BeagleBone Black with OTA updates via [RAUC](https://rauc.io/).

## Cheatsheet

```bash
# --- Build ---
make                              # incremental build (sdcard.img + update.raucb)
make rebuild                      # wipe rootfs + reinstall (after disabling packages)
make clean                        # nuclear: delete output/, recompile from scratch
make bundle                       # build + show output paths

# --- Configure (auto-saves defconfig on exit) ---
make menuconfig                   # buildroot packages & system settings
make linux-menuconfig             # kernel config
make uboot-menuconfig             # bootloader config
make busybox-menuconfig           # busybox applets

# --- Single-package operations ---
make <pkg>-rebuild                # recompile + reinstall one package
make <pkg>-dirclean               # wipe one package's build dir
make <pkg>-reconfigure            # re-run configure step
make linux-rebuild                # rebuild kernel (fast, when using OVERRIDE_SRCDIR)

# --- Deploy / flash ---
./scripts/deploy.sh <board-ip>            # build + upload .raucb + rauc install + reboot
./scripts/deploy-kmod.sh <pkg> <ip>       # fast: build one kmod, scp .ko, insmod (no OTA, no reboot)
./scripts/reset.sh                        # USB power-cycle BBB via uhubctl (brick recovery)
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=1M status=progress  # flash SD

# --- On the board (ssh root@<ip>, password: root) ---
rauc status                       # show slot states (A/B, booted, good/bad)
fw_printenv BOOT_ORDER            # check active boot slot order
fw_setenv BOOT_ORDER "A B"        # force next boot to slot A (rollback)
journalctl -b                     # logs from current boot
journalctl -k -f                  # follow kernel log

# --- Tests (labgrid, from host) ---
source tests/.venv/bin/activate
pytest tests/ --lg-env tests/env.yaml              # all tests
pytest tests/test_rauc.py --lg-env tests/env.yaml -v   # one test file

# --- Git ---
git submodule update --init --recursive   # first-time buildroot checkout
```

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
./scripts/deploy.sh <beaglebone-ip>
```

Default root password is `root`. Override with `BOARD_PASS=secret ./scripts/deploy.sh <ip>`.

### Manual update

```
make bundle
scp -O output/images/update.raucb root@<beaglebone-ip>:/tmp/
ssh root@<beaglebone-ip> rauc install /tmp/update.raucb
ssh root@<beaglebone-ip> reboot
```

On successful boot, the new slot is marked as good. If the new image fails to boot 3 times, U-Boot rolls back automatically.

### Rollback to the previous version

RAUC keeps the previous working rootfs on the inactive slot. You can switch
back at any time:

```bash
# Check which slot is booted and which is inactive
rauc status
```

```
=== Slot States ===
x [rootfs.1] (/dev/mmcblk0p3, ext4, booted)
      bootname: B
      boot status: good

o [rootfs.0] (/dev/mmcblk0p2, ext4, inactive)
      bootname: A
      boot status: good
```

The `x` marks the currently booted slot, `o` marks the inactive one. To roll
back to the inactive slot:

```bash
# Tell U-Boot to boot the other slot next
fw_setenv BOOT_ORDER "A B"    # put the desired slot first
reboot
```

After running `fw_setenv`, `rauc status` confirms the switch before rebooting:

```
=== Bootloader ===
Activated: rootfs.0 (A)       # ← next boot will use slot A

=== Slot States ===
o [rootfs.1] (/dev/mmcblk0p3, ext4, booted)    # still running on B
      bootname: B
      boot status: good

x [rootfs.0] (/dev/mmcblk0p2, ext4, inactive)  # ← will boot this next
      bootname: A
      boot status: good
```

After reboot, the system runs from slot A. The `rauc-mark-good` service marks
it as good automatically.

#### Automatic rollback (no intervention needed)

If an update breaks the system badly enough that it can't boot, U-Boot handles
rollback automatically:

1. Each slot has 3 boot attempts (`BOOT_A_LEFT` / `BOOT_B_LEFT`)
2. U-Boot decrements the counter on each boot
3. `rauc-mark-good.service` resets the counter to 3 on successful boot
4. If a slot fails 3 times in a row, U-Boot switches to the other slot

This means a bricked update recovers itself after 3 power cycles — no serial
console or manual intervention required.

## Custom Packages

The `package/` directory holds custom packages that are built alongside
standard Buildroot packages. A `hello-world` example is included.

### How it works

Two files in the project root wire external packages into Buildroot:

- **`Config.in`** — sources each package's Kconfig file so it appears in
  `make menuconfig` under "External options".
- **`external.mk`** — uses a wildcard (`package/*/*.mk`) to auto-include
  every package's build recipe. Adding a new package directory is enough —
  no need to edit `external.mk`.

### Package anatomy

Each package lives in its own directory under `package/`:

```
package/<name>/
├── Config.in      # Kconfig menu entry (BR2_PACKAGE_<NAME>)
├── <name>.mk      # build recipe (source location, build/install commands)
└── <name>.c       # source code (for local packages)
```

The `.mk` file defines where the source comes from:

- **Local source** (checked into this repo): `<NAME>_SITE_METHOD = local`
- **Git clone** (fetched during build): `<NAME>_SITE_METHOD = git` with
  `<NAME>_SITE = https://github.com/org/repo.git` and
  `<NAME>_VERSION = <tag-or-commit>`

### Adding a new package

1. Create `package/<name>/` with a `Config.in` and `<name>.mk`
2. Add a `source "$BR2_EXTERNAL_BBB_PATH/package/<name>/Config.in"` line
   to the root `Config.in`
3. Enable it in `make menuconfig` → "External options"
4. Build:

```bash
make menuconfig    # enable "<name>" under "External options"
make               # builds everything including the new package
```

Or skip menuconfig by adding `BR2_PACKAGE_<NAME>=y` to `defconfig` and
running `make`.

### Example: hello-world

A minimal C program that prints a greeting. To enable it:

```bash
make menuconfig    # enable "hello-world" under "External options"
make
```

Or add this line to `defconfig` and run `make`:

```
BR2_PACKAGE_HELLO_WORLD=y
```

After building, on the BeagleBone Black:

```bash
hello-world
Hello from BeagleBone Black!
```

See `doc/custom-packages.md` for full documentation including autotools/cmake
packages, dependencies, and naming rules.

## Out-of-Tree Kernel Modules

The `kmodules/` directory holds custom Linux kernel modules that build against
the Buildroot-built kernel and install into the target rootfs as `.ko` files.

### Layout

```
kmodules/
├── Config.in                   # menu grouping; lists each module
└── kmod-<name>/                # directory name becomes the buildroot package name
    ├── Config.in               # BR2_PACKAGE_KMOD_<NAME> Kconfig entry
    ├── kmod-<name>.mk          # Buildroot package definition (KMOD_<NAME>_* vars)
    ├── Kbuild                  # obj-m := <name>.o
    └── <name>.c                # module source → <name>.ko
```

**The `kmod-` directory prefix is required.** Buildroot derives the package
name from the directory name (`pkg-utils.mk:45`), and variable prefixes in
the `.mk` file must match. A mismatch causes the package to silently fail
to build.

Flat structure — no kernel-version or board-name nesting. The kernel version
is already pinned in `defconfig`, and board-specific behavior belongs in
device tree bindings, not directory layout. For version-conditional code,
use `#ifdef LINUX_VERSION_CODE` in the source.

### How it works

`external.mk` auto-includes every `kmodules/*/*.mk` via a wildcard. Each
module uses Buildroot's `kernel-module` infrastructure, which builds it
against the configured kernel and installs into
`/lib/modules/<version>/updates/` with `depmod` run automatically.

### Adding a module

```bash
make menuconfig    # External options → Out-of-tree kernel modules → kmod-<name>
make               # builds kernel + module + rootfs
```

On the BBB:

```bash
modprobe <name>
dmesg | tail
lsmod | grep <name>
```

### Fast iteration

For live-reloading a module without rebuilding the rootfs or rebooting:

```bash
./scripts/deploy-kmod.sh kmod-hello <board-ip>   # build + scp + insmod + dmesg tail
```

See `doc/kernel-modules.md` for the full walkthrough including the
`hello` example, naming conventions, all three deploy levels (OTA /
manual scp / scripted), and troubleshooting.

### Version bumping

Edit `BUNDLE_VERSION` in `board/bbb/post-image.sh`, then rebuild with `make bundle`.

## Project Structure

```
├── Makefile                    # wrapper around buildroot
├── defconfig                   # board configuration (tracked in git)
├── external.desc               # BR2_EXTERNAL tree descriptor
├── external.mk                 # auto-includes all package/*/*.mk
├── Config.in                   # sources each custom package's Kconfig
├── board/bbb/
│   ├── boot.cmd                # U-Boot A/B boot script (RAUC bootchooser)
│   ├── busybox.fragment        # BusyBox config additions
│   ├── linux.fragment          # kernel config additions (SquashFS, NBD, systemd)
│   ├── uboot.fragment          # U-Boot config additions (raw MMC env, setexpr)
│   ├── genimage.cfg            # A/B partition layout
│   ├── post-build.sh           # rootfs post-build hooks (systemd units, network)
│   ├── post-image.sh           # image generation + RAUC bundle packaging
│   ├── system.conf             # RAUC system configuration
│   ├── rauc-keys/              # development signing keys
│   │   ├── development-1.cert.pem
│   │   └── development-1.key.pem
│   └── rootfs-overlay/
│       └── etc/
│           └── fw_env.config   # U-Boot env access config
├── package/                    # custom external packages (see doc/custom-packages.md)
│   └── hello-world/            # example: minimal C program
├── patches/                    # per-package patches (see doc/package-customization.md)
├── scripts/                    # helper scripts (deploy, deploy-kmod, reset)
│   ├── deploy.sh               # build + upload + install OTA bundle
│   ├── deploy-kmod.sh          # build + scp + insmod a single kernel module (no OTA)
│   └── reset.sh                # USB power-cycle BBB via uhubctl
├── tests/                      # labgrid integration tests (pytest)
├── doc/                        # documentation (see doc/package-customization.md)
├── buildroot/                  # buildroot submodule
└── output/                     # build output (gitignored)
```
