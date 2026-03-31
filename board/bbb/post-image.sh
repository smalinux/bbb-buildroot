#!/bin/sh
set -eu

BOARD_DIR="$(dirname "$0")"
BINARIES_DIR="${BINARIES_DIR:-${0%/*}/../../output/images}"

# Parse args: --swu-version VERSION
SWU_VERSION="0.1.0"
while [ $# -gt 0 ]; do
    case "$1" in
        --swu-version) SWU_VERSION="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Compile U-Boot boot script
mkimage -C none -A arm -T script -d "${BOARD_DIR}/boot.cmd" "${BINARIES_DIR}/boot.scr"

# Generate SD card image
support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"

# Generate .swu update package
echo "Generating SWUpdate package (version ${SWU_VERSION})..."
SWU_DIR="${BINARIES_DIR}/swu-work"
rm -rf "${SWU_DIR}"
mkdir -p "${SWU_DIR}"

# Create sw-description with version substituted
sed "s/@@SWU_VERSION@@/${SWU_VERSION}/" "${BOARD_DIR}/sw-description" > "${SWU_DIR}/sw-description"

# Link rootfs image
ln -sf "${BINARIES_DIR}/rootfs.ext4" "${SWU_DIR}/rootfs.ext4"

# Build .swu (cpio archive, sw-description MUST be first)
(cd "${SWU_DIR}" && echo sw-description rootfs.ext4 | tr ' ' '\n' | cpio -ov -H crc > "${BINARIES_DIR}/update.swu")

rm -rf "${SWU_DIR}"

echo ""
echo "OTA update package: ${BINARIES_DIR}/update.swu"
