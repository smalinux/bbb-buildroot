#!/bin/sh
set -eu

BOARD_DIR="$(dirname "$0")"
TARGET_DIR="$1"

# Install RAUC system configuration
install -m 0644 -D "${BOARD_DIR}/system.conf" "${TARGET_DIR}/etc/rauc/system.conf"

# Install keyring (CA certificate) so RAUC can verify bundles
install -m 0644 -D "${BOARD_DIR}/rauc-keys/development-1.cert.pem" \
    "${TARGET_DIR}/etc/rauc/keyring.pem"

# Install U-Boot env access config
install -m 0644 -D "${BOARD_DIR}/rootfs-overlay/etc/fw_env.config" \
    "${TARGET_DIR}/etc/fw_env.config"

# Mount data partition (persistent storage for RAUC adaptive update indices)
install -m 0755 -d "${TARGET_DIR}/data"
grep -q '/data' "${TARGET_DIR}/etc/fstab" 2>/dev/null || \
    echo '/dev/mmcblk0p4	/data	ext4	defaults,noatime	0	2' >> "${TARGET_DIR}/etc/fstab"
install -m 0755 -d "${TARGET_DIR}/data/rauc"

# Ensure systemd wants directory exists
install -m 0755 -d "${TARGET_DIR}/usr/lib/systemd/system/multi-user.target.wants"

# --- systemd-networkd: configure ethernet with DHCP ---
install -m 0644 -D /dev/stdin "${TARGET_DIR}/usr/lib/systemd/network/20-wired.network" << 'EOF'
[Match]
Name=end0

[Network]
DHCP=yes

[DHCPv4]
UseDNS=yes
UseNTP=yes
EOF

# NTP: systemd-timesyncd handles time sync natively, no custom service needed.
# It was visible in boot log as "Started Network Time Synchronization".

# --- systemd service: RAUC mark-good ---
# Replaces the old S99rauc-mark-good SysV init script.
# Marks the current boot slot as good once the system reaches multi-user.
install -m 0644 -D /dev/stdin "${TARGET_DIR}/usr/lib/systemd/system/rauc-mark-good.service" << 'EOF'
[Unit]
Description=Mark current RAUC slot as good
After=multi-user.target
ConditionPathIsReadWrite=/dev/mmcblk0

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'fw_printenv BOOT_ORDER 2>/dev/null && rauc status mark-good'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
ln -sf /usr/lib/systemd/system/rauc-mark-good.service \
    "${TARGET_DIR}/usr/lib/systemd/system/multi-user.target.wants/rauc-mark-good.service"

# Remove any leftover SysV init scripts (in case of upgrade from busybox init)
rm -f "${TARGET_DIR}/etc/init.d/S49ntp"
rm -f "${TARGET_DIR}/etc/init.d/S99rauc-mark-good"
