################################################################################
#
# hello-world
#
################################################################################

HELLO_WORLD_VERSION = 1.0
HELLO_WORLD_SITE = $(BR2_EXTERNAL_BBB_PATH)/package/hello-world
HELLO_WORLD_SITE_METHOD = local

define HELLO_WORLD_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-o $(@D)/hello-world $(@D)/hello-world.c
endef

define HELLO_WORLD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/hello-world $(TARGET_DIR)/usr/bin/hello-world
endef

$(eval $(generic-package))
