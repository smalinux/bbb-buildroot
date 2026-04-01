# make rebuild — Clean Rootfs Without Recompiling

## Problem

Buildroot's incremental build only adds and updates files in `output/target/`.
When you disable a package in `make menuconfig`, its files remain in the
rootfs until you clean them out. A full `make clean` works but forces a
complete recompile of everything (toolchain, kernel, all packages), which
takes a long time.

## Solution

```
make rebuild
```

This target:

1. Deletes `output/target/` (the assembled root filesystem)
2. Deletes all `.stamp_target_installed` files in `output/build/`
3. Runs `make all`

The result is a fresh rootfs with only currently-enabled packages, built in
minutes instead of hours because all packages are already compiled — only the
install-to-target step is re-run.

## Why the stamp files matter

Buildroot tracks each package's install state with stamp files:

```
output/build/<package>-<version>/.stamp_target_installed
```

If `output/target/` is deleted but these stamps remain, buildroot thinks
packages are already installed and skips them. This causes failures like:

```
/usr/bin/sed: can't read output/target/etc/inittab: No such file or directory
```

The `skeleton` package creates the base filesystem layout (`/etc/inittab`,
`/dev/`, `/proc/`, etc.). Without clearing its stamp, it never re-runs and
the target directory stays empty.

## When to use

| Scenario | Command |
|----------|---------|
| Disabled a package in menuconfig | `make rebuild` |
| Switched init system | `make rebuild` |
| Changed rootfs overlay files | `make rebuild` |
| Rootfs has stale files from old config | `make rebuild` |
| Normal development (code changes) | `make` (incremental, faster) |
| Everything is broken | `make clean && make` (full recompile) |

## Typical workflow

```bash
make menuconfig          # disable htop (or whatever), save, exit
make rebuild             # clean rootfs, reinstall all enabled packages
```

## Comparison

| Target | Deletes | Recompiles | Time |
|--------|---------|-----------|------|
| `make` | nothing | only changed packages | seconds-minutes |
| `make rebuild` | `output/target/` + install stamps | nothing (reinstalls only) | minutes |
| `make clean` | entire `output/` | everything from scratch | hours |
