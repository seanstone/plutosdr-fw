################################################################################
#
# csdr
#
################################################################################

CSDR_VERSION = 6ef2a74
CSDR_SITE = https://github.com/simonyiszk/csdr.git
CSDR_SITE_METHOD = git
CSDR_LICENSE = BSD-3c
CSDR_DEPENDENCIES = fftw-single

ifeq ($(BR2_ARM_CPU_HAS_NEON),y)
CSDR_CFLAGS += -mfpu=neon -mvectorize-with-neon-quad -funsafe-math-optimizations
endif


define CSDR_BUILD_CMDS
	$(TARGET_CC) -std=gnu99 $(TARGET_CFLAGS) $(TARGET_LDFLAGS) $(CSDR_CFLAGS) $(@D)/fft_fftw.c $(@D)/libcsdr_wrapper.c -lm -lrt -lfftw3f -DUSE_FFTW -DLIBCSDR_GPL -DUSE_IMA_ADPCM  -fpic -shared -Wl,-soname,libcsdr.so -o $(@D)/libcsdr.so
	$(TARGET_CC) -std=gnu99 $(@D)/csdr.c $(TARGET_CFLAGS) $(TARGET_LDFLAGS) $(CSDR_CFLAGS) -lm -lrt -lfftw3f -DUSE_FFTW -DLIBCSDR_GPL -DUSE_IMA_ADPCM -L$(@D) -lcsdr -ffast-math -fdump-tree-vect-details -o  $(@D)/csdr
	$(TARGET_CXX)  $(@D)/nmux.cpp $(@D)/tsmpool.cpp $(CSDR_CFLAGS) -L$(@D) -lcsdr -lpthread  -o  $(@D)/nmux
endef

define CSDR_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 755 $(@D)/libcsdr.so $(TARGET_DIR)/usr/lib/libcsdr.so
	$(INSTALL) -D -m 755 $(@D)/csdr $(TARGET_DIR)/usr/bin
	$(INSTALL) -D -m 755 $(@D)/nmux $(TARGET_DIR)/usr/bin
endef


$(eval $(generic-package))

