"""
test_persistent_data.py — Verify persistent data bind-mounts on the BBB.

Run with:
    pytest tests/test_persistent_data.py --lg-env tests/env.yaml -v
"""

import pytest


class TestDataPersistService:
    """Verify the data-persist systemd service."""

    def test_service_exists(self, shell):
        stdout, _, rc = shell.run("systemctl cat data-persist.service")
        assert rc == 0

    def test_service_enabled(self, shell):
        stdout, _, rc = shell.run("systemctl is-enabled data-persist.service")
        assert rc == 0
        assert stdout[0].strip() == "enabled"

    def test_service_ran_successfully(self, shell):
        stdout, _, rc = shell.run(
            "systemctl show data-persist.service -p ActiveState --value"
        )
        assert rc == 0
        assert stdout[0].strip() == "active"

    def test_persist_script_exists(self, shell):
        stdout, _, rc = shell.run(
            "test -x /usr/lib/systemd/scripts/data-persist.sh && echo ok"
        )
        assert rc == 0


class TestBindMounts:
    """Verify persistent directories are bind-mounted from /data."""

    @pytest.mark.parametrize("data_path,mount_point", [
        ("/data/home", "/home"),
        ("/data/root", "/root"),
        ("/data/dropbear", "/etc/dropbear"),
        ("/data/journal", "/var/log/journal"),
    ])
    def test_directory_is_bind_mounted(self, shell, data_path, mount_point):
        """Each persistent path should be a bind mount from /data."""
        stdout, _, rc = shell.run(f"findmnt -n -o SOURCE {mount_point}")
        assert rc == 0, f"{mount_point} is not a mount point"
        source = stdout[0].strip()
        # The source should reference the data partition device
        assert "mmcblk0p4" in source or data_path in source, \
            f"{mount_point} source is {source}, expected /data partition"

    def test_machine_id_bind_mounted(self, shell):
        stdout, _, rc = shell.run("findmnt -n -o SOURCE /etc/machine-id")
        assert rc == 0, "/etc/machine-id is not bind-mounted"


class TestPersistentHome:
    """Verify /home and /root persist writes."""

    def test_root_home_writable(self, shell):
        stdout, _, rc = shell.run(
            "touch /root/.test_persist && rm /root/.test_persist && echo ok"
        )
        assert rc == 0

    def test_root_home_on_data_partition(self, shell):
        stdout, _, rc = shell.run("df /root | tail -1 | awk '{print $1}'")
        assert rc == 0
        assert "mmcblk0p4" in stdout[0], "/root is not on data partition"

    def test_home_on_data_partition(self, shell):
        stdout, _, rc = shell.run("df /home | tail -1 | awk '{print $1}'")
        assert rc == 0
        assert "mmcblk0p4" in stdout[0], "/home is not on data partition"


class TestPersistentSSHKeys:
    """Verify Dropbear SSH host keys are on the data partition."""

    def test_dropbear_dir_on_data(self, shell):
        stdout, _, rc = shell.run("df /etc/dropbear | tail -1 | awk '{print $1}'")
        assert rc == 0
        assert "mmcblk0p4" in stdout[0], "/etc/dropbear is not on data partition"

    def test_host_keys_exist(self, shell):
        """At least one host key should be present."""
        stdout, _, rc = shell.run("ls /etc/dropbear/dropbear_*_host_key 2>/dev/null")
        assert rc == 0, "No Dropbear host keys found"

    def test_host_keys_on_data(self, shell):
        """Keys should also be visible under /data/dropbear."""
        stdout, _, rc = shell.run("ls /data/dropbear/dropbear_*_host_key 2>/dev/null")
        assert rc == 0, "Host keys not found in /data/dropbear"


class TestPersistentJournal:
    """Verify journal logs are stored persistently."""

    def test_journal_dir_on_data(self, shell):
        stdout, _, rc = shell.run(
            "df /var/log/journal | tail -1 | awk '{print $1}'"
        )
        assert rc == 0
        assert "mmcblk0p4" in stdout[0], "/var/log/journal is not on data partition"

    def test_journal_has_entries(self, shell):
        stdout, _, rc = shell.run("journalctl -b --no-pager --lines=3")
        assert rc == 0
        assert len(stdout) > 0


