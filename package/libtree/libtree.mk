################################################################################
#
# libtree
#
################################################################################

LIBTREE_VERSION = v3.1.1
LIBTREE_SITE = https://github.com/haampie/libtree.git
LIBTREE_SITE_METHOD = git
LIBTREE_LICENSE = MIT
LIBTREE_LICENSE_FILES = LICENSE

define LIBTREE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define LIBTREE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libtree $(TARGET_DIR)/usr/bin/lddtree
endef

$(eval $(generic-package))
