#!/bin/bash

set -e 

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

function print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
function print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }
function print_request() {  echo -n -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }

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
    echo "Error occurred at line $lineno"
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

function disable_apt_auto_services() {
    print_info "Disabling apt automatic update services"
    for unit in "${APT_AUTO_SERVICES[@]}" "${APT_AUTO_TIMERS[@]}"; do
        systemctl stop "$unit" >/dev/null 2>&1 || true
        systemctl disable "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    done
}

function restore_apt_auto_services() {
    print_info "Restoring apt automatic update services"
    for unit in "${APT_AUTO_SERVICES[@]}" "${APT_AUTO_TIMERS[@]}"; do
        systemctl unmask "$unit" >/dev/null 2>&1 || true
        systemctl enable "$unit" >/dev/null 2>&1 || true
        systemctl start "$unit" >/dev/null 2>&1 || true
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

    print_info "Ensuring dpkg is idle"
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
        print_info "Repairing dpkg state"
        dpkg --configure -a >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get -f install -y >/dev/null 2>&1 || true
    fi

    DPKG_READY=1
}

function _remove_otbr_agent()
{
    /usr/bin/systemctl stop otbr-web || true
    /usr/bin/systemctl stop otbr-agent || true

    /usr/bin/systemctl disable otbr-web || true
    /usr/bin/systemctl disable otbr-agent || true

    killall otbr-web otbr-agent || true

    /usr/bin/systemctl stop otbr-firewall || true
    /usr/bin/systemctl disable otbr-firewall || true

    if [ -f "/usr/sbin/update-rc.d" ]; then
        /usr/sbin/update-rc.d otbr-firewall remove || true
    fi

    test ! -f ${FIREWALL_SERVICE} || rm ${FIREWALL_SERVICE} || true

    test ! -f ${SYSCTL_ACCEPT_RA_FILE} || rm -v ${SYSCTL_ACCEPT_RA_FILE} || true
    test ! -f ${SYSCTL_IP_FORWARD_FILE} || rm -v ${SYSCTL_IP_FORWARD_FILE} || true

    sed -i.bak '/88\s\+openthread/d' /etc/iproute2/rt_tables

    test ! -f /lib/libnss_mdns.so.2 || rm -rf /lib/libnss_mdns.so.2 || true
    test ! -f /usr/lib/libdns_sd.so || rm -rf /usr/lib/libdns_sd.so || true

    test ! -f /etc/rc2.d/S52mdns || rm -rf /etc/rc2.d/S52mdns || true
    test ! -f /etc/rc3.d/S52mdns || rm -rf /etc/rc3.d/S52mdns || true
    test ! -f /etc/rc4.d/S52mdns || rm -rf /etc/rc4.d/S52mdns || true
    test ! -f /etc/rc5.d/S52mdns || rm -rf /etc/rc5.d/S52mdns || true
    test ! -f /etc/rc0.d/K16mdns || rm -rf /etc/rc0.d/K16mdns || true
    test ! -f /etc/rc6.d/K16mdns || rm -rf /etc/rc6.d/K16mdns || true

    sysctl -p /etc/sysctl.conf || true
}

remove_homeassistant_core()
{
    /usr/bin/systemctl stop home-assistant > /dev/null || true
    /usr/bin/systemctl stop home-assistant > /dev/null || true

    /usr/bin/systemctl disable matter-server > /dev/null || true
    /usr/bin/systemctl disable matter-server > /dev/null || true

    dpkg --configure -a > /dev/null || true

    apt-get purge -y thirdreality-hacore > /dev/null || true
    apt-get purge -y thirdreality-hacore-config > /dev/null  || true
    apt-get purge -y thirdreality-python3.13 > /dev/null || true
    apt-get purge -y thirdreality-python3 > /dev/null || true
    apt-get purge -y thirdreality-otbr-agent  > /dev/null || true    
    #apt-get purge -y thirdreality-zigbee-mqtt  > /dev/null || true

    apt-get autoremove -y >/dev/null || true
    systemctl daemon-reload

    _remove_otbr_agent
}

remove_zigbee2mqtt()
{
    /usr/bin/systemctl stop zigbee2mqtt.service > /dev/null || true
    /usr/bin/systemctl stop mosquitto.service > /dev/null || true

    /usr/bin/systemctl disable zigbee2mqtt.service > /dev/null || true
    /usr/bin/systemctl disable mosquitto.service > /dev/null|| true

    dpkg --configure -a > /dev/null || true

    local z2m_backup_dir="/opt/z2m_tmp_backup"
    if [ -d /opt/zigbee2mqtt/data ]; then
        print_info "Backing up /opt/zigbee2mqtt/data before package removal"
        rm -rf /opt/zigbee2mqtt/data/log > /dev/null 2>&1 || true
        rm -rf "${z2m_backup_dir}" > /dev/null 2>&1 || true
        mkdir -p "${z2m_backup_dir}"
        cp -a /opt/zigbee2mqtt/data/. "${z2m_backup_dir}"/ >/dev/null 2>&1 || true

        /usr/bin/sync
        /usr/bin/sync
    fi

    apt-get purge -y thirdreality-zigbee-mqtt > /dev/null || true
    apt-get purge -y nodejs libsystemd-dev  > /dev/null || true
    apt-get purge -y mosquitto mosquitto-clients > /dev/null || true
    apt-get purge -y libmosquitto1 libdlt2 > /dev/null || true

    apt-get autoremove -y >/dev/null || true
    systemctl daemon-reload
    userdel mosquitto > /dev/null 2>&1 || true

    if [ -d "${z2m_backup_dir}" ]; then
        print_info "Restoring Zigbee2MQTT data from temporary backup"
        rm -rf /opt/zigbee2mqtt > /dev/null 2>&1 || true
        mkdir -p /opt/zigbee2mqtt/data
        cp -a "${z2m_backup_dir}"/. /opt/zigbee2mqtt/data/ >/dev/null 2>&1 || true
        rm -rf "${z2m_backup_dir}" > /dev/null 2>&1 || true

        /usr/bin/sync
        /usr/bin/sync
    else
        rm -rf /opt/zigbee2mqtt > /dev/null 2>&1 || true
    fi

    rm -rf /etc/mosquitto > /dev/null 2>&1 || true
}

