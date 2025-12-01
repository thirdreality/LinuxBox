#!/bin/bash

set -e 

repositories_to_remove=(
    "ghcr.io/home-assistant/aarch64-hassio-supervisor"
    "ghcr.io/home-assistant/odroid-n2-homeassistant"
    "ghcr.io/home-assistant/aarch64-hassio-cli"
    "ghcr.io/home-assistant/aarch64-hassio-multicast"
    "ghcr.io/home-assistant/aarch64-hassio-dns"
    "ghcr.io/home-assistant/aarch64-hassio-audio"
    "ghcr.io/home-assistant/aarch64-hassio-observer"
    "homeassistant/aarch64-addon-otbr"
    "homeassistant/aarch64-addon-matter-server"
)

error_handler() {
    local lineno=$1
    echo "Error occurred at line $lineno"
}

trap 'error_handler $LINENO' ERR

# systemctl stop haos-agent > /dev/null 2>&1 || true
# systemctl stop hassio-apparmor > /dev/null 2>&1 || true
# systemctl stop hassio-supervisor > /dev/null 2>&1 || true

# systemctl disable haos-agent > /dev/null 2>&1 || true
# systemctl disable hassio-apparmor > /dev/null 2>&1 || true
# systemctl disable hassio-supervisor > /dev/null 2>&1 || true

# apt-get remove -y homeassistant-supervised os-agent
# apt-get remove -y homeassistant-supervised\* > /dev/null 2>&1 || true

# if [ -f "/usr/bin/docker" ]; then
#     # Stop and kill containers and images.
#     for repo in "${repositories_to_remove[@]}"; do
#         images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo" || true)
#         if [ ! -z "$images" ]; then
#             for image in $images; do
#                 containers=$(docker ps -a -q --filter ancestor="$image")
#                 if [ -n "$containers" ]; then
#                     echo "Stopping containers based on image: $image"
#                     docker stop $containers
#                     docker rm $containers
#                 fi
                    
#                 echo "Removing image: $image"
#                 docker rmi "$image"
#             done
#         fi
#     done

#     echo "Selected containers stopped and images removed successfully."

#     sleep 5
#     docker system prune -a -f > /dev/null 2>&1

#     apt-get remove -y docker-ce docker-ce-cli containerd.io
#     apt-get remove -y docker-compose-plugin
#     apt-get remove -y docker-compose
#     apt-get remove -y docker.io
#     apt-get remove -y docker
#     apt-get remove -y docker-doc
#     apt-get remove -y docker-registry
# fi

if [ -f "/etc/hassio.json" ]; then
    rm -rf /etc/hassio.json
fi
            
if [ -d "/usr/share/hassio" ]; then
    rm -rf /usr/share/hassio
fi

if [ -d "/var/lib/homeassistant" ]; then
    rm -rf /var/lib/homeassistant
fi

/usr/bin/sync

sleep 0.5

echo "Update WIFI settings ..."

if [ -e "/usr/bin/nmcli" ]; then
    nmcli -t -f UUID con show | xargs -I {} nmcli con delete uuid {} 2>/dev/null || true
fi

/usr/bin/sync

# reset wifi connection information
if [ -e "/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" ]; then
    rm -rf /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf
fi

/usr/bin/sync

echo "Factory reset completed. Rebooting now..."

sleep 5

/usr/sbin/reboot
