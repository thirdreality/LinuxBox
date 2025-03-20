#!/bin/sh

BT_FIRMWARE_DIR="/etc/bluetooth/aml"


if [ ! -L "$BT_FIRMWARE_DIR/w1_bt_fw_uart.bin" ] || [ ! -L "$BT_FIRMWARE_DIR/a2dp_mode_cfg.txt" ] || [ ! -L "$BT_FIRMWARE_DIR/aml_bt_rf.txt" ]; then
    mkdir -p "$BT_FIRMWARE_DIR"
    [ -f /lib/firmware/w1/a2dp_mode_cfg.txt ] && ln -sf /lib/firmware/w1/a2dp_mode_cfg.txt "$BT_FIRMWARE_DIR/"
    [ -f /lib/firmware/w1/aml_bt_rf.txt ] && ln -sf /lib/firmware/w1/aml_bt_rf.txt "$BT_FIRMWARE_DIR/"
    [ -f /lib/firmware/w1/w1_bt_fw_uart.bin ] && ln -sf /lib/firmware/w1/w1_bt_fw_uart.bin "$BT_FIRMWARE_DIR/"
fi

echo 0 > /sys/class/rfkill/rfkill0/state
sleep 0.5
echo 1 > /sys/class/rfkill/rfkill0/state

modprobe sdio_bt
sleep 0.2

aml_hciattach -s 115200 /dev/ttyAML1 aml &> /dev/null
sleep 0.1

cnt=10
while [ $cnt -gt 0 ]; do
	hciconfig hci0 2> /dev/null
	if [ $? -eq 1 ]; then
		echo "checking hci0 ......."
		sleep 1
		cnt=$((cnt - 1))
	else
		break
	fi
done
if [ $cnt -eq 0 ];then
	echo "hci0 bring up failed!!!"
	exit 0
fi

rfkill unblock 3
hciconfig hci0 up
hciconfig hci0 noscan