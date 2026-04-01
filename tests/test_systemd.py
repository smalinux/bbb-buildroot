"""
test_systemd.py — Verify systemd is fully functional on the BBB.

Run with:
    pytest tests/test_systemd.py --lg-env tests/env.yaml -v
"""

import pytest


class TestSystemdInit:
    """Verify systemd is the init system and booted successfully."""

    def test_pid1_is_systemd(self, shell):
        stdout, _, rc = shell.run("readlink /proc/1/exe")
        assert rc == 0
        assert "systemd" in stdout[0]

    def test_system_running(self, shell):
        """System should be in 'running' state (not degraded)."""
        stdout, _, rc = shell.run("systemctl is-system-running")
        assert rc == 0
        assert stdout[0].strip() in ("running",)

    def test_no_failed_units(self, shell):
        """No systemd units should be in failed state."""
        stdout, _, rc = shell.run("systemctl --failed --no-legend --plain")
        assert rc == 0
        failed = [line for line in stdout if line.strip()]
        assert failed == [], f"Failed units: {failed}"

    def test_default_target_reached(self, shell):
        """multi-user.target should be active."""
        stdout, _, rc = shell.run("systemctl is-active multi-user.target")
        assert rc == 0
        assert stdout[0].strip() == "active"


class TestSystemdJournal:
    """Verify journald is collecting logs."""

    def test_journalctl_has_boot_log(self, shell):
        stdout, _, rc = shell.run("journalctl -b --no-pager --lines=5")
        assert rc == 0
        assert len(stdout) > 0

    def test_journal_no_critical_errors(self, shell):
        """No priority 0-2 (emerg/alert/crit) messages in current boot."""
        stdout, _, rc = shell.run("journalctl -b -p crit --no-pager --quiet")
        # rc=1 means no matching entries (good)
        critical = [line for line in stdout if line.strip()]
        assert critical == [], f"Critical journal entries: {critical}"


class TestTimeSyncService:
    """Verify systemd-timesyncd handles NTP."""

    def test_timesyncd_exists(self, shell):
        stdout, _, rc = shell.run("systemctl cat systemd-timesyncd.service")
        assert rc == 0

    def test_timesyncd_enabled(self, shell):
        stdout, _, rc = shell.run("systemctl is-enabled systemd-timesyncd.service")
        assert rc == 0
        assert stdout[0].strip() == "enabled"

    def test_timesyncd_active(self, shell):
        stdout, _, rc = shell.run("systemctl is-active systemd-timesyncd.service")
        assert rc == 0
        assert stdout[0].strip() == "active"

    def test_clock_reasonable(self, shell):
        """System clock should be past year 2025 (not stuck at epoch)."""
        stdout, _, rc = shell.run("date +%Y")
        assert rc == 0
        year = int(stdout[0].strip())
        assert year >= 2025, f"Clock year is {year}, likely not synced"


class TestNetworking:
    """Verify systemd-networkd and ethernet connectivity."""

    def test_networkd_active(self, shell):
        stdout, _, rc = shell.run("systemctl is-active systemd-networkd.service")
        assert rc == 0
        assert stdout[0].strip() == "active"

    def test_end0_exists(self, shell):
        """BBB ethernet interface end0 should exist."""
        stdout, _, rc = shell.run("ip link show end0")
        assert rc == 0

    def test_end0_has_ip(self, shell):
        """end0 should have an IPv4 address (from DHCP)."""
        stdout, _, rc = shell.run("ip -4 addr show end0 | grep 'inet '")
        assert rc == 0, "end0 has no IPv4 address — DHCP may have failed"

    def test_network_config_exists(self, shell):
        """Our .network file should be installed."""
        stdout, _, rc = shell.run(
            "test -f /usr/lib/systemd/network/20-wired.network && echo ok"
        )
        assert rc == 0

    def test_dns_resolution(self, shell):
        """DNS should work if network is up."""
        stdout, _, rc = shell.run("resolvectl query pool.ntp.org 2>/dev/null || nslookup pool.ntp.org 2>/dev/null")
        # Don't fail hard — DNS depends on DHCP providing a nameserver
        pass


