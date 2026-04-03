# Package Customization: Patches and Config Overrides

How to customize individual Buildroot packages (htop, dropbear, etc.) using
the BR2_EXTERNAL mechanism — without modifying the buildroot submodule.

## Two Types of Packages

Buildroot packages fall into two categories, and the customization approach
differs:

| Type | Examples | Config mechanism | Customization |
|------|----------|------------------|---------------|
| **kconfig-based** | linux, uboot, busybox, barebox | `.config` / menuconfig | Config fragments |
| **autotools/meson/cmake** | htop, dropbear, curl, etc. | `./configure` / meson options | `CONF_OPTS` in `external.mk` |

Config fragments **only work for kconfig-based packages**. For everything else,
use patches and/or build option overrides.

## Patches

Buildroot automatically applies patches from `<BR2_EXTERNAL>/patches/<package>/`
to any package. This is configured via `BR2_GLOBAL_PATCH_DIR` in the defconfig:

```
BR2_GLOBAL_PATCH_DIR="board/beagleboard/beaglebone/patches $(BR2_EXTERNAL_BBB_PATH)/patches"
```

### Directory layout

```
patches/
  htop/
    0001-fix-something.patch
    0002-add-feature.patch
  dropbear/
    0001-custom-banner.patch
  <any-package>/
    ...
```

Patches are applied **sorted by filename** after Buildroot extracts the package
source. Use the `NNNN-description.patch` naming convention.

### Creating a patch

```bash
# 1. Extract the package source
make htop-extract

# 2. Make your changes in the source tree
cd output/build/htop-<version>/
# edit files...

# 3. Generate a patch (from the package source root)
#    Option A: manual diff
diff -u file.c.orig file.c > ../../../patches/htop/0001-describe-change.patch

#    Option B: git format-patch (if you init a repo in the source tree)
git init && git add -A && git commit -m "baseline"
# make changes...
git add -A && git commit -m "describe change"
git format-patch -1 -o ../../../patches/htop/

# 4. Clean rebuild to verify the patch applies
make htop-dirclean && make
```

### Version handling

Patches are **not** version-specific — they apply to whatever package version is
selected in defconfig. When you bump a package version, patches that no longer
apply will fail the build. This is intentional: it forces you to review and
update your patches for the new version.

There is no per-version subdirectory structure. Buildroot does not support it,
and a build failure on version bump is a clearer signal than silently skipping
stale patches.

## Config Fragments (kconfig packages only)

Config fragments work for packages that use the Linux kconfig system:

| Package | Fragment file | menuconfig target |
|---------|--------------|-------------------|
| Linux kernel | `board/bbb/linux.fragment` | `make linux-menuconfig` |
| U-Boot | `board/bbb/uboot.fragment` | `make uboot-menuconfig` |
| BusyBox | `board/bbb/busybox.fragment` | `make busybox-menuconfig` |

A fragment contains only the options you want to **override** on top of the
package's default config. Buildroot merges fragments with the base config using
`support/kconfig/merge_config.sh` and then runs `olddefconfig`.

Example (`board/bbb/linux.fragment`):

```
CONFIG_SQUASHFS=y
CONFIG_BLK_DEV_NBD=y
```

When you change a fragment, the Makefile's auto-rebuild logic detects it and
triggers a rebuild of the affected package.

## Build Option Overrides (`external.mk`)

For non-kconfig packages, you can append or override configure/meson/cmake
options in `external.mk`:

```makefile
# Add custom meson options to htop
HTOP_CONF_OPTS += -Dcap=disabled

# Add custom autotools options to dropbear
DROPBEAR_CONF_OPTS += --disable-wtmp
```

These variables follow Buildroot's naming convention: `<PACKAGE>_CONF_OPTS`
(package name uppercased, hyphens replaced with underscores).

## Complete Layout

```
/src/bbb-buildroot/                   (BR2_EXTERNAL root)
  patches/
    htop/                              patches for htop
      0001-fix-foo.patch
    <any-package>/                     patches for any package
  board/bbb/
    linux.fragment                     kconfig fragment (linux)
    uboot.fragment                     kconfig fragment (uboot)
    busybox.fragment                   kconfig fragment (busybox)
  external.mk                         CONF_OPTS overrides
  defconfig                            main buildroot config
```

## Summary

- **Want to change source code?** Add a patch under `patches/<package>/`
- **Want to toggle a kconfig option?** Add it to the package's fragment file
- **Want to change build flags?** Add `<PKG>_CONF_OPTS` to `external.mk`
- **Never modify files inside `buildroot/`** — use the external tree mechanisms
