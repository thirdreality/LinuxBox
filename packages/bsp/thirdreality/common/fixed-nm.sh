#!/bin/sh

CONFIG_FILE="/etc/NetworkManager/NetworkManager.conf"
PATTERN_LINE="unmanaged-devices=*"
REPLACEMENT_LINE="unmanaged-devices=interface-name:*,except:interface-name:wlan0"

if [ -e $CONFIG_FILE ]; then
    echo "Fix the NetworkManager.conf ..."
    sed -i.bak "/$PATTERN_LINE/c $REPLACEMENT_LINE" "$CONFIG_FILE"
fi

exit 0