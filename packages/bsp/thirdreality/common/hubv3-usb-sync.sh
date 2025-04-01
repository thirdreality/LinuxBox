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
trap "on_exit" EXIT
on_exit() {
    local exit_code=$?
    
    # Remove the lock file
    rm -f "${LOCKFILE}"
    
    # Custom actions before the script exits
    echo "Running cleanup tasks..."
    /lib/thirdreality/hubv3-monitor.py set mqtt_pared

    if [ "$exit_code" -ne 0 ]; then
      echo "An error occurred during the execution of the script. Exit code $exit_code"
    fi
}


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

# Ensure only one instance of the script is running
readonly LOCKFILE="/tmp/install_docker_ha.lock"

if [ -e ${LOCKFILE} ] && kill -0 $(cat ${LOCKFILE}) 2>/dev/null; then
    echo "Script is already running, please wait for it to complete or terminate the existing process"
    exit 1
fi

# Create lock file
echo $$ > ${LOCKFILE}

# Ensure lock file is removed when script exits
trap "rm -f ${LOCKFILE}" EXIT

# Function: Check if Docker is installed
check_docker_installed() {
    if command -v docker &> /dev/null; then
        return 0  # Docker is installed
    else
        return 1  # Docker is not installed
    fi
}

install_normal_debs() {
    echo "Finding and installing normal deb packages..."

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
    )

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
                echo "Skipping excluded file: $deb_file"
                break
            fi
        done

        if [ "$exclude" = false ]; then
            echo "Installing: $deb_file"
            sudo dpkg -i "$deb_file"
            installed=0
        fi
    done

    if [ "$installed" -eq 0 ]; then
        # Attempt to fix any potential broken dependencies
        echo "Attempting to fix broken dependencies..."
        sudo apt-get install -f -y
    fi
}

# Function: Install Docker related deb packages
install_docker_debs() {
    echo "Finding and installing Docker related deb packages..."
    
    # Define the list of deb packages to install (in order)
    docker_debs=(
        "ca-certificates_*_all.deb"
        "docker-ce-cli_*_arm64.deb"
        "containerd.io_*_arm64.deb"
        "docker-buildx-plugin_*_arm64.deb"
        "docker-compose-plugin_*_arm64.deb"
        "docker-ce-rootless-extras_*_arm64.deb"
        "docker-ce_*_arm64.deb"
    )
    
    for deb_pattern in "${docker_debs[@]}"; do
        # Find matching deb files
        deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "$deb_pattern" -type f | head -n 1)
        
        if [ -n "$deb_file" ]; then
            echo "Installing: $deb_file"
            dpkg -i "$deb_file" || apt-get install -f -y
        else
            echo "Package not found: $deb_pattern"
        fi
    done
}

