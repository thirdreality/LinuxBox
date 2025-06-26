#!/bin/bash

# maintainer: guoping.liu@thirdreality.com

LC_ALL=en_US.UTF-8

DEBIAN_FRONTEND=noninteractive
APT_LISTCHANGES_FRONTEND=none
MACHINE=odroid-n2
TIMEOUT=1200

export LC_ALL DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND MACHINE

WORK_DIR="/mnt/R3Install"
EXTRA_WORK_DIR="/mnt/R3Archives"
CONFIG_DIR="/var/lib/homeassistant"

set -e

# Ensure lock file is removed when script exits,
# and perform additional error handling

on_exit() {
    local exit_code=$?
    
    # Remove the lock file
    rm -f "${LOCKFILE}"
    
    # Custom actions before the script exits
    echo "Running cleanup tasks..."
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_event_off  || true
    fi

    echo "System finished to install deb packages. " | wall

    if [ "$exit_code" -ne 0 ]; then
      echo "An error occurred during the execution of the script. Exit code $exit_code"
    fi
}

error_handler() {
    local lineno=$1
    echo "Error occurred at line $lineno"
}

# trap 'error_handler $LINENO' ERR
trap "on_exit" EXIT

while getopts "d:" opt; do
  case ${opt} in
    d )
      WORK_DIR=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-d directory]"
      exit 1
      ;;
  esac
done

echo "Using directory: ${WORK_DIR}"

exclude_patterns=(
    # "ca-certificates_"
    # "docker-ce-cli_"
    # "containerd.io_"
    # "docker-buildx-plugin_"
    # "docker-compose-plugin_"
    # "docker-ce-rootless-extras_"
    # "docker-ce_"
    # "hassio-config"
    # "os-agent"
    # "homeassistant-supervised"

    "hacore-config_"
    "python3_"
    "hacore_"
    "otbr-agent_"

    "linuxbox-supervisor_"

    "zigbee-mqtt_"
    "zigpy_handler_"

    "openhab_"
)

install_extra_debs() {
    echo "[EXTRA]Finding and installing normal deb packages..."

    # Skip if directory doesn't exist
    if [ ! -d "$EXTRA_WORK_DIR" ]; then
        echo "[EXTRA]Directory $EXTRA_WORK_DIR does not exist, skipping extra debs installation"
        return 0
    fi

    deb_files=$(find "$EXTRA_WORK_DIR" -maxdepth 1 -name "*.deb" -type f 2>/dev/null || true)

    if [ -z "$deb_files" ]; then
        echo "[EXTRA]No deb files found in $EXTRA_WORK_DIR"
        return 0
    fi

    local installed=1
    for deb_file in $deb_files; do
        exclude=false
        for pattern in "${exclude_patterns[@]}"; do
            if [[ "$deb_file" == *"$pattern"* ]]; then
                exclude=true
                echo "[EXTRA]Skipping excluded file: $deb_file"
                break
            fi
        done

        if [ "$exclude" = false ]; then
            echo "[EXTRA]Installing: $deb_file"
            dpkg -i "$deb_file"
            installed=0
        fi
    done

    if [ "$installed" -eq 0 ]; then
        # Attempt to fix any potential broken dependencies
        echo "Attempting to fix broken dependencies..."
        apt-get install -f -y > /dev/null || true
    fi

    return 0
}

install_deb_if_needed() {
    local deb_file="$1"
    local package_name="$2"
    local current_version
    local deb_version

    echo "+ ${deb_file}. " | wall
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_firmware_updating  || true
    fi    

    current_version=$(dpkg-query -W -f='${Version}\n' "${package_name}" 2>/dev/null || true)    
    if [ -n "$current_version" ]; then
        deb_version=$(dpkg-deb --info "${deb_file}" | grep Version | awk '{print $2}')
        
        echo "${package_name} is installed (version: ${current_version}), deb version: ${deb_version}"
        
        if dpkg --compare-versions "$deb_version" gt "$current_version"; then
            echo "A newer version is available. Installing: ${deb_file}"
            dpkg_install "$deb_file"

            if [ -e "/usr/local/bin/supervisor" ]; then
                /usr/local/bin/supervisor setting updated  || true
            fi            
        else
            echo "Installed version is up-to-date. No installation needed."
        fi
    else
        echo "${package_name} is not installed or version not available. Installing: ${deb_file}"
        dpkg_install "$deb_file"

        if [ -e "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor setting updated  || true
        fi            
    fi
}

dpkg_install() {
    local deb_file="$1"
    if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$deb_file"; then
        echo "Warning: Failed to install $deb_file" >&2
    else
        apt-mark manual "$(dpkg-deb --info "$deb_file" | grep Package | awk '{print $2}')" || echo "Warning: Failed to mark package as manual" >&2
    fi
}

install_supervisor_debs() {
    if [ ! -d "$WORK_DIR" ]; then
        return 0
    fi

    echo "Attempting to install supervisor debs..."

    # Install linux supervisor
    supervisor_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "linuxbox-supervisor_*.deb" -type f | head -n 1)
    if [ -n "$supervisor_deb_file" ]; then
        install_deb_if_needed "$supervisor_deb_file" "linuxbox-supervisor"
    else
        echo "No linuxbox supervisor deb file found in $WORK_DIR" >&2
    fi
    return 0
}

