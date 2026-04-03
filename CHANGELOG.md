# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
