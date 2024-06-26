#!/bin/sh

source /etc/device_config

file=/sys/kernel/config/usb_gadget/composite_gadget/functions/mass_storage.0/lun.0/file
bootimage=/mnt/boot.frm
conf=/mnt/config.txt
img=/tmp/vfat.img

ini_parser() {
 FILE=$1
 SECTION=$2
 eval `sed -e 's/[[:space:]]*\=[[:space:]]*/=/g' \
    -e 's/[#;\`].*$//' \
    -e 's/[[:space:]]*$//' \
    -e 's/^[[:space:]]*//' \
    -e "s/^\(.*\)=\([^\"']*\)$/\1=\"\2\"/" \
   < $FILE \
    | sed -n -e "/^\[$SECTION\]/,/^\s*\[/{/^[^;].*\=.*/p;}"`
}

reset() {
	echo "REBOOT/RESET using Watchdog timeout"
	flash_indication_off
	sync
	device_reboot reset
	sleep 10
}

dfu() {
	echo "Entering DFU mode using SW Reset"
	flash_indication_off
	sync
	device_reboot sf
}

flash_indication_on() {
	echo timer > /sys/class/leds/led0:green/trigger
	echo 40 > /sys/class/leds/led0:green/delay_off
	echo 40 > /sys/class/leds/led0:green/delay_on
}

flash_indication_off() {
	echo heartbeat > /sys/class/leds/led0:green/trigger
}

make_diagnostic_report () {
	FILE=$1
	cat  /opt/VERSIONS /etc/os-release /var/log/messages /proc/cpuinfo /proc/interrupts /proc/iomem /proc/meminfo /proc/cmdline /sys/kernel/debug/clk/clk_summary > ${FILE}
	grep -r "" /sys/kernel/debug/regmap/ >> ${FILE} 2>&1
	iio_info >> ${FILE} 2>&1
	ifconfig -a >> ${FILE} 2>&1
	mount >> ${FILE} 2>&1
	top -b -n1  >> ${FILE} 2>&1
	fw_printenv >> ${FILE} 2>&1
	unix2dos ${FILE}
}

