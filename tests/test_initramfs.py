"""
test_initramfs.py — Verify initramfs support on the BBB.

The initramfs provides a recovery shell (bbb.recovery) and overlayfs
root (bbb.overlayfs).  These tests verify the initramfs is installed,
the kernel can accept an initrd, and the overlayfs kernel module is
available.

Note: testing actual recovery boot and overlayfs boot requires changing
kernel cmdline args and rebooting, which is destructive.  These tests
verify the building blocks are in place.

Run with:
    pytest tests/test_initramfs.py --lg-env tests/env.yaml -v
"""

import pytest


class TestInitramfsImage:
    """Verify the initramfs uImage is installed in /boot/."""

    def test_initramfs_exists(self, shell):
        """The U-Boot-wrapped initramfs should be at /boot/."""
        stdout, _, rc = shell.run("test -f /boot/initramfs.uImage")
        assert rc == 0

    def test_initramfs_size_reasonable(self, shell):
        """The initramfs should be small (< 5 MB) — it's just busybox + init."""
        stdout, _, rc = shell.run("stat -c%s /boot/initramfs.uImage")
        assert rc == 0
        size = int(stdout[0].strip())
        assert size > 10000, "initramfs suspiciously small"
        assert size < 5 * 1024 * 1024, f"initramfs too large: {size} bytes"


class TestKernelInitrdSupport:
    """Verify the kernel was built with initrd/initramfs support."""

    def test_config_blk_dev_initrd(self, shell):
        """CONFIG_BLK_DEV_INITRD must be enabled."""
        stdout, _, rc = shell.run(
            "zcat /proc/config.gz 2>/dev/null | grep CONFIG_BLK_DEV_INITRD "
            "|| grep CONFIG_BLK_DEV_INITRD /boot/config-* 2>/dev/null"
        )
        # /proc/config.gz may not exist; skip gracefully
        if rc != 0:
            pytest.skip("kernel config not accessible on target")
        assert "CONFIG_BLK_DEV_INITRD=y" in stdout[0]


class TestOverlayfsSupport:
    """Verify overlayfs is available for the initramfs overlayfs-root mode."""

    def test_overlayfs_module_or_builtin(self, shell):
        """overlayfs must be built-in or loadable as a module."""
        # Check if already loaded or built-in
        stdout, _, rc = shell.run(
            "cat /proc/filesystems | grep overlay"
        )
        if rc == 0:
            return  # built-in or already loaded

        # Try loading the module
        stdout, _, rc = shell.run("modprobe overlay 2>/dev/null")
        if rc == 0:
            # Verify it's now available
            stdout, _, rc = shell.run(
                "cat /proc/filesystems | grep overlay"
            )
            assert rc == 0
        else:
            pytest.fail("overlayfs not available (not built-in and module not loadable)")

    def test_overlay_mount_works(self, shell):
        """Quick smoke test: create a tmpfs overlayfs and verify it mounts."""
        cmds = (
            "mkdir -p /tmp/ofs-test/{lower,upper,work,merged} && "
            "echo hello > /tmp/ofs-test/lower/test.txt && "
            "mount -t overlay overlay "
            "-o lowerdir=/tmp/ofs-test/lower,"
            "upperdir=/tmp/ofs-test/upper,"
            "workdir=/tmp/ofs-test/work "
            "/tmp/ofs-test/merged && "
            "cat /tmp/ofs-test/merged/test.txt && "
            "umount /tmp/ofs-test/merged && "
            "rm -rf /tmp/ofs-test"
        )
        stdout, _, rc = shell.run(cmds)
        assert rc == 0
        assert stdout[0].strip() == "hello"
