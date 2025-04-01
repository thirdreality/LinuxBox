#!/bin/bash

set -e 

SCRIPT="HubV3"

function print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
function print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }
function print_request() {  echo -n -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }

if [[ -f "/srv/homeassistant/bin/hass" ]]; then
    print_info "Stop and remove home-assistant.service & matter-server.service"

    systemctl stop home-assistant.service > /dev/null 2>&1
    systemctl stop matter-server.service > /dev/null 2>&1

    dpkg -r thirdreality-hacore > /dev/null 2>&1 || true
    dpkg -r thirdreality-python3.13 > /dev/null 2>&1 || true
    dpkg -r thirdreality-hacore-config > /dev/null 2>&1 || true

    print_info "Selected containers stopped and images removed successfully."
fi


repositories_to_remove=(
    "ghcr.io/home-assistant/odroid-n2-homeassistant"
    "ghcr.io/home-assistant/aarch64-hassio-supervisor"
    "homeassistant/aarch64-addon-matter-server"
    "ghcr.io/home-assistant/aarch64-hassio-dns"
    "ghcr.io/home-assistant/aarch64-hassio-cli"
    "ghcr.io/home-assistant/aarch64-hassio-multicast"
    "ghcr.io/home-assistant/aarch64-hassio-audio"
    "ghcr.io/home-assistant/aarch64-hassio-observer"
)

if [[ -f /usr/sbin/hassio-supervisor ]]; then    
    systemctl stop haos-agent > /dev/null 2>&1
    systemctl stop hassio-apparmor > /dev/null 2>&1
    systemctl stop hassio-supervisor > /dev/null 2>&1
    apt-get purge -y homeassistant-supervised\* > /dev/null 2>&1 || true
    dpkg -r homeassistant-supervised > /dev/null 2>&1 || true
    dpkg -r os-agent > /dev/null 2>&1 || true

    dpkg -r thirdreality-hassio-config > /dev/null 2>&1 || true

    # Stop and kill containers and images.
    for repo in "${repositories_to_remove[@]}"; do
        images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo")
        for image in $images; do
            containers=$(docker ps -a -q --filter ancestor="$image")
            if [ -n "$containers" ]; then
                print_info "Stopping containers based on image: $image"
                docker stop $containers
                docker rm $containers
            fi
                
            print_info "Removing image: $image"
            docker rmi "$image"
            one
    done

    print_info "Selected containers stopped and images removed successfully."

    sleep 5
    docker system prune -a -f > /dev/null 2>&1

    if [ -e "" ]; then
        rm -rf /etc/hassio.jon
    fi
        
    if [ -e "/var/lib/homeassistant" ]; then
        rm -rf /var/lib/homeassistant
    fi

    print_info "Remove old Home Assistant done"
else
    print_error "Home Assistant Supervised is not founed."
fi

if [ -e "/usr/local/thirdreality/zigpy_tools/bin/activate" ]; then
    dpkg -r thirdreality-zigpy-tools > /dev/null 2>&1 || true
fi

#docker stop $(docker ps -q) 2>/dev/null
#docker system prune -a -f

rm -rf /usr/share/hassio rm -rf /var/lib/homeassistant

sync

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

echo "Factory reset completed. Rebooting now..."

sleep 5

/usr/sbin/reboot


