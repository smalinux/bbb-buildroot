# Persistent Downloads, Toolchain, and Ccache

## What

`BR2_DL_DIR`, `BR2_HOST_DIR`, and `BR2_CCACHE_DIR` are pointed to `dl/`,
`host/`, and `ccache/` in the project root (outside `output/`), so they
survive when `output/` is deleted.

## Why

A full `rm -rf output/ && make` previously forced Buildroot to re-download
every source tarball and rebuild the entire cross-toolchain from scratch.
By moving these directories outside `output/`:

- **`dl/`** (downloads) — cached source tarballs persist across rebuilds.
- **`toolchain/`** (toolchain + host tools) — the cross-compiler and all host
  utilities persist. Deleting `output/` still forces a target rebuild but
  skips the expensive toolchain compilation.
- **`ccache/`** (compiler cache) — cached object files persist. Even after
  deleting `output/build/`, recompilation of C/C++ packages is near-instant
  because ccache serves the previously compiled objects.

## How it works

In `defconfig`:

```
BR2_DL_DIR="$(BR2_EXTERNAL_BBB_PATH)/dl"
BR2_HOST_DIR="$(BR2_EXTERNAL_BBB_PATH)/toolchain"
BR2_CCACHE=y
BR2_CCACHE_DIR="$(BR2_EXTERNAL_BBB_PATH)/ccache"
BR2_CCACHE_USE_BASEDIR=y
```

`BR2_EXTERNAL_BBB_PATH` resolves to the project root (the BR2_EXTERNAL
directory named `BBB` in `external.desc`), keeping paths portable.

`BR2_CCACHE_USE_BASEDIR=y` makes cache hits work even if the absolute
build path changes (e.g. different checkout location).

## Selective rebuilds

| Action | Effect |
|--------|--------|
| `rm -rf output/target && make` | Rebuild rootfs only (fastest) |
| `rm -rf output/ && make` | Rebuild everything except downloads, toolchain, and ccache |
| `rm -rf toolchain/ && make` | Force toolchain rebuild (ccache still speeds it up) |
| `rm -rf ccache/ && make` | Force cold recompilation |
| `rm -rf dl/ && make` | Force re-download of all sources |

## Ccache stats

```bash
# Check cache hit rate and size
make ccache-stats
```
