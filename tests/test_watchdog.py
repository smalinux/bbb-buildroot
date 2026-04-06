"""
test_watchdog.py — Verify hardware watchdog daemon on the BBB.

The AM335x has a built-in OMAP watchdog timer.  The watchdog daemon
pets /dev/watchdog0 at regular intervals; if the system hangs, the
hardware forces a reboot.

Run with:
    pytest tests/test_watchdog.py --lg-env tests/env.yaml -v

    # Include the destructive sysrq reboot test (takes ~90s):
    pytest tests/test_watchdog.py --lg-env tests/env.yaml -v --run-destructive
"""

import time

import pytest


def pytest_addoption(parser):
    """Register --run-destructive flag."""
    # guard against duplicate registration when conftest also adds options
    try:
        parser.addoption(
            "--run-destructive", action="store_true", default=False,
            help="run destructive tests (sysrq crash, forced reboot)",
        )
    except ValueError:
        pass


class TestWatchdogDevice:
    """Verify the OMAP watchdog hardware is present."""

    def test_watchdog_device_exists(self, shell):
        """The OMAP WDT should expose /dev/watchdog0."""
        stdout, _, rc = shell.run("test -c /dev/watchdog0")
        assert rc == 0

    def test_omap_wdt_driver_loaded(self, shell):
        """The omap_wdt kernel driver should be active."""
        stdout, _, rc = shell.run("dmesg | grep -i 'omap_wdt'")
        assert rc == 0
        assert len(stdout) > 0, "No omap_wdt messages in dmesg"


class TestWatchdogDaemon:
    """Verify the watchdog daemon is installed and running."""

    def test_binary_exists(self, shell):
        stdout, _, rc = shell.run("test -x /sbin/watchdog")
        assert rc == 0

    def test_config_exists(self, shell):
        stdout, _, rc = shell.run("test -f /etc/watchdog.conf")
        assert rc == 0

    def test_config_references_device(self, shell):
        """Config must point to the correct watchdog device."""
        stdout, _, rc = shell.run("grep 'watchdog-device' /etc/watchdog.conf")
        assert rc == 0
        assert "/dev/watchdog0" in stdout[0]


class TestWatchdogService:
    """Verify the systemd service is enabled and active."""

    def test_service_exists(self, shell):
        stdout, _, rc = shell.run("systemctl cat watchdog.service")
        assert rc == 0

    def test_service_enabled(self, shell):
        stdout, _, rc = shell.run("systemctl is-enabled watchdog.service")
        assert rc == 0
        assert stdout[0].strip() == "enabled"

    def test_service_active(self, shell):
        stdout, _, rc = shell.run("systemctl is-active watchdog.service")
        assert rc == 0
        assert stdout[0].strip() == "active"

    def test_daemon_process_running(self, shell):
        """The watchdog process should be running."""
        # pidof is from busybox (pgrep requires procps-ng which isn't installed)
        stdout, _, rc = shell.run("pidof watchdog")
        assert rc == 0

    def test_watchdog_device_open(self, shell):
        """The daemon should hold /dev/watchdog0 open (petting it)."""
        stdout, _, rc = shell.run(
            "ls -l /proc/$(pidof watchdog)/fd/ 2>/dev/null "
            "| grep watchdog"
        )
        assert rc == 0


class TestSysrqSupport:
    """Verify Magic SysRq is enabled (needed for watchdog crash testing)."""

    def test_sysrq_enabled(self, shell):
        """CONFIG_MAGIC_SYSRQ must be compiled in."""
        stdout, _, rc = shell.run("cat /proc/sys/kernel/sysrq")
        assert rc == 0
        # Value > 0 means sysrq is enabled (1 = all, or bitmask)
        assert int(stdout[0].strip()) > 0

    def test_sysrq_trigger_exists(self, shell):
        stdout, _, rc = shell.run("test -w /proc/sysrq-trigger")
        assert rc == 0


class TestWatchdogReboot:
    """Trigger a kernel panic via SysRq and verify the watchdog reboots the board.

    This is a destructive test — it crashes the kernel on purpose.  The
    hardware watchdog (OMAP WDT) should detect that the daemon stopped
    petting and force a reboot within ~60 seconds.

    Only runs with: pytest --run-destructive

    Procedure:
      1. Record uptime
      2. Trigger kernel panic via 'echo c > /proc/sysrq-trigger'
      3. Wait for the board to come back (SSH reconnect)
      4. Verify uptime is lower (board rebooted)
    """

    @pytest.fixture(autouse=True)
    def _skip_unless_destructive(self, request):
        if not request.config.getoption("--run-destructive"):
            pytest.skip("destructive test — pass --run-destructive to run")

    def test_sysrq_crash_triggers_watchdog_reboot(self, target, shell):
        """Crash the kernel and verify the watchdog brings the board back."""
        # 1. Record current uptime (seconds since boot)
        stdout, _, rc = shell.run("cat /proc/uptime")
        assert rc == 0
        uptime_before = float(stdout[0].split()[0])

        # 2. Trigger kernel panic — this kills the SSH connection
        #    Use nohup + background so the command is sent before the
        #    connection drops.  The shell.run() will likely raise or
        #    return an error — that's expected.
        try:
            shell.run("nohup sh -c 'sleep 1; echo c > /proc/sysrq-trigger' &")
        except Exception:
            pass  # connection lost — expected

        # 3. Wait for the board to reboot.  The OMAP WDT timeout is ~60s.
        #    Give extra margin for U-Boot + kernel boot.
        time.sleep(90)

        # 4. Reconnect SSH
        ssh = target.get_driver("SSHDriver")
        ssh.activate()

        # 5. Verify uptime is lower (board rebooted)
        stdout, _, rc = ssh.run("cat /proc/uptime")
        assert rc == 0
        uptime_after = float(stdout[0].split()[0])
        assert uptime_after < uptime_before, (
            f"Board did not reboot: uptime before={uptime_before:.0f}s, "
            f"after={uptime_after:.0f}s"
        )
