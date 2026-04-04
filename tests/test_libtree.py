"""
test_libtree.py — Verify the libtree custom package is installed and runs.

Run with:
    pytest tests/test_libtree.py --lg-env tests/env.yaml -v
"""


class TestLibtree:
    """Verify the libtree external package."""

    def test_binary_exists(self, shell):
        """libtree binary should be installed in /usr/bin."""
        stdout, _, rc = shell.run("test -x /usr/bin/libtree && echo ok")
        assert rc == 0
        assert "ok" in stdout[0]

    def test_runs_on_itself(self, shell):
        """libtree should be able to display its own shared library deps."""
        stdout, _, rc = shell.run("libtree /usr/bin/libtree")
        assert rc == 0
        assert any("libtree" in line for line in stdout)
