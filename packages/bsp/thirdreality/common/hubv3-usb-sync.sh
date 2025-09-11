#!/bin/bash

# maintainer: guoping.liu@thirdreality.com

LC_ALL=en_US.UTF-8

DEBIAN_FRONTEND=noninteractive
APT_LISTCHANGES_FRONTEND=none
MACHINE=odroid-n2
TIMEOUT=1200

export LC_ALL DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND MACHINE

WORK_DIR="/mnt/R3Install"
DEBUG_DIR="/mnt/R3Debug"

DEBUG_ZHA_DIR="/mnt/R3Debug/zhaquirks"
DEBUG_OTA_DIR="/mnt/R3Debug/ota"
DEBUG_FIRMWARE_DIR="/mnt/R3Debug/firmware"

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

    "board_firmware_"

    "hacore-config_"
    "python3_"
    "hacore_"
    "otbr-agent_"

    "linuxbox-supervisor_"

    "zigbee-mqtt_"
    "zigpy_handler_"

    "openhab_"
)

update_zhaquirks_for_debug()
{
    # If $DEBUG_ZHA_DIR exists, copy all files under it to
    # /srv/homeassistant/lib/python3.13/site-packages/zhaquirks/thirdreality.
    # Proceed only if the target directory exists.
    if [ ! -d "$DEBUG_ZHA_DIR" ]; then
        return 0
    fi

    # Prefer the known path; otherwise glob-search to support different Python minor versions
    local zha_target_dir="/srv/homeassistant/lib/python3.13/site-packages/zhaquirks/thirdreality"
    if [ ! -d "$zha_target_dir" ]; then
        zha_target_dir=$(ls -d /srv/homeassistant/lib/python*/site-packages/zhaquirks/thirdreality 2>/dev/null | head -n 1 || true)
    fi

    if [ -z "$zha_target_dir" ] || [ ! -d "$zha_target_dir" ]; then
        echo "[DEBUG-ZHA] zhaquirks target directory not found, skip: $zha_target_dir"
        return 0
    fi

    echo "[DEBUG-ZHA] Sync zhaquirks to: $zha_target_dir"
    # Preserve attributes and overwrite files with the same name
    cp -a "$DEBUG_ZHA_DIR"/. "$zha_target_dir"/
    rm -rf "$DEBUG_ZHA_DIR"/. || true
    rm -rf "$zha_target_dir"/__pycache__ || true

    local ha_running="no"
    systemctl is-active --quiet home-assistant.service && ha_running="yes" || true
    if [ "$ha_running" = "yes" ]; then systemctl restart home-assistant.service || true; fi

    echo "[DEBUG-ZHA] zhaquirks sync completed"
}

