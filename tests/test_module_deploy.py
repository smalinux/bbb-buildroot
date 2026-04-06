"""
test_module_deploy.py — Verify the invariants `make module-deploy` relies on.

module-deploy replaces /lib/modules/<kver>/ on the running system and runs
depmod. For that to work the board must:

  1. have the rootfs mounted rw (so the overwrite succeeds),
  2. expose /lib/modules/<kver>/ matching `uname -r`,
  3. have depmod available (busybox or kmod),
  4. have modprobe available (for reloading modules after deploy).

These are the contract between the helper script and the target system.
If any of them break, module-deploy silently produces a board where
modprobe can't find the freshly deployed modules.

Run with:
    pytest tests/test_module_deploy.py --lg-env tests/env.yaml -v
"""


class TestModuleDeployInvariants:
    def test_rootfs_is_rw(self, shell):
        """Script writes to /lib/modules/ — rootfs must be rw."""
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

    def test_modprobe_available(self, shell):
        """After deploy, user reloads modules with modprobe — it must exist."""
        _, _, rc = shell.run("command -v modprobe")
        assert rc == 0, "modprobe not found on target"

    def test_modules_dir_has_ko_files(self, shell):
        """The modules tree should contain at least one .ko file."""
        stdout, _, rc = shell.run("uname -r")
        assert rc == 0 and stdout, "uname -r failed"
        kver = stdout[0].strip()
        stdout, _, rc = shell.run(
            f"find /lib/modules/{kver} -name '*.ko' | head -1"
        )
        assert rc == 0 and stdout, (
            f"no .ko files in /lib/modules/{kver} — deploy would replace an empty tree"
        )
