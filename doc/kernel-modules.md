# Out-of-Tree Kernel Modules

How to add your own Linux kernel modules that live outside the kernel source
tree, build against the Buildroot-built kernel, and install into the target
rootfs automatically.

## Why out-of-tree

In-tree modules (under `linux/drivers/...`) require modifying the kernel source,
which couples your driver to a specific kernel fork and makes upstreaming
harder. Out-of-tree modules:

- Live in their own directory, versioned independently of the kernel
- Build against any kernel version via the kernel build system (`make M=...`)
- Can be developed, tested, and iterated without touching kernel sources
- Are the standard workflow for drivers that haven't been merged yet

## Directory layout

All out-of-tree modules live under `kmodules/` at the project root:

```
kmodules/
├── Config.in                   # menu grouping; lists each module
└── kmod-<name>/                # directory MUST start with "kmod-"
    ├── Config.in               # BR2_PACKAGE_KMOD_<NAME> Kconfig entry
    ├── kmod-<name>.mk          # Buildroot package definition
    ├── Kbuild                  # kernel build file (obj-m := <name>.o)
    └── <name>.c                # module source
```

**Directory naming rule:** buildroot derives the package name from the
directory name (see `buildroot/package/pkg-utils.mk:45-46`). The
directory `kmod-<name>/` becomes package `kmod-<name>`, which means
`.mk` variables must be prefixed `KMOD_<NAME>_*` (uppercased, hyphens →
underscores). A mismatch between directory name and variable prefix
causes the package to silently fail to build.

### Why flat (no version/board nesting)?

An earlier design considered `kmodules/<kernel-version>/<name>/` or
`kmodules/<board>/<name>/`. Both were rejected:

- **Kernel version** is already pinned globally in `defconfig`
  (`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`). Buildroot builds modules
  against exactly one kernel per build. Version directories would add
  nesting for a dimension that's fixed project-wide.
  For version-conditional code, use `#ifdef LINUX_VERSION_CODE` in the
  source — that's the idiomatic kernel approach.
- **Board name** isn't a module-level concern. Modules depend on the
  kernel API; board-specific behavior is expressed through device tree
  bindings, not directory layout.

Flat keeps the structure simple and mirrors the userspace `package/`
convention, so the mental model transfers.

## How it's wired up

Two pieces glue `kmodules/` into Buildroot:

1. **`external.mk`** (project root) — auto-includes every
   `kmodules/*/*.mk` via a wildcard. Adding a new module directory is
   enough; no editing required here.
2. **`kmodules/Config.in`** — a `menu` block that sources each module's
   `Config.in`. Add one `source` line per new module. The root `Config.in`
   sources this file once, so all modules appear under
   "External options → Out-of-tree kernel modules" in menuconfig.

Each module uses Buildroot's `kernel-module` infrastructure, which:

- Adds an automatic dependency on the kernel being built
- Runs `make -C $(LINUX_DIR) M=$(@D) modules` against the kernel source
- Installs the resulting `.ko` files into
  `/lib/modules/<version>/updates/` on the target
- Runs `depmod` so `modprobe` can find them

## Adding a new module

### 1. Create the directory

```bash
mkdir -p kmodules/kmod-mydriver
```

The `kmod-` prefix is required — buildroot's package name comes from
the directory name, and the `.mk` variables must match.

### 2. Write the source (`kmodules/kmod-mydriver/mydriver.c`)

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int __init mydriver_init(void)
{
    pr_info("mydriver: loaded\n");
    return 0;
}

static void __exit mydriver_exit(void)
{
    pr_info("mydriver: unloaded\n");
}

module_init(mydriver_init);
module_exit(mydriver_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Description of mydriver");
MODULE_VERSION("1.0");
```

### 3. Write the Kbuild file (`kmodules/kmod-mydriver/Kbuild`)

```makefile
obj-m := mydriver.o
```

For multi-file modules:

```makefile
obj-m := mydriver.o
mydriver-y := main.o helpers.o ioctl.o
```

### 4. Write the Buildroot package file (`kmodules/kmod-mydriver/kmod-mydriver.mk`)

```makefile
################################################################################
#
# kmod-mydriver
#
################################################################################

KMOD_MYDRIVER_VERSION = 1.0
KMOD_MYDRIVER_SITE = $(BR2_EXTERNAL_BBB_PATH)/kmodules/kmod-mydriver
KMOD_MYDRIVER_SITE_METHOD = local
KMOD_MYDRIVER_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))
```

**Naming convention:**
- Directory name: `kmod-<name>` (lowercase, hyphens allowed in `<name>`)
- `.mk` filename: `kmod-<name>.mk` (matches directory)
- Package variable prefix: `KMOD_<NAME>` with hyphens in `<name>`
  replaced by underscores and uppercased (e.g., directory
  `kmod-my-driver` → prefix `KMOD_MY_DRIVER`)
- Resulting `.ko` filename: matches the `obj-m` value in `Kbuild`
  (does NOT need the `kmod-` prefix — `obj-m := mydriver.o` gives
  `mydriver.ko`, loaded via `modprobe mydriver`)

### 5. Write the Kconfig entry (`kmodules/kmod-mydriver/Config.in`)

```kconfig
config BR2_PACKAGE_KMOD_MYDRIVER
	bool "kmod-mydriver"
	depends on BR2_LINUX_KERNEL
	help
	  Description of what the module does.
