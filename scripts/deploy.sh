#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <board-ip>"
    exit 1
fi

BOARD_IP="$1"
BUNDLE_FILE="output/images/update.raucb"
BOARD_PASS="${BOARD_PASS:-root}"

# SSH options: skip host key checking (keys change on every reflash)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Check sshpass is available
if ! command -v sshpass >/dev/null 2>&1; then
    echo "Error: sshpass not found. Install it:"
    echo "  sudo apt install sshpass"
    exit 1
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
sshpass -p "$BOARD_PASS" scp -O $SSH_OPTS "$BUNDLE_FILE" root@"${BOARD_IP}":/tmp/update.raucb

echo "Installing bundle..."
sshpass -p "$BOARD_PASS" ssh $SSH_OPTS root@"${BOARD_IP}" rauc install /tmp/update.raucb

# Reboot
echo ""
echo "Rebooting board..."
sshpass -p "$BOARD_PASS" ssh $SSH_OPTS root@"${BOARD_IP}" reboot || true

echo ""
echo "OTA update deployed. Board is rebooting."