remove_openhab()
{
    /usr/bin/systemctl stop openhab.service > /dev/null || true
    /usr/bin/systemctl disable openhab.service > /dev/null || true

    apt-get purge -y openhab* > /dev/null || true
    apt-get purge -y openjdk-17-jre* > /dev/null || true

    rm -rf /usr/share/keyrings/openhab.gpg > /dev/null || true
    rm -rf /etc/apt/sources.list.d/openhab.list > /dev/null || true
    rm -rf /var/log/openhab > /dev/null || true

    apt-get autoremove -y >/dev/null || true
    systemctl daemon-reload
}

remove_homeassistant_supervised()
{
    if [ -f /usr/sbin/hassio-supervisor ]; then    
        systemctl stop haos-agent > /dev/null 2>&1
        systemctl stop hassio-apparmor > /dev/null 2>&1
        systemctl stop hassio-supervisor > /dev/null 2>&1
        apt-get purge -y homeassistant-supervised\* > /dev/null 2>&1 || true
        dpkg -r homeassistant-supervised > /dev/null 2>&1 || true
        dpkg -r os-agent > /dev/null 2>&1 || true

        dpkg -r thirdreality-hassio-config > /dev/null 2>&1 || true

        # Stop and kill containers and images.
        for repo in "${repositories_to_remove[@]}"; do
            images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo" || true)
            if [ ! -z "$images" ]; then
                for image in $images; do
                    containers=$(docker ps -a -q --filter ancestor="$image")
                    if [ -n "$containers" ]; then
                        print_info "Stopping containers based on image: $image"
                        docker stop $containers
                        docker rm $containers
                    fi
                        
                    print_info "Removing image: $image"
                    docker rmi "$image"
                done
            fi
        done

        print_info "Selected containers stopped and images removed successfully."

        sleep 5
        docker system prune -a -f > /dev/null 2>&1

        if [ -f "/etc/hassio.json" ]; then
            rm -rf /etc/hassio.json
        fi
            
        if [ -e "/var/lib/homeassistant" ]; then
            rm -rf /var/lib/homeassistant
        fi

        if [ -d "/usr/share/hassio" ]; then
            rm -rf /usr/share/hassio
        fi

        print_info "Remove old Home Assistant done"
    else
        print_error "Home Assistant Supervised is not found."
    fi
}

remove_zigpy_tools()
{
    if [ -e "/usr/local/thirdreality/zigpy_tools/bin/activate" ]; then
        dpkg -r thirdreality-zigpy-tools > /dev/null 2>&1 || true

        print_info "Remove old thirdreality zigpy-tools done"
    fi
}

echo "System is start to perform factory reset actions. " | wall

if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led factory_reset
fi

# Stop and disable automatic apt services to avoid lock contention
disable_apt_auto_services

wait_for_dpkg_lock

remove_homeassistant_core

# remove zigbee2mqtt
remove_zigbee2mqtt

# remove openhab
remove_openhab

# remove homeassistant supervised
remove_homeassistant_supervised

remove_zigpy_tools

# Query and remove all packages matching "thirdreality", leaving room for future upgrades
dpkg --list | grep thirdreality | awk '{print $2}' | xargs apt-get remove -y

rm -rf /usr/share/hassio || true
rm -rf /var/lib/homeassistant  || true
rm -rf /var/lib/thread  || true
rm -rf /lib/thirdreality/conf/*  || true
rm -rf /lib/thirdreality/backup/*  || true
rm -rf /lib/thirdreality/archives/* || true

rm -rf /usr/lib/firmware/bl706/bflb_iot || true

/usr/bin/sync

sleep 0.5

if [ -e "/usr/bin/nmcli" ]; then
    nmcli -t -f UUID con show | xargs -I {} nmcli con delete uuid {} 2>/dev/null || true
fi

# reset wifi connection information
if [ -e "/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" ]; then
    rm -rf /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf
fi

#/usr/sbin/dhclient -r wlan0
#systemctl enable setupwifi.service

/usr/bin/systemctl daemon-reload || true

mkdir -p /var/lib/homeassistant/homeassistant
mkdir -p /var/lib/homeassistant/matter_server

if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led white
fi

echo "Factory reset completed. Rebooting now..."  | wall

restore_apt_auto_services

/usr/bin/sync
sleep 2
/usr/bin/sync

/usr/sbin/reboot
