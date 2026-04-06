# AM335x Cold Reset

## Problem

After `reboot`, the BeagleBone Black sometimes fails to boot and prints
`CCCCCCCC` on the serial console. The board requires a manual power cycle
to recover.

## Root cause

By default the AM335x kernel performs a **warm reset** (PRM_RSTCTRL
bit 0), which does not fully reset all on-chip peripherals. The MMC
controller can be left in an undefined state. When the ROM bootloader
then tries to load MLO/SPL from the SD card, it finds an unresponsive
bus and falls back to UART boot mode (the `CCCCCCCC` bytes are XMODEM
sync requests).

## Fix

The kernel's AM335x reset handler (`prm33xx.c`) already supports cold
reset — it checks `prm_reboot_mode == REBOOT_COLD` and writes bit 1 of
PRM_RSTCTRL instead of bit 0. Cold reset re-initialises all peripherals
including the MMC controller.

The fix is a single bootarg in `board/bbb/boot.cmd`:

```
reboot=cold
```

This sets the kernel's global `reboot_mode` to `REBOOT_COLD`, which
flows through `am33xx_restart()` into the cold reset path.

### Trade-off

Cold reset takes slightly longer than warm reset because the ROM must
re-initialise all peripherals from scratch. In practice the difference is
under one second.

## Verification

After flashing, reboot the board and check the reset-status register:

```
devmem2 0x44E00F08 w
```

Bit 1 (`GLOBAL_COLD_SW_RST`) should be set. The automated test
`tests/test_cold_reset.py` checks this, and also verifies the bootarg
is present in `/proc/cmdline`.
