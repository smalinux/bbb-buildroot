# Persistent Downloads, Toolchain, Ccache, and Parallel Builds

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
BR2_PER_PACKAGE_DIRECTORIES=y
```

`BR2_EXTERNAL_BBB_PATH` resolves to the project root (the BR2_EXTERNAL
directory named `BBB` in `external.desc`), keeping paths portable.

`BR2_CCACHE_USE_BASEDIR=y` makes cache hits work even if the absolute
build path changes (e.g. different checkout location).

`BR2_PER_PACKAGE_DIRECTORIES=y` gives each package its own isolated
`host/` and `target/` directories under `output/per-package/<pkg>/`.
This serves two purposes:

1. **Build isolation** — a package can only see headers and libraries
   from its explicitly declared dependencies, not from packages that
   happened to build first. Catches missing dependency declarations.
2. **Top-level parallel build** — because packages are isolated, the
   Makefile can build independent packages concurrently with `make -jN`.

The wrapper Makefile passes `-j$(NPROC)` (defaults to `nproc + 1`) to
the main build. Override with `make NPROC=4` if you want fewer jobs.

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
