################################################################################
#
# kmod-hello — minimal out-of-tree kernel module example
#
################################################################################

KMOD_HELLO_VERSION = 1.0
KMOD_HELLO_SITE = $(BR2_EXTERNAL_BBB_PATH)/kmodules/kmod-hello
KMOD_HELLO_SITE_METHOD = local
KMOD_HELLO_LICENSE = GPL-2.0

# kernel-module infra: builds against $(LINUX_DIR) via `make M=$(@D) modules`
# and installs the resulting .ko into /lib/modules/<ver>/updates/ with depmod.
$(eval $(kernel-module))
$(eval $(generic-package))
