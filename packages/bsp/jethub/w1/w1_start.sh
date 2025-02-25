#!/bin/bash

# Check aml_sdio.ko is loaded or not
if ! lsmod | grep -q "^aml_sdio"; then
    echo "Loading module: aml_sdio.ko ..."
    insmod /usr/lib/modules/$(uname -r)/kernel/drivers/net/wireless/w1ss1/vmac/aml_sdio.ko
else
    echo "Module aml_sdio.ko is already loaded."
fi

# Check vlsicomm.ko is loaded or not
if ! lsmod | grep -q "^vlsicomm"; then
    echo "Loading module: vlsicomm.ko ..."
    insmod /usr/lib/modules/$(uname -r)/kernel/drivers/net/wireless/w1ss1/vmac/vlsicomm.ko
else
    echo "Module vlsicomm.ko is already loaded."
fi

# Function to check and bring down a network interface
bring_down_interface() {
    local iface="$1"
    if ip a show "$iface" &>/dev/null; then
        if ip link show "$iface" | grep -q "state UP"; then
            echo "Interface $iface is up, bringing it down..."
            ifconfig "$iface" down
        else
            echo "Interface $iface exists but is already down."
        fi
    else
        echo "Interface $iface does not exist."
    fi
}

# Check and bring down wlan1
bring_down_interface "wlan1"

# Check and bring down p2p0
bring_down_interface "p2p0"
