"""
test_hello_world.py — Verify the hello-world custom package is installed and runs.

Run with:
    pytest tests/test_hello_world.py --lg-env tests/env.yaml -v
"""


class TestHelloWorld:
    """Verify the hello-world external package."""

    def test_binary_exists(self, shell):
        """hello-world binary should be installed in /usr/bin."""
        stdout, _, rc = shell.run("test -x /usr/bin/hello-world && echo ok")
        assert rc == 0
        assert "ok" in stdout[0]

    def test_output(self, shell):
        """hello-world should print the expected greeting."""
        stdout, _, rc = shell.run("/usr/bin/hello-world")
        assert rc == 0
        assert stdout[0].strip() == "Hello from BeagleBone Black!"
