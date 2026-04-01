#!/bin/sh
set -eu

BOARD_DIR="$(dirname "$0")"
BINARIES_DIR="${BINARIES_DIR:-${0%/*}/../../output/images}"

# Parse args: --bundle-version VERSION
BUNDLE_VERSION="0.1.0"
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-version) BUNDLE_VERSION="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Compile U-Boot boot script
mkimage -C none -A arm -T script -d "${BOARD_DIR}/boot.cmd" "${BINARIES_DIR}/boot.scr"

# Generate SD card image
support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"

# Generate RAUC update bundle
echo "Generating RAUC bundle (version ${BUNDLE_VERSION})..."
RAUC_DIR="${BINARIES_DIR}/rauc-work"
rm -rf "${RAUC_DIR}"
mkdir -p "${RAUC_DIR}"

# Create RAUC manifest
cat > "${RAUC_DIR}/manifest.raucm" << EOF
[update]
compatible=beaglebone-black
version=${BUNDLE_VERSION}

[image.rootfs]
filename=rootfs.ext4
type=ext4
EOF

# Copy rootfs image (RAUC rejects absolute symlinks in bundle contents)
cp "${BINARIES_DIR}/rootfs.ext4" "${RAUC_DIR}/rootfs.ext4"

# Remove old bundle if it exists (rauc refuses to overwrite)
rm -f "${BINARIES_DIR}/update.raucb"

# Build RAUC bundle (signed with dev key)
"${HOST_DIR:-$(dirname "$0")/../../output/host}/bin/rauc" bundle \
    --cert="${BOARD_DIR}/rauc-keys/development-1.cert.pem" \
    --key="${BOARD_DIR}/rauc-keys/development-1.key.pem" \
    "${RAUC_DIR}" \
    "${BINARIES_DIR}/update.raucb"

rm -rf "${RAUC_DIR}"

echo ""
echo "OTA update bundle: ${BINARIES_DIR}/update.raucb"
