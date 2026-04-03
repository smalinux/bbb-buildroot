#!/bin/sh
# data-persist.sh — Bind-mount persistent directories from /data into rootfs.
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

persist_dir() {
    src="$1"   # path on /data
    dst="$2"   # path on rootfs to overlay

    mkdir -p "$src" "$dst"

    # First boot: if /data dir is empty, seed it from rootfs
    if [ -z "$(ls -A "$src" 2>/dev/null)" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
        cp -a "$dst"/. "$src"/
    fi

    mount --bind "$src" "$dst"
}

# Machine ID: copy from rootfs on first boot, then always use /data copy
if [ ! -f /data/machine-id ]; then
    cp /etc/machine-id /data/machine-id 2>/dev/null || systemd-machine-id-setup
    cp /etc/machine-id /data/machine-id
fi
mount --bind /data/machine-id /etc/machine-id

# Bind-mount persistent directories
persist_dir /data/home      /home
persist_dir /data/root      /root
persist_dir /data/dropbear  /etc/dropbear
persist_dir /data/journal   /var/log/journal
