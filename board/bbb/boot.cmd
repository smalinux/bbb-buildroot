# A/B boot script for BeagleBone Black with SWUpdate
#
# U-Boot env variables used:
#   root_part   - active rootfs partition: 2=A (default), 3=B
#   upgrade_available - set to 1 by SWUpdate after installing update
#   bootcount   - incremented each boot when upgrade_available=1
#   bootlimit   - max boot attempts before rollback (default 3)

echo "=== SWUpdate A/B Boot ==="

# Defaults
if test -z "${root_part}"; then setenv root_part 2; fi
if test -z "${bootlimit}"; then setenv bootlimit 3; fi
if test -z "${bootcount}"; then setenv bootcount 0; fi
if test -z "${upgrade_available}"; then setenv upgrade_available 0; fi

# Bootcount rollback logic
if test "${upgrade_available}" = "1"; then
    setexpr bootcount ${bootcount} + 1
    saveenv

    if test ${bootcount} -gt ${bootlimit}; then
        echo "Boot limit reached! Rolling back..."
        if test "${root_part}" = "2"; then
            setenv root_part 3
        else
            setenv root_part 2
        fi
        setenv upgrade_available 0
        setenv bootcount 0
        saveenv
    fi
fi

echo "Booting from partition ${root_part}"

setenv bootargs console=ttyS0,115200n8 root=/dev/mmcblk0p${root_part} rw rootfstype=ext4 rootwait

load mmc 0:1 ${kernel_addr_r} zImage
load mmc 0:1 ${fdt_addr_r} am335x-boneblack.dtb

bootz ${kernel_addr_r} - ${fdt_addr_r}
