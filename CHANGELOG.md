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
