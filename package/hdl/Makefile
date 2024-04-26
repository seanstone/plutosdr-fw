PROJECT_PATH = projects/$(PROJECT_NAME)
SDK_PATH = $(PROJECT_PATH)/PROJECTNAME$(PROJECT_NAME)_ADIIGNOREVERSIONCHECK1_ADIUSEOOCSYNTHESIS1_MODEincr/$(PROJECT_NAME).sdk

.PHONY: all
all: $(PROJECT_PATH)/boot.bin $(PROJECT_PATH)/$(PROJECT_NAME).dtb $(PROJECT_PATH)/system_top.bit

################################## Boot image ###################################

$(BINARIES_DIR)/$(PROJECT_NAME)/u-boot.elf: $(BINARIES_DIR)/u-boot
	mkdir -p $(@D)
	cp $< $@

$(PROJECT_PATH)/u-boot.elf: $(BINARIES_DIR)/$(PROJECT_NAME)/u-boot.elf
	mkdir -p $(@D)
	cp $< $@

$(PROJECT_PATH)/boot.bin: $(SDK_PATH)/fsbl/fsbl/Debug/fsbl.elf $(PROJECT_PATH)/u-boot.elf
# bootgen requires a file extension
	echo img:{[bootloader] "PROJECTNAME$(PROJECT_NAME)_ADIIGNOREVERSIONCHECK1_ADIUSEOOCSYNTHESIS1_MODEincr/$(PROJECT_NAME).sdk/fsbl/fsbl/Debug/fsbl.elf" "PROJECTNAME$(PROJECT_NAME)_ADIIGNOREVERSIONCHECK1_ADIUSEOOCSYNTHESIS1_MODEincr/$(PROJECT_NAME).sdk/system_top.bit" "u-boot.elf" } > "$(PROJECT_PATH)/boot.bif"
	cd $(PROJECT_PATH) && bootgen -image boot.bif -w -o boot.bin

################################## Device tree ##################################

$(PROJECT_PATH)/$(PROJECT_NAME).dtb: $(PROJECT_PATH)/$(PROJECT_NAME).dts $(SDK_PATH)/dts
	cpp -nostdinc -I$(LINUX_DIR)/arch/arm/boot/dts -I$(LINUX_DIR)/include -undef -x assembler-with-cpp $< $<.preprocessed
	dtc -i $(SDK_PATH)/dts $<.preprocessed -o $@

$(PROJECT_PATH)/$(PROJECT_NAME).dts $(SDK_PATH)/dts: $(SDK_PATH)/system_top.xsa
	cd $(SDK_PATH) && xsct $(CURDIR)/generate_dts.tcl
# Delete nodes
	sed -i '/axi_ad9361/,/}/d' $(SDK_PATH)/dts/pl.dtsi
	sed -i '/misc_clk_0/,/}/d' $(SDK_PATH)/dts/pl.dtsi
	sed -i '/axi_ad9361_adc_dma/,/}/d' $(SDK_PATH)/dts/pl.dtsi
	sed -i '/axi_ad9361_dac_dma/,/}/d' $(SDK_PATH)/dts/pl.dtsi
	sed -i '/axi_iic_main/,/}/d' $(SDK_PATH)/dts/pl.dtsi
	sed -i '/axi_sysid_0/,/}/d' $(SDK_PATH)/dts/pl.dtsi

##################################### FSBL ######################################

$(SDK_PATH)/fsbl/fsbl/Debug/fsbl.elf: $(SDK_PATH)/system_top.xsa
	rm -rf $(SDK_PATH)/fsbl
	cd $(SDK_PATH) && \
		LD_PRELOAD="/lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libpcre2-8.so.0" \
		JAVA_TOOL_OPTIONS="-Dsun.java2d.xrender=false" \
		JAVA_OPTS="-Dsun.java2d.xrender=false" \
		DISPLAY="host.docker.internal:0" \
		xsct $(CURDIR)/create_fsbl_project.tcl

######################### Hardware design (bitstream) ###########################

$(BINARIES_DIR)/ip:
	mkdir -p $@

$(SDK_PATH)/system_top.xsa: $(BINARIES_DIR)/ip
	cd $(PROJECT_PATH) && \
		LD_PRELOAD="/lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libpcre2-8.so.0" \
		$(MAKE) ADI_IGNORE_VERSION_CHECK=1 ADI_USE_OOC_SYNTHESIS=1 MODE=incr -j1

$(PROJECT_PATH)/system_top.bit: $(SDK_PATH)/system_top.xsa
	cp $(SDK_PATH)/system_top.bit $@