calibrate () {
	/usr/sbin/ad936x_ref_cal -e $1 ad9361-phy
	if [ $? -eq 0 ]; then

		for dev in /sys/bus/iio/devices/*; do
			[ `cat ${dev}/name` == "ad9361-phy" ] && DEV_NAME=`basename ${dev}`
		done
		NEW_XO=`cat /sys/bus/iio/devices/${DEV_NAME}/xo_correction`
		flash_indication_on
		fw_setenv xo_correction $NEW_XO
		flash_indication_off

		sed -i -e "s/^xo_correction .*$/xo_correction = $NEW_XO/" -e "s/^calibrate .*$/calibrate = 0/" $conf
	else
		sed -i -e "s/^calibrate .*$/calibrate = 0/" $conf
	fi
}

process_ini() {
	FILE=$1

	ini_parser $FILE "NETWORK"
	ini_parser $FILE "WLAN"
	ini_parser $FILE "SYSTEM"
	ini_parser $FILE "USB_ETHERNET"

	rm -f /mnt/SUCCESS_ENV_UPDATE /mnt/FAILED_INVALID_UBOOT_ENV /mnt/CAL_STATUS


	fw_printenv qspiboot
	if [ $? -eq 0 ]; then
		flash_indication_on
		echo "hostname $hostname" > /tmp/fw_set.tmp
		echo "ipaddr $ipaddr" >> /tmp/fw_set.tmp
		echo "ipaddr_host $ipaddr_host" >> /tmp/fw_set.tmp
		echo "netmask $netmask" >> /tmp/fw_set.tmp
		echo "ssid_wlan $ssid_wlan" >> /tmp/fw_set.tmp
		echo "ipaddr_wlan $ipaddr_wlan" >> /tmp/fw_set.tmp
		echo "pwd_wlan $pwd_wlan" >> /tmp/fw_set.tmp
		echo "xo_correction $xo_correction" >> /tmp/fw_set.tmp
		echo "udc_handle_suspend $udc_handle_suspend" >> /tmp/fw_set.tmp
		echo "ipaddr_eth $ipaddr_eth" >> /tmp/fw_set.tmp
		echo "netmask_eth $netmask_eth" >> /tmp/fw_set.tmp
		fw_setenv -s /tmp/fw_set.tmp
		rm /tmp/fw_set.tmp
		flash_indication_off
		touch /mnt/SUCCESS_ENV_UPDATE
	else
		touch /mnt/FAILED_INVALID_UBOOT_ENV
	fi

	ini_parser $FILE "ACTIONS"

	if [ "$reset" == "1" ]
	then
		reset
	fi

	if [ "$dfu" == "1" ]
	then
		dfu
	fi

	if [ "$diagnostic_report" == "1" ]
	then
		make_diagnostic_report /mnt/diagnostic_report
	fi

	if [ "$calibrate" -gt "70000000" ]
	then
		calibrate $calibrate > /mnt/CAL_STATUS
	fi

	md5sum $FILE > /tmp/config.md5
}

handle_boot_frm () {
	FILE="$1"
	rm -f /mnt/BOOT_SUCCESS /mnt/BOOT_FAILED /mnt/FAILED_MTD_PARTITION_ERROR /mnt/FAILED_BOOT_CHSUM_ERROR
	head -3 /proc/mtd | sed 's/00010000/00001000/g' > /tmp/mtd

	md5=`tail -c 33 ${FILE}`
	head -c -33 ${FILE} > /tmp/boot_and_env_and_mtdinfo.bin

	tail -c 1024 /tmp/boot_and_env_and_mtdinfo.bin | head -3 > /tmp/mtd-info.txt
	head -c -1024 /tmp/boot_and_env_and_mtdinfo.bin > /tmp/boot_and_env.bin

	tail -c 131072 /tmp/boot_and_env.bin > /tmp/u-boot-env.bin
	head -c -131072 /tmp/boot_and_env.bin > /tmp/boot.bin

	frm=`md5sum /tmp/boot_and_env_and_mtdinfo.bin | cut -d ' ' -f 1`

	if [ "$frm" = "$md5" ]
	then
		diff -w /tmp/mtd /tmp/mtd-info.txt
		if [ $? -eq 0 ]; then
			flash_indication_on
			dd if=/tmp/boot.bin of=/dev/mtdblock0 bs=64k && dd if=/tmp/u-boot-env.bin of=/dev/mtdblock1 bs=64k && do_reset=1 && touch /mnt/BOOT_SUCCESS || touch /mnt/BOOT_FAILED
			flash_indication_off
		else
			cat /tmp/mtd /tmp/mtd-info.txt > /mnt/FAILED_MTD_PARTITION_ERROR
			do_reset=0
		fi
	else
		echo $md5 $frm >  /mnt/FAILED_BOOT_CHSUM_ERROR
		do_reset=0
	fi

	rm -f ${FILE} /tmp/boot_and_env_and_mtdinfo.bin /tmp/mtd-info.txt /tmp/boot_and_env.bin /tmp/u-boot-env.bin /tmp/boot.bin /tmp/mtd
}

handle_frimware_frm () {
	FILE="$1"
	MAGIC="$2"
	rm -f /mnt/SUCCESS /mnt/FAILED /mnt/FAILED_FIRMWARE_CHSUM_ERROR
	md5=`tail -c 33 ${FILE}`
	head -c -33 ${FILE} > /tmp/firmware.frm
	FRM_SIZE=`cat /tmp/firmware.frm | wc -c | xargs printf "%X\n"`
	frm=`md5sum /tmp/firmware.frm | cut -d ' ' -f 1`
	if [ "$frm" = "$md5" ]
	then
		flash_indication_on
		grep -q "${MAGIC}"  /tmp/firmware.frm && dd if=/tmp/firmware.frm of=/dev/mtdblock3 bs=64k && fw_setenv fit_size ${FRM_SIZE} && do_reset=1 && touch /mnt/SUCCESS || touch /mnt/FAILED
        flash_erase -j /dev/mtd4 0 0
        flash_indication_off
	else
		echo $frm $md5 > /mnt/FAILED_FIRMWARE_CHSUM_ERROR
		do_reset=0
	fi

	rm -f ${FILE} /tmp/firmware.frm
	sync
}

while [ 1 ]
do
 if [[ -r ${file} ]]
  then
    lun=`cat $file`
    if [ ${#lun} -eq 0 ]
    then
	do_reset=0
	losetup /dev/loop7 $img -o 512
	mkdir -p /mnt/
	mount /dev/loop7 /mnt/

	if [[ -s /mnt/$TARGET-fw-*.zip ]]
	then
		mv /mnt/$TARGET-fw-*.zip /tmp/
		unzip -o /tmp/$TARGET-fw-*.zip *.frm -d /mnt
		rm /tmp/$TARGET-fw-*.zip
	fi

	if [[ -s ${FIRMWARE} ]]
	then 
		handle_frimware_frm "${FIRMWARE}" "${FRM_MAGIC}"
	fi

	if [[ -s ${bootimage} ]]
	then
		handle_boot_frm "${bootimage}"
	fi

	md5sum -c /tmp/config.md5 || process_ini $conf

	if [ "$TARGET" == "m2k" ]; then
		if [[ -s /mnt/${CALIBFILENAME} ]]; then
			md5sum -c /tmp/${CALIBFILENAME}.md5
			if [ $? -ne 0 ]; then
				cp  /mnt/${CALIBFILENAME} /mnt_jffs2/${CALIBFILENAME} && do_reset=1
			fi

		else
			rm /mnt_jffs2/${CALIBFILENAME} && do_reset=1
		fi

		if [[ -s /mnt/${CALIBFILENAME_FACTORY} ]]; then
			if [[ ! -s /mnt_jffs2/${CALIBFILENAME_FACTORY} ]]; then
				cp /mnt/${CALIBFILENAME_FACTORY} /mnt_jffs2/${CALIBFILENAME_FACTORY}
					do_reset=1
			fi
		fi
	fi

	if [[ $do_reset = 1 ]]
	then
		reset
	fi

	cp /opt/ipaddr-* /mnt 2>/dev/null

	umount /mnt
	#losetup -d /dev/loop7
	echo $img > $file
	flash_indication_off
	sleep 1
    fi
fi

sleep 1

done

exit 1
