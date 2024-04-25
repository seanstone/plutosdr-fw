#!/bin/bash

# echo with color
function f_echo {
	echo -e "\e[1m\e[33m$1\e[0m"
}

# Extract installer
f_echo "Extracting installer"
chmod +x ./scripts/*.bin
./scripts/*.bin --target /home/user/installer --noexec

# Get AuthToken by repeating the following command until it succeeds
f_echo "Log into your Xilinx account to download the necessary files."
while ! /home/user/installer/xsetup -b AuthTokenGen
do
	f_echo "Your account information seems to be wrong. Please try logging in again."
	sleep 1
done

# Run installer
f_echo "You successfully logged into your account. The installation will begin now."
f_echo "If a window pops up, simply close it to finish the installation."
/home/user/installer/xsetup -c ./scripts/install_config_2023.txt -b Install -a XilinxEULA,3rdPartyEULA