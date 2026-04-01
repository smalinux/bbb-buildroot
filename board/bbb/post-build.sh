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

# Confirm boot on successful startup (mark slot as good)
# This runs at the end of init, telling RAUC + U-Boot the boot succeeded
install -m 0755 -d "${TARGET_DIR}/etc/init.d"
cat > "${TARGET_DIR}/etc/init.d/S99rauc-mark-good" << 'INITEOF'
#!/bin/sh
case "$1" in
    start)
        if fw_printenv BOOT_ORDER 2>/dev/null | grep -q "BOOT_ORDER="; then
            echo "Marking current slot as good..."
            rauc status mark-good
        fi
        ;;
esac
INITEOF
chmod 0755 "${TARGET_DIR}/etc/init.d/S99rauc-mark-good"
