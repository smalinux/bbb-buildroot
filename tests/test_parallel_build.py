"""
test_parallel_build.py — Verify per-package parallel build is configured.

Host-side tests (no board needed). Checks that defconfig enables
BR2_PER_PACKAGE_DIRECTORIES and the Makefile passes -jN to buildroot
for the main build targets.

Run with:
    pytest tests/test_parallel_build.py -v
"""

import os
import re

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
DEFCONFIG = os.path.join(PROJECT_ROOT, "defconfig")
MAKEFILE = os.path.join(PROJECT_ROOT, "Makefile")


class TestPerPackageDirectories:
    """BR2_PER_PACKAGE_DIRECTORIES is enabled in defconfig."""

    def test_defconfig_has_per_package_dirs(self):
        with open(DEFCONFIG) as f:
            content = f.read()
        assert "BR2_PER_PACKAGE_DIRECTORIES=y" in content

    def test_defconfig_has_ccache(self):
        """ccache and per-package dirs should both be enabled — they
        complement each other (ccache = faster per-package compile,
        per-package dirs = parallel package builds)."""
        with open(DEFCONFIG) as f:
            content = f.read()
        assert "BR2_CCACHE=y" in content


class TestMakefileParallel:
    """Makefile passes -jN for top-level parallel builds."""

    def test_br_make_parallel_defined(self):
        with open(MAKEFILE) as f:
            content = f.read()
        # BR_MAKE_PARALLEL should use -j$(NPROC)
        assert "BR_MAKE_PARALLEL" in content
        assert "-j$(NPROC)" in content

    def test_all_target_uses_parallel(self):
        """The main 'all' target should use BR_MAKE_PARALLEL."""
        with open(MAKEFILE) as f:
            content = f.read()
        assert "$(BR_MAKE_PARALLEL)" in content