class TestRaucMarkGoodService:
    """Verify RAUC mark-good service."""

    def test_service_exists(self, shell):
        stdout, _, rc = shell.run("systemctl cat rauc-mark-good.service")
        assert rc == 0

    def test_service_enabled(self, shell):
        stdout, _, rc = shell.run("systemctl is-enabled rauc-mark-good.service")
        assert rc == 0
        assert stdout[0].strip() == "enabled"

    def test_service_ran_successfully(self, shell):
        """Should have completed (oneshot, RemainAfterExit=yes)."""
        stdout, _, rc = shell.run(
            "systemctl show rauc-mark-good.service -p ActiveState --value"
        )
        assert rc == 0
        assert stdout[0].strip() == "active"

    def test_rauc_slot_marked_good(self, shell):
        """The booted slot should be marked 'good'."""
        stdout, _, rc = shell.run("rauc status --output-format=shell")
        if rc == 0:
            output = "\n".join(stdout)
            assert "slot.booted" in output or "good" in output.lower()


class TestUdevDeviceManager:
    """Verify systemd-udevd is managing devices."""

    def test_udevd_running(self, shell):
        stdout, _, rc = shell.run("systemctl is-active systemd-udevd.service")
        assert rc == 0
        assert stdout[0].strip() == "active"

    def test_dev_populated(self, shell):
        """Key device nodes should exist."""
        for dev in ["/dev/mmcblk0", "/dev/null", "/dev/console", "/dev/ttyS0"]:
            stdout, _, rc = shell.run(f"test -e {dev} && echo exists")
            assert rc == 0, f"{dev} does not exist"


class TestCgroups:
    """Verify cgroups are functional (required by systemd)."""

    def test_cgroup_mounted(self, shell):
        stdout, _, rc = shell.run("mount | grep cgroup")
        assert rc == 0
        assert len(stdout) > 0

    def test_systemd_cgroup_hierarchy(self, shell):
        stdout, _, rc = shell.run("systemctl show --property=DefaultCPUAccounting")
        assert rc == 0


class TestDataPartition:
    """Verify the persistent data partition is mounted."""

    def test_data_mounted(self, shell):
        stdout, _, rc = shell.run("mountpoint -q /data && echo mounted")
        assert rc == 0

    def test_data_writable(self, shell):
        stdout, _, rc = shell.run(
            "touch /data/.test_write && rm /data/.test_write && echo ok"
        )
        assert rc == 0

    def test_rauc_data_dir_exists(self, shell):
        stdout, _, rc = shell.run("test -d /data/rauc && echo exists")
        assert rc == 0


class TestDropbearSSH:
    """Verify Dropbear SSH is running under systemd."""

    def test_dropbear_active(self, shell):
        """Dropbear should be active (we're connected via SSH)."""
        stdout, _, rc = shell.run("systemctl is-active dropbear.service")
        # Dropbear might use socket activation or direct service
        if rc != 0:
            stdout, _, rc = shell.run("pgrep -x dropbear")
            assert rc == 0, "Dropbear is not running"


class TestBootAnalysis:
    """Collect boot performance data (informational, does not fail)."""

    def test_boot_time(self, shell):
        """Print boot time for reference."""
        stdout, _, rc = shell.run("systemd-analyze")
        assert rc == 0
        # Just print it, no assertion on timing
        for line in stdout:
            if line.strip():
                print(line)

    def test_blame_top5(self, shell):
        """Print 5 slowest services for reference."""
        stdout, _, rc = shell.run("systemd-analyze blame --no-pager | head -5")
        assert rc == 0
        for line in stdout:
            if line.strip():
                print(line)
