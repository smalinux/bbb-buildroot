#!/bin/sh
set -eu

BOARD_DIR="$(dirname "$0")"
TARGET_DIR="$1"

# Install SWUpdate runtime config
install -m 0644 -D "${BOARD_DIR}/swupdate.cfg" "${TARGET_DIR}/etc/swupdate.cfg"

# Confirm boot on successful startup (clear upgrade_available)
# This runs at the end of init, marking the boot as good
install -m 0755 -d "${TARGET_DIR}/etc/init.d"
cat > "${TARGET_DIR}/etc/init.d/S99swupdate-confirm" << 'INITEOF'
#!/bin/sh
case "$1" in
    start)
        if fw_printenv upgrade_available 2>/dev/null | grep -q "upgrade_available=1"; then
            echo "Confirming successful boot..."
            fw_setenv upgrade_available 0
            fw_setenv bootcount 0
        fi
        ;;
esac
INITEOF
chmod 0755 "${TARGET_DIR}/etc/init.d/S99swupdate-confirm"
