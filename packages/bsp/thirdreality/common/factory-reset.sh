#!/bin/bash

set -e 

SCRIPT="HubV3"

FIREWALL_SERVICE="/etc/init.d/otbr-firewall"
SYSCTL_ACCEPT_RA_FILE="/etc/sysctl.d/60-otbr-accept-ra.conf"
SYSCTL_IP_FORWARD_FILE="/etc/sysctl.d/60-otbr-ip-forward.conf"

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
    /usr/bin/systemctl stop home-assistant || true
    /usr/bin/systemctl stop home-assistant || true

    /usr/bin/systemctl disable matter-server || true
    /usr/bin/systemctl disable matter-server || true

    dpkg --configure -a || true

    apt purge -y thirdreality-hacore || true
    apt purge -y thirdreality-hacore-config  || true
    apt purge -y thirdreality-python3.13 || true
    apt purge -y thirdreality-python3 || true
    apt purge -y thirdreality-otbr-agent  || true    
    apt autoremove -y

    _remove_otbr_agent
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

remove_homeassistant_core

remove_homeassistant_supervised

remove_zigpy_tools

rm -rf /usr/share/hassio 
rm -rf /var/lib/homeassistant
rm -rf /var/lib/thread

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


echo "Factory reset completed. Rebooting now..."  | wall


/usr/bin/sync
sleep 2
/usr/bin/sync

/usr/sbin/reboot
