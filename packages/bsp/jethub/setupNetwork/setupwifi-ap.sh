#!/bin/sh

check_network()
{
	# Can be reduced but do not delete this sleep,
	# or the wifi will be unavailable
	sleep 5

	if iw dev wlan0 link | grep -q "Not connected"; then
		exit 0
	else
		systemctl disable setupwifi-ap.service
		systemctl stop setupwifi-ap.service
		exit 1
	fi
}

hostapd_conf()
{
	if [ ! -f /etc/ap_name ]; then
		cat /sys/class/net/wlan0/address |sed 's/\://g' |tr 'a-z' 'A-Z' > /etc/ap_name
	fi

	ap_name=`cat /etc/ap_name`
	ssid=3RE-SPK-$ap_name
	password=12345678

	echo 0 > /etc/hostapd.conf
    echo "interface=wlan1" > /etc/hostapd.conf
    echo "driver=nl80211" >> /etc/hostapd.conf
    echo "ctrl_interface=/var/run/hostapd" >> /etc/hostapd.conf
    echo "ssid=${ssid}" >> /etc/hostapd.conf
    echo "channel=6" >> /etc/hostapd.conf
    echo "ieee80211n=1" >> /etc/hostapd.conf
    echo "hw_mode=g" >> /etc/hostapd.conf
    echo "ignore_broadcast_ssid=0"  >> /etc/hostapd.conf
    echo "wpa=2" >> /etc/hostapd.conf
    echo "wpa_passphrase=${password}" >> /etc/hostapd.conf
    echo "wpa_key_mgmt=WPA-PSK" >> /etc/hostapd.conf
    echo "rsn_pairwise=CCMP" >> /etc/hostapd.conf
}

start_hostapd()
{
	hostapd_conf
	hostapd /etc/hostapd.conf -e /etc/entropy.bin &
	ifconfig wlan1 192.168.2.1
	/usr/bin/dnsmasq -iwlan1 --dhcp-option=3,192.168.2.1 --dhcp-range=192.168.2.50,192.168.2.200,12h -p100 &
	/usr/bin/tcpserver &
}

stop_hostapd()
{
	killall hostapd
	killall tcpserver
	killall dnsmasq
	ifconfig wlan1 down
}

case "$1" in
	start)
		start_hostapd
	;;
	stop)
		stop_hostapd
	;;
	check)
		check_network
	;;
esac
