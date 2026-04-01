# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Replace SWUpdate with RAUC for A/B OTA updates (signed bundles, U-Boot bootchooser)
- Add NTP time sync via BusyBox ntpd (needed for RAUC certificate validation)
- Enable SquashFS in kernel (required by RAUC to mount update bundles)
- Fix deploy.sh: skip host key checking, auto-authenticate with sshpass
- Switch U-Boot env from FAT file to raw MMC (fixes fw_printenv/fw_setenv for RAUC)
- Add Dropbear SSH server for remote access to the BeagleBone Black
