#!/bin/bash

#dbus-send --system --type=signal /com/3r/EventBus com._3reality.EventBus.Minicli string:"zigbee erase"


sync

sleep 0.5

echo "Update WIFI settings ..."
#/usr/local/3r-chinese-voice-service/recycle_aispeech_license
#start-stop-daemon -S -b -x /usr/sbin/restore_data_reboot.sh --

# reset wifi connection information
if [ -e "/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" ]; then
    rm -rf /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf
fi

/usr/sbin/dhclient -r wlan0
systemctl enable setupwifi.service

sync

/usr/sbin/reboot
