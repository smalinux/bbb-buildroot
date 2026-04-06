"""
test_tftp_nfs.py — Verify TFTP + NFS boot infrastructure is configured.

Host-side tests (no board needed). Checks that:
- linux.fragment has NFS root kernel configs
- uboot.fragment has bootmenu enabled
- boot.cmd supports mmc/tftp/nfs boot modes with bootmenu
- netboot-setup.sh and boot-mode.sh exist and are executable
- config.sh exposes HOST_IP and NFS_DIR

Run with:
    pytest tests/test_tftp_nfs.py -v
"""

import os
import subprocess
import textwrap

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
BOOT_CMD = os.path.join(PROJECT_ROOT, "board", "bbb", "boot.cmd")
LINUX_FRAGMENT = os.path.join(PROJECT_ROOT, "board", "bbb", "linux.fragment")
UBOOT_FRAGMENT = os.path.join(PROJECT_ROOT, "board", "bbb", "uboot.fragment")
NETBOOT_SETUP = os.path.join(PROJECT_ROOT, "scripts", "netboot-setup.sh")
BOOT_MODE = os.path.join(PROJECT_ROOT, "scripts", "boot-mode.sh")
CONFIG_SH = os.path.join(PROJECT_ROOT, "scripts", "config.sh")


class TestLinuxFragment:
    """Kernel has NFS root and IP autoconfigure support."""

    def test_nfs_root(self):
        with open(LINUX_FRAGMENT) as f:
            content = f.read()
        assert "CONFIG_ROOT_NFS=y" in content

    def test_nfs_v3(self):
        with open(LINUX_FRAGMENT) as f:
            content = f.read()
        assert "CONFIG_NFS_V3=y" in content

    def test_ip_pnp_dhcp(self):
        with open(LINUX_FRAGMENT) as f:
            content = f.read()
        assert "CONFIG_IP_PNP=y" in content
        assert "CONFIG_IP_PNP_DHCP=y" in content


class TestUbootFragment:
    """U-Boot has bootmenu command enabled."""

    def test_bootmenu_enabled(self):
        with open(UBOOT_FRAGMENT) as f:
            content = f.read()
        assert "CONFIG_CMD_BOOTMENU=y" in content


class TestBootCmd:
    """boot.cmd supports all three boot modes."""

    def test_has_boot_mode_var(self):
        with open(BOOT_CMD) as f:
            content = f.read()
        assert "boot_mode" in content

    def test_has_mmc_mode(self):
        with open(BOOT_CMD) as f:
            content = f.read()
        assert 'boot_mode mmc' in content

    def test_has_tftp_mode(self):
        with open(BOOT_CMD) as f:
            content = f.read()
        assert 'boot_mode}" = "tftp"' in content
        assert "tftp ${kernel_addr_r} zImage" in content

    def test_has_nfs_mode(self):
        with open(BOOT_CMD) as f:
            content = f.read()
        assert 'boot_mode}" = "nfs"' in content
        assert "root=/dev/nfs" in content
        assert "nfsroot=" in content

    def test_has_bootmenu(self):
        """boot.cmd sets up bootmenu entries and shows the menu."""
        with open(BOOT_CMD) as f:
            content = f.read()
        assert "bootmenu_0" in content
        assert "bootmenu_1" in content
        assert "bootmenu_2" in content
        assert "bootmenu_default" in content
        assert "bootmenu 3" in content

    def test_bootmenu_saves_env(self):
        """Each bootmenu entry sets boot_mode and saves env."""
        with open(BOOT_CMD) as f:
            content = f.read()
        for i in range(3):
            for line in content.splitlines():
                if f"bootmenu_{i}" in line and "=" in line:
                    assert "saveenv" in line, f"bootmenu_{i} missing saveenv"

    def test_rauc_ab_preserved(self):
        """MMC mode still has RAUC A/B slot selection."""
        with open(BOOT_CMD) as f:
            content = f.read()
        assert "BOOT_ORDER" in content
        assert "BOOT_A_LEFT" in content
        assert "rauc.slot=" in content


class TestScripts:
    """Network boot scripts exist and are executable."""

    @pytest.mark.parametrize("script", [NETBOOT_SETUP, BOOT_MODE])
    def test_exists_and_executable(self, script):
        assert os.path.isfile(script), f"{script} does not exist"
        assert os.access(script, os.X_OK), f"{script} is not executable"

    def test_boot_mode_validates_input(self):
        """boot-mode.sh rejects unknown modes."""
        result = subprocess.run(
            [BOOT_MODE, "bogus", "1.2.3.4"],
            capture_output=True, text=True,
            env={**os.environ, "HOME": "/nonexistent"},
        )
        assert result.returncode != 0
        assert "unknown mode" in result.stderr

    def test_netboot_setup_creates_symlinks(self, tmp_path):
        """netboot-setup.sh creates symlinks (not copies) in TFTP_DIR."""
        with open(NETBOOT_SETUP) as f:
            content = f.read()
        assert "ln -sf" in content


class TestConfigKeys:
    """config.sh exposes HOST_IP and NFS_DIR with defaults."""

    def _run_config(self, tmp_path, config_content=None, env_overrides=None):
        env = os.environ.copy()
        env["HOME"] = str(tmp_path)
        if config_content is not None:
            cfg_dir = tmp_path / ".config"
            cfg_dir.mkdir(parents=True, exist_ok=True)
            (cfg_dir / "bbb_buildroot_cfg").write_text(config_content)
        if env_overrides:
            env.update(env_overrides)

        script = textwrap.dedent(f"""\
            set -euo pipefail
            . "{CONFIG_SH}"
            echo "HOST_IP=$HOST_IP"
            echo "NFS_DIR=$NFS_DIR"
        """)
        result = subprocess.run(
            ["bash", "-c", script],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode == 0, f"config.sh failed: {result.stderr}"
        parsed = {}
        for line in result.stdout.strip().splitlines():
            key, _, value = line.partition("=")
            parsed[key] = value
        return parsed

    def test_defaults(self, tmp_path):
        cfg = self._run_config(tmp_path)
        assert cfg["HOST_IP"] == ""
        assert cfg["NFS_DIR"].endswith("output/target")

    def test_from_config_file(self, tmp_path):
        cfg = self._run_config(
            tmp_path,
            config_content="HOST_IP=10.0.0.1\nNFS_DIR=/nfs/bbb\n",
        )
        assert cfg["HOST_IP"] == "10.0.0.1"
        assert cfg["NFS_DIR"] == "/nfs/bbb"

    def test_env_overrides_file(self, tmp_path):
        cfg = self._run_config(
            tmp_path,
            config_content="HOST_IP=10.0.0.1\n",
            env_overrides={"HOST_IP": "99.99.99.99"},
        )
        assert cfg["HOST_IP"] == "99.99.99.99"
