#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <board-ip>"
    exit 1
fi

BOARD_IP="$1"
BUNDLE_FILE="output/images/update.raucb"

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
scp "$BUNDLE_FILE" root@"${BOARD_IP}":/tmp/update.raucb

echo "Installing bundle..."
ssh root@"${BOARD_IP}" rauc install /tmp/update.raucb

# Reboot
echo ""
echo "Rebooting board..."
ssh root@"${BOARD_IP}" reboot || true

echo ""
echo "OTA update deployed. Board is rebooting."