```

The `depends on BR2_LINUX_KERNEL` is required — out-of-tree modules
need a kernel to build against.

### 6. Register it in `kmodules/Config.in`

Add one line:

```kconfig
source "$BR2_EXTERNAL_BBB_PATH/kmodules/kmod-mydriver/Config.in"
```

### 7. Enable and build

```bash
make menuconfig
# → External options → Out-of-tree kernel modules → kmod-mydriver
make
```

Or skip menuconfig by adding `BR2_PACKAGE_KMOD_MYDRIVER=y` to `defconfig`
and running `make`.

## Loading modules on target

After flashing or OTA update, log in to the BBB:

```bash
# Load the module
modprobe mydriver

# Verify it loaded
lsmod | grep mydriver
dmesg | tail

# Unload
rmmod mydriver
```

Modules are installed under `/lib/modules/<kernel-version>/updates/` and
indexed by `depmod`, so `modprobe <name>` works without a full path.

### Auto-load at boot

To load a module at every boot, add its name to
`/etc/modules-load.d/<name>.conf` via the rootfs overlay:

```bash
mkdir -p board/bbb/rootfs-overlay/etc/modules-load.d
echo mydriver > board/bbb/rootfs-overlay/etc/modules-load.d/mydriver.conf
```

## Fast iteration workflow

Three levels of rebuild/deploy speed, from slowest to fastest.

### Building a single module

```bash
make kmod-hello               # first build (compiles once, stamps done)
make kmod-hello-rebuild       # incremental rebuild — always runs kbuild
make kmod-hello-dirclean      # wipe build dir, full rebuild next time
```

`<pkg>-rebuild` is the workhorse during development: it re-rsyncs the
source from `kmodules/<pkg>/`, invokes `make -C $(LINUX_DIR) M=... modules`,
and installs the resulting `.ko` into `output/target/lib/modules/<ver>/updates/`.
Takes a few seconds on incremental edits.

After rebuild, the artifacts live in two places:

| Path | Symbols | Notes |
|---|---|---|
| `output/build/kmod-hello-1.0/hello.ko` | full | freshly built, for live deploy + debugging |
| `output/target/lib/modules/<ver>/updates/hello.ko` | stripped | what ends up in the RAUC bundle |

### Level 1 — OTA (full rebuild + reboot)

Good for verifying the rootfs integration. Slow.

```bash
make bundle
./scripts/deploy.sh                     # uses BOARD from config (make bbb)
./scripts/deploy.sh <board-ip>          # or pass IP explicitly
```

### Level 2 — direct scp (no OTA, no reboot)

Manual version. Grabs the unstripped `.ko` from `output/build/`:

```bash
make kmod-hello-rebuild
scp output/build/kmod-hello-1.0/hello.ko root@<bbb>:/root/
ssh root@<bbb> "rmmod hello 2>/dev/null; insmod /root/hello.ko; dmesg | tail"
```

Note: `insmod` takes a **full path** and does NOT use `/lib/modules/`
indexing, so you can load an updated `.ko` even though an older copy
lives in the rootfs. `modprobe hello` would load the rootfs copy — use
`insmod /root/hello.ko` to explicitly load the fresh one. `/root/` is
bind-mounted to `/data/root/` by the data-persist service, so the copy
survives reboots (useful for manual reloading without re-scp'ing).

### Level 3 — `deploy-kmod.sh` (scripted)

The same steps wrapped in a script. Handles rebuild, locating the `.ko`,
scp, rmmod/insmod, and dmesg tail:

```bash
./scripts/deploy-kmod.sh kmod-hello              # uses BOARD from config (make bbb)
./scripts/deploy-kmod.sh kmod-hello <board-ip>   # or pass IP explicitly
```

If the package produces multiple `.ko` files, pass the module name
explicitly as the third argument:

```bash
./scripts/deploy-kmod.sh kmod-mydriver <board-ip> mydriver
```

Output on success:

```
==> Building kmod-hello...
==> Module: hello (from output/build/kmod-hello-1.0/hello.ko)
==> Uploading to 192.168.1.100:/root/hello.ko...
==> Reloading on board...
[   ...] hello: loaded on BeagleBone Black (built for 6.19.0-rc8, era 6.11+)
==> Done. Module 'hello' is loaded on 192.168.1.100.
```

### When to use which

| You want to... | Use |
|---|---|
| Test the full OTA flow before shipping | Level 1 (OTA) |
| Iterate on a driver while attaching gdb/kgdb | Level 2 or 3 (has symbols) |
| Just re-load the module fast during dev | Level 3 (scripted) |
| Verify depmod/modules.dep integration | Level 1 (OTA) — Level 2/3 bypass it |

## Handling kernel version differences

Kernel APIs change between versions. A module that compiled against 6.1
may fail on 6.11 because a function signature changed, a header moved,
or a type was renamed. The idiomatic response is **compile-time shims
in the source**, not forked directories per kernel version.

### The `LINUX_VERSION_CODE` pattern

Include `<linux/version.h>` and gate version-sensitive code with
`KERNEL_VERSION(x,y,z)` comparisons:

```c
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
/* new API — platform_driver.remove returns void */
static void my_remove(struct platform_device *pdev)
{
	do_cleanup(pdev);
}
#else
/* old API — returns int */
static int my_remove(struct platform_device *pdev)
{
	do_cleanup(pdev);
	return 0;
}
#endif