update_ota_for_debug()
{
    if [ ! -d "$DEBUG_FIRMWARE_DIR" ]; then
        return 0
    fi

    if [ ! -f "$DEBUG_FIRMWARE_DIR/local_index.json" ]; then
        return 0
    fi

    local ota_dir="/var/lib/homeassistant/homeassistant/zigpy_local_ota"
    mkdir -p "$ota_dir"
    find "$ota_dir" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | xargs -0r rm -f
    install -m 0644 "$DEBUG_FIRMWARE_DIR/local_index.json" "$ota_dir/local_index.json" && rm -f "$DEBUG_FIRMWARE_DIR/local_index.json"
    shopt -s nullglob

    for f in "$DEBUG_FIRMWARE_DIR"/*.ota; do
        install -m 0644 "$f" "$ota_dir/" && rm -f "$f"
    done
    shopt -u nullglob

    local ha_cfg="/var/lib/homeassistant/homeassistant/configuration.yaml"
    if [ ! -f "$ha_cfg" ]; then
        return 0
    fi

    if grep -qE "extra_providers|zigpy_local|z2m_local" "$ha_cfg"; then
        return 0
    fi

    echo "[DEBUG-OTA] Append local OTA providers for ZHA to $ha_cfg"
    {
        echo ""
        echo "zha:"
        echo "  zigpy_config:"
        echo "    ota:"
        echo "      extra_providers:"
        echo "        - type: z2m_local"
        echo "          index_file: $ota_dir/local_index.json"
        echo "        - type: zigpy_local"
        echo "          index_file: $ota_dir/local_index.json"
    } >> "$ha_cfg"
}

update_firmware_for_debug()
{
    if [ ! -d "$DEBUG_FIRMWARE_DIR" ]; then
        return 0
    fi

    local fw_dir="/usr/lib/firmware/bl706/partition_1m_images"
    local flasher="/usr/lib/firmware/bl706"

    # Handle Zigbee firmware
    if [ -f "$DEBUG_FIRMWARE_DIR/blz_whole_img.bin" ]; then
        echo "[DEBUG-FW] Update Zigbee firmware image"
        install -m 0644 "$DEBUG_FIRMWARE_DIR/blz_whole_img.bin" "$fw_dir/blz_whole_img.bin" && rm -f "$DEBUG_FIRMWARE_DIR/blz_whole_img.bin"

        local ha_running="no"
        local z2m_running="no"
        systemctl is-active --quiet home-assistant.service && ha_running="yes" || true
        systemctl is-active --quiet zigbee2mqtt.service && z2m_running="yes" || true

        if [ "$ha_running" = "yes" ]; then systemctl stop home-assistant.service || true; fi
        if [ "$z2m_running" = "yes" ]; then systemctl stop zigbee2mqtt.service || true; fi

        "$flasher" flash blz

        if [ -x "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor zigbee info || true
        fi

        if [ "$ha_running" = "yes" ]; then systemctl start home-assistant.service || true; fi
        if [ "$z2m_running" = "yes" ]; then systemctl start zigbee2mqtt.service || true; fi
    fi

    # Handle Thread firmware
    if [ -f "$DEBUG_FIRMWARE_DIR/thread_whole_img.bin" ]; then
        echo "[DEBUG-FW] Update Thread firmware image"
        install -m 0644 "$DEBUG_FIRMWARE_DIR/thread_whole_img.bin" "$fw_dir/thread_whole_img.bin" && rm -f "$DEBUG_FIRMWARE_DIR/thread_whole_img.bin"

        local otbr_running="no"
        systemctl is-active --quiet otbr-agent.service && otbr_running="yes" || true

        if [ "$otbr_running" = "yes" ]; then systemctl stop otbr-agent.service || true; fi

        "$flasher" flash thread

        if [ -x "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor thread info || true
        fi

        if [ "$otbr_running" = "yes" ]; then systemctl start otbr-agent.service || true; fi
    fi
}



install_extra_debs() {
    echo "[EXTRA]Finding and installing extra deb packages..."

    # Skip if directory doesn't exist
    if [ ! -d "$WORK_DIR" ]; then
        echo "[EXTRA]Directory $WORK_DIR does not exist, skipping extra debs installation"
        return 0
    fi

    deb_files=$(find "$WORK_DIR" -maxdepth 1 -name "*.deb" -type f 2>/dev/null || true)

    if [ -z "$deb_files" ]; then
        echo "[EXTRA]No deb files found in $WORK_DIR"
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

# custom protocol to fix dependency
execute_fix_dependency_if_needed() {
    local package_name="$1"
    local postinst_file="/var/lib/dpkg/info/${package_name}.postinst"
    
    if [ -f "$postinst_file" ]; then
        echo "Executing post-installation script for $package_name"
        if [ -x "$postinst_file" ]; then
            "$postinst_file" fix-dependency || echo "Warning: postinst execution failed for $package_name"
        else
            echo "Warning: post-installation script file $postinst_file is not executable"
        fi
    fi
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
            dpkg_install "$deb_file" "$package_name"

            if [ -e "/usr/local/bin/supervisor" ]; then
                /usr/local/bin/supervisor setting updated  || true
            fi            
        else
            echo "Installed version is up-to-date. No installation needed."
        fi
    else
        echo "${package_name} is not installed or version not available. Installing: ${deb_file}"
        dpkg_install "$deb_file" "$package_name"

        if [ -e "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor setting updated  || true
        fi            
    fi
}

dpkg_install() {
    local deb_file="$1"
    local package_name="$2"
    if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$deb_file"; then
        echo "Warning: Failed to install $deb_file" >&2
    else
        apt-mark manual "$package_name" || echo "Warning: Failed to mark package as manual" >&2
        execute_fix_dependency_if_needed "$package_name"
    fi
}

install_board_flash_debs() {
    if [ ! -d "$WORK_DIR" ]; then
        return 0
    else
        update_firmware_for_debug
        return 0
    fi

    echo "Attempting to install board firmware debs..."

    # Find board_firmware deb file
    board_firmware_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "board_firmware_*.deb" -type f | head -n 1)
    
    if [ -n "$board_firmware_deb_file" ]; then
        echo "Found board firmware deb: $board_firmware_deb_file"
        
        # Get deb version number
        deb_version=$(dpkg-deb --info "${board_firmware_deb_file}" | grep Version | awk '{print $2}')
        echo "Board flash deb version: $deb_version"
        
        # Check if already installed
        if dpkg -l | grep -q "^ii\s*thirdreality-board-firmware"; then
            # Get installed version number
            installed_version=$(dpkg-query -W -f='${Version}\n' "thirdreality-board-firmware" 2>/dev/null || true)
            echo "Installed version: $installed_version"
            
            # Compare version numbers, install if deb version is greater than installed version
            if dpkg --compare-versions "$deb_version" gt "$installed_version"; then
                echo "Newer version available. Installing: $board_firmware_deb_file"
                dpkg_install "$board_firmware_deb_file" "thirdreality-board-firmware"
            else
                echo "Installed version is up-to-date. No installation needed."
            fi
        else
            # Not installed before, check for force flag first
            if [ -f "$WORK_DIR/.force_board_flash" ]; then
                echo "Force flag found, installing board firmware without version check"
                dpkg_install "$board_firmware_deb_file" "thirdreality-board-firmware"
            elif [ -f "/etc/t3r-release" ]; then
                # Read version information from /etc/t3r-release
                source "/etc/t3r-release"
                echo "System version from /etc/t3r-release: $VERSION"
                
                # Parse system version number (format: v1.03.01.03)
                # Extract zigbee and thread version numbers
                if [[ "$VERSION" =~ v([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
                    system_zigbee_version="${BASH_REMATCH[3]}"
                    system_thread_version="${BASH_REMATCH[2]}"
                    echo "System zigbee version: $system_zigbee_version, thread version: $system_thread_version"
                    
                    # Parse deb version number (format: 1.03.01)
                    if [[ "$deb_version" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
                        deb_zigbee_version="${BASH_REMATCH[3]}"
                        deb_thread_version="${BASH_REMATCH[2]}"
                        echo "Deb zigbee version: $deb_zigbee_version, thread version: $deb_thread_version"
                        
                        # Check if either zigbee or thread version is greater than system version
                        if [ "$deb_zigbee_version" -gt "$system_zigbee_version" ] || [ "$deb_thread_version" -gt "$system_thread_version" ]; then
                            echo "Either zigbee or thread version is newer. Installing: $board_firmware_deb_file"
                            dpkg_install "$board_firmware_deb_file" "thirdreality-board-firmware"
                        else
                            echo "Version check failed. Zigbee: $deb_zigbee_version > $system_zigbee_version, Thread: $deb_thread_version > $system_thread_version"
                            echo "No installation needed."
                        fi
                    else
                        echo "Failed to parse deb version format: $deb_version"
                    fi
                else
                    echo "Failed to parse system version format: $VERSION"
                fi
            else
                echo "Warning: /etc/t3r-release not found, cannot determine system version"
            fi
        fi
    else
        echo "No board firmware deb file found in $WORK_DIR"
        update_firmware_for_debug
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
                execute_fix_dependency_if_needed "thirdreality-hacore-config"
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

    # Install hacore
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

    zigbee_mqtt_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "zigbee-mqtt_*.deb" -type f | head -n 1)
    if [ -n "$zigbee_mqtt_deb_file" ]; then
        install_deb_if_needed "$zigbee_mqtt_deb_file" "thirdreality-zigbee-mqtt"
        # 老版本兼容：If installation is successful, install dependencies
        # New: /usr/lib/thirdreality/post-fix-zigbee2mqtt.sh
        if [ -e "/usr/lib/thirdreality/post-install-zigbee2mqtt.sh" ]; then
            /usr/lib/thirdreality/post-install-zigbee2mqtt.sh > /dev/null || true
        fi             
        apt-get install -f > /dev/null || true
    else
        echo "No zigbee-mqtt deb file found in $WORK_DIR" >&2
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

install_supervisor_deb() {
    if [ ! -d "$WORK_DIR" ]; then
        return 0
    fi

    echo "Attempting to install supervisor deb..."

    # Find linuxbox-supervisor deb file
    supervisor_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "linuxbox-supervisor_*.deb" -type f | head -n 1)
    
    if [ -n "$supervisor_deb_file" ]; then
        echo "Found supervisor deb: $supervisor_deb_file"
        
        # Get deb version number
        deb_version=$(dpkg-deb --info "${supervisor_deb_file}" | grep Version | awk '{print $2}')
        echo "Deb version: $deb_version"
        
        # Check if already installed
        if dpkg -l | grep -q "^ii\s*linuxbox-supervisor"; then
            # Get installed version number
            installed_version=$(dpkg-query -W -f='${Version}\n' "linuxbox-supervisor" 2>/dev/null || true)
            echo "Installed version: $installed_version"
            
            # Compare version numbers, install if deb version is greater than installed version
            if dpkg --compare-versions "$deb_version" gt "$installed_version"; then
                echo "Newer version available. Installing: $supervisor_deb_file"
                dpkg_install "$supervisor_deb_file" "linuxbox-supervisor"
                echo "Supervisor installation completed."
            else
                echo "Installed version is up-to-date. No installation needed."
            fi
        else
            # Not installed before, install directly
            echo "linuxbox-supervisor is not installed. Installing: $supervisor_deb_file"
            dpkg_install "$supervisor_deb_file" "linuxbox-supervisor" 
            echo "Supervisor installation completed."
        fi
    else
        echo "No linuxbox-supervisor deb file found in $WORK_DIR"
    fi
    
    return 0
}

validate_config() {
    # Validate configuration and clean up invalid flags
    if [ -d "/mnt/R3Backup" ] && [ -f "/mnt/R3Backup/.enable-backup" ]; then
        # Check if thirdreality-python3 package is installed
        if ! dpkg -l | grep -q "^ii\s*thirdreality-python3"; then
            echo "Warning: .enable-backup flag found but thirdreality-python3 package not installed"
            echo "Removing .enable-backup flag..."
            rm -f "/mnt/R3Backup/.enable-backup"
            echo ".enable-backup flag removed due to missing thirdreality-python3 package"
        fi
    fi
}

main_procedure()
{  
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_firmware_updating  || true
    fi

    # Validate configuration first
    validate_config
    
    echo "System is start to install deb packages. " | wall

    # install supervisor
    install_supervisor_deb

    # install board firmware
    install_board_flash_debs

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
        /usr/bin/sync
        /usr/local/bin/supervisor led sys_event_off || true
    fi

    # Auto restore functionality
    if [ -d "/mnt/R3Backup" ] && [ -e "/usr/local/bin/supervisor" ]; then
        # Check if .enable-backup exists - force backup and exit
        if [ -f "/mnt/R3Backup/.enable-backup" ]; then
            /usr/local/bin/supervisor led sys_event_off || true
            echo "Found .enable-backup flag, forcing backup..."
            echo "System found .enable-backup flag, forcing backup..." | wall
            /usr/local/bin/supervisor setting backup || true
            rm -f "/mnt/R3Backup/.enable-backup"
            echo "Backup completed, .enable-backup flag removed"
            /usr/local/bin/supervisor led sys_event_off || true
            return 0
        fi
        
        # Check if .enable-restore exists - force restore if flag is present
        if [ -f "/mnt/R3Backup/.enable-restore" ]; then
            setting_files=$(find "/mnt/R3Backup" -maxdepth 1 -name "setting_*.tar.gz" -type f 2>/dev/null || true)
            if [ -n "$setting_files" ]; then
                /usr/local/bin/supervisor led sys_firmware_updating  || true
                echo "Found .enable-restore flag, attempting to restore..."
                echo "System found .enable-restore flag, attempting to restore..." | wall
                /usr/local/bin/supervisor setting restore || true
                /usr/local/bin/supervisor led sys_event_off || true
                echo "Restore completed, .enable-restore flag removed"
                rm -f "/mnt/R3Backup/.enable-restore"
            else
                echo "Warning: .enable-restore flag found but no setting files available"
                rm -f "/mnt/R3Backup/.enable-restore"
            fi
        fi
    fi

    update_ota_for_debug

    update_zhaquirks_for_debug    
}


main_procedure

exit 0
