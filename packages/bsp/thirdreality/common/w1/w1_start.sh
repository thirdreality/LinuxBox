#!/bin/bash
#
# Amlogic W155S1 WiFi driver loader with self-protection.
#
# The W155S1 is attached over SDIO. Its bring-up (SDIO enumeration, PMU power-on
# and firmware download) has no error checking or retry inside the driver, so a
# rare power/timing glitch can leave the chip half-initialised: wlan0 never
# appears and the BT side (which depends on the WiFi sdio common driver) then
# hangs. To make boot robust we load the modules, wait for wlan0 to show up, and
# on failure fully unload and retry (a clean rmmod/insmod re-triggers the SDIO
# power sequence, recovering most transient failures).

MODULE_DIR="/usr/lib/modules/$(uname -r)/kernel/drivers/net/wireless/w1/vmac"
MAX_TRIES=3          # total load attempts before giving up
WAIT_SECS=10         # seconds to wait for wlan0 after loading

log() { echo "[w1_start] $*"; }

module_loaded() { lsmod | grep -q "^$1"; }

load_modules() {
    if ! module_loaded aml_sdio; then
        log "Loading aml_sdio.ko ..."
        insmod "${MODULE_DIR}/aml_sdio.ko" || { log "insmod aml_sdio.ko FAILED"; return 1; }
    fi
    if ! module_loaded vlsicomm; then
        log "Loading vlsicomm.ko ..."
        insmod "${MODULE_DIR}/vlsicomm.ko" || { log "insmod vlsicomm.ko FAILED"; return 1; }
    fi
    return 0
}

unload_modules() {
    # Reverse order; ignore errors (module may already be gone).
    module_loaded vlsicomm && { log "Unloading vlsicomm ..."; rmmod vlsicomm 2>/dev/null; }
    module_loaded aml_sdio && { log "Unloading aml_sdio ..."; rmmod aml_sdio 2>/dev/null; }
}

# wlan0 appears once the firmware download / probe completed successfully.
wifi_ready() { [ -d /sys/class/net/wlan0 ]; }

wait_for_wifi() {
    local i=0
    while [ $i -lt "$WAIT_SECS" ]; do
        wifi_ready && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# --- Bring-up with bounded retry -------------------------------------------
try=1
wifi_ok=0
while [ $try -le "$MAX_TRIES" ]; do
    log "WiFi bring-up attempt ${try}/${MAX_TRIES}"
    if load_modules && wait_for_wifi; then
        log "wlan0 is up (attempt ${try})"
        wifi_ok=1
        break
    fi

    log "wlan0 did not appear within ${WAIT_SECS}s; power-cycling the chip (unload/reload)"
    unload_modules
    sleep 2   # let the SDIO power sequence settle before retrying
    try=$((try + 1))
done

if [ "$wifi_ok" -ne 1 ]; then
    log "ERROR: WiFi failed to come up after ${MAX_TRIES} attempts"
    exit 1
fi

# Function to check and bring up a network interface
bring_up_interface() {
    local iface="$1"
    if ip a show "$iface" &>/dev/null; then
        if ip link show "$iface" | grep -q "state UP"; then
            echo "Interface $iface exists and is already up."
        else
            echo "Interface $iface is down, bringing it up..."
            ifconfig "$iface" up
        fi
    else
        echo "Interface $iface does not exist."
    fi
}

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

# Check and bring up wlan0
bring_up_interface "wlan0"

# Check and bring down wlan1
bring_down_interface "wlan1"

# Check and bring down p2p0
bring_down_interface "p2p0"
