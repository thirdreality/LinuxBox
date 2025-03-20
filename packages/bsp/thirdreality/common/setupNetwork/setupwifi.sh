#!/bin/sh

check_network()
{
	# Can be reduced but do not delete this sleep,
	# or the wifi will be unavailable
	sleep 5

	if iw dev wlan0 link | grep -q "Not connected"; then
		exit 0
	else
		systemctl disable setupwifi.service
		systemctl stop setupwifi.service
		exit 1
	fi
}

hostapd_conf()
{
	# ap_name_file="/etc/ap_name"

	# # Ensure /etc/ap_name exists and is not empty
	# if [ ! -e "$ap_name_file" ] || [ ! -s "$ap_name_file" ]; then
	# 	cat /sys/class/net/wlan0/address | sed 's/://g' | tr 'a-z' 'A-Z' > "$ap_name_file"
	# fi

	# # Retry if ap_name is empty
	# max_retries=5
	# retry_count=0

	# while [ $retry_count -lt $max_retries ]; do
	# 	ap_name=$(cat "$ap_name_file")
		
	# 	if [ -n "$ap_name" ]; then
	# 		echo "AP name successfully retrieved: $ap_name"
	# 		break
	# 	fi

	# 	sleep 1
	# 	echo "Warning: Empty /etc/ap_name, retrying... ($((retry_count + 1))/$max_retries)"
	# 	cat /sys/class/net/wlan0/address | sed 's/://g' | tr 'a-z' 'A-Z' > "$ap_name_file"
	# 	retry_count=$((retry_count + 1))
	# done

	# ssid=3R-$ap_name
	# password=12345678

	# echo 0 > /etc/hostapd.conf
    # echo "interface=wlan1" > /etc/hostapd.conf
    # echo "driver=nl80211" >> /etc/hostapd.conf
    # echo "ctrl_interface=/var/run/hostapd" >> /etc/hostapd.conf
    # echo "ssid=${ssid}" >> /etc/hostapd.conf
    # echo "channel=6" >> /etc/hostapd.conf
    # echo "ieee80211n=1" >> /etc/hostapd.conf
    # echo "hw_mode=g" >> /etc/hostapd.conf
    # echo "ignore_broadcast_ssid=0"  >> /etc/hostapd.conf
    # echo "wpa=2" >> /etc/hostapd.conf
    # echo "wpa_passphrase=${password}" >> /etc/hostapd.conf
    # echo "wpa_key_mgmt=WPA-PSK" >> /etc/hostapd.conf
    # echo "rsn_pairwise=CCMP" >> /etc/hostapd.conf
}

start_service()
{
	if [ -e "/usr/lib/armbian/hubv3-led-ctrl" ]; then
  		/usr/lib/armbian/hubv3-led-ctrl setstate Y
	fi

	# hostapd_conf
	# hostapd /etc/hostapd.conf -e /etc/entropy.bin &
	# ifconfig wlan1 192.168.2.1
	# /usr/bin/dnsmasq -iwlan1 --dhcp-option=3,192.168.2.1 --dhcp-range=192.168.2.50,192.168.2.200,12h -p100 &
	# /usr/bin/tcpserver &

	/usr/bin/btgatt-server &
}

stop_service()
{
	#killall hostapd
	#killall tcpserver
	#killall dnsmasq
	killall btgatt-server
	ifconfig wlan1 down
}

case "$1" in
	start)
		start_service
	;;
	stop)
		stop_service
	;;
	check)
		check_network
	;;
esac
