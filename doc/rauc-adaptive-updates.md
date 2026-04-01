# RAUC Adaptive Updates

## What

Enable RAUC adaptive updates using the `block-hash-index` method. This allows
RAUC to skip writing blocks that already exist on the target during installation,
reducing I/O and install time. When combined with HTTP streaming (requires verity
bundle format, not yet supported by our RAUC 1.15.2), it also reduces download size.

## Why

A full rootfs image is ~256 MB. With adaptive updates, RAUC compares block hashes
between the bundle and existing slot contents, skipping identical blocks. For local
installs this reduces write I/O; for future HTTP streaming it will reduce download
size to roughly 10% of the bundle for small changes.

Unlike delta updates (which require a specific "from" version), adaptive updates
work from *any* previous version. The bundle remains a complete, self-contained
image — adaptive mode is purely an optimization.

## How It Works

1. **Bundle creation**: `rauc bundle` generates a SHA256 hash index for each
   4 KiB block in the rootfs image. This index (~0.8% overhead) is embedded in
   the bundle alongside the full image.

2. **Installation**: RAUC checks each block hash against data already on the
   target (both rootfs slots). Matching blocks are read locally instead of from
   the bundle, reducing disk writes.

3. **Index persistence**: After installation, RAUC stores the block-hash index
   in `/data/rauc/` (the `data-directory`). On the next update, this index is
   used directly instead of being regenerated from the slot contents.

## Changes Made

### 1. Kernel: NBD support (`board/bbb/linux.fragment`)

RAUC HTTP streaming uses a Network Block Device internally to convert NBD read
requests into HTTP Range Requests:

```
CONFIG_BLK_DEV_NBD=y
```

### 2. Buildroot: enable streaming (`defconfig`)

```
BR2_PACKAGE_RAUC_STREAMING=y
```

### 3. RAUC system config (`board/bbb/system.conf`)

Added to `[system]`:

```ini
data-directory=/data/rauc    # persistent storage for adaptive indices
```

Added `[streaming]` section:

```ini
[streaming]
send-headers=boot-id;system-version
```

### 4. Bundle manifest (`board/bbb/post-image.sh`)

Added `adaptive=block-hash-index` to the `[image.rootfs]` section of the
generated manifest:

```ini
[image.rootfs]
filename=rootfs.ext4
type=ext4
adaptive=block-hash-index
```

Bundle is built with `--mksquashfs-args="-b 64k"` (smaller squashfs blocks
improve deduplication granularity for adaptive updates).

### 5. Data partition mount (`board/bbb/post-build.sh`)

The data partition (`/dev/mmcblk0p4`, 128 MB) is mounted at `/data` via fstab.
The `/data/rauc/` directory is where RAUC stores:
- `central.raucs` — slot status for all slots
- Block-hash indices for each slot

### 6. Partition layout (unchanged)

The existing `genimage.cfg` already has a 128 MB data partition:

```
partition data {
    partition-type = 0x83
    image = "data.ext4"
    size = 128M
}
```

## Usage

### Building the bundle

```bash
make          # builds sdcard.img + update.raucb
make bundle   # rebuild bundle only
```

### Installing locally

```bash
# Copy bundle to BBB, then:
rauc install /tmp/update.raucb
```

RAUC will automatically compare block hashes against existing slot contents
and skip writing blocks that are already present.

### Installing via HTTP streaming (future)

HTTP streaming requires verity bundle format (`format=verity` in the manifest),
which is not supported by our current RAUC 1.15.2. Once RAUC is upgraded:

1. Add `format=verity` to the `[update]` section of the manifest
2. Add `bundle-formats=-plain` to system.conf `[system]` section
3. Host bundle on any HTTP server with Range Request support
4. Install with: `rauc install https://server/update.raucb`

The kernel NBD support and `[streaming]` config are already in place for this.

## Prerequisites

- Kernel must have **NBD support** (added to linux.fragment, for future streaming)
- `/data` partition must be mounted and writable
- RAUC streaming enabled in buildroot (`BR2_PACKAGE_RAUC_STREAMING=y`)

## Notes

- First adaptive install on a fresh system will be slower (RAUC generates the
  index on-demand for existing slot contents). Subsequent installs use the
  cached index.
- squashfs block size of 64k (`--mksquashfs-args="-b 64k"`) is a trade-off:
  smaller blocks = finer-grained deduplication but slightly larger bundle.
- To enable full HTTP streaming in the future, upgrade RAUC to a version that
  supports verity bundle format (1.8+).
