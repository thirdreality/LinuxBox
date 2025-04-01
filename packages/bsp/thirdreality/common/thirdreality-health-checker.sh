#!/bin/bash

INTERFACE="wlan0"  # 默认网络接口，可通过参数传入
CHECK_INTERVAL=3   # 检查间隔

repositories_to_remove=(
    "ghcr.io/home-assistant/aarch64-hassio-supervisor"
    "ghcr.io/home-assistant/odroid-n2-homeassistant"
    "homeassistant/aarch64-addon-matter-server"
    "ghcr.io/home-assistant/aarch64-hassio-dns"
    "ghcr.io/home-assistant/aarch64-hassio-cli"
    "ghcr.io/home-assistant/aarch64-hassio-multicast"
    "ghcr.io/home-assistant/aarch64-hassio-audio"
    "ghcr.io/home-assistant/aarch64-hassio-observer"
)    

check_network() {
    local msg
    msg=$(iw dev "$INTERFACE" link 2>&1)
    
    if echo "$msg" | grep -q "Not connected"; then
        echo "INFO: $INTERFACE not connected. Retrying in $CHECK_INTERVAL seconds..."
        return 1
    elif echo "$msg" | grep -q "No such device"; then
        log "WARNING: $INTERFACE device not found. Retrying in $CHECK_INTERVAL seconds..."
        echo 2
    else
        echo "INFO: $INTERFACE connected."
        return 0
    fi
}

stop_hassio_supervisored_mode()
{
    systemctl stop haos-agent > /dev/null 2>&1
    systemctl stop hassio-apparmor > /dev/null 2>&1
    systemctl stop hassio-supervisor > /dev/null 2>&1

    systemctl disable haos-agent > /dev/null 2>&1
    systemctl disable hassio-apparmor > /dev/null 2>&1
    systemctl disable hassio-supervisor > /dev/null 2>&1

    # Stop containers and images.
    for repo in "${repositories_to_remove[@]}"; do
        images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo")
        for image in $images; do
            containers=$(docker ps -a -q --filter ancestor="$image")
            if [ -n "$containers" ]; then
                echo "Stopping containers based on image: $image"
                docker stop $containers
            fi
        done
    done
}


# Function: Check if the output contains cpu_percent
check_cpu_percent() {
    echo "$1" | grep -q "cpu_percent"
}

check_observer() {
    # error state: only container 'hassio_observer' is running.
    running_containers_count=$(docker ps --format '{{.Names}}' | wc -l)
    if [ "$running_containers_count" -eq 1 ]; then
        running_container_name=$(docker ps --format '{{.Names}}')

        if [ "$running_container_name" == "hassio_observer" ]; then
            if [ -e "/run/supervisor/startup-marker" ]; then
                docker container stop hassio_observer 2>/dev/null
                rm -rf /run/supervisor/startup-marker 2>/dev/null

                systemctl restart hassio-supervisor.service 2>/dev/null
            fi
        fi
    fi

    # Step 2: Execute ha observer status and check for cpu_percent
    while true; do
        observer_status=$(/usr/bin/ha observer status 2>/dev/null)
        if check_cpu_percent "$observer_status"; then
            break
        else
            echo "Checking ha observer status, retrying in 2 seconds..."
            sleep 2
        fi
    done
}

check_core()
{
    while true; do
        # Step 3: Execute ha core status and check for cpu_percent
        core_status=$(/usr/bin/ha core status 2>/dev/null)
        if ! check_cpu_percent "$core_status"; then
            echo "Checking ha core status, attempting to start core..."
            /usr/bin/ha core start
            sleep 2  # Allow time for core to start
        fi

        # Recheck ha core status
        new_core_status=$(/usr/bin/ha core status 2>/dev/null)
        if check_cpu_percent "$new_core_status"; then
            echo "Success bringup ha core, watchdog exiting."
            break
        else
            echo "Check failed ha core status. Retrying later ..."
            sleep 5  # Allow time for core to start
        fi
    done
}

post_check_core() {
    sleep 15 
    while true; do
        # Recheck ha core status
        post_core_status=$(/usr/bin/ha core status 2>/dev/null)
        if check_cpu_percent "$post_core_status"; then
            echo "ha core running, watchdog hibernating."
            sleep 15 
        else
            echo "ha core failed, watchdog wakeup."
            break
        fi
    done
}

# main procedure for ha-core-matter
health_check_for_ha_core_matter_mode() {
    echo "Start watchdog for homeassistant-core-matter module."
    # main loop
    while true; do
        check_network
        local status=$?
        if [ "$status" -eq 0 ]; then
            /usr/bin/systemctl start home-assistant.service
            /usr/bin/systemctl start matter-server.service
            exit 0
        elif [ "$status" -eq 2 ]; then
            echo "ERROR: Network interface $INTERFACE not found. Retrying..."
        fi
        sleep "$CHECK_INTERVAL"
    done
}

# main procedure for hassio supervisored
health_check_for_hassio_supervisored_mode() {
    echo "Start watchdog for homeassistant-supervisored module."
    # main loop
    while true; do
        check_observer
        check_core
        post_check_core
    done    
}

echo "ThirdReality Health Check procedure ..."

is_hassio_supervisored_actived=$(systemctl is-active --quiet hassio-supervisor.service && echo "yes" || echo "no")

is_home_assistant_actived=$(systemctl is-active --quiet home-assistant.service && echo "yes" || echo "no")

if [ "$is_home_assistant_actived" == "yes" ]; then

    if [ "$is_hassio_supervisored_actived" == "yes" ]; then
        stop_hassio_supervisored_mode
    fi

    health_check_for_ha_core_matter_mode

elif [ "$is_hassio_supervisored_actived" == "yes" ]; then

    # homeassistant supervisored need docker.service
    is_docker_enabled=$(systemctl is-enabled --quiet docker.service && echo "yes" || echo "no")
    if [[ "$is_docker_enabled" == "no" ]]; then
        echo "docker.service is disabled. Exiting."
        exit 0
    fi

    if [ ! -e "/usr/bin/ha" ];
        echo "/usr/bin/ha is not installed. Exiting."
        exit 0
    fi

    health_check_for_hassio_supervisored_mode
fi






