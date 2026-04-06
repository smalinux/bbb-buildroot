#!/bin/bash
#
# module-deploy.sh — Push kernel modules to the BBB, no reboot.
#
# Usage:
#   ./scripts/module-deploy.sh <board-ip>
#
# Expects the kernel to already be built (`make linux-rebuild`).
# `make module-deploy BOARD=<ip>` does both steps automatically.
#
# Environment:
#   BOARD_PASS  — root password (default: root). Ignored without sshpass.
#
# Flow:
#   1. tar-stream output/target/lib/modules/<kver>/ to the board
#   2. depmod -a on target
#   3. done — no reboot, modules are available immediately via modprobe
#
# When to use this instead of kernel-deploy:
#   - You changed only module code (.c files under drivers/, fs/, net/, etc.)
#     that compiles as =m, not =y.
#   - You do NOT need a new zImage or DTB — those are built-in code changes.
#   - You want the fastest possible deploy: no zImage upload, no reboot.
#
# After deploying, reload the module on target:
#   modprobe -r <module>   # unload old
#   modprobe <module>       # load new
#   dmesg | tail            # check output
#
# Compared to deploy-kmod.sh:
#   deploy-kmod.sh — builds and deploys a single out-of-tree kmodule
#                     package (from kmodules/), insmod's directly into /root/.
#   module-deploy.sh — deploys the FULL in-tree module tree from a kernel
#                      build into /lib/modules/<kver>/ where modprobe can
#                      find them. For in-tree kernel modules.
#
set -euo pipefail

# Load user config (BOARD, BOARD_PASS, DTB, etc.)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Accept board IP as $1, fall back to BOARD from config.
BOARD_IP="${1:-$BOARD}"
if [ -z "$BOARD_IP" ]; then
    echo "Usage: $0 <board-ip>" >&2
    echo "  or set BOARD in ~/.config/bbb_buildroot_cfg (make bbb)" >&2
    exit 1
fi

# --- helpers ---------------------------------------------------------------

log()  { echo "==> $*"; }

run() {
    echo "  \$ $*"
    "$@"
}

elapsed() {
    local dt=$(( $(date +%s) - $1 ))
    echo "${dt}s"
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
else
    SSH="ssh $SSH_OPTS root@${BOARD_IP}"
fi

# --- validate local artifacts ----------------------------------------------

# Kernel version = directory name under output/target/lib/modules/.
MODULES_DIR=$(echo output/target/lib/modules/*)
KVER=$(basename "$MODULES_DIR")
if [ ! -d "$MODULES_DIR" ] || [ "$KVER" = "*" ]; then
    echo "Error: no modules found under output/target/lib/modules/" >&2
    echo "Run 'make linux-rebuild' first." >&2
    exit 1
fi

KO_COUNT=$(find "$MODULES_DIR" -name '*.ko' | wc -l)
MODULES_SIZE=$(du -sh "$MODULES_DIR" | cut -f1)

if [ "$KO_COUNT" -eq 0 ]; then
    echo "Error: no .ko files under $MODULES_DIR — nothing to deploy." >&2
    exit 1
fi

log "Kernel $KVER — ${KO_COUNT} modules (${MODULES_SIZE})"

# --- deploy ----------------------------------------------------------------

T0=$(date +%s)

# Stream the modules tree as tar over ssh — avoids scp's per-file overhead
# (hundreds of .ko files). Wipe the target dir first so stale modules don't
# linger from a previous kernel config with different =m selections.
STEP_T=$(date +%s)
log "Uploading modules (/lib/modules/${KVER}/, ${KO_COUNT} modules, ${MODULES_SIZE})..."
run $SSH "rm -rf /lib/modules/${KVER} && mkdir -p /lib/modules/${KVER}"
echo "  \$ tar -cf - $KVER | ssh ... tar -C /lib/modules -xf -"
tar -C "output/target/lib/modules" -cf - "$KVER" | \
    $SSH "tar -C /lib/modules -xf -"
log "done ($(elapsed $STEP_T))"

STEP_T=$(date +%s)
log "Running depmod on target..."
run $SSH "depmod -a ${KVER} && sync"
log "done ($(elapsed $STEP_T))"

echo ""
log "Modules deployed in $(elapsed $T0). No reboot — reload modules with:"
echo "    modprobe -r <module> && modprobe <module>"
