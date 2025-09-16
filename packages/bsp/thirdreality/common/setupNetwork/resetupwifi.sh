#!/bin/bash
echo "Resetting WiFi connection..."

# Find last-used saved WiFi connection (TYPE=wifi or 802-11-wireless) from NetworkManager
mapfile -t WIFI_CONNS < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wifi" || $2=="802-11-wireless"{print $1}')

if [ ${#WIFI_CONNS[@]} -eq 0 ]; then
	echo "No saved WiFi connections found"
	exit 1
fi

last_name=""
last_ts=0
for name in "${WIFI_CONNS[@]}"; do
	# Some NM versions support connection.timestamp; fallback to 0 if unavailable
	ts=$(nmcli -s -g connection.timestamp connection show "$name" 2>/dev/null | tr -d '[:space:]')
	[[ -z "$ts" ]] && ts=0
	# Ensure numeric comparison
	if [[ "$ts" =~ ^[0-9]+$ ]]; then
		if (( ts > last_ts )); then
			last_ts=$ts
			last_name="$name"
		fi
	fi
done

if [ -z "$last_name" ]; then
	# Fallback: pick the first WiFi profile
	last_name="${WIFI_CONNS[0]}"
fi

echo "Selected saved WiFi profile: $last_name (last used timestamp: $last_ts)"

# Extract SSID and PSK from the saved profile
SSID=$(nmcli -s -g 802-11-wireless.ssid connection show "$last_name" 2>/dev/null)
PSK=$(nmcli -s -g 802-11-wireless-security.psk connection show "$last_name" 2>/dev/null)

if [ -z "$SSID" ]; then
	echo "Failed to read SSID from profile: $last_name"
	exit 1
fi

echo "SSID: $SSID"
[ -n "$PSK" ] && echo "PSK: (hidden)" || echo "PSK: (none/open or stored in agent)"

echo "Reset WiFi radio..."
nmcli radio wifi off
sleep 2
nmcli radio wifi on
sleep 3

# Attempt to bring the saved connection up; if that fails, try explicit connect
if ! nmcli -w 10 connection up "$last_name" 2>/dev/null; then
	echo "Profile up failed, trying explicit connect to SSID..."
	if [ -n "$PSK" ]; then
		nmcli -w 20 device wifi connect "$SSID" password "$PSK"
	else
		nmcli -w 20 device wifi connect "$SSID"
	fi
fi

echo "WiFi reset completed"