load_image_for_single_hassio_images() {
    # tar file path
    local tar_file=$1

    # image repo
    local repo=$2

    # image tag/version
    local tag=$3

    # config key in dns/audio/xxx.json/update.json
    local config=$4

    # contain id
    local container_id=$5

    local result=1

    IMAGE="$repo"
    echo "Update IMAGE [$IMAGE]."
    
    echo "Fetching current version for $repo..."

    set +e
    current_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo:" | awk -F ":" '{print $2}'| grep -v "^latest$")
    set -e

    if [ $? -ne 0 ]; then
        echo "Error: unable to determine the current version for repository $repo."
        return 1 # Or handle error accordingly
    fi

    if [ -z "$current_version" ]; then
        echo "Install a new image [$tar_file]."
        docker load < "$tar_file" 2>&1 

        # audio.json
        # cli.json
        # dns.json
        # homeassistant.json
        # multicast.json
        # observer.json
        CONFIG_FILE="${CONFIG_DIR}/${config}.json"
        if [ -e "$CONFIG_FILE" ]; then
            sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
        fi

        UPDATER_FILE="${CONFIG_DIR}/updater.json"
        if [ -e "$UPDATER_FILE" ]; then
            sed -i "s/\"${config}\": \".*\"/\"${config}\": \"${tag}\"/" "$UPDATER_FILE"
        fi

        result=0
    else
        if [[ "$current_version" < "$tag" ]]; then
            echo "Found newer version for [$repo]"

            if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
                systemctl stop hassio-supervisor.service
            fi

            docker container rm --force ${container_id} || true
            IMAGE_IDS=$(docker images --no-trunc --filter "reference=${IMAGE}" --format "{{.ID}}" | uniq || echo "")
            docker image rm --force "${IMAGE_IDS}" || true

            echo "Check disk patition ..."
            df -h /var/lib/docker

            echo "Loading a new image [$tar_file]."
            docker load < "$tar_file" 2>&1 

            # audio.json
            # cli.json
            # dns.json
            # homeassistant.json
            # multicast.json
            # observer.json
            CONFIG_FILE="${CONFIG_DIR}/${config}.json"
            if [ -e "$CONFIG_FILE" ]; then
                sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
            fi

            UPDATER_FILE="${CONFIG_DIR}/updater.json"
            if [ -e "$UPDATER_FILE" ]; then
                sed -i "s/\"${config}\": \".*\"/\"${config}\": \"${tag}\"/" "$UPDATER_FILE"
            fi
            
            result=0
        else
            echo "Current image version [ $repo:$current_version ] is up-to-date or newer. skip current image tar."
        fi
    fi  

    return $result
}

