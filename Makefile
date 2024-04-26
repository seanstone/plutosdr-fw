.PHONY: default
default: all

OS := $(shell uname -s)
ifeq ($(OS),Darwin)

############################# Docker #############################

DOCKER_ARGS = \
		--init --rm -it --privileged \
		-e DISPLAY=host.docker.internal:0 \
		-v .:/home/user/plutosdr-fw \
		-v ./.ssh:/home/user/.ssh \
		-v ./build/images:/home/user/images \
		-v /tmp/.X11-unix:/tmp/.X11-unix \
		--platform linux/amd64 plutosdr-build

DOCKER_INIT_CMDS = cd /home/user/plutosdr-fw && sudo mount -o loop build.img build && sudo chown user:users build && mkdir -p build/images && sudo mount --bind /home/user/images build/images && sudo mount -o loop Xilinx.img /tools/Xilinx

.PHONY: docker
docker:
	docker build -t plutosdr-build .

build.img:
	truncate -s 20G build.img
	docker run  \
		$(DOCKER_ARGS) \
		sudo -H -u user bash -c "cd /home/user/plutosdr-fw && mkfs.ext4 build.img && chmod 600 .ssh/id_rsa"

Xilinx.img:
	truncate -s 120G Xilinx.img
	docker run $(DOCKER_ARGS) \
		sudo -H -u user bash -c "cd /home/user/plutosdr-fw && mkfs.ext4 Xilinx.img && sudo mkdir -p /tools/Xilinx && sudo mount -o loop Xilinx.img /tools/Xilinx && sudo chown user:users /tools/Xilinx && ./scripts/install.sh"

.PHONY: bash
bash:
	mkdir -p build/images
	docker run $(DOCKER_ARGS) \
		sudo -H -u user bash -c "$(DOCKER_INIT_CMDS) && bash"

.PHONY: vivado
vivado:
	xhost +
	mkdir -p build/images
	docker run $(DOCKER_ARGS) \
		sudo -H -u user bash -c "$(DOCKER_INIT_CMDS) && ./scripts/start_vivado.sh"

%: build.img
	mkdir -p build/images
	docker run $(DOCKER_ARGS) \
		sudo -H -u user bash -c "$(DOCKER_INIT_CMDS) && make $*"

Makefile:
	ls Makefile

################################### Patches ####################################

.PHONY: patch
patch: patch-br

.PHONY: patch-br
patch-br:
	for patch in patches/buildroot/*.patch; do \
		patch -d buildroot -p1 --forward < $$patch || true; \
	done

else

################################## Docker ###################################

export SHELL:=/bin/bash

export VIVADO_VERSION ?= 2023.2
export VIVADO_SETTINGS ?= /tools/Xilinx/Vivado/$(VIVADO_VERSION)/settings64.sh

ifdef TARGET
$(shell echo $(TARGET) > .target)
else
ifeq (,$(wildcard .target))
TARGET = pluto
else
TARGET = $(shell cat .target)
endif
endif

$(info TARGET: $(TARGET))
SUPPORTED_TARGETS := $(notdir $(wildcard targets/*))
$(if $(filter $(TARGET),$(SUPPORTED_TARGETS)),,$(error Invalid TARGET variable; valid values are: $(SUPPORTED_TARGETS)))

.PHONY: default
default: all

# Include target specific settings
include targets/$(TARGET)/$(TARGET).mk

################################## Buildroot ###################################

export BR2_EXTERNAL=$(CURDIR)
export BR2_DEFCONFIG=$(CURDIR)/targets/$(TARGET)/defconfig
export O=$(CURDIR)/build/$(TARGET)

export PATH := $(PATH):$(O)/../host/bin/

all menuconfig: $(O)/.config

## Making sure defconfig is already run
$(O)/.config: 
	$(MAKE) defconfig

## Import BR2_* definitions
include $(BR2_DEFCONFIG)
HDL_PROJECT := $(patsubst "%",%,$(HDL_PROJECT))

export UBOOT_DIR = $(strip $(O)/build/uboot-$(BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION))

## Pass targets to buildroot
%:
	env - PATH=$(PATH) USER=$(USER) HOME=$(HOME) TERM=$(TERM) \
    	$(MAKE) TARGET=$(TARGET) UBOOT_DIR=$(UBOOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) BR2_DEFCONFIG=$(BR2_DEFCONFIG) O=$(O) -C buildroot $*

################################### U-Boot #####################################

## Generate reference defconfig with missing options set to default as a base for comparison using diffconfig
$(UBOOT_DIR)/.$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)_defconfig:
	$(MAKE) -C $(UBOOT_DIR) KCONFIG_CONFIG=$@ $(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)_defconfig

## Generate diff with reference config
uboot-diffconfig: $(UBOOT_DIR)/.$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)_defconfig linux-extract
	$(LINUX_DIR)/scripts/diffconfig -m $< $(UBOOT_DIR)/.config > $(BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES)

#################################### Linux ####################################

export LINUX_DIR = $(strip $(O)/build/linux-$(BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION))

## Generate reference defconfig with missing options set to default as a base for comparison using diffconfig
$(LINUX_DIR)/.$(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig:
	$(MAKE) -C $(LINUX_DIR) KCONFIG_CONFIG=$@ ARCH=arm $(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig

## Generate diff with reference config
linux-diffconfig: $(LINUX_DIR)/.$(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig linux-extract
	$(LINUX_DIR)/scripts/diffconfig -m $< $(LINUX_DIR)/.config > $(BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES)

#################################### Busybox ##################################

BUSYBOX_VERSION = $$(awk '/^BUSYBOX_VERSION/{print $$3}' buildroot/package/busybox/busybox.mk)
export BUSYBOX_DIR = $(strip $(O)/build/busybox-$(BUSYBOX_VERSION))

busybox-diffconfig: $(BR2_PACKAGE_BUSYBOX_CONFIG)
	$(LINUX_DIR)/scripts/diffconfig -m $< $(BUSYBOX_DIR)/.config > $(BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES)

#################################### Clean #####################################

.PHONY: clean-all clean-target

clean-all: clean clean-ip

clean-ip:
	rm -rf build/ip

clean-target:
	rm -rf $(O)/target
	find $(O) -name ".stamp_target_installed" |xargs rm -rf

clean-images:
	rm -f $(O)/images/*

##################################### DFU ######################################

.PHONY: dfu-fw dfu-uboot dfu-all dfu-ram

dfu-fw: $(O)/images/$(TARGET).dfu
	dfu-util -D $< -a firmware.dfu

boot.dfu: $(O)/images/boot.dfu 

dfu-boot: $(O)/images/boot.dfu 
	dfu-util -D $< -a boot.dfu

dfu-boot-env: $(O)/images/uboot-env.dfu
	dfu-util -D $< -a uboot-env.dfu

dfu-all: dfu-fw dfu-boot dfu-boot-env

dfu-ram: $(O)/images/$(TARGET).dfu
	sshpass -p analog ssh root@$(TARGET).local '/usr/sbin/device_reboot ram;'
	sleep 5
	dfu-util -D $(O)/images/$(TARGET).dfu -a firmware.dfu
	dfu-util -e

################################################################################

endif

.PHONY: upload
upload:
	cp $(O)/images/$(TARGET).frm /run/media/*/PlutoSDR/
	cp $(O)/images/boot.frm /run/media/*/PlutoSDR/
	sudo eject /run/media/$$USER/PlutoSDR

.PHONY: dfu
dfu: build/images/pluto.dfu
	sudo dfu-util -D $< -a firmware.dfu