export VIVADO_VERSION ?= 2018.2
PATH := $(PATH):/opt/Xilinx/SDK/$(VIVADO_VERSION)/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin
VIVADO_SETTINGS ?= /opt/Xilinx/Vivado/$(VIVADO_VERSION)/settings64.sh
HAVE_VIVADO ?= 1

CROSS_COMPILE ?= arm-linux-gnueabihf-

NCORES = $(shell grep -c ^processor /proc/cpuinfo)

VERSION = $(shell git describe --abbrev=4 --dirty --always --tags)
LATEST_TAG = $(shell git describe --abbrev=0 --tags)
HAVE_VIVADO = $(shell bash -c "source $(VIVADO_SETTINGS) > /dev/null 2>&1 && vivado -version > /dev/null 2>&1 && echo 1 || echo 0")

TARGET ?= pluto
SUPPORTED_TARGETS := pluto sidekiqz2

TARGETS += build/$(TARGET).frm
ifeq ($(HAVE_VIVADO), 1)
TARGETS += build/boot.frm jtag-bootstrap
endif

ifeq (, $(shell which dfu-suffix))
$(warning "No dfu-utils in PATH consider doing: sudo apt-get install dfu-util")
else
TARGETS += build/$(TARGET).dfu build/uboot-env.dfu
ifeq ($(HAVE_VIVADO), 1)
TARGETS += build/boot.dfu
endif
endif

ifeq ($(findstring $(TARGET),$(SUPPORTED_TARGETS)),)
all:
	@echo "Invalid TARGET variable ; valid values are: pluto, sidekiqz2" &&
	exit 1
else
# Include target specific constants
include scripts/$(TARGET).mk
export HDL_PROJECT ?= $(TARGET)
all: zip-all
endif

.NOTPARALLEL: all

################################## Buildroot ###################################

