#!/bin/bash

# Do not use set -e to avoid aborting the whole script when a single command fails
# set -e

SCRIPT="HubV3"

FIREWALL_SERVICE="/etc/init.d/otbr-firewall"
SYSCTL_ACCEPT_RA_FILE="/etc/sysctl.d/60-otbr-accept-ra.conf"
SYSCTL_IP_FORWARD_FILE="/etc/sysctl.d/60-otbr-ip-forward.conf"
RESTORE_APT_SERVICES="${RESTORE_APT_SERVICES:-0}"
DPKG_LOCK_MAX_WAIT="${DPKG_LOCK_MAX_WAIT:-30}"

DPKG_LOCK_FILES=(
    "/var/lib/dpkg/lock-frontend"
    "/var/lib/dpkg/lock"
    "/var/cache/apt/archives/lock"
    "/var/lib/apt/lists/lock"
)
DPKG_READY=0

function _ts() { date '+%Y-%m-%d %H:%M:%S'; }
function print_info()  { echo -e "\e[1;34m[$( _ts )] [${SCRIPT}] INFO:\e[0m $1"; }
function print_error() { echo -e "\e[1;31m[$( _ts )] [${SCRIPT}] ERROR:\e[0m $1"; }
function print_request() { echo -n -e "\e[1;34m[$( _ts )] [${SCRIPT}] INFO:\e[0m $1"; }

# Helper: check whether a systemd service unit exists on this system.
# Returns 0 if the unit is known, non-zero otherwise.
service_exists() {
    local unit="$1"
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || systemctl status "$unit" >/dev/null 2>&1
}

repositories_to_remove=(
    "ghcr.io/home-assistant/odroid-n2-homeassistant"
    "ghcr.io/home-assistant/aarch64-hassio-supervisor"
    "homeassistant/aarch64-addon-matter-server"
    "homeassistant/aarch64-addon-otbr"
    "ghcr.io/home-assistant/aarch64-hassio-dns"
    "ghcr.io/home-assistant/aarch64-hassio-cli"
    "ghcr.io/home-assistant/aarch64-hassio-multicast"
    "ghcr.io/home-assistant/aarch64-hassio-audio"
    "ghcr.io/home-assistant/aarch64-hassio-observer"
)

error_handler() {
    local lineno=$1
    print_error "Error occurred at line $lineno (continuing anyway)"
}

trap 'error_handler $LINENO' ERR

APT_AUTO_SERVICES=(
    "apt-daily.service"
    "apt-daily-upgrade.service"
    "unattended-upgrades.service"
)

APT_AUTO_TIMERS=(
    "apt-daily.timer"
    "apt-daily-upgrade.timer"
)

get_trhub_model() {
  if [ -f /etc/armbian-release ]; then
    local board=$(grep "^BOARD=" /etc/armbian-release | cut -d'=' -f2)
    if [ -n "$board" ]; then
      echo "$board"
    else
      echo "trhubv3"
    fi
  else
    echo "trhubv3"
  fi
}

function disable_apt_auto_services() {
    print_info "Disabling apt automatic update services (start)"
    for unit in "${APT_AUTO_SERVICES[@]}" "${APT_AUTO_TIMERS[@]}"; do
        systemctl stop "$unit" >/dev/null 2>&1 || true
        systemctl disable "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    done
    print_info "Disabling apt automatic update services (done)"
}

function restore_apt_auto_services() {
    print_info "Restoring apt automatic update services"
    for unit in "${APT_AUTO_SERVICES[@]}" "${APT_AUTO_TIMERS[@]}"; do
        systemctl unmask "$unit" >/dev/null 2>&1 || true
        systemctl enable "$unit" >/dev/null 2>&1 || true
        # 不启动服务，因为马上就要 reboot 了
        # systemctl start "$unit" >/dev/null 2>&1 || true
    done
}

