#!/bin/bash

set -e 

systemctl stop hassio-supervisor.service
systemctl stop hassio-apparmor.service

systemctl disable hassio-supervisor.service
systemctl disable hassio-apparmor.service

apt-get remove -y homeassistant-supervised os-agent

docker stop $(docker ps -q) 2>/dev/null

docker system prune -a -f

rm -rf /usr/share/hassio

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

echo "Factory reset completed. Rebooting now..."

sleep 5

/usr/sbin/reboot


