#!/bin/bash
echo "Resetting WiFi connection..."

# Dynamically get the name of the currently active WiFi connection
CURRENT_WIFI=$(nmcli -t -f NAME,TYPE connection show --active | grep 'wireless' | cut -d: -f1)

if [ -z "$CURRENT_WIFI" ]; then
    echo "No active WiFi connection found"
    exit 1
fi

echo "Current WiFi connection: $CURRENT_WIFI"

# Reset WiFi radio
nmcli radio wifi off
sleep 3
nmcli radio wifi on
sleep 5

# Reconnect
nmcli c down "$CURRENT_WIFI" 2>/dev/null
nmcli c up "$CURRENT_WIFI"
echo "WiFi reset completed"