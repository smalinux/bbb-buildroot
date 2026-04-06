"""
test_config.py — Verify that scripts/config.sh loads user config correctly.

These are host-side tests (no board needed). They exercise the config
loader's precedence rules:
  1. Environment variables override everything
  2. Config file values fill in unset variables
  3. Fallback defaults apply when neither env nor file sets the value

Run with:
    pytest tests/test_config.py -v
"""

import os
import subprocess
import textwrap

import pytest

SCRIPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "scripts")
CONFIG_SH = os.path.join(SCRIPTS_DIR, "config.sh")


def run_config(env_overrides=None, config_content=None, tmpdir=None):
    """Source config.sh in a subshell and print all config variables.

    Args:
        env_overrides: dict of env vars to set before sourcing
        config_content: string to write to a fake config file
        tmpdir: pytest tmp_path for the fake config file

    Returns:
        dict of variable names to values
    """
    env = os.environ.copy()
    # Point HOME at tmpdir so config.sh reads our fake config file
    # at $HOME/.config/bbb_buildroot_cfg instead of the real one.
    if tmpdir is not None:
        env["HOME"] = str(tmpdir)
        if config_content is not None:
            cfg_dir = tmpdir / ".config"
            cfg_dir.mkdir(parents=True, exist_ok=True)
            (cfg_dir / "bbb_buildroot_cfg").write_text(config_content)
    if env_overrides:
        env.update(env_overrides)

    # Source config.sh then print each variable we care about.
    script = textwrap.dedent(f"""\
        set -euo pipefail
        . "{CONFIG_SH}"
        echo "BOARD=$BOARD"
        echo "BOARD_PASS=$BOARD_PASS"
        echo "DTB=$DTB"
        echo "TFTP_DIR=$TFTP_DIR"
        echo "OUTPUT_DIR=$OUTPUT_DIR"
    """)
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, f"config.sh failed: {result.stderr}"
    parsed = {}
    for line in result.stdout.strip().splitlines():
        key, _, value = line.partition("=")
        parsed[key] = value
    return parsed


class TestConfigDefaults:
    """When no config file and no env vars, fallback defaults apply."""

    def test_defaults(self, tmp_path):
        cfg = run_config(tmpdir=tmp_path)
        assert cfg["BOARD"] == ""
        assert cfg["BOARD_PASS"] == "root"
        assert cfg["DTB"] == "am335x-boneblack.dtb"
        assert cfg["TFTP_DIR"] == "/srv/tftp"
        assert cfg["OUTPUT_DIR"] == "output"


class TestConfigFile:
    """Config file values fill in unset variables."""

    def test_board_from_file(self, tmp_path):
        cfg = run_config(
            tmpdir=tmp_path,
            config_content="BOARD=10.0.0.42\n",
        )
        assert cfg["BOARD"] == "10.0.0.42"
        # Other defaults still apply
        assert cfg["BOARD_PASS"] == "root"

    def test_all_keys_from_file(self, tmp_path):
        content = textwrap.dedent("""\
            BOARD=192.168.7.2
            BOARD_PASS=secret
            DTB=custom.dtb
            TFTP_DIR=/tftpboot
            OUTPUT_DIR=/tmp/out
        """)
        cfg = run_config(tmpdir=tmp_path, config_content=content)
        assert cfg["BOARD"] == "192.168.7.2"
        assert cfg["BOARD_PASS"] == "secret"
        assert cfg["DTB"] == "custom.dtb"
        assert cfg["TFTP_DIR"] == "/tftpboot"
        assert cfg["OUTPUT_DIR"] == "/tmp/out"


class TestEnvOverride:
    """Environment variables take precedence over config file."""

    def test_env_overrides_file(self, tmp_path):
        cfg = run_config(
            tmpdir=tmp_path,
            config_content="BOARD=10.0.0.42\nDTB=file.dtb\n",
            env_overrides={"BOARD": "99.99.99.99"},
        )
        # Env wins for BOARD
        assert cfg["BOARD"] == "99.99.99.99"
        # File still wins for DTB (no env override)
        assert cfg["DTB"] == "file.dtb"

    def test_env_overrides_default(self, tmp_path):
        cfg = run_config(
            tmpdir=tmp_path,
            env_overrides={"BOARD_PASS": "hunter2"},
        )
        assert cfg["BOARD_PASS"] == "hunter2"
