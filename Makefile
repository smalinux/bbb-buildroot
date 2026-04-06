BUILDROOT_DIR := $(CURDIR)/buildroot
OUTPUT_DIR    := $(CURDIR)/output
DEFCONFIG     := $(CURDIR)/defconfig
LOCAL_MK      := $(CURDIR)/local.mk

BR_MAKE := $(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(CURDIR)

# Targets that should auto-save defconfig after running
CONFIG_TARGETS := menuconfig nconfig xconfig gconfig linux-menuconfig uboot-menuconfig busybox-menuconfig

# Fragment files — auto-rebuild packages when these change
BUSYBOX_FRAGMENT := $(CURDIR)/board/bbb/busybox.fragment
LINUX_FRAGMENT   := $(CURDIR)/board/bbb/linux.fragment
BUSYBOX_STAMP    := $(OUTPUT_DIR)/build/.busybox-fragment-stamp
LINUX_STAMP      := $(OUTPUT_DIR)/build/.linux-fragment-stamp

# ---------------------------------------------------------------------------
# Auto-rebuild for OVERRIDE_SRCDIR packages
# ---------------------------------------------------------------------------
#
# Problem: when you develop a package (kernel, u-boot, htop, ...) from a local
# source tree via OVERRIDE_SRCDIR in local.mk, Buildroot does NOT watch that
# tree for changes.  Running plain "make" won't notice you edited a .c file.
# You'd have to remember to run "make linux-rebuild" manually every time.
#
# Solution: before the main build, we compare file timestamps in each override
# source directory against a stamp file.  If anything is newer, we trigger
# "<pkg>-rebuild" automatically.  This makes "make" the only command you need.
#
# How it works, step by step:
#
#   1. OVERRIDE_PAIRS — at Makefile parse time, we sed local.mk to extract
#      every "<PKG>_OVERRIDE_SRCDIR = <path>" line into a flat word list:
#        LINUX /src/linux-bbb UBOOT /src/uboot-bbb ...
#
#   2. override_rebuild_all — a shell loop called from the "all" target.
#      It walks the word list two at a time (PKG, PATH) and for each:
#        a. Converts PKG to the buildroot target name (LINUX → linux)
#        b. Runs "find <path> -newer <stamp>" looking for source files
#           (.c .h .S .dts Makefile Kconfig etc.)
#        c. If any file is newer (or no stamp exists yet = first build):
#           - runs "make <pkg>-rebuild" (which rsyncs + recompiles)
#           - touches the stamp so next "make" is a no-op
#
#   3. The stamp files live in output/build/.override-stamps/<PKG>.
#      "make clean" wipes output/ entirely, so stamps reset naturally.
#
# To add a new package: just add a line to local.mk, e.g.:
#   UBOOT_OVERRIDE_SRCDIR = /src/uboot-bbb
# The Makefile picks it up automatically — no other changes needed.
# ---------------------------------------------------------------------------

# Where stamp files are stored (one per overridden package)
OVERRIDE_STAMP_DIR := $(OUTPUT_DIR)/build/.override-stamps

# Step 1: parse local.mk into a flat "PKG PATH PKG PATH ..." word list.
# The sed extracts the uppercase package name and the path from each line.
# Example: "LINUX_OVERRIDE_SRCDIR = /src/linux-bbb" → "LINUX /src/linux-bbb"
ifneq ($(wildcard $(LOCAL_MK)),)
OVERRIDE_PAIRS := $(shell sed -n 's/^\([A-Z_]*\)_OVERRIDE_SRCDIR\s*=\s*\(.*\)/\1 \2/p' $(LOCAL_MK))
endif

# Step 2: shell loop over OVERRIDE_PAIRS two words at a time (PKG, PATH).
# Converts PKG to buildroot target name (LINUX → linux, HOST_RAUC → host-rauc).
# Uses "find -newer <stamp>" to check for changed source files (.c .h .S .dts etc.).
# If anything is newer (or no stamp yet), triggers "<pkg>-rebuild" and touches stamp.
# "-print -quit" stops at first match — fast even for huge trees like linux.
define override_rebuild_all
	@set -- $(OVERRIDE_PAIRS); \
	while [ $$# -ge 2 ]; do \
		pkg_upper="$$1"; srcdir="$$2"; shift 2; \
		pkg="$$(echo $$pkg_upper | tr 'A-Z' 'a-z' | tr '_' '-')"; \
		stamp="$(OVERRIDE_STAMP_DIR)/$$pkg_upper"; \
		mkdir -p $(OVERRIDE_STAMP_DIR); \
		if [ ! -f "$$stamp" ] || [ -n "$$(find "$$srcdir" -newer "$$stamp" \
			\( -name '*.c' -o -name '*.h' -o -name '*.S' -o -name '*.dts' \
			   -o -name '*.dtsi' -o -name 'Makefile' -o -name 'Kconfig*' \
			   -o -name 'Kbuild*' -o -name '*.cfg' \) -print -quit 2>/dev/null)" ]; then \
			echo ">>> $$srcdir changed — triggering $$pkg-rebuild"; \
			$(BR_MAKE) $$pkg-rebuild; \
			touch "$$stamp"; \
		fi; \
	done
endef

# ---------------------------------------------------------------------------
# Auto-rebuild for kmodules/
# ---------------------------------------------------------------------------
#
# Problem: kmodules use SITE_METHOD=local, which tells buildroot to rsync
# the source tree from kmodules/<pkg>/ into output/build/ ONCE. After the
# .stamp_rsynced file lands, buildroot never re-checks the source — so
# editing a .c file in kmodules/ and running `make` will NOT rebuild the
# module. The stale .ko sits in the rootfs and you wonder why your edits
# don't take effect.
#
# Solution: mirror the override_rebuild_all pattern — for each directory
# under kmodules/, compare source file timestamps against a stamp file,
# and trigger `make <pkg>-rebuild` if anything is newer.
#
# Each subdirectory of kmodules/ is a kmodule package whose name equals
# the directory name (enforced by buildroot's pkgname rule, see
# kmodules/kmod-hello/kmod-hello.mk as reference). So the loop is simpler
# than override_rebuild_all: no OVERRIDE_PAIRS parsing needed.
# ---------------------------------------------------------------------------

KMODULES_DIR       := $(CURDIR)/kmodules
KMOD_STAMP_DIR     := $(OUTPUT_DIR)/build/.kmod-stamps

# Shell loop: for each kmodules/<pkg>/ directory, check if any source
# file is newer than the stamp. If so, trigger <pkg>-rebuild.
# Watches .c/.h/.S/Makefile/Kbuild/Kconfig — same filetypes as
# override_rebuild_all for consistency.
define kmod_rebuild_all
	@if [ -d $(KMODULES_DIR) ]; then \
		for srcdir in $(KMODULES_DIR)/*/; do \
			[ -d "$$srcdir" ] || continue; \
			pkg="$$(basename "$$srcdir")"; \
			stamp="$(KMOD_STAMP_DIR)/$$pkg"; \
			mkdir -p $(KMOD_STAMP_DIR); \
			if [ ! -f "$$stamp" ] || [ -n "$$(find "$$srcdir" -newer "$$stamp" \
				\( -name '*.c' -o -name '*.h' -o -name '*.S' \
				   -o -name 'Makefile' -o -name 'Kbuild*' -o -name 'Kconfig*' \) \
				-print -quit 2>/dev/null)" ]; then \
				if [ -d $(OUTPUT_DIR)/build/$${pkg}-* ] 2>/dev/null; then \
					echo ">>> kmodules/$$pkg changed — triggering $$pkg-rebuild"; \
					$(BR_MAKE) $$pkg-rebuild; \
				fi; \
				touch "$$stamp"; \
			fi; \
		done; \
	fi
endef

# ---------------------------------------------------------------------------
# User config: ~/.config/bbb_buildroot_cfg
# ---------------------------------------------------------------------------
#
# Board-specific settings (IP, password, TFTP dir, etc.) live in a single
# user-level config file. `make bbb` writes it with BBB defaults; scripts
# source scripts/config.sh which loads it automatically.
#
# The Makefile loads BOARD from the config so that deploy targets work
# without an explicit BOARD=<ip> argument after initial setup.
# ---------------------------------------------------------------------------
BBB_CFG := $(HOME)/.config/bbb_buildroot_cfg
ifneq ($(wildcard $(BBB_CFG)),)
# Read BOARD from config only if not already set on the command line.
# This lets `make kernel-deploy` Just Work after `make bbb`.
ifeq ($(origin BOARD),undefined)
BOARD := $(shell sed -n 's/^BOARD=//p' $(BBB_CFG))
endif
endif

.PHONY: all $(CONFIG_TARGETS) defconfig-load defconfig-save help bundle rebuild kernel-deploy module-deploy bbb config

all: $(OUTPUT_DIR)/.config
	@# Auto-rebuild busybox if its fragment changed
	@if [ -f $(BUSYBOX_FRAGMENT) ] && ! cmp -s $(BUSYBOX_FRAGMENT) $(BUSYBOX_STAMP) 2>/dev/null; then \
		if ls $(OUTPUT_DIR)/build/busybox-* >/dev/null 2>&1; then \
			echo ">>> busybox.fragment changed — triggering busybox-rebuild"; \
			$(BR_MAKE) busybox-rebuild; \
		fi; \
		mkdir -p $(dir $(BUSYBOX_STAMP)) && cp $(BUSYBOX_FRAGMENT) $(BUSYBOX_STAMP); \
	fi
	@# Auto-rebuild linux if its fragment changed
	@if [ -f $(LINUX_FRAGMENT) ] && ! cmp -s $(LINUX_FRAGMENT) $(LINUX_STAMP) 2>/dev/null; then \
		if ls $(OUTPUT_DIR)/build/linux-* >/dev/null 2>&1; then \
			echo ">>> linux.fragment changed — triggering linux-rebuild"; \
			$(BR_MAKE) linux-rebuild; \
		fi; \
		mkdir -p $(dir $(LINUX_STAMP)) && cp $(LINUX_FRAGMENT) $(LINUX_STAMP); \
	fi
	@# Auto-rebuild any package whose OVERRIDE_SRCDIR has changed files
	$(call override_rebuild_all)
	@# Auto-rebuild any kmodule whose source files have changed. Buildroot
	# treats kmodules/ as SITE_METHOD=local: it rsyncs once, stamps it, and
	# never re-checks the source. Without this loop, editing a .c file and
	# running `make` would silently ship the stale .ko.
	$(call kmod_rebuild_all)
	$(BR_MAKE)

# Load saved defconfig into output on first build
$(OUTPUT_DIR)/.config: $(DEFCONFIG) | buildroot-check
	@mkdir -p $(OUTPUT_DIR)
	cp $(DEFCONFIG) $@
	$(BR_MAKE) olddefconfig

# menuconfig and friends: run, then auto-save defconfig
$(CONFIG_TARGETS): $(OUTPUT_DIR)/.config
	$(BR_MAKE) $@
	cp $(OUTPUT_DIR)/.config $(DEFCONFIG)
	@echo ""
	@echo ">>> defconfig updated."

# Load stock beaglebone defconfig and save it
beaglebone_defconfig: | buildroot-check
	$(BR_MAKE) beaglebone_defconfig
	cp $(OUTPUT_DIR)/.config $(DEFCONFIG)
	@echo ""
	@echo ">>> defconfig updated from stock beaglebone_defconfig."

# Generate RAUC update bundle (rebuild rootfs + package it)
bundle: $(OUTPUT_DIR)/.config
	$(BR_MAKE)
	@echo ""
	@echo "Output:"
	@echo "  SD card image: $(OUTPUT_DIR)/images/sdcard.img"
	@echo "  OTA bundle:    $(OUTPUT_DIR)/images/update.raucb"

# Wipe target dir and rebuild — gives a clean rootfs without recompiling.
# Use after disabling packages in menuconfig.
# Must also wipe .stamp_target_installed so buildroot re-runs package
# install steps (including skeleton which creates /etc/inittab etc).
rebuild:
	rm -rf $(OUTPUT_DIR)/target
	find $(OUTPUT_DIR)/build -name '.stamp_target_installed' -delete 2>/dev/null; true
	$(MAKE) all

# Fast kernel deploy — skip RAUC/rootfs entirely. Overwrites zImage, DTB,
# and /lib/modules on the running (active) slot. Dev-only shortcut; real
# OTA must still go through `make bundle && ./scripts/deploy.sh`.
# Board IP comes from: BOARD=<ip> on CLI > ~/.config/bbb_buildroot_cfg > error.
# Two-step: rebuild kernel, then deploy. Run the script alone
# (./scripts/kernel-deploy.sh <ip>) to skip the rebuild when you've
# already run `make linux-rebuild` yourself.
kernel-deploy: $(OUTPUT_DIR)/.config
	@if [ -z "$(BOARD)" ]; then \
		echo "Usage: make kernel-deploy BOARD=<ip>"; \
		echo "  or run 'make bbb' first to set a default board."; exit 1; \
	fi
	$(BR_MAKE) linux-rebuild
	./scripts/kernel-deploy.sh $(BOARD)

# Fast module-only deploy — push /lib/modules/<kver>/ to the board and run
# depmod. No zImage, no DTB, no reboot. Use when you only changed code that
# compiles as =m (loadable modules), not =y (built-in).
# Reload on target: modprobe -r <mod> && modprobe <mod>
module-deploy: $(OUTPUT_DIR)/.config
	@if [ -z "$(BOARD)" ]; then \
		echo "Usage: make module-deploy BOARD=<ip>"; \
		echo "  or run 'make bbb' first to set a default board."; exit 1; \
	fi
	$(BR_MAKE) linux-rebuild
	./scripts/module-deploy.sh $(BOARD)

# Ensure submodule is initialized
buildroot-check:
	@if [ ! -f $(BUILDROOT_DIR)/Makefile ]; then \
		echo "Initializing buildroot submodule..."; \
		git submodule update --init --recursive; \
	fi

# Select a board by copying its template to the user config file.
# Each board keeps a template at board/<name>/board.cfg. Adding a new
# board = adding a directory + template + a two-line Makefile target:
#   bbai:
#   	$(call install-board-cfg,bbai)
#
# install-board-cfg(board):
#   1. Copies board/<board>/board.cfg → ~/.config/bbb_buildroot_cfg
#   2. Prints a confirmation message
# Copies template only if no config exists yet. If the user already has
# a config (possibly hand-edited), refuse to overwrite it. Use FORCE=1
# to replace it: make bbb FORCE=1
define install-board-cfg
	@mkdir -p $(dir $(BBB_CFG))
	@if [ -f $(BBB_CFG) ] && [ "$(FORCE)" != "1" ]; then \
		echo "$(BBB_CFG) already exists (not overwritten)."; \
		echo "To replace it with a fresh template: make $(1) FORCE=1"; \
	else \
		cp $(CURDIR)/board/$(1)/board.cfg $(BBB_CFG); \
		echo ">>> Wrote $(BBB_CFG) (from board/$(1)/board.cfg)"; \
		echo "    Edit it to set your board IP, then run make kernel-deploy etc."; \
	fi
endef

bbb:
	$(call install-board-cfg,bbb)

# Print the active (resolved) config values. Sources config.sh so the
# output reflects the full precedence chain: env > config file > defaults.
# This is what scripts will actually see at runtime.
config:
	@. $(CURDIR)/scripts/config.sh; \
	echo "Active config (env > ~/.config/bbb_buildroot_cfg > defaults):"; \
	echo ""; \
	if [ -n "$$BOARD_NAME" ]; then \
		echo "  BOARD_NAME  = $$BOARD_NAME  (template: board/$$BOARD_NAME/board.cfg)"; \
	else \
		echo "  BOARD_NAME  = (not set)"; \
	fi; \
	echo "  BOARD       = $$BOARD"; \
	echo "  BOARD_PASS  = $$BOARD_PASS"; \
	echo "  DTB         = $$DTB"; \
	echo "  TFTP_DIR    = $$TFTP_DIR"; \
	echo "  OUTPUT_DIR  = $$OUTPUT_DIR"; \
	echo ""; \
	if [ -f $(BBB_CFG) ]; then \
		echo "Config file: $(BBB_CFG)"; \
	else \
		echo "No config file. Run 'make bbb' to create one."; \
	fi

help:
	@echo "BeagleBone Black Buildroot wrapper"
	@echo ""
	@echo "  make                - build the system image"
	@echo "  make menuconfig     - configure (auto-saves defconfig)"
	@echo "  make linux-menuconfig - configure Linux kernel"
	@echo "  make bundle         - build + generate RAUC OTA bundle"
	@echo "  make kernel-deploy BOARD=<ip> - fast kernel/modules push (no OTA, reboots board)"
	@echo "  make module-deploy BOARD=<ip> - push modules only (no reboot, reload with modprobe)"
	@echo "  make rebuild        - clean rootfs + rebuild (no recompile)"
	@echo "  make clean          - full clean (recompiles everything)"
	@echo "  make bbb            - write ~/.config/bbb_buildroot_cfg with BBB defaults"
	@echo "  make config         - show current board config"
	@echo "  make help           - this message"
	@echo ""
	@echo "All standard buildroot targets are supported."
	@echo "Config targets auto-save defconfig after closing."

# Any other buildroot target: pass through (must be last — catch-all)
%: $(OUTPUT_DIR)/.config
	$(BR_MAKE) $@
