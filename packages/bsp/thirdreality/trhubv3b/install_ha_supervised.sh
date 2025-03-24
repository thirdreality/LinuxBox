#!/bin/bash
# by liuguoping
# https://github.com/armbian/os/blob/main/userpatches/extensions/ha.sh

LC_ALL=en_US.UTF-8

DEBIAN_FRONTEND=noninteractive
APT_LISTCHANGES_FRONTEND=none
MACHINE=odroid-n2
TIMEOUT=1200

export LC_ALL DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND MACHINE

############################################################################################################
# Functions

SCRIPT="HubV3"

SUPPORTED_OS=( "bookworm" "jammy" "noble" )

function print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
function print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

function print_request() {  echo -n -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }


check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root!"
        exit 1
    fi
}


check_distro() {
    CURRENT_OS=$(lsb_release -d | sed -E 's/Description:\s+//')
    for distro in "${SUPPORTED_OS[@]}"; do
        if [[ "${CURRENT_OS}" =~ "${distro}" ]]; then
            print_info "Current distro: '$CURRENT_OS' - supported"
            return 0
        fi
    done
    print_error "This script is not supported on this OS: '$CURRENT_OS'"
    print_error "Supported OS: ${SUPPORTED_OS[*]}"
    exit 1
}


check_and_install_tools() {
    if [[ -f /usr/sbin/hassio-supervisor ]]; then
        print_info "hassio-supervisor has been installed, exiting ..."
        exit 1
    fi

    print_info "Using mirrors.tuna.tsinghua.edu.cn as source list ..."
	cat <<-EOF > /etc/apt/sources.list
	deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
	# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware

	deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
	# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware

	deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
	# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware

	deb https://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
	# deb-src https://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
	EOF

    apt-get update -y || { print_error "Failed to update package list"; }
    DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt install apparmor bluez  cifs-utils curl dbus \
        jq libglib2.0-bin lsb-release network-manager \
        nfs-common systemd-journal-remote systemd-resolved udisks2 \
        wget -y || { print_error "Failed to install necessary tools."; }
}

check_and_install_docker() {

    print_info "Check CGROUP config..."
    if grep -q "extraargs=systemd.unified_cgroup_hierarchy=false" /boot/armbianEnv.txt; then
        print_info "... Already modified: /boot/armbianEnv.txt"
    else
        print_info "... Modifying /boot/armbianEnv.txt"
        echo "extraargs=systemd.unified_cgroup_hierarchy=false" >> /boot/armbianEnv.txt
    fi

    if [ -x "$(command -v docker)" ]; then
        print_info "Docker already installed"
    else
        print_info "Installing docker..."
        curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh --mirror Aliyun

        if [[ -n "${SUDO_USER}" ]] ; then 
            usermod -aG docker "$SUDO_USER"
        fi
        rm -f get-docker.sh

        update_docker_config

        print_info "Installing docker done"
    fi
}

update_docker_config() {
    mkdir -p /etc/docker/

    # 定义要写入的JSON内容
    cat <<-EOF > /etc/docker/daemon.json
    {
    "log-driver": "journald",
    "storage-driver": "overlay2",
    "ip6tables": true,
    "experimental": true,
    "log-opts": {
        "tag": "{{.Name}}"
    },
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.xuanyuan.me"
    ]
    }
EOF

    # Restart Docker to apply the changes
    echo "Restarting Docker daemon..."
    sudo systemctl restart docker

    # Check the status of Docker service
    if systemctl is-active --quiet docker; then
        echo "Docker daemon restarted successfully."
    else
        echo "Failed to restart Docker daemon."
    fi
}

