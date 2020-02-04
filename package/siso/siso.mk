SISO_SITE_METHOD := local
SISO_SITE := ~/SISO
SISO_DEPENDENCIES += gnuradio sse2neon
SISO_INSTALL_TARGET := YES

define SISO_BUILD_CMDS
	$(MAKE) WORKING_DIR=$(@D) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" LD="$(TARGET_LD)" -C $(@D)/app
endef

define SISO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/app/bin/* $(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))