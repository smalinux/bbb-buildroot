BUILDROOT_DIR := $(CURDIR)/buildroot
OUTPUT_DIR    := $(CURDIR)/output
DEFCONFIG     := $(CURDIR)/defconfig

BR_MAKE := $(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(CURDIR)

# Targets that should auto-save defconfig after running
CONFIG_TARGETS := menuconfig nconfig xconfig gconfig linux-menuconfig uboot-menuconfig busybox-menuconfig

.PHONY: all $(CONFIG_TARGETS) defconfig-load defconfig-save help bundle

all: $(OUTPUT_DIR)/.config
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

# Any other buildroot target: pass through
%: $(OUTPUT_DIR)/.config
	$(BR_MAKE) $@

# Ensure submodule is initialized
buildroot-check:
	@if [ ! -f $(BUILDROOT_DIR)/Makefile ]; then \
		echo "Initializing buildroot submodule..."; \
		git submodule update --init --recursive; \
	fi

help:
	@echo "BeagleBone Black Buildroot wrapper"
	@echo ""
	@echo "  make                - build the system image"
	@echo "  make menuconfig     - configure (auto-saves defconfig)"
	@echo "  make linux-menuconfig - configure Linux kernel"
	@echo "  make bundle         - build + generate RAUC OTA bundle"
	@echo "  make clean          - clean build output"
	@echo "  make help           - this message"
	@echo ""
	@echo "All standard buildroot targets are supported."
	@echo "Config targets auto-save defconfig after closing."