check_and_install_os_agent(){
    # os-agent   deb: amd64 https://github.com/home-assistant/os-agent/releases/download/1.6.0/os-agent_1.6.0_linux_x86_64.deb
	# os-agent   deb: arm64 https://github.com/home-assistant/os-agent/releases/download/1.6.0/os-agent_1.6.0_linux_aarch64.deb
	# os-agent   deb: armhf https://github.com/home-assistant/os-agent/releases/download/1.6.0/os-agent_1.6.0_linux_armv7.deb

    # https://github.com/home-assistant/os-agent/releases/download/1.7.2/os-agent_1.7.2_linux_aarch64.deb

    HA_OS_AGENT_ARCH="aarch64"
	HA_OS_AGENT_VERSION="1.7.2"
	HA_OS_AGENT_FILENAME="os-agent_${HA_OS_AGENT_VERSION}_linux_${HA_OS_AGENT_ARCH}.deb"
	HA_OS_AGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${HA_OS_AGENT_VERSION}/${HA_OS_AGENT_FILENAME}"

    if [ -f "/tmp/${HA_OS_AGENT_FILENAME}" ]; then
        #network error
        rm -rf "/tmp/${HA_OS_AGENT_FILENAME}"
    fi

    print_info "download os agent ..."
    wget --progress=dot:giga -P /tmp/ ${HA_OS_AGENT_URL}

    if [ -f "/tmp/${HA_OS_AGENT_FILENAME}" ]; then
        print_info "install os agent ..."
        dpkg -i "/tmp/${HA_OS_AGENT_FILENAME}"

        print_info "remove os agent deb..."
        rm -rf "/tmp/${HA_OS_AGENT_FILENAME}"
    fi
}

check_and_install_supervised()
{
    # https://github.com/home-assistant/supervised-installer/releases/download/2.0.0/homeassistant-supervised.deb
    # https://github.com/home-assistant/supervised-installer/releases/download/3.0.0/homeassistant-supervised.deb

    HA_SUPERVISED_VERSION="3.0.0"
	HA_SUPERVISED_FILENAME="homeassistant-supervised.deb"
	HA_SUPERVISED_URL="https://github.com/home-assistant/supervised-installer/releases/download/${HA_SUPERVISED_VERSION}/homeassistant-supervised.deb"

    # The homeassistant-supervised.deb will overide the config file, just recover it!
    CONFIG_FILE="/etc/NetworkManager/NetworkManager.conf"
    PATTERN_LINE="unmanaged-devices=*"
    REPLACEMENT_LINE="unmanaged-devices=interface-name:*,except:interface-name:wlan0"

    if [ -f "/tmp/${HA_SUPERVISED_FILENAME}" ]; then
        #network error
        rm -rf "/tmp/${HA_SUPERVISED_FILENAME}"
    fi

    print_info "download supervised ..."

    wget --progress=dot:giga -P /tmp/ ${HA_SUPERVISED_URL}

    if [ -f "/tmp/${HA_SUPERVISED_FILENAME}" ]; then
        print_info "install supervised ..."
        #apt install "/tmp/${HA_SUPERVISED_FILENAME}"
        MACHINE=${MACHINE} dpkg -i "/tmp/${HA_SUPERVISED_FILENAME}"

        print_info "remove supervised deb..."
        rm -rf "/tmp/${HA_SUPERVISED_FILENAME}"

        update_docker_config

        sed -i.bak "/$PATTERN_LINE/c $REPLACEMENT_LINE" "$CONFIG_FILE"
    fi

    if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
        chmod 644 "/etc/systemd/system/hassio-supervisor.service"
    fi

    if [ -e "/etc/systemd/system/hassio-apparmor.service" ]; then
        chmod 644 "/etc/systemd/system/hassio-apparmor.service"
    fi        
}

