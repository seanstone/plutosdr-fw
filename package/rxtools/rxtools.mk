################################################################################
#
# rxtools
#
################################################################################

RXTOOLS_VERSION = 811b21c
RXTOOLS_SITE = https://github.com/rxseger/rx_tools.git
RXTOOLS_SITE_METHOD = git

RXTOOLS_INSTALL_STAGING = YES
RXTOOLS_LICENSE = GPL-2.0
RXTOOLS_LICENSE_FILES =  COPYING
RXTOOLS_DEPENDENCIES = soapy-sdr

$(eval $(cmake-package))