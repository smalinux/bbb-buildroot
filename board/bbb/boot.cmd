# A/B boot script for BeagleBone Black with RAUC
#
# U-Boot env variables used (RAUC bootchooser):
#   BOOT_ORDER  - slot priority: "A B" or "B A"
#   BOOT_A_LEFT - remaining boot attempts for slot A
#   BOOT_B_LEFT - remaining boot attempts for slot B

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

setenv bootargs console=ttyS0,115200n8 root=/dev/mmcblk0p${root_part} rw rootfstype=ext4 rootwait rauc.slot=${boot_slot}

# Load kernel and DTB from the active rootfs partition (/boot/)
# so they are updated together with the rootfs via RAUC OTA.
load mmc 0:${root_part} ${kernel_addr_r} boot/zImage
load mmc 0:${root_part} ${fdt_addr_r} boot/am335x-boneblack.dtb

bootz ${kernel_addr_r} - ${fdt_addr_r}
