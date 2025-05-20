#!/bin/bash

# maintainer: guoping.liu@thirdreality.com

LC_ALL=en_US.UTF-8

DEBIAN_FRONTEND=noninteractive
APT_LISTCHANGES_FRONTEND=none
MACHINE=odroid-n2
TIMEOUT=1200

export LC_ALL DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND MACHINE

WORK_DIR="/mnt"
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
        /usr/local/bin/supervisor led mqtt_pared
    fi

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
    "ca-certificates_"
    "docker-ce-cli_"
    "containerd.io_"
    "docker-buildx-plugin_"
    "docker-compose-plugin_"
    "docker-ce-rootless-extras_"
    "docker-ce_"
    "hassio-config"
    "os-agent"
    "homeassistant-supervised"

    "hacore-config_"
    "python3_"
    "hacore_"
    "otbr-agent_"

    "linuxbox-supervisor_"
)

install_extra_debs() {
    echo "[POST]Finding and installing normal deb packages..."

    deb_files=$(find "$WORK_DIR" -maxdepth 1 -name "*.deb" -type f)

    if [ -z "$deb_files" ]; then
        return
    fi

    local installed=1
    for deb_file in $deb_files; do
        exclude=false
        for pattern in "${exclude_patterns[@]}"; do
            if [[ "$deb_file" == *"$pattern"* ]]; then
                exclude=true
                echo "[POST]Skipping excluded file: $deb_file"
                break
            fi
        done

        if [ "$exclude" = false ]; then
            echo "[POST]Installing: $deb_file"
            sudo dpkg -i "$deb_file"
            installed=0
        fi
    done

    if [ "$installed" -eq 0 ]; then
        # Attempt to fix any potential broken dependencies
        echo "Attempting to fix broken dependencies..."
        apt-get install -f -y || true
    fi
}

install_deb_if_needed() {
    local deb_file="$1"
    local package_name="$2"
    local current_version
    local deb_version

    current_version=$(dpkg-query -W -f='${Version}\n' "${package_name}" 2>/dev/null || true)    
    if [ -n "$current_version" ]; then
        deb_version=$(dpkg-deb --info "${deb_file}" | grep Version | awk '{print $2}')
        
        echo "${package_name} is installed (version: ${current_version}), deb version: ${deb_version}"
        
        if dpkg --compare-versions "$deb_version" gt "$current_version"; then
            echo "A newer version is available. Installing: ${deb_file}"
            dpkg_install "$deb_file"
        else
            echo "Installed version is up-to-date. No installation needed."
        fi
    else
        echo "${package_name} is not installed or version not available. Installing: ${deb_file}"
        dpkg_install "$deb_file"
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
    echo "Try to installing supervisor debs..."

    # 安装 linux supervisor
    supervisor_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "linuxbox-supervisor_*.deb" -type f | head -n 1)
    if [ -n "$supervisor_deb_file" ]; then
        install_deb_if_needed "$supervisor_deb_file" "linuxbox-supervisor"
    else
        echo "Warning: No linuxbox supervisor deb file found in $WORK_DIR" >&2
    fi
}

# main procedure - 2
install_core_matter_debs() {
    echo "Installing core matter debs..."

    # 安装 hacore-config
    # 检查是否已经安装 thirdreality-hacore-config 包， 注意：这个包不能升级!!!!
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
            echo "Warning: No hacore-config deb file found in $WORK_DIR" >&2
        fi
    else
        echo "thirdreality-hacore-config is already installed, skipping installation."
    fi

    # 安装 python3
    python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python3_*.deb" -type f | head -n 1)
    if [ -n "$python3_deb_file" ]; then
        install_deb_if_needed "$python3_deb_file" "thirdreality-python3"
    else
        python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python_*.deb" -type f | head -n 1)
        if [ -n "$python3_deb_file" ]; then
            install_deb_if_needed "$python3_deb_file" "thirdreality-python3"
        else
            echo "Warning: No python3 deb file found in $WORK_DIR" >&2
        fi
    fi

    # 安装 hacore
    hacore_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore_*.deb" -type f | head -n 1)
    if [ -n "$hacore_deb_file" ]; then
        install_deb_if_needed "$hacore_deb_file" "thirdreality-hacore"
    else
        echo "Warning: No hacore deb file found in $WORK_DIR" >&2
    fi

    # 安装 otbr-agent, otbr-agent_2023.07.10.deb
    otbr_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "otbr-agent_*.deb" -type f | head -n 1)
    if [ -n "$otbr_deb_file" ]; then
        install_deb_if_needed "$otbr_deb_file" "thirdreality-otbr-agent"
    else
        echo "Warning: No otbr-agent deb file found in $WORK_DIR" >&2
    fi

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor ota update
    fi
}

# main procedure - 3
install_all_deb_images() {
    echo "Installing all deb images and loading Docker images..."
    local overall_status=0
    local deb_installed=0  # Track if any deb was installed

    # LED indication (continue on error)
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led mqtt_paring
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
        /usr/local/bin/supervisor led mqtt_pared
    fi

    return $overall_status
}

main_procedure()
{
    install_supervisor_debs

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led mqtt_paring
    fi

    # install home-assistant-core
    is_home_assistant_running=$(systemctl is-active --quiet home-assistant.service && echo "yes" || echo "no")
    hacore_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore-config_*.deb" -type f | head -n 1)
    hacore_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore_*.deb" -type f | head -n 1)
    otbr_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "otbr-agent_*.deb" -type f | head -n 1)

    if [[ "$is_home_assistant_running" == "yes" || -n "$hacore_config_deb_file" || -n "$hacore_deb_file" || -n "$otbr_deb_file" ]]; then
        install_core_matter_debs
    else
        echo "TODO: install_all_deb_images"
        # install_all_deb_images
    fi

    # install zigbee2mqtt

    # install HomeBridge


    install_extra_debs

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led mqtt_pared
    fi
}


main_procedure

exit 0