class TestMachineId:
    """Verify machine-id is stable and persistent."""

    def test_machine_id_not_empty(self, shell):
        stdout, _, rc = shell.run("cat /etc/machine-id")
        assert rc == 0
        mid = stdout[0].strip()
        assert len(mid) == 32, f"machine-id looks wrong: {mid}"

    def test_machine_id_matches_data(self, shell):
        """machine-id on rootfs should match the one on /data."""
        stdout, _, rc = shell.run("cat /etc/machine-id")
        assert rc == 0
        rootfs_id = stdout[0].strip()

        stdout, _, rc = shell.run("cat /data/machine-id")
        assert rc == 0
        data_id = stdout[0].strip()

        assert rootfs_id == data_id


class TestShellHistory:
    """Verify shell history persists across sessions."""

    def test_history_file_on_data_partition(self, shell):
        """History file should be on the persistent /data partition."""
        stdout, _, rc = shell.run("df /root/.ash_history 2>/dev/null | tail -1 | awk '{print $1}'")
        # File may not exist yet on a fresh system; create it first
        if rc != 0:
            shell.run("touch /root/.ash_history")
            stdout, _, rc = shell.run("df /root/.ash_history | tail -1 | awk '{print $1}'")
        assert rc == 0
        assert "mmcblk0p4" in stdout[0], "history file is not on data partition"

    def test_data_persist_before_getty(self, shell):
        """data-persist.service must start before getty.target (login shells)."""
        stdout, _, rc = shell.run(
            "systemctl show data-persist.service -p Before --value"
        )
        assert rc == 0
        assert "getty.target" in stdout[0], "data-persist must be Before=getty.target"

    def test_histsize_set(self, shell):
        """HISTSIZE should be set by profile.d/shell.sh."""
        stdout, _, rc = shell.run("sh -lc 'echo $HISTSIZE'")
        assert rc == 0
        assert stdout[0].strip() == "1000"

    def test_history_write_and_read(self, shell):
        """Write a unique command to history file and verify it persists."""
        marker = "test_history_marker_12345"
        shell.run(f"echo '{marker}' >> /root/.ash_history")
        stdout, _, rc = shell.run(f"grep -c '{marker}' /root/.ash_history")
        assert rc == 0
        assert int(stdout[0].strip()) >= 1
        # Cleanup
        shell.run(f"sed -i '/{marker}/d' /root/.ash_history")

    def test_trap_exits_on_term(self, shell):
        """SIGTERM trap must call 'exit', not the broken 'history -w'."""
        stdout, _, rc = shell.run("sh -lc 'trap' 2>&1")
        assert rc == 0
        trap_output = " ".join(stdout)
        assert "exit 0" in trap_output, (
            "TERM/HUP trap must use 'exit 0' to trigger SAVE_ON_EXIT; "
            "BusyBox ash's 'history -w' is a no-op"
        )
        assert "history -w" not in trap_output, (
            "history -w is a no-op in BusyBox ash — trap must use 'exit 0'"
        )


class TestDataPartitionHealth:
    """General health checks for the data partition."""

    def test_data_not_full(self, shell):
        """Data partition should not be more than 90% full."""
        stdout, _, rc = shell.run(
            "df /data | tail -1 | awk '{print $5}' | tr -d '%'"
        )
        assert rc == 0
        usage = int(stdout[0].strip())
        assert usage < 90, f"/data is {usage}% full"

    def test_rauc_dir_exists(self, shell):
        stdout, _, rc = shell.run("test -d /data/rauc && echo ok")
        assert rc == 0

    def test_all_data_dirs_exist(self, shell):
        """All expected persistent directories should exist."""
        for d in ["home", "root", "dropbear", "journal", "rauc"]:
            stdout, _, rc = shell.run(f"test -d /data/{d} && echo ok")
            assert rc == 0, f"/data/{d} does not exist"