function log_dpkg_lock_holders() {
    local file holders
    for file in "${DPKG_LOCK_FILES[@]}"; do
        if [ -f "$file" ]; then
            holders=$(fuser "$file" 2>/dev/null || true)
            if [ -n "$holders" ]; then
                print_info "Lock file $file held by PIDs: $holders"
                for pid in $holders; do
                    if [ -d "/proc/$pid" ]; then
                        local proc_info
                        proc_info=$(ps -p "$pid" -o pid=,ppid=,cmd= 2>/dev/null || true)
                        if [ -n "$proc_info" ]; then
                            print_info "    $proc_info"
                        fi
                    fi
                done
            else
                print_info "Lock file $file exists but fuser reported no holders; possible stale lock"
            fi
        fi
    done

    local running
    running=$(pgrep -a -f '(apt[-. ]|apt$|dpkg|unattended-upgrade)' 2>/dev/null || true)
    if [ -n "$running" ]; then
        print_info "Running package-management processes:\n$running"
    fi
}

function terminate_package_processes() {
    local killed_any=0
    local pids cmdline exe_path

    pids=$(pgrep -f 'apt|dpkg|unattended-upgrade' 2>/dev/null || true)
    for pid in $pids; do
        if [ -z "$pid" ] || ! kill -0 "$pid" >/dev/null 2>&1; then
            continue
        fi

        exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)

        if [[ "$exe_path" =~ /(apt|dpkg|unattended-upgrade)/ ]] ||
           [[ "$cmdline" == *"/usr/share/unattended-upgrades/"* ]] ||
           [[ "$cmdline" == *"/usr/lib/apt/"* ]] ||
           [[ "$cmdline" == *"systemd-apt-"* ]]; then
            print_info "Killing PID $pid ($cmdline)"
            kill -9 "$pid" >/dev/null 2>&1 || true
            killed_any=1
        fi
    done

    if [ "$killed_any" -eq 0 ]; then
        print_info "No package-management processes required termination"
    fi
}

function wait_for_dpkg_lock() {
    if [ "$DPKG_READY" -eq 1 ]; then
        return 0
    fi

    print_info "Ensuring dpkg is idle (start)"
    log_dpkg_lock_holders
    terminate_package_processes

    local locks_found=0
    for file in "${DPKG_LOCK_FILES[@]}"; do
        if [ -f "$file" ]; then
            print_info "Removing stale lock $file"
            rm -f "$file" >/dev/null 2>&1 || true
            locks_found=1
        fi
    done

    if [ "$locks_found" -eq 1 ]; then
        print_info "Repairing dpkg state (dpkg --configure -a only; skip apt-get -f install when no network)"
        dpkg --configure -a >/dev/null 2>&1 || true
    fi

    print_info "Ensuring dpkg is idle (done)"
    DPKG_READY=1
}

