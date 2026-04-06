# TFTP + NFS Boot (Zero-Flash Development)

## What

Network boot eliminates SD card writes entirely during kernel
development. U-Boot loads the kernel and DTB from the host via TFTP,
and optionally mounts the rootfs from the host via NFS.

TFTP files are **symlinks** into `output/images/`, so every `make`
automatically updates what U-Boot fetches — no separate deploy step.

## Boot Modes

On every boot, a 3-second menu appears on the serial console:

```
  MMC boot (A/B RAUC)
  TFTP boot (kernel from network)
  NFS boot (kernel + rootfs from network)
```

The current mode is highlighted. Press arrow keys to change, Enter to
select. If no key is pressed within 3 seconds, it boots the current
mode automatically. The selection is saved to U-Boot env, so the next
boot defaults to the same choice.

| Mode | Kernel source | Rootfs source | When to use |
|------|--------------|---------------|-------------|
| `mmc` (default) | SD card (active RAUC slot) | SD card | Production, OTA updates |
| `tftp` | TFTP server | SD card (active slot) | Kernel iteration (no rootfs changes) |
| `nfs` | TFTP server | NFS from host | Kernel + rootfs iteration (zero writes) |

## Setup

### 1. Install TFTP server

```bash
sudo apt install tftpd-hpa
```

### 2. Edit your config (optional)

`HOST_IP` is auto-detected from the network route to BOARD — you
normally don't need to set it. Override only if auto-detection picks
the wrong interface:

```sh
# In ~/.config/bbb_buildroot_cfg:
#HOST_IP=192.168.0.100     # override auto-detected host IP
TFTP_DIR=/srv/tftp          # where tftpd-hpa serves from
NFS_DIR=output/target       # NFS export path (default is fine)
```

### 3. Run make bbb

```bash
make bbb              # or: make bbb FORCE=1  to re-run setup
```

This does everything:
- Writes the config template (if not already present)
- Creates **symlinks** in `TFTP_DIR`: `zImage → output/images/zImage`,
  `DTB → output/images/DTB`
- Installs `nfs-kernel-server` if missing
- Adds `NFS_DIR` to `/etc/exports` (idempotent)
- Runs `exportfs -ra`

### 4. Build and switch mode

```bash
make                              # build (TFTP symlinks auto-update)
make tftp-boot         # switch board to TFTP boot + reboot
# or
make nfs-boot          # switch board to NFS boot + reboot
```

That's it. From now on:

```bash
make                   # rebuild kernel
ssh root@<ip> reboot   # board fetches new kernel from TFTP automatically
```

## Make Targets

| Target | What it does |
|--------|-------------|
| `make bbb` | One-time setup: config + TFTP symlinks + NFS export |
| `make tftp-boot` | Switch board to TFTP mode + reboot |
| `make nfs-boot` | Switch board to NFS mode + reboot |
| `make mmc-boot` | Switch board back to SD card boot + reboot |

## Development Workflows

### TFTP kernel iteration

After one-time setup, the cycle is just:

```bash
make                          # rebuild kernel (symlinks update TFTP dir)
ssh root@<ip> reboot          # board loads new kernel from TFTP
```

No copy, no deploy, no SCP. The TFTP dir always has the latest build.

### NFS rootfs iteration

Changes to `output/target/` are instantly visible on the BBB:

```bash
# On host:
vim output/target/etc/some-config

# On BBB: already there (NFS mount)
cat /etc/some-config
```

No reboot needed for rootfs changes. For kernel changes, rebuild and
reboot.

### Switch back to SD card

```bash
make mmc-boot
```

## Config Keys

Set in `~/.config/bbb_buildroot_cfg` (see `make config`):

| Key | Default | Purpose |
|-----|---------|---------|
| `TFTP_DIR` | `/srv/tftp` | Host TFTP directory (symlinks created here) |
| `HOST_IP` | *(auto-detected)* | Host IP (auto from route to BOARD, override if needed) |
| `NFS_DIR` | `output/target` | Host directory exported via NFS |

## How It Works

### TFTP symlinks

`make bbb` creates symlinks in `TFTP_DIR`:

```
/srv/tftp/zImage → /src/bbb-buildroot/output/images/zImage
/srv/tftp/am335x-boneblack.dtb → /src/bbb-buildroot/output/images/am335x-boneblack.dtb
```

Since these are symlinks, every `make` that rebuilds the kernel
automatically updates what U-Boot fetches. No copy step needed.

### Boot mode switching

`make tftp-boot` / `make nfs-boot` / `make mmc-boot` SSH to the board
and run `fw_setenv boot_mode <mode>` + `reboot`. The boot script reads
`boot_mode` and branches accordingly.

## Kernel Config

Enabled in `linux.fragment` for NFS root support:

```
CONFIG_NFS_FS=y       # NFS filesystem support
CONFIG_NFS_V3=y       # NFS version 3
CONFIG_NFS_V4=y       # NFS version 4
CONFIG_ROOT_NFS=y     # mount root filesystem via NFS
CONFIG_IP_PNP=y       # IP auto-configuration at boot
CONFIG_IP_PNP_DHCP=y  # DHCP for kernel IP auto-config
```

## U-Boot Config

Enabled in `uboot.fragment`:

```
CONFIG_CMD_BOOTMENU=y   # interactive boot menu on serial console
```

## Troubleshooting

### TFTP timeout

- Verify host TFTP server is running: `systemctl status tftpd-hpa`
- Check firewall: `sudo ufw allow tftp` or `sudo ufw allow 69/udp`
- Verify symlinks exist: `ls -la $TFTP_DIR/zImage`
- Ping test from U-Boot prompt: `ping ${serverip}`

### NFS mount fails

- Verify NFS export: `showmount -e localhost`
- Check `no_root_squash` is set (embedded Linux runs as root)
- Try manual mount from BBB: `mount -t nfs -o v3,tcp <host>:/path /mnt`

### Board doesn't get an IP

- The boot script runs `dhcp` if `ipaddr` is not set
- For static IP: `fw_setenv ipaddr 192.168.0.101`

### Going back to normal boot

```bash
make mmc-boot
```

All RAUC functionality (OTA, rollback, slot selection) works normally.
