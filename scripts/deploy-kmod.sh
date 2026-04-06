#!/bin/bash
#
# deploy-kmod.sh — Build a single kernel module and deploy it to the BBB
# without going through the OTA/RAUC flow. Much faster than `make bundle
# && ./scripts/deploy.sh` when iterating on a driver: no rootfs rebuild, no RAUC
# bundle, no reboot — just insmod the freshly built .ko.
#
# Usage:
#   ./deploy-kmod.sh <kmod-package> <board-ip> [<module-name>]
#
# Args:
#   <kmod-package>   buildroot package name (e.g., kmod-hello)
#   <board-ip>       BBB IP address or hostname
#   <module-name>    optional: .ko name without extension. Auto-detected
#                    if the package produces exactly one .ko.
#
# Example:
#   ./deploy-kmod.sh kmod-hello 192.168.1.100
#   ./deploy-kmod.sh kmod-hello 192.168.1.100 hello    # explicit name
#
# Flow:
#   1. make <kmod-package>-rebuild      # incremental, seconds
#   2. locate the freshly built .ko under output/build/<pkg>-*/
#   3. scp .ko to /root/ on the BBB
#   4. rmmod old copy (if loaded), insmod new copy
#   5. dump last dmesg lines so you can see the pr_info output
#
# The .ko that gets deployed is the UNSTRIPPED build artifact (has full
# debug symbols). The RAUC bundle uses a stripped copy — useful for
# production but hostile to gdb/crash. This script keeps symbols for
# interactive debugging.
#
set -euo pipefail

# Load user config (BOARD, BOARD_PASS, DTB, etc.)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <kmod-package> [<board-ip>] [<module-name>]" >&2
    echo "Example: $0 kmod-hello 192.168.1.100" >&2
    echo "  or set BOARD in ~/.config/bbb_buildroot_cfg (make bbb)" >&2
    exit 1
fi

KMOD_PKG="$1"
# Board IP: $2 if given, else BOARD from config.
BOARD_IP="${2:-$BOARD}"
if [ -z "$BOARD_IP" ]; then
    echo "Error: no board IP. Pass as \$2 or set BOARD in config (make bbb)." >&2
    exit 1
fi
MOD_NAME="${3:-}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Check sshpass availability
if ! command -v sshpass >/dev/null 2>&1; then
    echo "Error: sshpass not found. Install it:" >&2
    echo "  sudo apt install sshpass" >&2
    exit 1
fi

# Step 1: build (incremental rebuild is fast; first time builds the kernel)
echo "==> Building ${KMOD_PKG}..."
make "${KMOD_PKG}-rebuild"

# Step 2: locate the .ko — glob the build directory since the version
# suffix is in the directory name (e.g., output/build/kmod-hello-1.0/)
BUILD_DIR=$(echo output/build/${KMOD_PKG}-*)
if [ ! -d "${BUILD_DIR}" ]; then
    echo "Error: build dir not found: ${BUILD_DIR}" >&2
    exit 1
fi

if [ -z "${MOD_NAME}" ]; then
    # Auto-detect: find the single .ko in the build dir
    KO_FILES=("${BUILD_DIR}"/*.ko)
    if [ ${#KO_FILES[@]} -ne 1 ] || [ ! -e "${KO_FILES[0]}" ]; then
        echo "Error: could not auto-detect .ko name in ${BUILD_DIR}" >&2
        echo "Found: ${KO_FILES[*]:-none}" >&2
        echo "Pass the module name explicitly as the third argument." >&2
        exit 1
    fi
    KO_PATH="${KO_FILES[0]}"
    MOD_NAME=$(basename "${KO_PATH}" .ko)
else
    KO_PATH="${BUILD_DIR}/${MOD_NAME}.ko"
    if [ ! -f "${KO_PATH}" ]; then
        echo "Error: ${KO_PATH} not found" >&2
        exit 1
    fi
fi

echo "==> Module: ${MOD_NAME} (from ${KO_PATH})"

# Step 3: scp the .ko to /root/ on the board
echo "==> Uploading to ${BOARD_IP}:/root/${MOD_NAME}.ko..."
sshpass -p "${BOARD_PASS}" scp -O ${SSH_OPTS} "${KO_PATH}" \
    "root@${BOARD_IP}:/root/${MOD_NAME}.ko"

# Step 4: rmmod (ignore errors — may not be loaded) then insmod
# Step 5: print last dmesg lines so init/exit messages are visible
echo "==> Reloading on board..."
sshpass -p "${BOARD_PASS}" ssh ${SSH_OPTS} "root@${BOARD_IP}" \
    "rmmod ${MOD_NAME} 2>/dev/null || true; \
     insmod /root/${MOD_NAME}.ko && \
     dmesg | tail -5"

echo ""
echo "==> Done. Module '${MOD_NAME}' is loaded on ${BOARD_IP}."
