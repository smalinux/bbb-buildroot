# Kernel SquashFS Support for RAUC

## What

RAUC bundles are internally formatted as SquashFS images. When `rauc install`
runs on the target, it mounts the bundle via a loop device using the kernel's
SquashFS filesystem driver. Without kernel support, installation fails with:

```
Failed mounting bundle: squashfs support not enabled in kernel
```

## How

SquashFS is enabled via a kernel config fragment rather than modifying the
stock beaglebone kernel defconfig directly:

- **`board/bbb/linux.fragment`** contains `CONFIG_SQUASHFS=y`
- **`defconfig`** sets `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` to point at
  this fragment

Buildroot merges the fragment on top of the base kernel config during the
build. This keeps the stock kernel defconfig untouched and makes our
customizations explicit and auditable.

## Why a fragment instead of linux-menuconfig?

The stock `beaglebone_defconfig` kernel config is maintained by buildroot. If
we ran `make linux-menuconfig` and saved, we'd snapshot the entire kernel
`.config` (thousands of lines) into our tree, making future kernel version
upgrades harder to diff and merge.

Config fragments contain only the delta — in this case, a single line. Buildroot
applies fragments after loading the base defconfig via `scripts/kconfig/merge_config.sh`.

## How to add or change kernel config options

There are two approaches. The fragment approach is preferred for targeted
changes; `linux-menuconfig` is useful for exploring available options.

### Approach 1: Edit the fragment directly

1. Open `board/bbb/linux.fragment` and add the `CONFIG_` line:
   ```
   CONFIG_SQUASHFS=y
   CONFIG_NEW_OPTION=y
   ```
2. Rebuild:
   ```
   make linux-rebuild all
   ```

To disable an option that the base defconfig enables, use the `# is not set`
syntax:
```
# CONFIG_SOME_OPTION is not set
```

### Approach 2: Use linux-menuconfig

1. Run the interactive kernel configurator:
   ```
   make linux-menuconfig
   ```
2. Navigate the menus and enable/disable options. Save and exit.
3. This writes the full `.config` to `output/build/linux-*/.config`. It does
   **not** automatically update the fragment.
4. Compare the new config against the base to find your delta:
   ```
   diff <(make linux-config-show-base 2>/dev/null || cat output/build/linux-*/.config.old) \
        output/build/linux-*/.config
   ```
   Or simply check that your intended option is set:
   ```
   grep CONFIG_NEW_OPTION output/build/linux-*/.config
   ```
5. Add the changed lines to `board/bbb/linux.fragment`.
6. Verify the fragment works from a clean state:
   ```
   make linux-dirclean linux-rebuild all
   ```

### Notes

- Always put kernel customizations in the fragment, not in a forked full
  defconfig. The stock `beaglebone_defconfig` is maintained by the kernel
  community and updated with each kernel version bump. Fragments survive
  kernel upgrades; full config snapshots require manual rebasing.
- `make linux-rebuild` recompiles without cleaning. Use `make linux-dirclean`
  first if changing fundamental options (e.g., switching built-in vs module).
- The fragment path is set in defconfig via:
  ```
  BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL_BBB_PATH)/board/bbb/linux.fragment"
  ```
  Multiple fragments can be listed space-separated if needed.
