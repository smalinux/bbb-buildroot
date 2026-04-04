# Kernel Modules: Handling Multiple Kernel Versions and Boards

Design rationale for how the `kmodules/` tree handles two variability
dimensions: kernel API drift between versions, and differences between
target boards.

## The question

Out-of-tree modules face a tension: kernel APIs change between versions,
and boards differ in which hardware exists. A naive response is to nest
the source tree by these axes:

```
kmodules/
├── 6.1.x/
│   └── hello/...
├── 6.18.x/
│   └── hello/...
└── bbb/
    └── my-driver/...
```

This scales poorly. The actual right answer is the idiomatic kernel
practice: one source tree per module, with compile-time shims for version
differences, and defconfig-per-board for enablement differences.

## Against version-nested subdirectories

**Per-kernel-version copies** (`kmodules/<version>/<name>/`):

- **Drift** — bug fixes and features diverge between copies; no single
  source of truth. The longer the copies live, the worse the divergence.
- **Redundant storage** — buildroot builds against exactly one kernel at
  a time (pinned in `defconfig` via `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`).
  Only one copy is ever compiled. The rest is dead weight.
- **Unbounded growth** — each kernel bump adds a new subdirectory forever.
- **Proprietary-blob pattern** — this is how vendor BSPs (Realtek, MediaTek)
  ship their out-of-tree WiFi trees, and they are famously painful to
  maintain.

## Against board-nested subdirectories

**Per-board copies** (`kmodules/<board>/<name>/`):

- A correct driver doesn't know what board it's on. It binds to a
  hardware device through a **device tree `compatible` string**. If the
  same chip appears on two boards, the same driver serves both — the DTS
  decides whether to instantiate it.
- Genuinely board-specific driver code almost never exists in a
  well-designed driver. When it does, it's usually a device tree design
  failure that should be fixed by expressing the difference as DT
  properties, not C code.
- What **does** vary per board: **which modules you enable**, not the
  module source. That's a `defconfig` concern.

## The idiomatic approach

### Kernel API drift → compile-time shims

Use `LINUX_VERSION_CODE` + the `KERNEL_VERSION(x,y,z)` macro from
`<linux/version.h>` to gate version-sensitive code. Example (from a
real kernel API break — `platform_driver.remove` changed return type
to `void` in 6.11):

```c
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
static void my_remove(struct platform_device *pdev) {
	/* new signature: returns void */
}
#else
static int my_remove(struct platform_device *pdev) {
	/* old signature: returns int */
	return 0;
}
#endif
```

For modules that touch many version-sensitive APIs, extract the shims
into a dedicated `compat.h` so the driver's business logic stays
readable. That's the pattern nvidia, zfs, and most long-lived
out-of-tree drivers use.

### Board enablement → per-board defconfig

When this project grows beyond BBB, adopt the buildroot-standard
pattern: create `configs/<board>_defconfig` for each board. Each
defconfig selects which `BR2_PACKAGE_KMOD_*` to enable. Identical
kernel module sources serve every board; only the *set* of enabled
modules varies.

The Makefile would then accept a `BOARD=<name>` variable that picks
which defconfig to copy into `output/.config` at first build. This is
infrastructure worth adding **at the moment a second board shows up**,
not preemptively.

### Genuinely independent hardware → separate modules

If you're bringing up an entirely different chip for a different board
(not a variant of the same driver), that's a **new module** at the top
level:

```
kmodules/
├── rtl8188/
└── ath9k-htc/
```

Each is its own buildroot package with its own `BR2_PACKAGE_KMOD_*`
Kconfig, enabled on the boards that need it. Flat, explicit.

## When nesting at the top level is OK

If you have two **forks** of the same driver that cannot be unified
(e.g., a clean upstream-style implementation plus a vendor BSP fork
that depends on board hacks), name them at the top level:

```
kmodules/
├── my-wifi-upstream/     # clean, upstream-style
└── my-wifi-vendor/       # vendor BSP fork with board hacks
```

Each is a separate buildroot package. The Kconfig `depends on` /
`choice` blocks can enforce that only one is enabled at a time.

## Rules for this project

1. **Structure stays flat.** `kmodules/<name>/` — no version or board
   subdirectories.
2. **Version differences live in source code.** Use
   `LINUX_VERSION_CODE` conditionals, or a `compat.h` header for heavy
   users. The `hello` example demonstrates the minimal pattern.
3. **Board differences live in defconfig + device tree.** When a second
   board appears, introduce `configs/<board>_defconfig`. Don't duplicate
   module sources.
4. **Forks are separate top-level modules.** Never shadow the same
   module name at a nested level.
5. **When in doubt, read how long-lived out-of-tree drivers solve it.**
   nvidia, zfs-linux, and dkms-based drivers are the reference.

## See also

- `doc/kernel-modules.md` — step-by-step guide to adding a module
- `kmodules/kmod-hello/hello.c` — minimal example with version compat shim
- `linux/Documentation/kbuild/modules.rst` — upstream kbuild docs