load_image_for_hassio_supervisor() {
    local tar_file=$1
    local repo=$2
    local tag=$3

    local result=1

    SUPERVISOR_IMAGE="ghcr.io/home-assistant/aarch64-hassio-supervisor"
    SUPERVISOR_MACHINE="odroid-n2"
    SUPERVISOR_DATA="/var/lib/homeassistant"

    set +e
    current_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo:" | awk -F ":" '{print $2}'| grep -v "^latest$")
    set -e

    if [ $? -ne 0 ]; then
        echo "Error: unable to determine the current version for repository $repo."
        return 1 # Or handle error accordingly
    fi    

    if [ -z "$current_version" ]; then
        echo "Install a new image [$tar_file]."
        docker load < "$tar_file" 2>&1 

        docker tag "${repo}:${tag}" "${repo}:latest"

        CONFIG_FILE="${CONFIG_DIR}/config.json"
        if [ -e "$CONFIG_FILE" ]; then
            sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
        fi

        UPDATER_FILE="${CONFIG_DIR}/updater.json"
        if [ -e "$UPDATER_FILE" ]; then
            sed -i "s/\"supervisor\": \".*\"/\"supervisor\": \"${tag}\"/" "$UPDATER_FILE"
            sed -i 's/"auto_update":\s*true/"auto_update": false/g' "$UPDATER_FILE"
            sed -i 's/"auto_update":\s*false/"auto_update": false/g' "$UPDATER_FILE"
        fi

        docker container rm --force hassio_supervisor || true

        echo "[INFO] Creating a new Supervisor container..."
        # shellcheck disable=SC2086
        docker container create \
            --name hassio_supervisor \
            --privileged --security-opt apparmor="hassio-supervisor" \
            -v /run/docker.sock:/run/docker.sock:rw \
            -v /run/containerd/containerd.sock:/run/containerd/containerd.sock:rw \
            -v /run/systemd-journal-gatewayd.sock:/run/systemd-journal-gatewayd.sock:rw \
            -v /run/dbus:/run/dbus:ro \
            -v /run/supervisor:/run/os:rw \
            -v /run/udev:/run/udev:ro \
            -v /etc/machine-id:/etc/machine-id:ro \
            -v ${SUPERVISOR_DATA}:/data:rw,slave \
            -e SUPERVISOR_SHARE=${SUPERVISOR_DATA} \
            -e SUPERVISOR_NAME=hassio_supervisor \
            -e SUPERVISOR_MACHINE=${SUPERVISOR_MACHINE} \
            "${SUPERVISOR_IMAGE}:latest"


        echo "[INFO] Check Supervisor container..."
        docker images --no-trunc --filter "reference=${SUPERVISOR_IMAGE}:latest" --format "{{.ID}}" || echo "" || true
        docker inspect --format='{{.Image}}' hassio_supervisor || echo "" || true

        result=0
    else
        if [[ "$current_version" < "$tag" ]]; then
            echo "Found newer version for [$repo]"

            if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
                systemctl stop hassio-supervisor.service
            fi

            docker container rm --force hassio_supervisor || true

            IMAGE_IDS=$(docker images --no-trunc --filter "reference=${SUPERVISOR_IMAGE}" --format "{{.ID}}" | uniq || echo "")
            docker image rm --force "${IMAGE_IDS}" || true

            echo "Check disk patition ..."
            df -h /var/lib/docker

            echo "Loading a new image [$tar_file]."
            docker load < "$tar_file" 2>&1 

            docker tag "${repo}:${tag}" "${repo}:latest"
            
            CONFIG_FILE="${CONFIG_DIR}/config.json"
            if [ -e "$CONFIG_FILE" ]; then
                sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
            fi

            UPDATER_FILE="${CONFIG_DIR}/updater.json"
            if [ -e "$UPDATER_FILE" ]; then
                sed -i "s/\"supervisor\": \".*\"/\"supervisor\": \"${tag}\"/" "$UPDATER_FILE"
                sed -i 's/"auto_update":\s*true/"auto_update": false/g' "$UPDATER_FILE"
                sed -i 's/"auto_update":\s*false/"auto_update": false/g' "$UPDATER_FILE"                
            fi

            echo "[INFO] Creating a new Supervisor container..."

            # shellcheck disable=SC2086
            docker container create \
                --name hassio_supervisor \
                --privileged --security-opt apparmor="hassio-supervisor" \
                -v /run/docker.sock:/run/docker.sock:rw \
                -v /run/containerd/containerd.sock:/run/containerd/containerd.sock:rw \
                -v /run/systemd-journal-gatewayd.sock:/run/systemd-journal-gatewayd.sock:rw \
                -v /run/dbus:/run/dbus:ro \
                -v /run/supervisor:/run/os:rw \
                -v /run/udev:/run/udev:ro \
                -v /etc/machine-id:/etc/machine-id:ro \
                -v ${SUPERVISOR_DATA}:/data:rw,slave \
                -e SUPERVISOR_SHARE=${SUPERVISOR_DATA} \
                -e SUPERVISOR_NAME=hassio_supervisor \
                -e SUPERVISOR_MACHINE=${SUPERVISOR_MACHINE} \
                "${SUPERVISOR_IMAGE}:latest"

            echo "[INFO] Check Supervisor container..."
            docker images --no-trunc --filter "reference=${SUPERVISOR_IMAGE}:latest" --format "{{.ID}}" || echo "" || true
            docker inspect --format='{{.Image}}' hassio_supervisor || echo "" || true

            result=0
        else
            echo "Current image version [ $repo:$current_version ] is up-to-date or newer. skip current image tar."
        fi
    fi

    return $result
}

