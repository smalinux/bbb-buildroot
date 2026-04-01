"""
Labgrid conftest — provides fixtures for BBB integration tests.

Usage:
    pytest tests/ --lg-env tests/env.yaml -v

The env.yaml defines the BBB target (SSH connection). Override the IP:
    pytest tests/ --lg-env tests/env.yaml --lg-coordinator ws://...
    or edit env.yaml directly.
"""

import pytest


@pytest.fixture(scope="session")
def shell(target):
    """Get an SSHDriver shell connected to the BBB."""
    ssh = target.get_driver("SSHDriver")
    ssh.activate()
    return ssh


@pytest.fixture(scope="session")
def systemctl(shell):
    """Helper to run systemctl commands and return output."""

    def _run(args):
        stdout, stderr, returncode = shell.run(f"systemctl {args}")
        return stdout, returncode

    return _run
