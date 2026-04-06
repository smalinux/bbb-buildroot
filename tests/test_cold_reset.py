"""
test_cold_reset.py — Verify the kernel uses cold reset on the AM335x.

Cold reset (PRM_RSTCTRL bit 1) fully re-initialises all peripherals
including the MMC controller, preventing the ROM bootloader from hanging
with "CCCCCCCC" after reboot.

Run with:
    pytest tests/test_cold_reset.py --lg-env tests/env.yaml -v
"""


class TestColdReset:
    """Verify cold reset is configured and active."""

    def test_reboot_cold_in_cmdline(self, shell):
        """The reboot=cold bootarg must be present in /proc/cmdline."""
        stdout, _, rc = shell.run("cat /proc/cmdline")
        assert rc == 0
        assert "reboot=cold" in stdout[0], (
            f"reboot=cold not in cmdline: {stdout[0]}"
        )

    def test_prm_rstst_cold_bit(self, shell):
        """PRM_RSTST (0x44E00F08) bit 1 (GLOBAL_COLD_SW_RST) should be
        set after a cold reset.  If only bit 0 (GLOBAL_WARM_SW_RST) is
        set, the bootarg is not taking effect.
        """
        stdout, _, rc = shell.run("devmem2 0x44E00F08 w")
        assert rc == 0, "devmem2 not available — enable BR2_PACKAGE_DEVMEM2"
        value = None
        for line in stdout:
            if "0x44E00F08" in line.lower() or "value" in line.lower():
                parts = line.strip().split()
                value = int(parts[-1], 16)
                break
        assert value is not None, f"Could not parse devmem2 output: {stdout}"
        cold_bit = (value >> 1) & 1
        assert cold_bit == 1, (
            f"PRM_RSTST=0x{value:x}: cold-reset bit not set — "
            "kernel may still be using warm reset"
        )
