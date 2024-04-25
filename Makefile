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

else

#################################### Buildroot ####################################

BR2_EXTERNAL := $(CURDIR)
BR2_DEFCONFIG := $(CURDIR)/configs/zynq_pluto_defconfig
O := $(CURDIR)/build
include $(BR2_DEFCONFIG)
REMOTE := $(shell git remote -v | grep origin | grep fetch)
REMOTE := $(dir $(word 1, $(REMOTE:origin%=%)))
REMOTE := $(REMOTE:%/=%)
export

all menuconfig defconfig: $(O)/.config

## Making sure defconfig is already run
$(O)/.config:
	$(MAKE) zynq_pluto_defconfig

%:
	env - PATH=$(PATH) USER=$(USER) HOME=$(HOME) TERM=$(TERM) LD_PRELOAD=$(LD_PRELOAD) \
		CC=$(CC) CXX=$(CXX) CPPFLAGS=$(CPPFLAGS) BR2_MAKE=$(BR2_MAKE) \
		HOSTCC=$(HOSTCC_NOCCACHE) HOSTCXX=$(HOSTCXX_NOCCACHE) HOSTCC_NOCCACHE=$(HOSTCC_NOCCACHE) HOSTCXX_NOCCACHE=$(HOSTCXX_NOCCACHE) \
		$(MAKE) BR2_EXTERNAL=$(BR2_EXTERNAL) BR2_DEFCONFIG=$(BR2_DEFCONFIG) O=$(O) REMOTE=$(REMOTE) -C buildroot $*

#################################### Linux ####################################

export LINUX_DIR = $(strip $(O)/build/linux-$(BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION))

## Generate reference defconfig with missing options set to default as a base for comparison using diffconfig
$(LINUX_DIR)/.$(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig:
	$(MAKE) -C $(LINUX_DIR) KCONFIG_CONFIG=$@ ARCH=arm $(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig

## Generate diff with reference config
linux-diffconfig: $(LINUX_DIR)/.$(BR2_LINUX_KERNEL_DEFCONFIG)_defconfig linux-extract
	$(LINUX_DIR)/scripts/diffconfig -m $< $(LINUX_DIR)/.config > $(BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES)

###############################################################################

clean-target:
	rm -rf $(O)/target
	find $(O) -name ".stamp_target_installed" | xargs rm -rf

endif

.PHONY: dfu
dfu: build/images/pluto.dfu
	sudo dfu-util -D $< -a firmware.dfu
