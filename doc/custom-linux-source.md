# Using Local Source Trees (OVERRIDE_SRCDIR)

## What

Buildroot's `OVERRIDE_SRCDIR` mechanism lets you build any package from a local source
directory instead of downloading it. The local tree is rsynced into the build directory
as-is — no download, no clone, no commit required.

## Why

This is useful during active development of a package (kernel, htop, etc.). You edit
files locally and rebuild immediately without waiting for Buildroot to fetch anything.

## How

Add `<PKG>_OVERRIDE_SRCDIR` entries to `local.mk` at the project root. The variable
name is the package name uppercased with hyphens replaced by underscores.

```makefile
# local.mk
LINUX_OVERRIDE_SRCDIR = /src/linux-bbb
HTOP_OVERRIDE_SRCDIR  = /path/to/your/htop
```

The defconfig points to this file via:

```
BR2_PACKAGE_OVERRIDE_FILE="$(BR2_EXTERNAL_BBB_PATH)/local.mk"
```

When an override is set, Buildroot ignores the package's configured version/URL and
rsyncs the local directory into `output/build/<pkg>-custom/` instead.

## Rebuilding

After modifying files in the local source tree, just run:

```bash
make                    # auto-detects changes and triggers <pkg>-rebuild
```

The top-level Makefile parses `local.mk` for all `_OVERRIDE_SRCDIR` entries and uses
`find -newer` against a stamp file to detect source changes. If any source file
(`.c`, `.h`, `.S`, `.dts`, `Makefile`, `Kconfig`, etc.) is newer than the last build
stamp, it automatically runs `<pkg>-rebuild` before the main build. No manual
`linux-rebuild` needed.

You can still force a rebuild manually:

```bash
make linux-rebuild      # force re-rsync and rebuild
```

## Finding the variable name

The variable name follows the pattern `<PKG>_OVERRIDE_SRCDIR` where `<PKG>` is the
Buildroot package name uppercased with hyphens as underscores. Examples:

| Package    | Variable                    |
|------------|-----------------------------|
| linux      | `LINUX_OVERRIDE_SRCDIR`     |
| htop       | `HTOP_OVERRIDE_SRCDIR`      |
| busybox    | `BUSYBOX_OVERRIDE_SRCDIR`   |
| libcurl    | `LIBCURL_OVERRIDE_SRCDIR`   |
| host-rauc  | `HOST_RAUC_OVERRIDE_SRCDIR` |

## Switching back to upstream

Remove or comment out the line in `local.mk`:

```makefile
# LINUX_OVERRIDE_SRCDIR = /src/linux-bbb
```
