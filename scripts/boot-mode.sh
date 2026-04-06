#!/bin/bash
#
# boot-mode.sh — Switch the board's boot mode and reboot.
#
# Usage:
#   ./scripts/boot-mode.sh <mode> [board-ip]
#
# Modes:
#   mmc   — SD card A/B RAUC boot (default/production)
#   tftp  — kernel from TFTP, rootfs from SD card
#   nfs   — kernel from TFTP, rootfs from NFS
#
# Sets the U-Boot env via fw_setenv over SSH, then reboots.
# For tftp/nfs, also sets serverip from HOST_IP in config.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

MODE="${1:-}"
BOARD_IP="${2:-$BOARD}"

if [ -z "$MODE" ] || [ -z "$BOARD_IP" ]; then
    echo "Usage: $0 <mmc|tftp|nfs> [board-ip]" >&2
    exit 1
fi

case "$MODE" in
    mmc|tftp|nfs) ;;
    *) echo "Error: unknown mode '$MODE'. Use mmc, tftp, or nfs." >&2; exit 1 ;;
esac

# --- SSH setup (same pattern as kernel-deploy.sh) -------------------------

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ControlMaster=no"

if command -v sshpass >/dev/null 2>&1; then
    SSH="sshpass -p $BOARD_PASS ssh $SSH_OPTS root@${BOARD_IP}"
else
    SSH="ssh $SSH_OPTS root@${BOARD_IP}"
fi

# --- Set boot mode --------------------------------------------------------

echo "==> Setting boot_mode=${MODE} on ${BOARD_IP}..."

CMD="fw_setenv boot_mode $MODE"

# For network modes, also set serverip so U-Boot knows where to TFTP from
if [ "$MODE" = "tftp" ] || [ "$MODE" = "nfs" ]; then
    if [ -z "$HOST_IP" ]; then
        echo "Error: could not detect HOST_IP (needed for $MODE mode)." >&2
        echo "  Set BOARD in config or override: HOST_IP=x.x.x.x make $MODE-boot" >&2
        exit 1
    fi
    CMD="$CMD && fw_setenv serverip $HOST_IP"
    # TFTP subdirectory: files live under $TFTP_DIR/$BOARD_NAME/ on the host,
    # so U-Boot needs the relative prefix for tftp commands.
    CMD="$CMD && fw_setenv tftp_dir $BOARD_NAME/"

    # NFS mode also needs the NFS export path on the host
    if [ "$MODE" = "nfs" ]; then
        # Resolve NFS_DIR to absolute path
        case "$NFS_DIR" in
            /*) nfs_abs="$NFS_DIR" ;;
            *)  nfs_abs="$(cd "$(dirname "$0")/.." && pwd)/$NFS_DIR" ;;
        esac
        CMD="$CMD && fw_setenv nfs_dir $nfs_abs"
    fi
fi

$SSH "$CMD && sync && reboot" || true

echo "==> Board is rebooting into ${MODE} mode."
