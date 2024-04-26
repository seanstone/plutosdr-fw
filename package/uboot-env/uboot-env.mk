################################################################################
#
# uboot-env
#
################################################################################

UBOOT_ENV_SITE_METHOD := local
UBOOT_ENV_SITE = $(BR2_EXTERNAL)/package/uboot-env
UBOOT_ENV_INSTALL_IMAGES = YES
UBOOT_ENV_DEPENDENCIES = uboot

export UBOOT_DIR

define UBOOT_ENV_BUILD_CMDS
	cd $(@D) && PATH=$(BR2_EXTERNAL)/build/host/bin/:$(PATH) CROSS_COMPILE=arm-buildroot-linux-gnueabihf- $(BR2_EXTERNAL)/package/uboot-env/get_default_envs.sh > uboot-env.txt
	cd $(@D) && echo attr_name=compatible >> uboot-env.txt
	cd $(@D) && echo attr_val=ad9364 >> uboot-env.txt
	cd $(@D) && sed -i 's,^\(maxcpus[ ]*=\).*,\1'2',g' uboot-env.txt
	cd $(@D) && $(UBOOT_DIR)/tools/mkenvimage -s 0x20000 uboot-env.txt -o uboot-env.bin
endef

define UBOOT_ENV_INSTALL_IMAGES_CMDS
	cp $(@D)/uboot-env.bin $(BINARIES_DIR)
endef

$(eval $(generic-package))
