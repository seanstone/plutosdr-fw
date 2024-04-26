################################################################################
#
# hdl
#
################################################################################

HDL_SITE_METHOD := local
HDL_SITE = $(BR2_EXTERNAL)/package/hdl
HDL_INSTALL_STAGING = YES
HDL_DEPENDENCIES = host-device-tree-xlnx uboot linux

SDR_LIST = pluto

define HDL_CONFIGURE_CMDS
	cd $(BR2_EXTERNAL)/hdl && git apply --reject --whitespace=fix $(BR2_EXTERNAL)/patches/hdl.patch || true
endef

define HDL_BUILD_CMDS
	source "$(HDL_VIVADO_PATH)/settings64.sh" && source "$(HDL_VITIS_PATH)/settings64.sh" && \
		for PROJECT_NAME in $(SDR_LIST); do cd $(@D) && $(MAKE) -j1 PROJECT_NAME=$${PROJECT_NAME}; done
endef

define HDL_INSTALL_STAGING_CMDS
	for PROJECT_NAME in $(SDR_LIST); do \
		mkdir -p $(BINARIES_DIR)/$${PROJECT_NAME} && \
		cp $(@D)/projects/$${PROJECT_NAME}/boot.bin $(BINARIES_DIR)/$${PROJECT_NAME}/; \
		cp $(@D)/projects/$${PROJECT_NAME}/$${PROJECT_NAME}.dtb $(BINARIES_DIR)/$${PROJECT_NAME}/; \
		cp $(@D)/projects/$${PROJECT_NAME}/system_top.bit $(BINARIES_DIR)/$${PROJECT_NAME}/; \
	done
endef

export HDL_VIVADO_PATH
export HDL_VITIS_PATH
export BINARIES_DIR
export LINUX_DIR

$(eval $(generic-package))
