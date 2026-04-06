#!/bin/bash
#
# netboot-setup.sh — One-time TFTP + NFS host setup.
#
# Called by `make bbb` after writing the config file. Sets up:
#
#   1. dnsmasq — TFTP server + proxy DHCP (sets next-server so U-Boot
#      automatically knows where to TFTP from)
#
#   2. TFTP symlinks — zImage and DTB in TFTP_DIR point to output/images/
#      so every `make` automatically updates what U-Boot fetches.
#
#   3. NFS export — adds NFS_DIR (output/target/) to /etc/exports so the
#      BBB can mount the rootfs over the network.
#
# All paths come from the config file (~/.config/bbb_buildroot_cfg).
#
# Usage:
#   ./scripts/netboot-setup.sh          # reads config
#   make bbb                            # calls this automatically
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/config.sh"

# Resolve OUTPUT_DIR to absolute path for symlinks
ABS_OUTPUT="$PROJECT_ROOT/$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# dnsmasq — TFTP server + proxy DHCP
#
# Proxy DHCP injects "next-server" (our host IP) into the router's DHCP
# replies, so U-Boot's `dhcp` command automatically uses our host as the
# TFTP server. No fw_setenv serverip needed.
# ---------------------------------------------------------------------------
setup_dnsmasq() {
    echo "==> Setting up dnsmasq (TFTP + proxy DHCP)..."

    if ! dpkg -l dnsmasq >/dev/null 2>&1; then
        echo "    Installing dnsmasq (needs sudo)..."
        sudo apt-get install -y dnsmasq
    fi

    if [ -z "$HOST_IP" ]; then
        echo "    Warning: HOST_IP not detected, skipping proxy DHCP config."
        echo "    Set BOARD in config so HOST_IP can be auto-detected."
        return
    fi

    # Detect the subnet from HOST_IP (e.g. 192.168.0.134 → 192.168.0.0)
    local subnet
    subnet="$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0/')"

    # Clear any conflicting settings from main dnsmasq.conf (our .d/ file
    # handles everything). Back up the original first.
    if grep -q '^[^#]' /etc/dnsmasq.conf 2>/dev/null; then
        sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
        sudo sh -c 'grep "^#\|^$" /etc/dnsmasq.conf > /etc/dnsmasq.conf.tmp && mv /etc/dnsmasq.conf.tmp /etc/dnsmasq.conf'
        echo "    Cleared active settings from /etc/dnsmasq.conf (backup: .bak)"
    fi

    # Generate dnsmasq config from template
    local conf="/etc/dnsmasq.d/bbb-netboot.conf"
    sed -e "s|TFTP_DIR_PLACEHOLDER|$TFTP_DIR|" \
        -e "s|HOST_IP_PLACEHOLDER|$HOST_IP|" \
        -e "s|192.168.0.0|$subnet|" \
        "$PROJECT_ROOT/board/bbb/dnsmasq.conf" | sudo tee "$conf" >/dev/null

    echo "    Wrote $conf"
    echo "    TFTP root: $TFTP_DIR"
    echo "    Proxy DHCP: next-server=$HOST_IP (subnet $subnet)"

    sudo systemctl restart dnsmasq
    echo "    dnsmasq restarted."
}

# ---------------------------------------------------------------------------
# TFTP symlinks — zImage + DTB point to output/images/ so every build
# is immediately available to U-Boot without any copy step.
# ---------------------------------------------------------------------------
setup_tftp() {
    echo "==> Setting up TFTP symlinks in $TFTP_DIR..."

    # Organize under $TFTP_DIR/$BOARD_NAME/ so multiple projects/boards
    # can share the same TFTP root without collisions.
    local tftp_board_dir="$TFTP_DIR/$BOARD_NAME"

    if [ ! -d "$TFTP_DIR" ]; then
        echo "    Creating $TFTP_DIR (needs sudo)..."
        sudo mkdir -p "$TFTP_DIR"
        sudo chown "$USER" "$TFTP_DIR"
    fi

    mkdir -p "$tftp_board_dir"

    # Symlink zImage
    ln -sf "$ABS_OUTPUT/images/zImage" "$tftp_board_dir/zImage"
    echo "    $tftp_board_dir/zImage → $ABS_OUTPUT/images/zImage"

    # Symlink DTB
    ln -sf "$ABS_OUTPUT/images/$DTB" "$tftp_board_dir/$DTB"
    echo "    $tftp_board_dir/$DTB → $ABS_OUTPUT/images/$DTB"

    echo "    OK — every 'make' updates TFTP automatically via symlinks."
}

# ---------------------------------------------------------------------------
# NFS export — add output/target/ to /etc/exports (idempotent).
# ---------------------------------------------------------------------------
setup_nfs() {
    # Resolve NFS_DIR to absolute path
    local nfs_abs
    if [ -d "$NFS_DIR" ]; then
        nfs_abs="$(cd "$NFS_DIR" && pwd)"
    else
        case "$NFS_DIR" in
            /*) nfs_abs="$NFS_DIR" ;;
            *)  nfs_abs="$PROJECT_ROOT/$NFS_DIR" ;;
        esac
    fi

    echo "==> Setting up NFS export for $nfs_abs..."

    if ! dpkg -l nfs-kernel-server >/dev/null 2>&1; then
        echo "    Installing nfs-kernel-server (needs sudo)..."
        sudo apt-get install -y nfs-kernel-server
    fi

    # all_squash + anonuid/anongid = host build user:
    #   - Board root writes → stored as build user on host → no sudo needed
    #   - Host user writes → board root can still access (root reads everything)
    #   - Both sides can read/write without permission issues
    local export_line="$nfs_abs *(rw,no_subtree_check,all_squash,anonuid=$(id -u),anongid=$(id -g))"
    if grep -qF "$nfs_abs" /etc/exports 2>/dev/null; then
        echo "    Already exported: $nfs_abs"
    else
        echo "$export_line" | sudo tee -a /etc/exports >/dev/null
        echo "    Added to /etc/exports: $export_line"
    fi

    sudo exportfs -ra
    echo "    OK — output/target/ is served via NFS."
}

# ---------------------------------------------------------------------------

setup_dnsmasq
setup_tftp
setup_nfs

echo ""
echo "Network boot ready. Next steps:"
echo "  1. Build:  make"
echo "  2. Switch: make tftp-boot   (or make nfs-boot)"
echo "  3. Done — every 'make' updates TFTP automatically."
echo "  4. To go back: make mmc-boot"
