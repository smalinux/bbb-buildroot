# Multi-mode boot script for BeagleBone Black
#
# On every boot, a 3-second menu appears on the serial console:
#
#   [0] MMC boot (A/B RAUC)           ← default if boot_mode=mmc
#   [1] TFTP boot (kernel from network)
#   [2] NFS boot (kernel + rootfs from network)
#
# Selecting an entry saves boot_mode to env, so the next boot defaults
# to the same choice. Press Enter or wait 3s for the highlighted default.
#
# For tftp/nfs, set the host IP once:
#   fw_setenv serverip 192.168.0.100
#
# For nfs, also set the NFS export path:
#   fw_setenv nfs_dir /src/bbb-buildroot/output/target
#
# You can also switch modes without the menu (e.g. over SSH):
#   fw_setenv boot_mode tftp && reboot
#   fw_setenv boot_mode nfs  && reboot
#   fw_setenv boot_mode mmc  && reboot
#
# U-Boot env variables used (RAUC bootchooser, mmc mode only):
#   BOOT_ORDER  - slot priority: "A B" or "B A"
#   BOOT_A_LEFT - remaining boot attempts for slot A
#   BOOT_B_LEFT - remaining boot attempts for slot B

# Default to mmc boot if boot_mode is not set
if test -z "${boot_mode}"; then setenv boot_mode mmc; fi

# Boot menu is available manually from U-Boot prompt: run bootmenu_show
# To use it interactively, stop autoboot and type: run bootmenu_show

echo "=== Boot mode: ${boot_mode} ==="

# ---------------------------------------------------------------------------
# Common bootargs (shared across all modes)
# ---------------------------------------------------------------------------
# reboot=cold: use cold reset (PRM_RSTCTRL bit 1) so the MMC controller
# is fully re-initialised — prevents ROM bootloader "CCCCCCCC" hang.
setenv base_args "console=ttyS0,115200n8 reboot=cold"

# ---------------------------------------------------------------------------
# TFTP boot — kernel + DTB from network, rootfs from active MMC slot
# ---------------------------------------------------------------------------
if test "${boot_mode}" = "tftp"; then
    # Get an IP via DHCP if the board doesn't have one yet.
    # autoload=no: only do DHCP, don't try to TFTP download a file.
    # dnsmasq proxy DHCP sets serverip (next-server) to the host automatically.
    if test -z "${ipaddr}"; then
        setenv autoload no
        dhcp
    fi

    echo "Loading kernel + DTB from ${serverip}:${tftp_dir}..."
    tftp ${kernel_addr_r} ${tftp_dir}zImage
    tftp ${fdt_addr_r} ${tftp_dir}am335x-boneblack.dtb

    # Load initramfs from TFTP if available (recovery + overlayfs support)
    setenv initrd_args "-"
    if tftp ${ramdisk_addr_r} ${tftp_dir}initramfs.uImage; then
        setenv initrd_args "${ramdisk_addr_r}"
    fi

    # Root from the active RAUC slot on MMC (default to partition 2 = slot A).
    # The user can override: fw_setenv root_part 3  (for slot B)
    if test -z "${root_part}"; then setenv root_part 2; fi

    setenv bootargs "${base_args} root=/dev/mmcblk0p${root_part} rw rootfstype=ext4 rootwait ${optargs}"
    echo "Booting TFTP kernel with MMC rootfs (partition ${root_part})..."
    bootz ${kernel_addr_r} ${initrd_args} ${fdt_addr_r}
fi

# ---------------------------------------------------------------------------
# NFS boot — kernel + DTB from TFTP, rootfs from NFS
# ---------------------------------------------------------------------------
if test "${boot_mode}" = "nfs"; then
    # Get an IP via DHCP if the board doesn't have one yet.
    # autoload=no: only do DHCP, don't try to TFTP download a file.
    # dnsmasq proxy DHCP sets serverip (next-server) to the host automatically.
    if test -z "${ipaddr}"; then
        setenv autoload no
        dhcp
    fi

    echo "Loading kernel + DTB from ${serverip}:${tftp_dir}..."
    tftp ${kernel_addr_r} ${tftp_dir}zImage
    tftp ${fdt_addr_r} ${tftp_dir}am335x-boneblack.dtb

    # nfs_dir must be set: fw_setenv nfs_dir /path/to/output/target
    if test -z "${nfs_dir}"; then
        echo "ERROR: nfs_dir not set. Run:"
        echo "  fw_setenv nfs_dir /path/to/nfsroot"
        exit
    fi

    setenv bootargs "${base_args} root=/dev/nfs rw nfsroot=${serverip}:${nfs_dir},v3,tcp ip=dhcp ${optargs}"
    echo "Booting NFS root from ${serverip}:${nfs_dir}..."
    bootz ${kernel_addr_r} - ${fdt_addr_r}
fi

# ---------------------------------------------------------------------------
# MMC boot — A/B RAUC boot from SD card (default, production path)
# ---------------------------------------------------------------------------
echo "=== RAUC A/B Boot ==="

# Defaults
if test -z "${BOOT_ORDER}"; then setenv BOOT_ORDER "A B"; fi
if test -z "${BOOT_A_LEFT}"; then setenv BOOT_A_LEFT 3; fi
if test -z "${BOOT_B_LEFT}"; then setenv BOOT_B_LEFT 3; fi

# Select slot: try each in BOOT_ORDER, skip if no attempts left
setenv boot_slot ""
for slot in ${BOOT_ORDER}; do
    if test -z "${boot_slot}"; then
        if test "${slot}" = "A" && test ${BOOT_A_LEFT} -gt 0; then
            setenv boot_slot A
            setenv root_part 2
            setexpr BOOT_A_LEFT ${BOOT_A_LEFT} - 1
        elif test "${slot}" = "B" && test ${BOOT_B_LEFT} -gt 0; then
            setenv boot_slot B
            setenv root_part 3
            setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1
        fi
    fi
done

if test -z "${boot_slot}"; then
    echo "No bootable slot found! Resetting to defaults..."
    setenv BOOT_ORDER "A B"
    setenv BOOT_A_LEFT 3
    setenv BOOT_B_LEFT 3
    setenv boot_slot A
    setenv root_part 2
fi

saveenv

echo "Booting slot ${boot_slot} (partition ${root_part})"

# optargs: extra kernel cmdline args from U-Boot env (e.g. bbb.recovery,
# bbb.overlayfs).  Set via: fw_setenv optargs bbb.recovery
setenv bootargs "${base_args} root=/dev/mmcblk0p${root_part} rw rootfstype=ext4 rootwait rauc.slot=${boot_slot} ${optargs}"

# Load kernel and DTB from the active rootfs partition (/boot/)
# so they are updated together with the rootfs via RAUC OTA.
load mmc 0:${root_part} ${kernel_addr_r} boot/zImage
load mmc 0:${root_part} ${fdt_addr_r} boot/am335x-boneblack.dtb

# Load initramfs if present; boot without it otherwise (backward compat).
# The initramfs provides a recovery shell (bbb.recovery) and overlayfs
# root support (bbb.overlayfs).  U-Boot reads the size from the uImage
# header, so no :${filesize} suffix is needed.
setenv initrd_args "-"
if load mmc 0:${root_part} ${ramdisk_addr_r} boot/initramfs.uImage; then
    setenv initrd_args "${ramdisk_addr_r}"
fi

bootz ${kernel_addr_r} ${initrd_args} ${fdt_addr_r}