.PHONY: patch
patch:
	for patch in configs/patches/*.patch; do \
		patch -d buildroot -p1 --forward < $$patch || true; \
	done

## Pass targets to buildroot
%:
	$(MAKE) BR2_EXTERNAL=$(CURDIR)/configs BR2_DEFCONFIG=$(CURDIR)/configs/config -C buildroot $*

include configs/config

################################### Metadata ###################################

.PHONY: license
license: build/LICENSE.html

.PRECIOUS: build/LICENSE.html
build/LICENSE.html: versions legal-info
	scripts/legal_info_html.sh "$(COMPLETE_NAME)" "configs/$(TARGET)/VERSIONS"

.PHONY: versions
versions: configs/$(TARGET)/VERSIONS

configs/$(TARGET)/VERSIONS:
	echo device-fw $(VERSION) > configs/$(TARGET)/VERSIONS
	echo hdl $(shell cd hdl && git describe --abbrev=4 --dirty --always --tags) >> configs/$(TARGET)/VERSIONS
	echo linux $(BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION) >> configs/$(TARGET)/VERSIONS
	echo u-boot-xlnx $(BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION) >> configs/$(TARGET)/VERSIONS

################################### U-Boot #####################################

export UIMAGE_LOADADDR=0x8000

build/u-boot.elf: uboot
	mkdir -p $(@D)
	cp buildroot/output/images/u-boot $@

build/uboot-env.bin: build/uboot-env.txt
	buildroot/output/build/uboot-$(BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION)/tools/mkenvimage -s 0x20000 -o $@ $<

build/uboot-env.txt: uboot
	mkdir -p $(@D)
	CROSS_COMPILE=$(CROSS_COMPILE) scripts/get_default_envs.sh > $@
	echo attr_name=compatiable >> $@
	echo attr_val=ad9364 >> $@
	sed -i 's,^\(maxcpus[ ]*=\).*,\1'2',g' $@

#################################### Linux ####################################

build/zImage: linux
	mkdir -p $(@D)
	cp buildroot/output/images/zImage $@

build/%.dtb: linux
	mkdir -p $(@D)
	cp buildroot/output/images/*.dtb $(@D)

#################################### Rootfs ####################################

.PHONY: rootfs
rootfs: build/rootfs.cpio.xz

build/rootfs.cpio.xz: license
	mkdir -p $(@D)
	cp build/LICENSE.html configs/$(TARGET)/msd/LICENSE.html
	$(MAKE) -C buildroot
	cp buildroot/output/images/rootfs.cpio.xz $@

###################################### HDL #####################################

.PHONY: hdl
hdl: build/system_top.bit

build/system_top.bit: build/sdk/hw_0/system_top.bit
	cp $< $@

build/sdk/fsbl/Release/fsbl.elf build/sdk/hw_0/system_top.bit: build/system_top.hdf
	rm -Rf build/sdk
ifeq (1, ${HAVE_VIVADO})
	bash -c "source $(VIVADO_SETTINGS) && xsdk -batch -source scripts/create_fsbl_project.tcl"
else
	mkdir -p build/sdk/hw_0
	unzip -o build/system_top.hdf system_top.bit -d build/sdk/hw_0
endif

build/sdk/hw_0/ps7_init.tcl:
	cp hdl/projects/$(HDL_PROJECT)/$(HDL_PROJECT).srcs/sources_1/bd/system/ip/system_sys_ps7_0/ps7_init.tcl $@

build/system_top.hdf:
	mkdir -p $(@D)
ifeq (1, ${HAVE_VIVADO})
	bash -c "source $(VIVADO_SETTINGS) && make -C hdl/projects/$(HDL_PROJECT) && cp hdl/projects/$(HDL_PROJECT)/$(HDL_PROJECT).sdk/system_top.hdf $@"
else
ifneq ($(HDF_URL),)
	wget -T 3 -t 1 -N --directory-prefix build $(HDF_URL)
endif
endif

#################################### Images ####################################

.PHONY: itb
itb: build/$(TARGET).itb

build/$(TARGET).itb: uboot build/zImage build/rootfs.cpio.xz $(addprefix build/,$(TARGET_DTS_FILES)) build/system_top.bit
	buildroot/output/build/uboot-$(BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION)/tools/mkimage -f scripts/$(TARGET).its $@

build/boot.bin: build/sdk/fsbl/Release/fsbl.elf build/u-boot.elf
	@echo img:{[bootloader] $^ } > build/boot.bif
	bash -c "source $(VIVADO_SETTINGS) && bootgen -image build/boot.bif -w -o $@"

################################### Products ###################################

.PHONY: fw frm dfu
fw: frm dfu

frm: build/$(TARGET).frm

dfu: build/$(TARGET).dfu

### MSD update firmware file ###

build/$(TARGET).frm: build/$(TARGET).itb
	md5sum $< | cut -d ' ' -f 1 > $@.md5
	cat $< $@.md5 > $@

build/boot.frm: build/boot.bin build/uboot-env.bin scripts/target_mtd_info.key
	cat $^ | tee $@ | md5sum | cut -d ' ' -f1 | tee -a $@

### DFU update firmware file ###

build/%.dfu: build/%.bin
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

build/$(TARGET).dfu: build/$(TARGET).itb
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

###

zip-all: $(TARGETS)
	zip -j build/$(ZIP_ARCHIVE_PREFIX)-fw-$(VERSION).zip $^

jtag-bootstrap: build/u-boot.elf build/sdk/hw_0/ps7_init.tcl build/sdk/hw_0/system_top.bit scripts/run.tcl
	$(CROSS_COMPILE)strip build/u-boot.elf
	zip -j build/$(ZIP_ARCHIVE_PREFIX)-$@-$(VERSION).zip $^

#################################### Clean #####################################

.PHONY: clean-all clean-build clean-hdl clean-target

clean-all: clean-build clean-hdl clean

clean-build:
	rm -rf build

clean-hdl:
	make -C hdl clean

clean-target:
	rm -rf buildroot/output/target
	find buildroot/output/ -name ".stamp_target_installed" |xargs rm -rf

##################################### DFU ######################################

.PHONY: dfu-$(TARGET) dfu-sf-uboot dfu-all dfu-ram

dfu-$(TARGET): build/$(TARGET).dfu
	dfu-util -D build/$(TARGET).dfu -a firmware.dfu
	dfu-util -e

dfu-sf-uboot: build/boot.dfu build/uboot-env.dfu
	echo "Erasing u-boot be careful - Press Return to continue... " && read key  && \
		dfu-util -D build/boot.dfu -a boot.dfu && \
		dfu-util -D build/uboot-env.dfu -a uboot-env.dfu
	dfu-util -e

dfu-all: build/$(TARGET).dfu build/boot.dfu build/uboot-env.dfu
	echo "Erasing u-boot be careful - Press Return to continue... " && read key && \
		dfu-util -D build/$(TARGET).dfu -a firmware.dfu && \
		dfu-util -D build/boot.dfu -a boot.dfu  && \
		dfu-util -D build/uboot-env.dfu -a uboot-env.dfu
	dfu-util -e

dfu-ram: build/$(TARGET).dfu
	sshpass -p analog ssh root@$(TARGET) '/usr/sbin/device_reboot ram;'
	sleep 5
	dfu-util -D build/$(TARGET).dfu -a firmware.dfu
	dfu-util -e

################################################################################

.PHONY: upload
upload:
	cp build/$(TARGET).frm /run/media/*/PlutoSDR/
	cp build/boot.frm /run/media/*/PlutoSDR/
	sudo eject /run/media/$$USER/PlutoSDR