function _remove_otbr_agent()
{
    # Fast path: if otbr-agent is not installed at all, skip the rest.
    if ! service_exists "otbr-agent.service" && ! command -v otbr-agent >/dev/null 2>&1; then
        print_info "otbr-agent not present; skipping _remove_otbr_agent"
        return 0
    fi

    /usr/bin/systemctl stop otbr-web > /dev/null 2>&1 || true
    /usr/bin/systemctl stop otbr-agent > /dev/null 2>&1 || true

    /usr/bin/systemctl disable otbr-web > /dev/null 2>&1 || true
    /usr/bin/systemctl disable otbr-agent > /dev/null 2>&1 || true

    killall otbr-web otbr-agent > /dev/null 2>&1 || true

    /usr/bin/systemctl stop otbr-firewall > /dev/null 2>&1 || true
    /usr/bin/systemctl disable otbr-firewall > /dev/null 2>&1 || true

    if [ -f "/usr/sbin/update-rc.d" ]; then
        /usr/sbin/update-rc.d otbr-firewall remove > /dev/null 2>&1 || true
    fi

    test ! -f ${FIREWALL_SERVICE} || rm ${FIREWALL_SERVICE} > /dev/null 2>&1 || true

    test ! -f ${SYSCTL_ACCEPT_RA_FILE} || rm -v ${SYSCTL_ACCEPT_RA_FILE} > /dev/null 2>&1 || true
    test ! -f ${SYSCTL_IP_FORWARD_FILE} || rm -v ${SYSCTL_IP_FORWARD_FILE} > /dev/null 2>&1 || true

    sed -i.bak '/88\s\+openthread/d' /etc/iproute2/rt_tables || true

    test ! -f /lib/libnss_mdns.so.2 || rm -rf /lib/libnss_mdns.so.2 > /dev/null 2>&1 || true
    test ! -f /usr/lib/libdns_sd.so || rm -rf /usr/lib/libdns_sd.so > /dev/null 2>&1 || true

    test ! -f /etc/rc2.d/S52mdns || rm -rf /etc/rc2.d/S52mdns || true
    test ! -f /etc/rc3.d/S52mdns || rm -rf /etc/rc3.d/S52mdns > /dev/null 2>&1 || true
    test ! -f /etc/rc4.d/S52mdns || rm -rf /etc/rc4.d/S52mdns > /dev/null 2>&1 || true
    test ! -f /etc/rc5.d/S52mdns || rm -rf /etc/rc5.d/S52mdns > /dev/null 2>&1 || true
    test ! -f /etc/rc0.d/K16mdns || rm -rf /etc/rc0.d/K16mdns > /dev/null 2>&1 || true
    test ! -f /etc/rc6.d/K16mdns || rm -rf /etc/rc6.d/K16mdns > /dev/null 2>&1 || true

    sysctl -p /etc/sysctl.conf > /dev/null 2>&1 || true
}

remove_homeassistant_core()
{
    if ! service_exists "home-assistant.service"; then
        print_info "home-assistant.service not found; skipping remove_homeassistant_core"
        return 0
    fi

    print_info "remove_homeassistant_core (start)"
    /usr/bin/systemctl stop home-assistant > /dev/null 2>&1 || true
    /usr/bin/systemctl stop matter-server > /dev/null 2>&1 || true

    /usr/bin/systemctl disable home-assistant > /dev/null 2>&1 || true
    /usr/bin/systemctl disable matter-server > /dev/null 2>&1|| true

    dpkg --configure -a > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-hacore > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-hacore-config > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-python3.13 > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-python3 > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-otbr-agent  > /dev/null 2>&1 || true    

    apt-get autoremove -y >/dev/null 2>&1 || true
    systemctl daemon-reload || true

    _remove_otbr_agent
    print_info "remove_homeassistant_core (done)"
}

remove_zigbee2mqtt()
{
    if ! service_exists "zigbee2mqtt.service"; then
        print_info "zigbee2mqtt.service not found; skipping remove_zigbee2mqtt"
        return 0
    fi

    print_info "remove_zigbee2mqtt (start)"
    /usr/bin/systemctl stop zigbee2mqtt.service > /dev/null 2>&1|| true
    /usr/bin/systemctl disable zigbee2mqtt.service > /dev/null 2>&1 || true

    # Do NOT stop/disable mosquitto: it is a pre-installed base component and is
    # enabled by default. The device reboots at the end of factory reset, so
    # leaving it enabled lets it start automatically on the next boot.

    dpkg --configure -a > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-zigbee-mqtt > /dev/null 2>&1 || true

    # NOTE: nodejs and mosquitto are now pre-installed base components of the
    # factory image (nodejs is also required by the openthread web UI, and
    # mosquitto is the shipped MQTT broker), so factory reset must NOT remove
    # them. Only the zigbee2mqtt application and its data are removed here.

    apt-get autoremove -y >/dev/null 2>&1 || true
    systemctl daemon-reload || true

    rm -rf /opt/zigbee2mqtt > /dev/null 2>&1 || true
    print_info "remove_zigbee2mqtt (done)"
}

