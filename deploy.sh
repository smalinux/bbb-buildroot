#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <board-ip>"
    exit 1
fi

BOARD_IP="$1"
SWU_FILE="output/images/update.swu"

# Build
echo "Building update package..."
make swu

# Check .swu exists
if [ ! -f "$SWU_FILE" ]; then
    echo "Error: $SWU_FILE not found"
    exit 1
fi

# Upload
echo ""
echo "Uploading to ${BOARD_IP}:8080..."
curl -f -F "file=@${SWU_FILE}" "http://${BOARD_IP}:8080/upload"

# Reboot
echo ""
echo "Rebooting board..."
ssh root@"${BOARD_IP}" reboot || true

echo ""
echo "OTA update deployed. Board is rebooting."
