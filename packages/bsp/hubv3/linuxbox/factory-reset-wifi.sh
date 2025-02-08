#!/bin/bash

echo "Start to perform factory reseting ..."

if [ -e "/usr/lib/armbian/jethub-led-ctrl" ]; then
    /usr/lib/armbian/jethub-led-ctrl setstate Y
fi

sync

sleep 0.5

echo "Reset WIFI settings ..."
#/usr/local/3r-chinese-voice-service/recycle_aispeech_license
#start-stop-daemon -S -b -x /usr/sbin/restore_data_reboot.sh --

# reset wifi connection information
if [ -e "/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" ]; then
    rm -rf /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf
fi

/usr/sbin/dhclient -r wlan0
#systemctl enable setupwifi.service

sync

echo "Rebooting system ..."
/usr/sbin/reboot
