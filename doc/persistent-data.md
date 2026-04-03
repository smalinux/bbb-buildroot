# Persistent Data Partition

## What

User data, SSH host keys, logs, and machine identity are stored on the
persistent `/data` partition (p4) and bind-mounted over the rootfs at boot.
This data survives A/B OTA updates — when RAUC writes a new rootfs to the
inactive slot, `/data` is untouched.

## Why

In an A/B OTA system, the rootfs partitions (p2, p3) are completely overwritten
during updates. Without persistence, every update would:

- Regenerate SSH host keys (triggering "host key changed" warnings)
- Lose shell history, dotfiles, and user home directories
- Reset the machine ID (breaking log correlation)
- Lose journal logs from previous boots

## What is Persisted

| Rootfs path | Persisted at | Contents |
|---|---|---|
| `/home` | `/data/home/` | User home directories |
| `/root` | `/data/root/` | Root home, shell history, dotfiles |
| `/etc/dropbear` | `/data/dropbear/` | SSH host keys |
| `/var/log/journal` | `/data/journal/` | systemd journal (all boot logs) |
| `/etc/machine-id` | `/data/machine-id` | Stable machine identity |
| `/data/rauc` | (direct) | RAUC slot status + adaptive indices |

## How It Works

### Boot sequence

1. systemd mounts `/data` from `/dev/mmcblk0p4` (via fstab → `data.mount`)
2. `data-persist.service` runs (Before journald, dropbear, multi-user)
3. The service script:
   - Creates subdirectories on `/data` if they don't exist (first boot)
   - Seeds them with current rootfs contents if empty (first boot only)
   - Bind-mounts each `/data/<dir>` over the rootfs path

### First boot behavior

On the very first boot (fresh SD card), `/data` is empty. The persist script
copies the initial contents from the rootfs into `/data`. After that, the
`/data` copy is authoritative — rootfs contents are hidden by the bind mount.

### OTA update behavior

When RAUC installs a new rootfs:
1. The new rootfs has fresh default files in `/home`, `/root`, `/etc/dropbear`
2. On next boot, `data-persist.service` bind-mounts `/data/*` over them
3. The user's data from before the update is back, untouched

### Implementation

The service unit (`data-persist.service`) runs a shell script that does the
bind mounts:

```ini
[Unit]
Description=Bind-mount persistent data from /data partition
DefaultDependencies=no
After=data.mount
Requires=data.mount
Before=systemd-journald.service dropbear.service multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/scripts/data-persist.sh
RemainAfterExit=yes

[Install]
WantedBy=local-fs.target
```

Key ordering:
- `After=data.mount` — `/data` must be mounted first
- `Before=systemd-journald.service` — journal must write to the persisted dir
- `Before=dropbear.service` — SSH must use the persisted host keys

## Adding More Persistent Paths

Edit `/usr/lib/systemd/scripts/data-persist.sh` and add a new `persist_dir`
call:

```sh
persist_dir /data/myapp  /var/lib/myapp
```

## Partition Layout

```
p1: boot    (FAT, 16 MB)   — bootloader only
p2: rootfsA (ext4, 512 MB) — overwritten by OTA
p3: rootfsB (ext4, 512 MB) — overwritten by OTA
p4: data    (ext4, 128 MB) — NEVER overwritten, persistent
```

## Notes

- The `/data` partition is **never touched** by RAUC. It only writes to the
  rootfs slots (p2/p3).
- If `/data` gets corrupted, the system still boots — the persist script
  creates fresh directories and seeds from rootfs defaults.
- To factory-reset persistent data: `rm -rf /data/* && reboot`.
- Journal size is managed by systemd-journald's `SystemMaxUse` setting
  (default ~10% of filesystem). On 128 MB, that's ~12 MB of logs.
- The 128 MB data partition should be sufficient for typical embedded use.
  If more space is needed, resize p4 in `genimage.cfg`.