remove_openhab()
{
    if ! service_exists "openhab.service"; then
        print_info "openhab.service not found; skipping remove_openhab"
        return 0
    fi

    print_info "remove_openhab (start)"
    /usr/bin/systemctl stop openhab.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable openhab.service > /dev/null 2>&1 || true

    apt-get purge -y openhab* > /dev/null 2>&1 || true
    apt-get purge -y openjdk-17-jre* > /dev/null 2>&1 || true

    rm -rf /usr/share/keyrings/openhab.gpg > /dev/null 2>&1 || true
    rm -rf /etc/apt/sources.list.d/openhab.list > /dev/null 2>&1 || true
    rm -rf /var/log/openhab > /dev/null 2>&1 || true

    apt-get autoremove -y >/dev/null 2>&1 || true
    systemctl daemon-reload || true
    print_info "remove_openhab (done)"
}

remove_music_assistant()
{
    if ! service_exists "music-assistant.service"; then
        print_info "music-assistant.service not found; skipping remove_music_assistant"
        return 0
    fi

    print_info "remove_music_assistant (start)"
    /usr/bin/systemctl stop music-assistant.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable music-assistant.service > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-music-assistant > /dev/null 2>&1 || true
    print_info "remove_music_assistant (done)"
}

remove_linuxbox_bridge()
{
    if ! service_exists "linuxbox-hubv3-bridge.service"; then
        print_info "linuxbox-hubv3-bridge.service not found; skipping remove_linuxbox_bridge"
        return 0
    fi

    print_info "remove_linuxbox_bridge (start)"
    /usr/bin/systemctl stop linuxbox-hubv3-bridge.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable linuxbox-hubv3-bridge.service > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-bridge > /dev/null 2>&1 || true
    print_info "remove_linuxbox_bridge (done)"
}

restore_serial_tty()
{
    print_info "Restoring serial tty service (start)"
    systemctl unmask serial-getty@ttyAML0.service >/dev/null 2>&1 || true
    systemctl enable serial-getty@ttyAML0.service >/dev/null 2>&1 || true
    systemctl start serial-getty@ttyAML0.service >/dev/null 2>&1 || true
    print_info "Restoring serial tty service (done)"
}