load_image_for_matter_server() {
    local tar_file=$1
    local repo=$2
    local tag=$3

    local result=1

    IMAGE="homeassistant/aarch64-addon-matter-server"
    CONFIG_FILE="${CONFIG_DIR}/addons.json"

    set +e
    current_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo:" | awk -F ":" '{print $2}'| grep -v "^latest$")
    set -e

    if [ $? -ne 0 ]; then
        echo "Error: unable to determine the current version for repository $repo."
        return 1 # Or handle error accordingly
    fi    

    if [ -z "$current_version" ]; then
        echo "Install a new image [$tar_file]."
        docker load < "$tar_file" 2>&1 

        docker container rm --force addon_core_matter_server || true

        if [ -e "$CONFIG_FILE" ]; then
            jq '.user.core_matter_server.version = "${tag}"' ${CONFIG_FILE} > temp.json && mv temp.json ${CONFIG_FILE}
        fi

        result=0
    else
        if [[ "$current_version" < "$tag" ]]; then
            echo "Found newer version for [$repo]"

            if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
                systemctl stop hassio-supervisor.service
            fi

            docker container rm --force addon_core_matter_server || true
            IMAGE_IDS=$(docker images --no-trunc --filter "reference=${IMAGE}" --format "{{.ID}}" | uniq || echo "")
            docker image rm --force "${IMAGE_IDS}" || true

            echo "Check disk patition ..."
            df -h /var/lib/docker

            echo "Loading a new image [$tar_file]."
            docker load < "$tar_file" 2>&1 
            
            if [ -e "$CONFIG_FILE" ]; then
                jq '.user.core_matter_server.version = "${tag}"' ${CONFIG_FILE} > temp.json && mv temp.json ${CONFIG_FILE}
            fi

            result=0
        else
            echo "Current image version [ $repo:$current_version ] is up-to-date or newer. skip current image tar."
        fi
    fi

    return $result
}

# Function: Load Docker images
load_docker_images() {
    echo "Finding and loading Docker images..."
    local result=1

    # Find all .tar files, "-maxdepth 1" is very important, 
    # because you don't know what the users will place in the USB Stick
    tar_files=$(find "$WORK_DIR" -maxdepth 1 -name "*.tar" -type f)
    
    if [ -z "$tar_files" ]; then
        echo "No Docker image files found"
        return $result
    fi
    
    for tar_file in $tar_files; do
        echo "Checking repositories in tar file: [ $tar_file ]"
        # Check if tar file contains 'repositories'
        if tar -tf "$tar_file" | grep -q "repositories"; then
            repositories=$(tar -Oxf "$tar_file" repositories)
        else
            echo "Warning: No 'repositories' file found in [ $tar_file ], skipping..."
            continue
        fi

        # Extract repository and tag from the JSON content
        repo=$(echo "$repositories" | jq -r 'keys[0]')
        tag=$(echo "$repositories" | jq -r '.[] | keys[0]')

        echo "New version: [$tag]"

        if [ "$tag" == "latest" ]; then
            # latest is a tag, just skip it
            echo "Skip image: [$tar_file] with tag 'latest'"
            continue
        fi

        case "$repo" in
            *"-addon-"*)
                if [[ "$repo" == *"addon-matter-server"* ]]; then 
                    load_image_for_matter_server "${tar_file}" "${repo}" "${tag}" || result=1
                else
                    echo "Loading addon image: [$tar_file]"
                    docker load < "$tar_file" 2>&1 
                fi
                ;;
            *"hassio-supervisor"*)
                load_image_for_hassio_supervisor "${tar_file}" "${repo}" "${tag}" || result=1
                ;;
            *"homeassistant"*)
                load_image_for_single_hassio_images "${tar_file}" "${repo}" "${tag}" "homeassistant" "homeassistant" || result=1
                ;;
            *"hassio-cli"*)
                load_image_for_single_hassio_images "${tar_file}" "${repo}" "${tag}" "cli" "hassio_cli" || result=1
                ;;
            *"hassio-audio"*)
                load_image_for_single_hassio_images "${tar_file}" "${repo}" "${tag}" "audio" "hassio_audio" || result=1
                ;;
            *"hassio-dns"*)
                load_image_for_single_hassio_images "${tar_file}" "${repo}" "${tag}" "dns" "hassio_dns" || result=1
                ;;
            *"hassio-multicast"*)
                load_image_for_single_hassio_images "${tar_file}" "${repo}" "${tag}" "multicast" "hassio_multicast" || result=1
                ;;
            *"hassio-observer"*)
                load_image_for_single_hassio_images "${tar_file}" "${repo}" "${tag}" "observer" "hassio_observer" || result=1
                ;;  
            # Other repo cases...
            *)
                echo "Unrecognized repository pattern for [ $tar_file ], skipping..."
                # Use continue here if there's logic after the case statement to skip for unrecognized cases
                ;; 
        esac

    done

    # ha supervisor update
    # ha core update
    # ha addons core_matter_server update

    return $result
}