check_install_suervised_process()
{
    print_info "Restore deb.debian.org as source list ..."
	cat <<-EOF > /etc/apt/sources.list
    deb http://deb.debian.org/debian bookworm main contrib non-free
    #deb-src http://deb.debian.org/debian bookworm main contrib non-free

    deb http://deb.debian.org/debian bookworm-updates main contrib non-free
    #deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free

    deb http://deb.debian.org/debian bookworm-backports main contrib non-free
    #deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free

    deb http://security.debian.org/ bookworm-security main contrib non-free
    #deb-src http://security.debian.org/ bookworm-security main contrib non-free
	EOF


    i=0

    while ! docker ps | grep -q hassio_supervisor;
    do
        sleep 5
        i=$((i+5))
        if (( i % 30 == 0 )); then
            echo "Waiting for Home Assistant supervisor is up $i secs....." >&2
        fi
        if [ -n "${TIMEOUT}" ]; then
            if [ $i -gt "${TIMEOUT}" ]; then
                print_error "Timeout waiting for supervisor. Please check internet connection and try again"
                exit 5
            fi
        fi
    done

    print_info "Installing Home Assistant Supervised done. Install Home Assistant core"

    i=0

    while ! curl http://127.0.0.1:8123 >/dev/null 2>&1
    do
        sleep 5
        i=$((i+5))
        if (( i % 30 == 0 )); then
            echo "Waiting for Home Assistant core connection $i secs....." >&2
        fi
        if [ -n "${TIMEOUT}" ]; then
            if [ $i -gt "${TIMEOUT}" ]; then
                print_error "Timeout waiting for landingpage. Please check internet connection and try again"
                exit 6
            fi
        fi
    done

    print_info "Home Assistant landingpage is up. Install Home Assistant core"

    i=0

    # Loop to wait for 'homeassistant' without 'landing'
    while true; do
        if docker ps | grep -q " homeassistant" && ! docker ps | grep -q "landing"; then
            break
        else
            sleep 5
            i=$((i+5))
            # Every 15 seconds, display a waiting message
            if (( i % 30 == 0 )); then
                echo "Waiting for Home Assistant core up $i secs....." >&2    #DEBUG
            fi
            if [ -n "${TIMEOUT}" ]; then
                if [ $i -gt "${TIMEOUT}" ]; then
                    print_error "Timeout waiting for Home Assistant Core. Please check internet connection and try again"
                    exit 6
                fi
            fi
        fi
    done

    print_info "Home Assistant up and running."
    print_request "Try access http://"
    read -r _{,} _ _ _ _ ip _ < <(ip r g 1.0.0.0) ; echo "$ip:8123"
}

# All the images.
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

check_and_uninstall_suervised_process()
{
    if [[ -f /usr/sbin/hassio-supervisor ]]; then    
        systemctl stop haos-agent > /dev/null 2>&1
        systemctl stop hassio-apparmor > /dev/null 2>&1
        systemctl stop hassio-supervisor > /dev/null 2>&1
        apt-get purge -y homeassistant-supervised\* > /dev/null 2>&1 || true
        dpkg -r homeassistant-supervised > /dev/null 2>&1 || true
        dpkg -r homeassistant-supervised-jethome > /dev/null 2>&1 || true
        dpkg -r os-agent > /dev/null 2>&1

        # docker ps --format json|jq -r .Names | grep -E 'addon_|hassio_' | xargs -n 1 docker stop || true
        # sleep 1
        # if [ -n "$(docker ps --format json|jq -r .Names | grep -E 'addon_|hassio_')" ]; then
        #     print_info "Wait for stop containers"
        #     docker ps --format json|jq -r .Names | grep -E 'addon_|hassio_' | xargs -n 1 docker stop  || true
        #     sleep 5
        # fi

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
            done
        done

        print_info "Selected containers stopped and images removed successfully."

        sleep 5
        docker system prune -a -f > /dev/null 2>&1
        docker system prune -a -f > /dev/null 2>&1

        print_info "Remove old Home Assistant done"
    else
        print_error "Home Assistant Supervised is not founed."
    fi
}
############################################################################################################

current_time=$(date +"%H:%M:%S")
echo "Current Time: $current_time"

case "$1" in
    install) check_root; check_distro; check_and_install_tools; check_and_install_docker; check_and_install_os_agent; check_and_install_supervised;check_install_suervised_process ;;
    uninstall) check_root; check_distro;check_and_uninstall_suervised_process;;
    *) echo "Usage: $0 {install|uninstall}"; exit 1 ;;
esac

current_time=$(date +"%H:%M:%S")
echo "Current Time: $current_time"