update_zigbee2mqtt_config()
{
    local config_file="/opt/zigbee2mqtt/data/configuration.yaml"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    print_info "Checking Zigbee2MQTT configuration file"
    
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="/opt/zigbee2mqtt/data/configuration_${timestamp}.yaml"
    
    print_info "Creating backup: $backup_file"
    cp "$config_file" "$backup_file" || {
        print_error "Failed to create backup file"
        return 1
    }
    
    print_info "Updating Zigbee2MQTT frontend settings"
    
    /usr/bin/python3 << 'PYTHON_EOF'
import sys

config_file = "/opt/zigbee2mqtt/data/configuration.yaml"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    modified = False
    result_lines = []
    in_frontend_section = False
    
    for line in lines:
        stripped = line.lstrip()
        
        if line.strip() == 'frontend:':
            in_frontend_section = True
            result_lines.append(line)
            continue
        
        if in_frontend_section and stripped and not line.startswith(' ') and not line.startswith('\t'):
            in_frontend_section = False
        
        if in_frontend_section and stripped.startswith('enabled:'):
            current_value = stripped.split(':', 1)[1].strip().lower()
            if current_value == 'false':
                result_lines.append("  enabled: true\n")
                modified = True
            else:
                result_lines.append(line)
        else:
            result_lines.append(line)
    
    if modified:
        with open(config_file, 'w', encoding='utf-8') as f:
            f.writelines(result_lines)
        print("Frontend enabled set to true", file=sys.stderr)
    else:
        print("Frontend already enabled, no changes needed", file=sys.stderr)
    
    sys.exit(0)

except Exception as e:
    print(f"Error updating configuration: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

    if [ $? -ne 0 ]; then
        print_error "Failed to update configuration"
        if [ -f "$backup_file" ]; then
            print_info "Restoring from backup due to update failure"
            cp "$backup_file" "$config_file" || true
        fi
        return 1
    fi
    
    print_info "Zigbee2MQTT configuration updated successfully"
}

# ========== 主流程开始 ==========

print_info "=== Factory reset script started ==="
echo "System is starting to perform factory reset actions." | wall

# 设置 LED 为 factory reset 状态
if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led clear || true
    /usr/local/bin/supervisor led factory_reset || true
fi

trhub_model=$(get_trhub_model)
print_info "TRHub model: $trhub_model"

# Stop and disable automatic apt services to avoid lock contention
disable_apt_auto_services

wait_for_dpkg_lock

remove_homeassistant_core

# remove zigbee2mqtt
if [ "$trhub_model" == "trhubv3" ] || [ "$trhub_model" == "trhubv3a" ]; then
    remove_zigbee2mqtt
    remove_linuxbox_bridge
else
    /usr/bin/systemctl stop linuxbox-hubv3-bridge.service > /dev/null 2>&1 || true
    /usr/bin/systemctl stop zigbee2mqtt.service > /dev/null 2>&1 || true
    update_zigbee2mqtt_config
fi

/usr/bin/sync

# remove openhab
remove_openhab

remove_music_assistant

print_info "Purging remaining thirdreality packages (start)"
if [ "$trhub_model" == "trhubv3" ] || [ "$trhub_model" == "trhubv3a" ]; then
    debs=$(dpkg --list | awk '/^ii/ && $2 ~ /^thirdreality-/{print $2}')
    if [ -n "$debs" ]; then
        print_info "Found thirdreality packages: $debs"
        echo "$debs" | xargs -r apt-get remove -y || true
    else
        print_info "No thirdreality packages found"
    fi
fi
print_info "Purging remaining thirdreality packages (done)"

print_info "Removing hassio/homeassistant/thread and thirdreality paths (start)"
rm -rf /usr/share/hassio > /dev/null 2>&1 || true
rm -rf /var/lib/homeassistant > /dev/null 2>&1 || true
rm -rf /var/lib/thread  > /dev/null 2>&1 || true
rm -rf /lib/thirdreality/conf/*  > /dev/null 2>&1 || true
rm -rf /lib/thirdreality/backup/*  > /dev/null 2>&1 || true
rm -rf /lib/thirdreality/archives/* > /dev/null 2>&1 || true
rm -rf /usr/lib/firmware/bl706/bflb_iot > /dev/null 2>&1 || true
print_info "Removing hassio/homeassistant/thread and thirdreality paths (done)"

/usr/bin/sync
sleep 0.5

print_info "Removing NetworkManager connections (start)"
if [ -e "/usr/bin/nmcli" ]; then
    nmcli -t -f UUID con show | xargs -I {} nmcli con delete uuid {} 2>/dev/null || true
fi
print_info "Removing NetworkManager connections (done)"

# reset wifi connection information
if [ -e "/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" ]; then
    rm -rf /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf || true
fi

/usr/bin/systemctl daemon-reload || true

mkdir -p /var/lib/homeassistant/homeassistant || true
mkdir -p /var/lib/homeassistant/matter_server || true

# Restore serial tty service
restore_serial_tty

# Restore apt-related services (do not actively start units)
restore_apt_auto_services

# Set LED to white (indicates reboot is about to happen)
if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led white || true
fi

print_info "=== Factory reset script finished, rebooting ==="
echo "Factory reset completed. Rebooting now..."  | wall

/usr/bin/sync
sleep 1
/usr/bin/sync

# Force reboot even if previous commands failed
print_info "Executing reboot command..."
/usr/sbin/reboot -f || /sbin/reboot -f || reboot -f

# If all commands above fail, try using systemctl as a fallback
sleep 1
systemctl reboot -f || true

# Last-resort fallback using SysRq trigger
sleep 1
echo b > /proc/sysrq-trigger 2>/dev/null || true

