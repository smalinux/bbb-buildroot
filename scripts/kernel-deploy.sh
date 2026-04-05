#!/bin/bash
#
# kernel-deploy.sh — Push pre-built kernel + modules to the BBB, no OTA/RAUC.
#
# Usage:
#   ./scripts/kernel-deploy.sh <board-ip>
#
# Expects the kernel to already be built (`make linux-rebuild`).
# `make kernel-deploy BOARD=<ip>` does both steps automatically.
#
# Environment:
#   BOARD_PASS  — root password (default: root). Ignored without sshpass.
#   DTB         — device tree blob name (default: am335x-boneblack.dtb)
#
# Flow:
#   1. scp zImage + DTB + /lib/modules/<ver>/ to the active rootfs slot
#   2. depmod -a on target, sync, reboot
#
# Why this works: boot.cmd loads kernel and DTB from the *active* rootfs
# partition (/boot/zImage, /boot/am335x-boneblack.dtb). Overwriting those
# files on the running system replaces the kernel the bootloader will
# load on next boot — the inactive slot is untouched. This is strictly a
# development shortcut; production updates must go through RAUC so the
# A/B invariants hold.
#
# Not used: genimage, rootfs rebuild, RAUC bundling, rauc install. That
# is where most of `make bundle && ./scripts/deploy.sh` time goes.
#
set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <board-ip>" >&2
    exit 1
fi

BOARD_IP="$1"
BOARD_PASS="${BOARD_PASS:-root}"
DTB="${DTB:-am335x-boneblack.dtb}"

# --- helpers ---------------------------------------------------------------

log()  { echo "==> $*"; }

# Run a command, printing it first and showing its output.
# Usage: run <cmd> [args...]
run() {
    echo "  \$ $*"
    "$@"
}

# Same as run() but allow the command to fail (for reboot).
run_ok() {
    echo "  \$ $*"
    "$@" || true
}

elapsed() {
    local dt=$(( $(date +%s) - $1 ))
    echo "${dt}s"
}

# Human-readable file size (works on both GNU and busybox stat).
fsize() { stat --printf='%s' "$1" 2>/dev/null || stat -f'%z' "$1" 2>/dev/null; }

human() {
    local bytes
    bytes=$(fsize "$1")
    if [ "$bytes" -ge 1048576 ]; then
        echo "$(( bytes / 1048576 ))M"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(( bytes / 1024 ))K"
    else
        echo "${bytes}B"
    fi
}

# --- ssh setup -------------------------------------------------------------

# SSH options: skip host key checking (dropbear regenerates keys on every
# reflash) and disable control master (avoids muxclient errors when a stale
# socket exists from a previous session).
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ControlMaster=no"

# Use sshpass if available + BOARD_PASS is set; otherwise plain ssh
# (assumes key-based auth or interactive password prompt).
if command -v sshpass >/dev/null 2>&1; then
    SSH="sshpass -p $BOARD_PASS ssh $SSH_OPTS root@${BOARD_IP}"
    SCP="sshpass -p $BOARD_PASS scp -O $SSH_OPTS"
else
    SSH="ssh $SSH_OPTS root@${BOARD_IP}"
    SCP="scp -O $SSH_OPTS"
fi

# --- validate local artifacts ----------------------------------------------

ZIMAGE="output/images/zImage"
DTB_FILE="output/images/${DTB}"

if [ ! -f "$ZIMAGE" ] || [ ! -f "$DTB_FILE" ]; then
    echo "Error: missing $ZIMAGE or $DTB_FILE" >&2
    echo "Run 'make linux-rebuild' first." >&2
    exit 1
fi

# Kernel version = directory name under output/target/lib/modules/.
# Buildroot's linux-rebuild repopulates this, so it's always in sync
# with the zImage we just built.
MODULES_DIR=$(echo output/target/lib/modules/*)
KVER=$(basename "$MODULES_DIR")
if [ ! -d "$MODULES_DIR" ] || [ "$KVER" = "*" ]; then
    echo "Error: no modules found under output/target/lib/modules/" >&2
    exit 1
fi

KO_COUNT=$(find "$MODULES_DIR" -name '*.ko' | wc -l)
MODULES_SIZE=$(du -sh "$MODULES_DIR" | cut -f1)

log "Kernel $KVER — zImage $(human "$ZIMAGE"), DTB $(human "$DTB_FILE"), ${KO_COUNT} modules (${MODULES_SIZE})"

# --- deploy ----------------------------------------------------------------

T0=$(date +%s)

STEP_T=$(date +%s)
log "Uploading zImage + $DTB to ${BOARD_IP}:/boot/..."
run $SCP "$ZIMAGE" "$DTB_FILE" root@"${BOARD_IP}":/boot/
log "done ($(elapsed $STEP_T))"

# Stream the modules tree as tar over ssh — avoids scp's per-file overhead
# (hundreds of .ko files). Wipe the target dir first so stale modules don't
# linger.
STEP_T=$(date +%s)
log "Uploading modules (/lib/modules/${KVER}/, ${KO_COUNT} modules, ${MODULES_SIZE})..."
run $SSH "rm -rf /lib/modules/${KVER} && mkdir -p /lib/modules/${KVER}"
echo "  \$ tar -cf - $KVER | ssh ... tar -C /lib/modules -xf -"
tar -C "output/target/lib/modules" -cf - "$KVER" | \
    $SSH "tar -C /lib/modules -xf -"
log "done ($(elapsed $STEP_T))"

STEP_T=$(date +%s)
log "Running depmod + sync + reboot on target..."
run_ok $SSH "depmod -a ${KVER} && sync && reboot"
log "done ($(elapsed $STEP_T))"

echo ""
log "Kernel deployed in $(elapsed $T0). Board is rebooting."