static struct platform_driver my_driver = {
	.probe  = my_probe,
	.remove = my_remove,
	/* ... */
};
```

The kernel's `include/linux/version.h` defines `LINUX_VERSION_CODE` as
a packed integer (major × 65536 + minor × 256 + patch), so numeric
comparisons work directly.

### Identifying the kernel at build time

Use `<generated/utsrelease.h>` → `UTS_RELEASE` to embed the exact
kernel version string the module was built against:

```c
#include <generated/utsrelease.h>

pr_info("mydriver: built for kernel %s\n", UTS_RELEASE);
```

The `hello` module demonstrates both patterns — see
`kmodules/kmod-hello/hello.c`.

### When to use a `compat.h`

If a module touches many version-sensitive APIs, the `#if` blocks
clutter the driver logic. Extract them into a `compat.h` header that
defines stable wrappers:

```c
/* kmodules/mydriver/compat.h */
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
#define COMPAT_REMOVE_RETURN void
#define COMPAT_REMOVE_RETURN_VAL(x)
#else
#define COMPAT_REMOVE_RETURN int
#define COMPAT_REMOVE_RETURN_VAL(x) return (x)
#endif
```

```c
/* kmodules/mydriver/mydriver.c */
#include "compat.h"

static COMPAT_REMOVE_RETURN my_remove(struct platform_device *pdev)
{
	do_cleanup(pdev);
	COMPAT_REMOVE_RETURN_VAL(0);
}
```

The `zfs-linux`, `nvidia`, and DKMS-style drivers all use this pattern
for modules that support many kernel versions.

### What NOT to do

- **Don't fork the directory per kernel version.** `kmodules/6.1.x/`
  and `kmodules/6.18.x/` diverge over time; fixes land in one copy and
  not the other. Buildroot only compiles against one kernel at a time
  anyway.
- **Don't pin to one kernel and hope.** If you're upgrading the kernel,
  actually test your modules against the new version and add compat
  shims for anything that broke.

See `doc/kernel-modules-versioning.md` for the full design rationale,
including how to handle multi-board enablement via per-board defconfigs.

## Troubleshooting

### Module build fails with "No such file or directory: .../Kbuild"

Your `Kbuild` file is missing or misnamed. It must be exactly `Kbuild`
(capital K) in the module directory.

### "Unknown symbol in module" at load time

The module was built against a different kernel config/version than what
is running. Rebuild from scratch:

```bash
make kmod-mydriver-dirclean && make
```

### Module doesn't appear in `modprobe`

`depmod` wasn't run, or the module isn't in `/lib/modules/<ver>/updates/`.
Check:

```bash
find /lib/modules -name "mydriver.ko"
depmod -a
```

### Module symbols not exported for other modules

Use `EXPORT_SYMBOL(func)` or `EXPORT_SYMBOL_GPL(func)` in your source.
Without this, dependent modules get "Unknown symbol" errors.

## Reference

- Buildroot kernel-module infra:
  `buildroot/package/pkg-kernel-module.mk`
- Kernel documentation on out-of-tree modules:
  `linux/Documentation/kbuild/modules.rst`