# main procedure - 2
install_core_matter_debs() {
    echo "Installing core matter debs..."

    # Install hacore-config
    # Check if thirdreality-hacore-config package is already installed. NOTE: This package CANNOT be upgraded!!!!
    if ! dpkg -l | grep -q "^ii\s*thirdreality-hacore-config"; then
        hacore_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore-config_*.deb" -type f | head -n 1)
        if [ -n "$hacore_config_deb_file" ]; then
            echo "Installing: $hacore_config_deb_file"
            if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$hacore_config_deb_file"; then
                echo "Warning: Failed to install $hacore_config_deb_file" >&2
            else
                apt-mark manual "thirdreality-hacore-config" || echo "Warning: Failed to mark hacore-config as manual" >&2
            fi
        else
            echo "No hacore-config deb file found in $WORK_DIR" >&2
        fi
    else
        echo "thirdreality-hacore-config is already installed, skipping installation."
    fi

    # Install Python3
    python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python3_*.deb" -type f | head -n 1)
    if [ -n "$python3_deb_file" ]; then
        install_deb_if_needed "$python3_deb_file" "thirdreality-python3"
    else
        python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python_*.deb" -type f | head -n 1)
        if [ -n "$python3_deb_file" ]; then
            install_deb_if_needed "$python3_deb_file" "thirdreality-python3"
        else
            echo "No python3 deb file found in $WORK_DIR" >&2
        fi
    fi

    # 安装 hacore
    hacore_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore_*.deb" -type f | head -n 1)
    if [ -n "$hacore_deb_file" ]; then
        install_deb_if_needed "$hacore_deb_file" "thirdreality-hacore"
    else
        echo "No hacore deb file found in $WORK_DIR" >&2
    fi

    # Install otbr-agent (e.g., otbr-agent_2023.07.10.deb)
    otbr_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "otbr-agent_*.deb" -type f | head -n 1)
    if [ -n "$otbr_deb_file" ]; then
        install_deb_if_needed "$otbr_deb_file" "thirdreality-otbr-agent"
    else
        echo "No otbr-agent deb file found in $WORK_DIR" >&2
    fi

    return 0
}

install_zigbee2mqtt_debs() {
    echo "Attempting to install Zigbee2MQTT debs..."

    # Install zigbee-mqtt (e.g., zigbee-mqtt_2.3.0.deb)
    # Check if thirdreality-zigbee-mqtt package is already installed
    if ! dpkg -l | grep -q "^ii\s*thirdreality-zigbee-mqtt"; then
        zigbee_mqtt_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "zigbee-mqtt_*.deb" -type f | head -n 1)
        if [ -n "$zigbee_mqtt_deb_file" ]; then

            if [ -e "/usr/local/bin/supervisor" ]; then
                /usr/local/bin/supervisor led sys_firmware_updating  || true
            fi

            echo "+ ${zigbee_mqtt_deb_file}. " | wall
            echo "Installing: $zigbee_mqtt_deb_file"

            if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$zigbee_mqtt_deb_file"; then
                echo "Warning: Failed to install $zigbee_mqtt_deb_file" >&2
            else
                apt-mark manual "thirdreality-zigbee-mqtt" || echo "Warning: Failed to mark thirdreality-zigbee-mqtt as manual" >&2

                if [ -e "/usr/local/bin/supervisor" ]; then
                    /usr/local/bin/supervisor setting updated  || true
                fi

                # If installation is successful, install dependencies
                if [ -e "/usr/lib/thirdreality/post-install-zigbee2mqtt.sh" ]; then
                    /usr/lib/thirdreality/post-install-zigbee2mqtt.sh > /dev/null || true
                fi

                apt-get install -f > /dev/null || true

            fi
        else
            echo "No zigbee-mqtt deb file found in $WORK_DIR" >&2
        fi
    else
        echo "thirdreality-zigbee-mqtt is already installed, upgrading."

        echo "Installing: $zigbee_mqtt_deb_file"
        if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$zigbee_mqtt_deb_file"; then
            echo "Warning: Failed to install $zigbee_mqtt_deb_file" >&2
        else
            apt-mark manual "thirdreality-zigbee-mqtt" || echo "Warning: Failed to mark thirdreality-zigbee-mqtt as manual" >&2
        
            if [ -e "/usr/local/bin/supervisor" ]; then
                /usr/local/bin/supervisor setting updated  || true
            fi         

            # If installation is successful, install dependencies
            if [ -e "/usr/lib/thirdreality/post-install-zigbee2mqtt.sh" ]; then
                /usr/lib/thirdreality/post-install-zigbee2mqtt.sh > /dev/null || true
                apt-get install -f > /dev/null || true
            fi            
        fi        
    fi
}

