#!/bin/sh

BT_FIRMWARE_DIR="/etc/bluetooth/aml"

# --- Wait for the WiFi side before touching the radio ----------------------
#
# The W155S1 is a WiFi/BT combo: both halves sit on the same SDIO bus and share
# the chip PMU/AON domain. Two things below are unsafe until the WiFi driver has
# finished bringing the chip up:
#   * writing rfkill0/state pulses reset-gpios (GPIOX_21) low for 200ms, which
#     resets the shared chip;
#   * sdio_bt's probe needs g_w1_hif_ops, which is only populated by the WiFi
#     driver's SDIO probe - without it the probe calls a NULL function pointer
#     and oopses, leaving the module wedged in "loading" state until reboot.
# amlogicw1.service is ordered before us, but guard here too so manual starts and
# resetupwifi.sh recovery paths are equally safe.
WIFI_WAIT_SECS=30

i=0
while [ ! -d /sys/class/net/wlan0 ]; do
	if [ "$i" -ge "$WIFI_WAIT_SECS" ]; then
		echo "[w1_bt_start] wlan0 absent after ${WIFI_WAIT_SECS}s; skipping BT bring-up to avoid resetting the shared W155S1 chip"
		exit 0
	fi
	[ "$i" -eq 0 ] && echo "[w1_bt_start] waiting for wlan0 before starting Bluetooth ..."
	sleep 1
	i=$((i + 1))
done

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