# Function: Install Home Assistant related deb packages
install_ha_debs() {
    echo "Finding and installing Home Assistant related deb packages..."

    hassio_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hassio-config_*.deb" -type f | head -n 1)
    if [ -n "$hassio_config_deb_file" ]; then
        echo "Installing: $hassio_config_deb_file"
        DEBIAN_FRONTEND=noninteractive dpkg -i "$hassio_config_deb_file"

        # mark it manual install
        apt-mark manual "thirdreality-hassio-config"
    else
        echo "No hassio-config*.deb file found. exiting ..."
        return
    fi

    os_agent_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "os-agent_*.deb" -type f | head -n 1)
    if [ -n "$os_agent_deb_file" ]; then
        echo "Installing: $os_agent_deb_file"
        DEBIAN_FRONTEND=noninteractive dpkg -i "$os_agent_deb_file"

        # mark it manual install
        apt-mark manual "os-agent"
    else
        echo "No os-agent.deb file found."
    fi

    if [ -e "/usr/bin/ha" ]; then
        echo "homeassistant-supervised is already installed, skipping homeassistant-supervised installation step"
        return
    fi

    supervised_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "homeassistant-supervised*.deb" -type f | head -n 1)
    if [ -n "${supervised_deb_file}" ]; then
        echo "Installing: $supervised_deb_file"

        rm -rf "/run/supervisor/startup-marker"
        rm -rf "${WORK_DIR}/homeassistant-supervised/"

        echo "Updating: $supervised_deb_file"

        dpkg-deb -R ${supervised_deb_file} "${WORK_DIR}/homeassistant-supervised/"

        #/etc/NetworkManager/NetworkManager.conf, fixed it for W155S1 driver.
        TARGET_FILE="${WORK_DIR}/homeassistant-supervised/DEBIAN/postinst"
        sed -i '/systemctl restart "${SERVICE_NM}"/i \
# Define configuration file and pattern lines\
MACHINE=odroid-n2\
CONFIG_FILE="/etc/NetworkManager/NetworkManager.conf"\
PATTERN_LINE="unmanaged-devices=*"\
REPLACEMENT_LINE="unmanaged-devices=interface-name:*,except:interface-name:wlan0"\
\
# If the configuration file exists, update it\
if [ -e $CONFIG_FILE ]; then\
    sed -i.bak "/$PATTERN_LINE/c $REPLACEMENT_LINE" "$CONFIG_FILE"\
fi\
        ' "$TARGET_FILE"

        # apparmor.txt
        OLD_LINE="curl -sL \${URL_APPARMOR_PROFILE} > \"\${DATA_SHARE}/apparmor/hassio-supervisor\""
        NEW_LINE="#curl -sL \${URL_APPARMOR_PROFILE} > \"\${DATA_SHARE}/apparmor/hassio-supervisor\""
        #NEW_LINE="cp /lib/thirdreality/apparmor.txt \"\${DATA_SHARE}/apparmor/hassio-supervisor\""
        # replace apparmor.txt with local apparmor.txt,last update: Oct 26, 2023
        sed -i.bak "s|$OLD_LINE|$NEW_LINE|" "$TARGET_FILE"

        # Line 68: curl -q ${URL_CHECK_ONLINE} >/dev/null 2>&1
        OLD_ONLINE="sleep 2"
        NEW_ONLINE="break"
        sed -i.bak "s|$OLD_ONLINE|$NEW_ONLINE|" "$TARGET_FILE"

        echo "Code inserted successfully."

        dpkg-deb -b "${WORK_DIR}/homeassistant-supervised" "${WORK_DIR}/homeassistant-supervised-modified.deb"

        echo "Install ${WORK_DIR}/homeassistant-supervised-modified.deb ..."
        DEBIAN_FRONTEND=noninteractive MACHINE=odroid-n2 dpkg -i "${WORK_DIR}/homeassistant-supervised-modified.deb"
        
        # mark it manual install
        apt-mark manual "homeassistant-supervised"

        rm -rf "${WORK_DIR}/homeassistant-supervised-modified.deb"
        rm -rf "${WORK_DIR}/homeassistant-supervised"

        if [ -f "/lib/systemd/system/thirdreality-health-checker.service" ]; then
            /usr/bin/systemctl start thirdreality-health-checker.service
        fi 

        if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
            chmod 644 "/etc/systemd/system/hassio-supervisor.service"
        fi

        if [ -e "/etc/systemd/system/hassio-apparmor.service" ]; then
            chmod 644 "/etc/systemd/system/hassio-apparmor.service"
        fi
    else
        echo "No homeassistant-supervised.deb file found."        
    fi

    rm -rf /var/lib/apt/lists/*
}


# Function: Install Home Assistant related deb packages
install_core_and_matter_debs() {
    echo "Finding and installing Home Assistant related deb packages..."

    hacore_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore-config_*.deb" -type f | head -n 1)
    if [ -n "$hacore_config_deb_file" ]; then
        echo "Installing: $hacore_config_deb_file"
        DEBIAN_FRONTEND=noninteractive dpkg -i "$hacore_config_deb_file"

        # mark it manual install
        apt-mark manual "thirdreality-hacore-config"
    else
        echo "No hacore-config*.deb file found. exiting ..."
        return
    fi


    rm -rf /var/lib/apt/lists/*
}


# main procedure - 1
install_supervised_docker()
{
    echo "Starting Docker and Home Assistant installation..."
    local status=0  # 记录整体安装状态

    # LED Green blink
    /lib/thirdreality/hubv3-monitor.py set mqtt_paring || {
        echo "Warning: Failed to set LED to pairing mode" >&2
    }

    # 安装基础依赖包（即使失败也继续）
    if ! install_normal_debs; then
        echo "Warning: Failed to install normal dependencies" >&2
        status=1
    fi

    # 检查并安装Docker
    if ! check_docker_installed; then
        echo "Docker is not installed, starting Docker installation..."
        if ! install_docker_debs; then
            echo "Error: Docker installation failed" >&2
            status=1
        fi
    else
        echo "Docker is already installed, skipping Docker installation step"
    fi

    # 再次验证Docker状态
    if check_docker_installed; then
        echo "Docker is available, proceeding with image loading..."

        # 停止健康检查服务（如果存在）
        if [ -e "/lib/systemd/system/thirdreality-health-checker.service" ]; then
            /usr/bin/systemctl stop thirdreality-health-checker.service || {
                echo "Warning: Failed to stop health-checker service" >&2
            }
        fi

        # 加载Docker镜像（强制继续）
        if ! load_docker_images; then
            echo "Warning: Failed to load some Docker images" >&2
            status=1
        fi

        # 重启健康检查服务（如果之前停止了）
        if [ -e "/lib/systemd/system/thirdreality-health-checker.service" ]; then
            /usr/bin/systemctl start thirdreality-health-checker.service || {
                echo "Warning: Failed to restart health-checker service" >&2
            }
        fi

        # 显示当前镜像列表（无论是否加载成功）
        docker images 2>/dev/null || echo "Warning: Failed to list Docker images" >&2

        # 停止Supervisor服务（如果存在）
        if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
            systemctl stop hassio-supervisor.service || {
                echo "Warning: Failed to stop supervisor service" >&2
            }
        fi
    else
        echo "Error: Docker is not available, skipping image loading steps" >&2
        status=1
    fi

    # 安装HA相关包（即使之前步骤失败也继续尝试）
    echo "Attempting Home Assistant installation..."
    if ! install_ha_debs; then
        echo "Warning: Failed to install Home Assistant packages" >&2
        status=1
    fi

    # 最终状态报告
    if [ "$status" -eq 0 ]; then
        echo "Installation completed successfully!"
    else
        echo "Installation completed with warnings/errors (check logs)" >&2
    fi

    # LED恢复（无论成功与否都尝试）
    /lib/thirdreality/hubv3-monitor.py set mqtt_pared || {
        echo "Warning: Failed to restore LED status" >&2
    }
}

# main procedure - 2
install_core_matter_debs() {
    echo "Installing core matter debs..."

    /lib/thirdreality/hubv3-monitor.py set mqtt_paring || {
        echo "Warning: Failed to set LED to pairing mode" >&2
    }

    # 安装 hacore-config
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

    # 安装 python3
    python3_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "python_*.deb" -type f | head -n 1)
    if [ -n "$python3_deb_file" ]; then
        echo "Installing: $python3_deb_file"
        if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$python3_deb_file"; then
            echo "Warning: Failed to install $python3_deb_file" >&2
        else
            apt-mark manual "thirdreality-python3.13" || echo "Warning: Failed to mark python3.13 as manual" >&2
        fi
    else
        echo "Warning: No python3 deb file found in $WORK_DIR" >&2
    fi

    # 安装 hacore
    hacore_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore_*.deb" -type f | head -n 1)
    if [ -n "$hacore_deb_file" ]; then
        echo "Installing: $hacore_deb_file"
        if ! DEBIAN_FRONTEND=noninteractive dpkg -i "$hacore_deb_file"; then
            echo "Warning: Failed to install $hacore_deb_file" >&2
        else
            apt-mark manual "thirdreality-hacore" || echo "Warning: Failed to mark hacore as manual" >&2
        fi
    else
        echo "Warning: No hacore deb file found in $WORK_DIR" >&2
    fi

    # 重启健康检查服务（如果之前停止了）
    if [ -e "/lib/systemd/system/thirdreality-health-checker.service" ]; then
        /usr/bin/systemctl start thirdreality-health-checker.service || {
            echo "Warning: Failed to restart health-checker service" >&2
        }
    fi    

    # LED恢复（无论成功与否都尝试）
    /lib/thirdreality/hubv3-monitor.py set mqtt_pared || {
        echo "Warning: Failed to restore LED status" >&2
    }
}


# main procedure - 3
install_all_deb_images() {
    echo "Installing all deb images and loading Docker images..."
    local overall_status=0
    local deb_installed=0  # Track if any deb was installed

    # LED indication (continue on error)
    /lib/thirdreality/hubv3-monitor.py set mqtt_paring || {
        echo "Warning: Failed to set LED pairing mode" >&2
    }

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

    # 重启健康检查服务（如果之前停止了）
    if [ -e "/lib/systemd/system/thirdreality-health-checker.service" ]; then
        /usr/bin/systemctl start thirdreality-health-checker.service || {
            echo "Warning: Failed to restart health-checker service" >&2
        }
    fi

    # Final LED indication (always attempt)
    /lib/thirdreality/hubv3-monitor.py set mqtt_pared || {
        echo "Warning: Failed to restore LED status" >&2
        overall_status=1
    }

    return $overall_status
}

hacore_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hacore-config_*.deb" -type f | head -n 1)
is_home_assistant_running=$(systemctl is-active --quiet home-assistant.service && echo "yes" || echo "no")


if [[ -n "$hacore_config_deb_file" || "$is_home_assistant_running" == "yes" ]]; then
    install_core_matter_debs
else
    hassio_config_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "hassio-config_*.deb" -type f | head -n 1)
    
    is_hassio_supervisored_enabled=$(systemctl is-enabled --quiet hassio-supervisor.service && echo "yes" || echo "no")

    if [[ -n "$hassio_config_deb_file" || "$is_hassio_supervisored_enabled" == "yes" ]]; then
        install_supervised_docker
    else
        install_all_deb_images
    fi
fi


exit 0