# Restore Kernel Log Verbosity & Increase rootfs Size

## What

Two configuration changes:

1. **Kernel console loglevel restored to 7 (KERN_DEBUG)** — previously lowered
   to 4 (KERN_WARNING) to suppress verbose inode messages during RAUC installs.
   Reverted so all kernel messages are visible on the console for debugging.

2. **Root filesystem size increased from 60 MB to 256 MB** — the default 60 MB
   was too small once additional packages (RAUC, Dropbear, etc.) were added,
   causing build failures or a nearly-full rootfs with no room for runtime data.

## Why

- **Loglevel**: During development, full kernel logs are essential for
  diagnosing boot issues, driver failures, and RAUC slot-switching problems.
  The suppression can be re-applied for production builds later.

- **Rootfs size**: With SquashFS, RAUC, networking, and SSH packages enabled,
  the 60 MB ext4 image was running out of space. 256 MB provides comfortable
  headroom for development.

## How

### Kernel loglevel

Changed in `board/bbb/linux.fragment`:

```
CONFIG_CONSOLE_LOGLEVEL_DEFAULT=7
```

This is applied as a kernel config fragment on top of `omap2plus_defconfig`.

### Rootfs size

Changed in `defconfig`:

```
BR2_TARGET_ROOTFS_EXT2_SIZE="256M"
```

## Notes

- The loglevel can also be overridden at runtime: `dmesg -n 7` or via kernel
  command line `loglevel=7` in `boot.cmd`.
- For production, consider reducing `CONFIG_CONSOLE_LOGLEVEL_DEFAULT` back to 4
  and sizing the rootfs closer to actual usage.
