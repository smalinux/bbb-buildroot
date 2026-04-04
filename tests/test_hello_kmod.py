"""
test_hello_kmod.py — Verify the hello out-of-tree kernel module.

Exercises the kmodules/ infrastructure end-to-end: the .ko is installed
into /lib/modules/<ver>/updates/, depmod indexed it, modprobe loads it,
and the init/exit pr_info() messages land in dmesg.

Run with:
    pytest tests/test_hello_kmod.py --lg-env tests/env.yaml -v
"""


class TestHelloKmod:
    """Verify the hello out-of-tree kernel module."""

    def test_ko_installed(self, shell):
        """hello.ko should be installed under /lib/modules/<ver>/updates/."""
        stdout, _, rc = shell.run("find /lib/modules -name 'hello.ko'")
        assert rc == 0
        assert any("updates/hello.ko" in line for line in stdout), (
            f"hello.ko not in updates/: {stdout}"
        )

    def test_modprobe_finds_module(self, shell):
        """depmod should have indexed hello so modinfo can resolve it."""
        stdout, _, rc = shell.run("modinfo hello")
        assert rc == 0
        # MODULE_DESCRIPTION from hello.c
        assert any("BeagleBone Black" in line for line in stdout)

    def test_load_unload(self, shell):
        """Load, verify lsmod + dmesg, unload, verify dmesg."""
        # Ensure clean slate
        shell.run("rmmod hello 2>/dev/null; true")

        # Load
        _, _, rc = shell.run("modprobe hello")
        assert rc == 0

        # lsmod should list it
        stdout, _, rc = shell.run("lsmod | grep '^hello '")
        assert rc == 0
        assert any(line.startswith("hello") for line in stdout)

        # dmesg should contain the init message
        stdout, _, rc = shell.run("dmesg | grep 'hello: loaded' | tail -1")
        assert rc == 0
        assert any("loaded on BeagleBone Black" in line for line in stdout)

        # Unload
        _, _, rc = shell.run("rmmod hello")
        assert rc == 0

        # dmesg should contain the exit message
        stdout, _, rc = shell.run("dmesg | grep 'hello: unloaded' | tail -1")
        assert rc == 0
        assert any("unloaded" in line for line in stdout)

        # lsmod should no longer list it
        _, _, rc = shell.run("lsmod | grep '^hello '")
        assert rc != 0
