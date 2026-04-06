#!/bin/sh
#
# mkinitrfs.sh — Build a minimal initramfs for BBB recovery + overlayfs.
#
# Called from post-build.sh during the buildroot build.  Produces a small
# (~1-2 MB) cpio archive containing busybox + the /init script, wrapped
# as a U-Boot ramdisk image and installed to ${TARGET_DIR}/boot/.
#
# Usage (called automatically by post-build.sh):
#   ./board/bbb/mkinitrfs.sh <target-dir>
#
# The initramfs is loaded by U-Boot alongside zImage + DTB.  If the file
# is missing (e.g. old rootfs), boot.cmd falls back to direct boot.
#
set -eu

TARGET_DIR="$1"
BOARD_DIR="$(dirname "$0")"

WORK=$(mktemp -d "${TARGET_DIR}/../.initramfs-work.XXXXXX")
# shellcheck disable=SC2064
trap "rm -rf '${WORK}'" EXIT

# --- Directory skeleton ---
# Use explicit paths — brace expansion is a bash-ism, not POSIX sh.
for d in bin lib dev proc sys tmp etc mnt/root mnt/lower mnt/data; do
    mkdir -p "${WORK}/${d}"
done

# --- Install busybox ---
cp "${TARGET_DIR}/bin/busybox" "${WORK}/bin/busybox"

# --- Copy shared libraries (skip if busybox is static) ---
# Find the cross-readelf from the host tools.  The toolchain prefix
# varies (arm-buildroot-linux-gnueabihf-, arm-linux-, etc.) so we
# glob for any *-readelf in HOST_DIR.
READELF=""
if [ -n "${HOST_DIR:-}" ]; then
    READELF=$(ls "${HOST_DIR}/bin/"*-readelf 2>/dev/null | head -1) || true
fi
# Fall back to plain readelf (works when host and target are same arch,
# or for checking ELF headers regardless of arch).
[ -z "$READELF" ] && READELF="readelf"

# Check if busybox needs shared libraries
INTERP=$("$READELF" -l "${TARGET_DIR}/bin/busybox" 2>/dev/null \
    | sed -n 's/.*\[Requesting program interpreter: \(.*\)\]/\1/p') || true

if [ -n "$INTERP" ]; then
    # Dynamically linked — copy the program interpreter
    mkdir -p "${WORK}/$(dirname "$INTERP")"
    cp -L "${TARGET_DIR}${INTERP}" "${WORK}${INTERP}"

    # Copy every shared library busybox needs (typically just libc)
    for lib in $("$READELF" -d "${TARGET_DIR}/bin/busybox" 2>/dev/null \
        | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
        for libdir in /lib /usr/lib; do
            if [ -e "${TARGET_DIR}${libdir}/${lib}" ]; then
                mkdir -p "${WORK}${libdir}"
                cp -L "${TARGET_DIR}${libdir}/${lib}" "${WORK}${libdir}/${lib}"
                break
            fi
        done
    done
else
    echo "initramfs: busybox is statically linked (no libs needed)"
fi

# --- Create busybox applet symlinks ---
# Only the applets needed by /init and basic recovery tasks.
for applet in \
    sh mount umount switch_root mkdir cat grep sed sleep echo \
    ls cp mv rm ln chmod mknod stat df du \
    dmesg reboot poweroff halt vi \
    ip ifconfig ping ps kill
do
    ln -sf busybox "${WORK}/bin/${applet}"
done

# --- Install init script ---
install -m 0755 "${BOARD_DIR}/initramfs/init" "${WORK}/init"

# --- Create cpio archive ---
CPIO_GZ="${WORK}.cpio.gz"
(cd "${WORK}" && find . | cpio -o -H newc --quiet | gzip -9) > "${CPIO_GZ}"

# --- Wrap as U-Boot ramdisk image ---
mkimage -A arm -T ramdisk -C gzip -n "BBB initramfs" \
    -d "${CPIO_GZ}" \
    "${TARGET_DIR}/boot/initramfs.uImage" >/dev/null

rm -f "${CPIO_GZ}"

SIZE=$(stat -c%s "${TARGET_DIR}/boot/initramfs.uImage" 2>/dev/null || echo "?")
echo "initramfs: installed ${TARGET_DIR}/boot/initramfs.uImage (${SIZE} bytes)"
