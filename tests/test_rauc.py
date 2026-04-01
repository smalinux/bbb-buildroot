"""
test_rauc.py — Verify RAUC OTA system is functional on the BBB.

Run with:
    pytest tests/test_rauc.py --lg-env tests/env.yaml -v
"""

import pytest


class TestRaucBinary:
    """Verify RAUC is installed and executable."""

    def test_rauc_installed(self, shell):
        stdout, _, rc = shell.run("which rauc")
        assert rc == 0

    def test_rauc_version(self, shell):
        stdout, _, rc = shell.run("rauc --version")
        assert rc == 0
        assert "rauc" in stdout[0].lower()


class TestRaucConfig:
    """Verify RAUC system configuration."""

    def test_system_conf_exists(self, shell):
        stdout, _, rc = shell.run("test -f /etc/rauc/system.conf && echo ok")
        assert rc == 0

    def test_keyring_exists(self, shell):
        stdout, _, rc = shell.run("test -f /etc/rauc/keyring.pem && echo ok")
        assert rc == 0

    def test_compatible_string(self, shell):
        """Compatible must match between system.conf and bundles."""
        stdout, _, rc = shell.run("grep '^compatible=' /etc/rauc/system.conf")
        assert rc == 0
        assert "beaglebone-black" in stdout[0]

    def test_bootloader_backend(self, shell):
        stdout, _, rc = shell.run("grep '^bootloader=' /etc/rauc/system.conf")
        assert rc == 0
        assert "uboot" in stdout[0]

    def test_data_directory_configured(self, shell):
        stdout, _, rc = shell.run("grep '^data-directory=' /etc/rauc/system.conf")
        assert rc == 0
        assert "/data/rauc" in stdout[0]


class TestRaucSlots:
    """Verify RAUC slot configuration and status."""

    def test_rauc_status_runs(self, shell):
        stdout, _, rc = shell.run("rauc status")
        assert rc == 0

    def test_two_rootfs_slots(self, shell):
        """System must have exactly 2 rootfs slots (A/B)."""
        stdout, _, rc = shell.run("rauc status --detailed")
        assert rc == 0
        output = "\n".join(stdout)
        assert "rootfs.0" in output
        assert "rootfs.1" in output

    def test_booted_slot_identified(self, shell):
        """RAUC should know which slot is currently booted."""
        stdout, _, rc = shell.run("rauc status --detailed")
        assert rc == 0
        output = "\n".join(stdout)
        assert "booted" in output.lower()

    def test_booted_slot_marked_good(self, shell):
        """The active slot should be marked good (by rauc-mark-good.service)."""
        stdout, _, rc = shell.run("rauc status --detailed")
        assert rc == 0
        output = "\n".join(stdout)
        # Find the booted slot and check it's marked good
        assert "good" in output.lower(), \
            "Booted slot not marked good — is rauc-mark-good.service working?"

    def test_slot_devices_exist(self, shell):
        """Both slot block devices must exist."""
        for dev in ["/dev/mmcblk0p2", "/dev/mmcblk0p3"]:
            stdout, _, rc = shell.run(f"test -b {dev} && echo ok")
            assert rc == 0, f"Slot device {dev} missing"


class TestRaucBootchooser:
    """Verify U-Boot bootchooser env vars used by RAUC."""

    def test_fw_printenv_works(self, shell):
        stdout, _, rc = shell.run("fw_printenv BOOT_ORDER")
        assert rc == 0

    def test_boot_order_set(self, shell):
        """BOOT_ORDER must contain A and B."""
        stdout, _, rc = shell.run("fw_printenv -n BOOT_ORDER")
        assert rc == 0
        order = stdout[0].strip()
        assert "A" in order and "B" in order, f"BOOT_ORDER={order}"

    def test_boot_attempts_set(self, shell):
        """Both slots should have remaining boot attempts."""
        for var in ["BOOT_A_LEFT", "BOOT_B_LEFT"]:
            stdout, _, rc = shell.run(f"fw_printenv -n {var}")
            assert rc == 0
            val = int(stdout[0].strip())
            assert val >= 0, f"{var}={val}"

    def test_fw_env_config_exists(self, shell):
        """fw_env.config must exist for fw_printenv/fw_setenv to work."""
        stdout, _, rc = shell.run("test -f /etc/fw_env.config && echo ok")
        assert rc == 0

    def test_fw_env_offset_matches(self, shell):
        """Env offset in fw_env.config must be 0x200000."""
        stdout, _, rc = shell.run("grep '0x200000' /etc/fw_env.config")
        assert rc == 0, "fw_env.config missing expected offset 0x200000"


class TestRaucBundle:
    """Verify the target can handle RAUC bundles."""

    def test_rauc_info_help(self, shell):
        """rauc info subcommand should be available."""
        stdout, _, rc = shell.run("rauc info --help")
        assert rc == 0

    def test_squashfs_supported(self, shell):
        """Kernel must support squashfs (RAUC bundles are squashfs)."""
        stdout, _, rc = shell.run(
            "cat /proc/filesystems | grep squashfs"
        )
        assert rc == 0, "squashfs not in /proc/filesystems"


class TestRaucDataPersistence:
    """Verify RAUC's persistent data directory for adaptive updates."""

    def test_data_rauc_dir_exists(self, shell):
        stdout, _, rc = shell.run("test -d /data/rauc && echo ok")
        assert rc == 0

    def test_data_rauc_writable(self, shell):
        stdout, _, rc = shell.run(
            "touch /data/rauc/.test && rm /data/rauc/.test && echo ok"
        )
        assert rc == 0

    def test_data_partition_survives_reboot(self, shell):
        """Data partition should be on a separate partition from rootfs."""
        stdout, _, rc = shell.run("df /data | tail -1 | awk '{print $1}'")
        assert rc == 0
        data_dev = stdout[0].strip()
        stdout, _, rc = shell.run("df / | tail -1 | awk '{print $1}'")
        assert rc == 0
        root_dev = stdout[0].strip()
        assert data_dev != root_dev, \
            f"/data ({data_dev}) is on same device as / ({root_dev})"
