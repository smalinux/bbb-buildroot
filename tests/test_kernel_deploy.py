"""
test_kernel_deploy.py — Verify the invariants `make kernel-deploy` relies on.

kernel-deploy overwrites /boot/zImage, /boot/<dtb>, and /lib/modules/<kver>/
on the running (active) slot. For that to work the board must:

  1. have /boot/zImage and /boot/am335x-boneblack.dtb present
     (that is where boot.cmd's `load mmc` reads from),
  2. have the rootfs mounted rw (so the overwrite succeeds),
  3. expose /lib/modules/<kver>/ matching `uname -r`,
  4. have depmod available (busybox or kmod).

These are the contract between boot.cmd + the helper script. If any of
them break, `make kernel-deploy` silently produces a board that boots
stale bits. A full reboot-after-deploy E2E test is left out on purpose:
it is slow and flaky, and these invariants are what actually matter.

Run with:
    pytest tests/test_kernel_deploy.py --lg-env tests/env.yaml -v
"""


class TestKernelDeployInvariants:
    def test_boot_zimage_present(self, shell):
        """boot.cmd loads /boot/zImage — it must exist on the active slot."""
        _, _, rc = shell.run("test -f /boot/zImage")
        assert rc == 0, "/boot/zImage missing — kernel-deploy would orphan the kernel"

    def test_boot_dtb_present(self, shell):
        """boot.cmd loads /boot/am335x-boneblack.dtb."""
        _, _, rc = shell.run("test -f /boot/am335x-boneblack.dtb")
        assert rc == 0, "/boot/am335x-boneblack.dtb missing"

    def test_rootfs_is_rw(self, shell):
        """Script writes to /boot/ and /lib/modules/ — rootfs must be rw."""
        stdout, _, _ = shell.run("findmnt -n -o OPTIONS /")
        assert any("rw" in line.split(",") for line in stdout), (
            f"rootfs not mounted rw: {stdout}"
        )

    def test_modules_dir_matches_uname(self, shell):
        """/lib/modules/$(uname -r) must exist — that's where tar unpacks to."""
        stdout, _, rc = shell.run("uname -r")
        assert rc == 0 and stdout, "uname -r failed"
        kver = stdout[0].strip()
        _, _, rc = shell.run(f"test -d /lib/modules/{kver}")
        assert rc == 0, f"/lib/modules/{kver} missing"

    def test_depmod_available(self, shell):
        """Script runs `depmod -a` on the target after uploading modules."""
        _, _, rc = shell.run("command -v depmod")
        assert rc == 0, "depmod not found on target"
