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

WIFI_IF="wlan0"

# Retry up to 3 times: rescan -> list -> connect
for attempt in $(seq 1 3); do
    echo "Attempt $attempt: rescanning WiFi..."
    nmcli device wifi rescan ifname "$WIFI_IF" 2>/dev/null || true
    sleep 5
    
    echo "Checking if SSID '$SSID' is visible..."
    if nmcli -t -f SSID device wifi list 2>/dev/null | awk 'length>0' | grep -Fxq "$SSID"; then
        echo "SSID found, attempting connection..."
        if nmcli -w 20 connection up "$last_name" 2>/dev/null; then
            echo "Connection successful"
            break
        else
            echo "Connection failed, will retry..."
        fi
    else
        echo "SSID not found in scan results, skipping connect..."
    fi
    
    [ "$attempt" -lt 3 ] && sleep 2
done

echo "WiFi reset completed"