# Fast Kernel Deploy (no OTA)

The standard update path (`make bundle && ./scripts/deploy.sh <ip>`)
rebuilds the rootfs, generates an `sdcard.img`-style image, wraps it in
a signed RAUC bundle, uploads it, and installs it into the inactive
slot. That is the correct flow for releases, but it is slow (minutes)
and overkill when all you changed is a `.c` file under the kernel tree.

`make kernel-deploy BOARD=<ip>` is a development shortcut that skips the
bundle entirely.

## Usage

```bash
# Build + deploy in one step:
make kernel-deploy BOARD=192.168.1.100

# Or if you already ran `make linux-rebuild` yourself, skip the build:
./scripts/kernel-deploy.sh 192.168.1.100

# Password override (defaults to "root"):
BOARD_PASS=secret ./scripts/kernel-deploy.sh 192.168.1.100

# Non-default DTB:
DTB=am335x-boneblack-wireless.dtb ./scripts/kernel-deploy.sh 192.168.1.100
```

## What it does

`make kernel-deploy BOARD=<ip>` runs two steps:

1. `make linux-rebuild` — incremental kernel build. With
   `LINUX_OVERRIDE_SRCDIR` pointed at a local checkout, a one-file
   change recompiles in seconds.
2. `./scripts/kernel-deploy.sh <ip>` — the deploy-only step:
   a. `scp output/images/zImage output/images/<dtb>` to `/boot/` on
      the board.
   b. tar-stream `output/target/lib/modules/<kver>/` over SSH to
      `/lib/modules/<kver>/` on the board (wipes the old dir first).
   c. `depmod -a <kver>` on the board, then `sync && reboot`.

Run the script directly when you've already built the kernel.

## Why this works

`board/bbb/boot.cmd` loads the kernel and DTB from the *active* rootfs
partition:

```
load mmc 0:${root_part} ${kernel_addr_r} boot/zImage
load mmc 0:${root_part} ${fdt_addr_r} boot/am335x-boneblack.dtb
```

The running system's `/boot/` **is** the active slot's boot directory,
and the rootfs is mounted `rw`. Overwriting `/boot/zImage` and
`/boot/am335x-boneblack.dtb` on the live system replaces exactly the
files U-Boot will load on the next boot. Modules under `/lib/modules/`
are consumed by the kernel at runtime after reboot — writing them in
place is equivalent to what a RAUC bundle install would do.

The inactive slot is not touched. The RAUC A/B invariants (slot
symmetry, signature check, boot attempt counters) are bypassed, which
is why this is a **development-only** shortcut.

## When to use which deploy path

| Situation | Use |
|---|---|
| Iterating on a single out-of-tree kmodule | `./scripts/deploy-kmod.sh <pkg> <ip>` (insmod, no reboot) |
| Iterating on in-tree modules (=m code) | `make module-deploy BOARD=<ip>` (no reboot) |
| Iterating on kernel core, scheduler, DTS | `make kernel-deploy BOARD=<ip>` |
| Verifying a release candidate end-to-end | `make bundle && ./scripts/deploy.sh <ip>` |
| Release, CI, anything stored on disk | `make bundle && ./scripts/deploy.sh <ip>` |

## Caveats

- **Overwrites the active slot.** If the new kernel fails to boot, the
  board rolls back to the *other* slot (via RAUC's `BOOT_A_LEFT`/
  `BOOT_B_LEFT` attempt counters). You still have a working fallback —
  but it is the kernel that was in the other slot, not the previous
  good kernel you just overwrote. Re-flash or run `./scripts/deploy.sh`
  to restore.
- **Not reproducible.** The active slot's rootfs now contains a kernel
  that was never part of a signed bundle. Do not ship a board in this
  state.
- **Modules dir is wiped and replaced**, so any locally-installed
  modules under `/lib/modules/<kver>/` on the board are lost. This is
  intentional — stale modules cause nasty "unknown symbol" loads.
- Requires `sshpass` on the host (same as `deploy.sh`).
