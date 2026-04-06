#!/bin/bash
set -e

# Load user config (BOARD, BOARD_PASS, DTB, etc.)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Accept board IP as $1, fall back to BOARD from config.
BOARD_IP="${1:-$BOARD}"
if [ -z "$BOARD_IP" ]; then
    echo "Usage: $0 <board-ip>"
    echo "  or set BOARD in ~/.config/bbb_buildroot_cfg (make bbb)"
    exit 1
fi

BUNDLE_FILE="output/images/update.raucb"

# SSH options: skip host key checking (keys change on every reflash),
# disable control master (avoids muxclient errors from stale sockets).
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ControlMaster=no"

# Use sshpass if available; otherwise plain ssh (key auth or interactive prompt).
if command -v sshpass >/dev/null 2>&1; then
    SSH="sshpass -p $BOARD_PASS ssh $SSH_OPTS root@${BOARD_IP}"
    SCP="sshpass -p $BOARD_PASS scp -O $SSH_OPTS"
else
    SSH="ssh $SSH_OPTS root@${BOARD_IP}"
    SCP="scp -O $SSH_OPTS"
fi

# Build
echo "Building update bundle..."
make

# Check bundle exists
if [ ! -f "$BUNDLE_FILE" ]; then
    echo "Error: $BUNDLE_FILE not found"
    exit 1
fi

# Upload and install
echo ""
echo "Uploading bundle to ${BOARD_IP}..."
$SCP "$BUNDLE_FILE" root@"${BOARD_IP}":/tmp/update.raucb

echo "Installing bundle..."
$SSH rauc install /tmp/update.raucb

# Reboot
echo ""
echo "Rebooting board..."
$SSH reboot || true

echo ""
echo "OTA update deployed. Board is rebooting."