install_openhab_debs() 
{
    echo "Attempting to install OpenHAB debs..."
}

install_zigpy_handler_debs()
{
    echo "Attempting to install zigpy device handler debs..."

    # Install zigpy_handler_*.deb
    if [ ! -d "$WORK_DIR" ]; then
        echo "Warning: Directory $WORK_DIR does not exist, cannot install zigpy handler" >&2
        return 0
    fi
    
    zigpy_handler_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "zigpy_handler_*.deb" -type f 2>/dev/null | head -n 1)
    if [ -n "$zigpy_handler_deb_file" ]; then
        install_deb_if_needed "$zigpy_handler_deb_file" "thirdreality-zigpy-handler"
    else
        echo "Warning: No zigpy device handler deb file found in $WORK_DIR" >&2
        # Don't fail the script if zigpy handler is not found
        return 0
    fi
}

# main procedure - 3
install_all_deb_images() {
    if [ ! -d "$WORK_DIR" ]; then
        return 0
    fi

    echo "Installing all deb images and loading Docker images..."
    local overall_status=0
    local deb_installed=0  # Track if any deb was installed

    # LED indication (continue on error)
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_firmware_updating  || true
    fi

    # Process .deb files
    deb_files=$(find "$WORK_DIR" -maxdepth 1 -name "*.deb" -type f)
    if [ -n "$deb_files" ]; then
        for deb_file in $deb_files; do
            echo "Installing: $deb_file"
            if dpkg -i "$deb_file"; then
                deb_installed=1
            else
                echo "Warning: Failed to install $deb_file" >&2
                overall_status=1
            fi
        done

        # Fix dependencies only if at least one package was installed
        if [ "$deb_installed" -eq 1 ]; then
            echo "Attempting to fix broken dependencies..."
            if ! apt-get install -f -y; then
                echo "Warning: Failed to fix dependencies" >&2
                overall_status=1
            fi
        fi
    else
        echo "No .deb files found in $WORK_DIR"
    fi

    # Process .tar files for Docker
    tar_files=$(find "$WORK_DIR" -maxdepth 1 -name "*.tar" -type f)
    if [ -n "$tar_files" ]; then
        for tar_file in $tar_files; do
            echo "Processing Docker image: $tar_file"
            
            # Check for repositories file
            if ! tar -tf "$tar_file" | grep -q "repositories"; then
                echo "Warning: No 'repositories' file in $tar_file" >&2
                overall_status=1
                continue
            fi

            # Load Docker image
            if ! docker load < "$tar_file"; then
                echo "Error: Failed to load Docker image $tar_file" >&2
                overall_status=1
            fi
        done
    else
        echo "No Docker image files found in $WORK_DIR"
    fi

    # Final LED indication (always attempt)
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_event_off  || true
    fi

    return $overall_status
}

main_procedure()
{
    install_supervisor_debs

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_firmware_updating  || true
    fi

    echo "System is start to install deb packages. " | wall

    if [ -d "$WORK_DIR" ]; then
        # install home-assistant-core
        is_home_assistant_running=$(systemctl is-active --quiet home-assistant.service && echo "yes" || echo "no")
        hacore_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore-config_*.deb" -type f | head -n 1)
        hacore_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore_*.deb" -type f | head -n 1)
        otbr_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "otbr-agent_*.deb" -type f | head -n 1)

        if [[ "$is_home_assistant_running" == "yes" || -n "$hacore_config_deb_file" || -n "$hacore_deb_file" || -n "$otbr_deb_file" ]]; then
            install_core_matter_debs
        else
            # Install Python3
            python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python3_*.deb" -type f | head -n 1)
            if [ -n "$python3_deb_file" ]; then
                install_deb_if_needed "$python3_deb_file" "thirdreality-python3"
            else
                python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python_*.deb" -type f | head -n 1)
                if [ -n "$python3_deb_file" ]; then
                    install_deb_if_needed "$python3_deb_file" "thirdreality-python3"
                fi
            fi

            # Install zigpy_tools
            zigpy_tools_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "zigpy_tools_*.deb" -type f | head -n 1)
            if [ -n "$zigpy_tools_deb_file" ]; then
                install_deb_if_needed "$zigpy_tools_deb_file" "thirdreality-zigpy-tools"
            fi        
        fi

        # install zigbee2mqtt
        install_zigbee2mqtt_debs

        # install openhab
        install_openhab_debs

        # install zigpy_handler
        install_zigpy_handler_debs
    fi

    # install all debs, leaving room for future upgrades
    install_extra_debs

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_event_off || true
    fi

    # Auto restore functionality
    if [ -d "/mnt/3RBackup" ] && [ -e "/usr/local/bin/supervisor" ]; then
        setting_files=$(find "/mnt/3RBackup" -maxdepth 1 -name "setting_*.tar.gz" -type f 2>/dev/null || true)
        if [ -n "$setting_files" ]; then
            echo "Found backup settings, attempting to restore..."
            /usr/local/bin/supervisor setting restore || true
        fi
    fi
}


main_procedure

exit 0
