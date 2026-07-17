#!/bin/bash
#
# resetupwifi.sh [soft|reload|auto]
#
# WiFi recovery helper, invoked by the supervisor when the device has been
# offline for a configurable amount of time. The supervisor owns the timing and
# the status LED (slow yellow blink = no network); this script only performs the
# actual recovery. Reboot is intentionally NOT used: it is too visible to the
# user and hurts the experience.
#
# Levels (escalating in "force"):
#   soft   - nmcli radio off/on + rescan + reconnect. Lightweight. Often does
#            NOT recover a wedged SDIO WiFi chip.
#   reload - Reload the W155S1 driver stack (rmmod sdio_bt/vlsicomm/aml_sdio,
#            then reload via w1_start.sh). Reloading aml_sdio triggers
#            set_usb_wifi_power(0)/(1) in the driver, i.e. a real power-cycle of
#            the WiFi chip WITHOUT rebooting the box (invisible to the user).
#            NOTE: briefly interrupts W155S1 Bluetooth. zigbee/thread run on the
#            separate bl706 chip and are unaffected.
#   auto   - (default) Currently behaves like 'soft'. Escalation to 'reload' is
#            intentionally DISABLED until the 'reload' path is validated on
#            hardware (see the commented hook in run_auto). Test it first by
#            invoking 'resetupwifi.sh reload' directly.

WIFI_IF="wlan0"
LEVEL="${1:-auto}"

log() { echo "[resetupwifi] $*"; }

# ---- connectivity: has IPv4 on wlan0 AND can reach the default gateway ----
is_online() {
    ip -4 addr show "$WIFI_IF" 2>/dev/null | grep -q "inet " || return 1
    local gw
    gw=$(ip -4 route show default dev "$WIFI_IF" 2>/dev/null | awk '/default/{print $3; exit}')
    [ -z "$gw" ] && gw=$(ip -4 route show default 2>/dev/null | awk '/default/{print $3; exit}')
    [ -z "$gw" ] && return 1
    ping -c 2 -W 2 -I "$WIFI_IF" "$gw" >/dev/null 2>&1
}

wait_online() {
    local secs="$1" waited=0
    while [ "$waited" -lt "$secs" ]; do
        is_online && return 0
        sleep 3
        waited=$((waited + 3))
    done
    is_online
}

# ---- find the last-used saved WiFi profile ----
LAST_NAME=""
SSID=""
select_wifi_profile() {
    mapfile -t WIFI_CONNS < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wifi" || $2=="802-11-wireless"{print $1}')
    if [ ${#WIFI_CONNS[@]} -eq 0 ]; then
        log "No saved WiFi connections found"
        return 1
    fi

    local last_ts=0 name ts
    LAST_NAME=""
    for name in "${WIFI_CONNS[@]}"; do
        # Some NM versions support connection.timestamp; fallback to 0 if absent.
        ts=$(nmcli -s -g connection.timestamp connection show "$name" 2>/dev/null | tr -d '[:space:]')
        [[ -z "$ts" ]] && ts=0
        if [[ "$ts" =~ ^[0-9]+$ ]] && (( ts > last_ts )); then
            last_ts=$ts
            LAST_NAME="$name"
        fi
    done
    [ -z "$LAST_NAME" ] && LAST_NAME="${WIFI_CONNS[0]}"

    SSID=$(nmcli -s -g 802-11-wireless.ssid connection show "$LAST_NAME" 2>/dev/null)
    log "Selected saved WiFi profile: $LAST_NAME (last used ts: $last_ts, ssid: ${SSID:-unknown})"
    [ -n "$SSID" ] || { log "Failed to read SSID from profile: $LAST_NAME"; return 1; }
    return 0
}

# ---- try to bring up the selected profile, up to 3 rescans ----
reconnect_profile() {
    local attempt
    for attempt in $(seq 1 3); do
        log "Attempt $attempt: rescanning WiFi..."
        nmcli device wifi rescan ifname "$WIFI_IF" 2>/dev/null || true
        sleep 5
        if nmcli -t -f SSID device wifi list 2>/dev/null | awk 'length>0' | grep -Fxq "$SSID"; then
            log "SSID '$SSID' visible, connecting..."
            if nmcli -w 20 connection up "$LAST_NAME" 2>/dev/null; then
                log "Connection command succeeded"
                return 0
            fi
            log "Connection failed, will retry..."
        else
            log "SSID '$SSID' not in scan results"
        fi
        [ "$attempt" -lt 3 ] && sleep 2
    done
    return 1
}

# ---- Level: soft (radio toggle + reconnect) ----
soft_recover() {
    log "Soft recovery: toggling WiFi radio and reconnecting..."
    nmcli radio wifi off
    sleep 2
    nmcli radio wifi on
    sleep 3
    reconnect_profile
}

# ---- Level: reload (WiFi chip power-cycle via driver reload) ----
reload_recover() {
    log "Reload recovery: power-cycling the WiFi chip via driver reload..."
    log "NOTE: this briefly interrupts W155S1 Bluetooth (zigbee/thread unaffected)."

    nmcli radio wifi off 2>/dev/null || true
    sleep 1

    # aml_sdio is shared by Bluetooth (sdio_bt) and WiFi (vlsicomm). Unload the
    # whole stack top-down so aml_sdio itself can be removed and re-probed.
    systemctl stop amlogicw1-bt.service 2>/dev/null || true
    rmmod sdio_bt 2>/dev/null || true
    rmmod vlsicomm 2>/dev/null || true
    rmmod aml_sdio 2>/dev/null || true
    sleep 2

    # Reload the WiFi stack. w1_start.sh does: insmod aml_sdio (which triggers
    # set_usb_wifi_power(0)/(1) = a real chip power-cycle) -> insmod vlsicomm ->
    # bring up wlan0.
    if [ -x /usr/lib/firmware/w1/w1_start.sh ]; then
        /usr/lib/firmware/w1/w1_start.sh || true
    else
        modprobe aml_sdio 2>/dev/null || true
        modprobe vlsicomm 2>/dev/null || true
    fi
    sleep 3

    # Restore Bluetooth.
    if systemctl list-unit-files amlogicw1-bt.service >/dev/null 2>&1; then
        systemctl start amlogicw1-bt.service 2>/dev/null || true
    elif [ -x /usr/lib/firmware/w1/w1_bt_start.sh ]; then
        /usr/lib/firmware/w1/w1_bt_start.sh || true
    fi

    nmcli radio wifi on 2>/dev/null || true
    sleep 3

    reconnect_profile
}

# ---- Level: auto (currently soft only; reload escalation disabled pending test) ----
run_auto() {
    soft_recover

    # TODO: enable ONLY after validating 'resetupwifi.sh reload' on hardware.
    # If still offline after soft recovery, escalate to a WiFi-chip power-cycle:
    #
    # if ! wait_online 15; then
    #     log "Still offline after soft recovery; escalating to reload..."
    #     reload_recover
    # fi
}

# =============================== main ===============================
log "WiFi recovery started (level: $LEVEL)"

if ! select_wifi_profile; then
    log "Cannot proceed without a saved WiFi profile"
    exit 1
fi

case "$LEVEL" in
    soft)   soft_recover ;;
    reload) reload_recover ;;
    auto)   run_auto ;;
    *)      log "Unknown level '$LEVEL', falling back to soft"; soft_recover ;;
esac

if wait_online 10; then
    log "WiFi recovery completed: ONLINE"
    exit 0
else
    log "WiFi recovery completed: still OFFLINE"
    exit 1
fi
