# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Add hardware watchdog daemon (OMAP WDT) — auto-reboots on system hang, monitors load and memory; enable Magic SysRq (`CONFIG_MAGIC_SYSRQ=y`) for crash testing
- Add TFTP + NFS boot support — `make bbb` sets up TFTP symlinks + NFS export; `make tftp-boot`/`nfs-boot`/`mmc-boot` switch modes; U-Boot bootmenu for interactive selection on serial console
- Add user-level board config (`~/.config/bbb_buildroot_cfg`) — `make bbb` copies `board/bbb/board.cfg` template, all deploy scripts read from it, CLI overrides still win; new boards just need a template + two-line Makefile target
- Add `make module-deploy BOARD=<ip>` for fast module-only push (linux-rebuild + tar modules + depmod, no zImage, no reboot)
- Add reboot=cold bootarg to fix intermittent "CCCCCCCC" hang on reboot (AM335x MMC not reset on warm reboot)
- Move helper scripts (deploy.sh, deploy-kmod.sh, reset.sh) into scripts/ to declutter project root
- Add `make kernel-deploy BOARD=<ip>` for fast kernel+modules push (linux-rebuild + scp zImage/DTB/modules + depmod + reboot, no RAUC bundle, no rootfs rebuild)

## [1.0] - 2026-04-04

Initial release — BeagleBone Black Buildroot platform with RAUC A/B OTA updates, out-of-tree kernel module infrastructure, and labgrid integration tests.


- Add out-of-tree kernel module support (kmodules/ directory, auto-included via external.mk wildcard, grouped under "Out-of-tree kernel modules" menu)
- Auto-rebuild kmodules on source-file changes — Makefile watches kmodules/*/*.{c,h,S,Makefile,Kbuild,Kconfig} against a stamp and triggers <pkg>-rebuild on change (SITE_METHOD=local packages otherwise never re-check the source)
- Add deploy-kmod.sh script for fast single-module iteration (build + scp + insmod, no OTA, no reboot, keeps debug symbols)
- Document three deploy levels for kernel modules (OTA / manual scp / deploy-kmod.sh) with a when-to-use-which table
- Add hello out-of-tree kernel module example (kmodules/hello/, loads/unloads with pr_info, labgrid test verifies .ko install + modprobe + dmesg)
- Document kernel module versioning strategy (flat kmodules/ structure, LINUX_VERSION_CODE compat shims, per-board defconfig) and demonstrate pattern in hello.c via HELLO_KERNEL_ERA macro and UTS_RELEASE logging
- Fix package-customization.md to correctly document buildroot's native per-version patch directories (patches/<pkg>/<version>/*.patch takes precedence over patches/<pkg>/*.patch)
- Move downloads (dl/) and toolchain (toolchain/) outside output/ to survive clean rebuilds
- Enable ccache (ccache/) outside output/ to speed up recompilation after clean builds
- Enable less pager for colored systemctl output (systemd needs less for ANSI color passthrough)
- Fix failed unmount of /var/log/journal during shutdown (add ExecStop umounts, re-enable DefaultDependencies)
- Add libtree external package (ldd as a tree, cloned from GitHub)
- Add custom external package support (package/ directory, Config.in, external.mk wildcard) with hello-world example
- Fix ncurses "cannot initialize terminal type" over SSH by falling back to xterm when TERM is missing from terminfo
- Replace SWUpdate with RAUC for A/B OTA updates (signed bundles, U-Boot bootchooser)
- Add NTP time sync via BusyBox ntpd (needed for RAUC certificate validation)
- Enable SquashFS in kernel (required by RAUC to mount update bundles)
- Fix deploy.sh: skip host key checking, auto-authenticate with sshpass
- Switch U-Boot env from FAT file to raw MMC (fixes fw_printenv/fw_setenv for RAUC)
- Move kernel and DTB into rootfs so RAUC OTA updates include them
- Restore kernel console loglevel to 7 (debug) for full boot diagnostics
- Increase rootfs ext4 size from 60M to 256M for development headroom
- Add Dropbear SSH server for remote access to the BeagleBone Black
- Add reset.sh for USB power-cycling the BBB via uhubctl (auto-discovers smart hubs)
- Enable RAUC adaptive updates (block-hash-index) with HTTP streaming and verity bundles
- Switch init system from BusyBox init to systemd (with kernel config, service units)
- Add labgrid integration test suite for systemd verification on real hardware
- Add labgrid integration tests for RAUC OTA (slots, bootchooser, config, adaptive data)
- Fix networking: add systemd-networkd config for end0 (DHCP)
- Replace custom ntpd service with systemd-timesyncd (built-in)
- Document RAUC A/B rollback procedure in README (manual + automatic)
- Add persistent data partition with shell history, SSH keys, journal, and machine-id
- Refactor post-build.sh: split inline services into standalone files under board/bbb/systemd/ and board/bbb/network/
- Add colored shell prompt (root@BBB) and aliases (ll, la, vim, rebootf)
- Fix DHCP IP changing across reboots (use MAC-based client identifier)
- Reduce shutdown timeout from 90s to 10s for fast reboot
- Add patches/ directory and document package customization (patches, fragments, CONF_OPTS)
- Add local.mk with OVERRIDE_SRCDIR support for building packages from local source trees (e.g. kernel, htop)
- Auto-rebuild packages when OVERRIDE_SRCDIR source files change (find -newer stamp in Makefile)
- Document OVERRIDE_SRCDIR mechanism for using custom local source directories
- Fix missing terminal colors (htop, systemctl): set TERM=linux fallback for serial/dumb consoles
