# Fast Module Deploy (no reboot)

`make module-deploy BOARD=<ip>` pushes only the kernel module tree
(`/lib/modules/<kver>/`) to the board and runs `depmod -a`. No zImage,
no DTB, no reboot. Modules are available immediately via `modprobe`.

This is the fastest deploy path for changes to code compiled as `=m`
(loadable modules). If you changed built-in (`=y`) code, the kernel
image itself changed — use `make kernel-deploy` instead.

## Usage

```bash
# Build + deploy in one step:
make module-deploy BOARD=192.168.1.100

# Or if you already ran `make linux-rebuild` yourself, skip the build:
./scripts/module-deploy.sh 192.168.1.100

# Password override (defaults to "root"):
BOARD_PASS=secret ./scripts/module-deploy.sh 192.168.1.100
```

After deploying, reload the module on the board:

```bash
modprobe -r <module>    # unload old version
modprobe <module>       # load new version
dmesg | tail            # check output
```

## What it does

`make module-deploy BOARD=<ip>` runs two steps:

1. `make linux-rebuild` — incremental kernel build. With
   `LINUX_OVERRIDE_SRCDIR` pointed at a local checkout, a one-file
   change recompiles in seconds.
2. `./scripts/module-deploy.sh <ip>` — the deploy-only step:
   a. Wipes `/lib/modules/<kver>/` on the board (removes stale modules
      from a previous config with different `=m` selections).
   b. tar-streams `output/target/lib/modules/<kver>/` over SSH.
   c. Runs `depmod -a <kver>` on the board so `modprobe` sees the new
      modules.

No reboot happens — the old modules remain loaded in memory until you
explicitly `modprobe -r` and `modprobe` them.

## When to use which deploy path

| Situation | Use |
|---|---|
| Changed a single out-of-tree kmodule (kmodules/) | `./scripts/deploy-kmod.sh <pkg> <ip>` (insmod, no reboot) |
| Changed in-tree module code (drivers/, net/, etc. compiled as =m) | `make module-deploy BOARD=<ip>` (no reboot) |
| Changed kernel core, scheduler, DTS, or built-in (=y) code | `make kernel-deploy BOARD=<ip>` (reboots) |
| Release candidate or CI | `make bundle && ./scripts/deploy.sh <ip>` |

## Compared to deploy-kmod.sh

`deploy-kmod.sh` builds and deploys a **single out-of-tree kmodule
package** (from `kmodules/`) — it `insmod`s the `.ko` directly from
`/root/`, bypassing `modprobe` and the module dependency tree.

`module-deploy.sh` deploys the **full in-tree module tree** from a
kernel build into `/lib/modules/<kver>/` where `modprobe` can resolve
dependencies. Use this for in-tree kernel modules (e.g., a driver under
`drivers/net/wireless/` that you're modifying in your
`LINUX_OVERRIDE_SRCDIR` tree).

## Caveats

- **Running modules stay loaded.** Deploying new `.ko` files does not
  affect already-loaded modules. You must `modprobe -r` the old module
  and `modprobe` the new one. If the module is in use (e.g., a
  filesystem or network driver), you may need to stop services first.
- **Modules dir is wiped and replaced**, so any locally-installed
  modules under `/lib/modules/<kver>/` on the board are lost.
- If the kernel version (`uname -r`) changed (e.g., you modified
  `EXTRAVERSION`), the new modules land in a different directory and
  `modprobe` won't find them until after a reboot with the new kernel.
  Use `make kernel-deploy` in that case.
- Requires `sshpass` on the host (same as `deploy.sh`), unless SSH
  key auth is configured.
