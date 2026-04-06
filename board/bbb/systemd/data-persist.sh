#!/bin/sh
# data-persist.sh — Bind-mount persistent directories from /data into rootfs.
#
# Usage: data-persist.sh start   — create bind mounts (boot)
#        data-persist.sh stop    — undo bind mounts (shutdown)
#
# Runs early at boot (via data-persist.service) after /data is mounted.
# On first boot, seeds /data subdirectories from rootfs defaults.
# On subsequent boots, /data contents override rootfs (bind-mount).
#
# Layout on /data partition:
#   /data/rauc/         — RAUC slot status + adaptive update indices
#   /data/home/         — user home directories
#   /data/root/         — root home directory, shell history
#   /data/dropbear/     — SSH host keys (prevents host-key-changed after OTA)
#   /data/journal/      — systemd journal (persistent logs across reboots)
#   /data/machine-id    — stable machine identity across OTA updates

set -eu

# Skip bind mounts on NFS root — the whole rootfs is already live on the
# host, and /data (mmcblk0p4) would shadow NFS-served directories.
rootfstype=$(awk '$2 == "/" {print $3}' /proc/mounts)
if [ "$rootfstype" = "nfs" ] || [ "$rootfstype" = "nfs4" ]; then
    echo "data-persist: NFS root detected, skipping bind mounts."
    exit 0
fi

# All persistent bind mounts: /data source → rootfs destination.
# Add new entries here — start and stop are handled automatically.
MOUNTS="
/data/home      /home
/data/root      /root
/data/dropbear  /etc/dropbear
/data/journal   /var/log/journal
"

do_start() {
    # Machine ID: copy from rootfs on first boot, then always use /data copy
    if [ ! -f /data/machine-id ]; then
        cp /etc/machine-id /data/machine-id 2>/dev/null || systemd-machine-id-setup
        cp /etc/machine-id /data/machine-id
    fi
    mount --bind /data/machine-id /etc/machine-id

    # Bind-mount persistent directories
    echo "$MOUNTS" | while read -r src dst; do
        [ -z "$src" ] && continue
        mkdir -p "$src" "$dst"
        # First boot: if /data dir is empty, seed it from rootfs
        if [ -z "$(ls -A "$src" 2>/dev/null)" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
            cp -a "$dst"/. "$src"/
        fi
        mount --bind "$src" "$dst"
    done
}

do_stop() {
    # Unmount in reverse order so nested mounts are undone first
    echo "$MOUNTS" | tac | while read -r src dst; do
        [ -z "$dst" ] && continue
        umount "$dst" 2>/dev/null || true
    done
    umount /etc/machine-id 2>/dev/null || true
}

case "${1:-start}" in
    start) do_start ;;
    stop)  do_stop  ;;
    *)     echo "Usage: $0 {start|stop}" >&2; exit 1 ;;
esac
