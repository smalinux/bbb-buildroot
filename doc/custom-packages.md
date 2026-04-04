# Custom External Packages

How to add your own packages to the BR2_EXTERNAL tree so Buildroot builds and
installs them automatically.

## How it works

Buildroot's `BR2_EXTERNAL` mechanism lets you keep custom packages outside the
buildroot source tree. The project root is already registered as an external
tree (see `external.desc`). Two files wire everything together:

- **`Config.in`** (project root) — sources each package's Kconfig file so it
  appears in `make menuconfig` under "External options".
- **`external.mk`** (project root) — includes every `package/*/*.mk` via a
  wildcard, so new packages are picked up automatically without editing this
  file.

## Adding a new package

### 1. Create the package directory

```
mkdir -p package/<name>
```

### 2. Write `package/<name>/Config.in`

```kconfig
config BR2_PACKAGE_<NAME>
	bool "<name>"
	help
	  One-line description of the package.
```

`<NAME>` must be the uppercase version of `<name>` with hyphens replaced by
underscores (e.g., `hello-world` → `HELLO_WORLD`).

### 3. Write `package/<name>/<name>.mk`

For a **local source** package (source lives in the external tree):

```makefile
<NAME>_VERSION = 1.0
<NAME>_SITE = $(BR2_EXTERNAL_BBB_PATH)/package/<name>
<NAME>_SITE_METHOD = local

define <NAME>_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-o $(@D)/<name> $(@D)/<name>.c
endef

define <NAME>_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/<name> $(TARGET_DIR)/usr/bin/<name>
endef

$(eval $(generic-package))
```

For a **git-hosted** package (Buildroot clones it during the build):

```makefile
<NAME>_VERSION = v1.0.0
<NAME>_SITE = https://github.com/yourorg/<name>.git
<NAME>_SITE_METHOD = git

$(eval $(generic-package))
```

Other `SITE_METHOD` options: `wget` (tarball URL), `svn`, `hg`, `bzr`, `scp`.

### 4. Add a `source` line to `Config.in`

Edit the root `Config.in` and add:

```kconfig
source "$BR2_EXTERNAL_BBB_PATH/package/<name>/Config.in"
```

You do NOT need to edit `external.mk` — the wildcard picks up new `.mk` files
automatically.

### 5. Enable and build

```bash
make menuconfig     # navigate to "External options", enable your package
make                # builds everything including the new package
```

## Example: hello-world

The `package/hello-world/` package is a minimal working example. It compiles a
single C file and installs the binary to `/usr/bin/hello-world` on the target.

```
package/hello-world/
├── Config.in          # Kconfig menu entry
├── hello-world.c      # source code
└── hello-world.mk     # build recipe
```

After enabling it in menuconfig and building, run it on the BBB:

```
# hello-world
Hello from BeagleBone Black!
```

## Tips

- **Naming**: the directory name, `.mk` filename, and the lowercase portion of
  the Kconfig symbol must all match (e.g., `hello-world`, `hello-world.mk`,
  `BR2_PACKAGE_HELLO_WORLD`).
- **Rebuild a single package**: `make <name>-rebuild` recompiles and reinstalls.
- **Full clean of a package**: `make <name>-dirclean && make` removes the
  package build directory entirely and rebuilds from scratch.
- **Autotools/CMake**: replace `$(eval $(generic-package))` with
  `$(eval $(autotools-package))` or `$(eval $(cmake-package))` and Buildroot
  handles configure/make automatically.
- **Dependencies**: add `<NAME>_DEPENDENCIES = libfoo libbar` to pull in other
  packages before building yours.
