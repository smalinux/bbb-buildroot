#!/bin/sh
set -eu

BOARD_DIR="$(dirname "$0")"
TARGET_DIR="$1"

# --- RAUC ---
install -m 0644 -D "${BOARD_DIR}/system.conf" "${TARGET_DIR}/etc/rauc/system.conf"
install -m 0644 -D "${BOARD_DIR}/rauc-keys/development-1.cert.pem" \
    "${TARGET_DIR}/etc/rauc/keyring.pem"

# --- U-Boot env access ---
install -m 0644 -D "${BOARD_DIR}/rootfs-overlay/etc/fw_env.config" \
    "${TARGET_DIR}/etc/fw_env.config"

# --- Data partition mount ---
install -m 0755 -d "${TARGET_DIR}/data"
grep -q '/data' "${TARGET_DIR}/etc/fstab" 2>/dev/null || \
    echo '/dev/mmcblk0p4	/data	ext4	defaults,noatime	0	2' >> "${TARGET_DIR}/etc/fstab"
install -m 0755 -d "${TARGET_DIR}/data/rauc"

# --- systemd unit directories ---
install -m 0755 -d "${TARGET_DIR}/usr/lib/systemd/system/multi-user.target.wants"
install -m 0755 -d "${TARGET_DIR}/usr/lib/systemd/system/local-fs.target.wants"

# --- Network: systemd-networkd ---
install -m 0644 -D "${BOARD_DIR}/network/20-wired.network" \
    "${TARGET_DIR}/usr/lib/systemd/network/20-wired.network"

# --- Service: data-persist (bind-mount /data/* over rootfs) ---
install -m 0755 -D "${BOARD_DIR}/systemd/data-persist.sh" \
    "${TARGET_DIR}/usr/lib/systemd/scripts/data-persist.sh"
install -m 0644 -D "${BOARD_DIR}/systemd/data-persist.service" \
    "${TARGET_DIR}/usr/lib/systemd/system/data-persist.service"
ln -sf /usr/lib/systemd/system/data-persist.service \
    "${TARGET_DIR}/usr/lib/systemd/system/local-fs.target.wants/data-persist.service"

# --- Drop-in: delay /var/log/journal unmount until journald stops ---
# systemd auto-generates var-log-journal.mount for the bind mount created
# by data-persist.sh. Without this ordering, the unmount races journald.
install -m 0644 -D "${BOARD_DIR}/systemd/var-log-journal.mount.d/dependencies.conf" \
    "${TARGET_DIR}/usr/lib/systemd/system/var-log-journal.mount.d/dependencies.conf"

# --- Shell history: DefaultEnvironment for all services ---
# Injects HISTFILE/ENV into every service (agetty, dropbear, etc.) via
# systemd's manager config. This avoids modifying login options which
# broke session tracking and prevented clean reboot.
install -m 0644 -D "${BOARD_DIR}/systemd/10-environment.conf" \
    "${TARGET_DIR}/etc/systemd/system.conf.d/10-environment.conf"

# --- Service: rauc-mark-good ---
install -m 0644 -D "${BOARD_DIR}/systemd/rauc-mark-good.service" \
    "${TARGET_DIR}/usr/lib/systemd/system/rauc-mark-good.service"
ln -sf /usr/lib/systemd/system/rauc-mark-good.service \
    "${TARGET_DIR}/usr/lib/systemd/system/multi-user.target.wants/rauc-mark-good.service"

# --- Service: watchdog (hardware watchdog daemon) ---
install -m 0644 -D "${BOARD_DIR}/systemd/watchdog.service" \
    "${TARGET_DIR}/usr/lib/systemd/system/watchdog.service"
ln -sf /usr/lib/systemd/system/watchdog.service \
    "${TARGET_DIR}/usr/lib/systemd/system/multi-user.target.wants/watchdog.service"

# --- Cleanup legacy SysV init scripts ---
rm -f "${TARGET_DIR}/etc/init.d/S49ntp"
rm -f "${TARGET_DIR}/etc/init.d/S99rauc-mark-good"
