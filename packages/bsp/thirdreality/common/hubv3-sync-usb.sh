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
        "os-agent_"
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


load_image_for_hassio_supervisor() {
    local tar_file=$1
    local repo=%2
    local tag=%3

    local result=1

    SUPERVISOR_IMAGE="ghcr.io/home-assistant/aarch64-hassio-supervisor"

    current_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo:" | awk -F ":" '{print $2}'| grep -v "^latest$")

    if [ -z "$current_version" ]; then
        echo "Install a new image [$tar_file]."
        docker load < "$tar_file" 2>&1 

        docker tag "${repo}:${tag}" "${repo}:latest"

        CONFIG_FILE="${CONFIG_DIR}/config.json"
        if [ -e "$CONFIG_FILE" ]; then
            sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
        fi

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
            result=0

            CONFIG_FILE="${CONFIG_DIR}/config.json"
            if [ -e "$CONFIG_FILE" ]; then
                sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
            fi

        else
            echo "Current image version [ $repo:$current_version ] is up-to-date or newer. skip current image tar."
        fi
    fi  
}



load_image_for_homeassistant() {
    local new_repo=$1
    local new_tag=%2
}


load_image_for_hassio_dns() {
    local new_repo=$1
    local new_tag=%2
}

load_image_for_hassio_cli() {
    local new_repo=$1
    local new_tag=%2
}


load_image_for_hassio_multicast() {
    local new_repo=$1
    local new_tag=%2
}


load_image_for_hassio_audio() {
    local new_repo=$1
    local new_tag=%2
}

load_image_for_hassio_observer() {
    local new_repo=$1
    local new_tag=%2
}

# # Stop container(s) running the current version, if any
# container_ids=$(docker ps -a --filter "ancestor=$repo:$current_version" --format "{{.ID}}")
# if [ ! -z "$container_ids" ]; then                   
#     docker stop $container_ids 2>/dev/null || true
#     docker rm -f $container_ids
# fi
# echo "Removing old image: [ $repo:$current_version ]"
# docker rmi "$repo:$current_version"  2>/dev/null

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

        # Load if the repo contains '-addon-', too complex, just load it!
        if [ "$repo" == *"-addon-"* ]; then
            echo "Loading addon image: [$tar_file]"

            docker load < "$tar_file" 

            # if [[ "$repo" == *"-addon-matter-server"* && -e "/usr/bin/ha" ]]; then
            #     if ! /usr/bin/ha addons core_matter_server update; then
            #         echo "Warning: Failed to update core_matter_server."
            #     fi
            # fi

            result=0
            continue
        fi
        
        if [[ "$repo" == *"hassio-supervisor"* ]]; then 
            load_image_for_hassio_supervisor ${tar_file} ${repo} ${tag}
        elif [[ "$repo" == *"homeassistant"* ]]; then
            load_image_for_homeassistant ${tar_file} ${repo} ${tag}
        elif [[ "$repo" == *"hassio-cli"* ]]; then
            load_image_for_hassio_cli ${tar_file} ${repo} ${tag}
        elif [[ "$repo" == *"hassio-audio"* ]]; then
            load_image_for_hassio_audio ${tar_file} ${repo} ${tag}
        elif [[ "$repo" == *"hassio-dns"* ]]; then
            load_image_for_hassio_dns ${tar_file} ${repo} ${tag}
        elif [[ "$repo" == *"hassio-multicast"* ]]; then   
            load_image_for_hassio_multicast ${tar_file} ${repo} ${tag}
        elif [[ "$repo" == *"hassio-observer"* ]]; then   
            load_image_for_hassio_observer ${tar_file} ${repo} ${tag}            
        fi

        # Get current image version if exists
        current_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo:" | awk -F ":" '{print $2}'| grep -v "^latest$")

        if [ -z "$current_version" ]; then
            echo "Install a new image [$tar_file]."
            docker load < "$tar_file" 2>&1 

            if [[ "$repo" == *"hassio-supervisor"* ]]; then
                docker tag "${repo}:${tag}" "${repo}:latest"
            fi

            result=0
        else
            echo "Found exist image, version [$current_version]"
            # Compare versions
            if [[ "$current_version" < "$tag" ]]; then
                echo "Found newer version for [$repo]"
                
                if [[ "$repo" == *"hassio-supervisor"* ]]; then
                    if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
                        systemctl stop hassio-supervisor.service
                    fi
                elif [[ "$repo" == *"homeassistant"* ]]; then
                    if [ ! -e "/usr/bin/ha" ]; then
                        /usr/bin/ha core stop
                    fi
                elif [[ "$repo" == *"hassio-cli"* ]]; then
                    echo "Updating [$repo]"
                elif [[ "$repo" == *"hassio-audio"* ]]; then
                    if [ ! -e "/usr/bin/ha" ]; then
                        /usr/bin/ha audio stop
                    fi
                elif [[ "$repo" == *"hassio-dns"* ]]; then
                    if [ ! -e "/usr/bin/ha" ]; then
                        /usr/bin/ha dns stop
                    fi
                elif [[ "$repo" == *"hassio-multicast"* ]]; then   
                    if [ ! -e "/usr/bin/ha" ]; then
                        /usr/bin/ha multicast stop
                    fi                                 
                fi

                # Stop container(s) running the current version, if any
                container_ids=$(docker ps -a --filter "ancestor=$repo:$current_version" --format "{{.ID}}")
                if [ ! -z "$container_ids" ]; then                   
                    docker stop $container_ids 2>/dev/null || true
                    docker rm -f $container_ids
                fi

                echo "Removing old image: [ $repo:$current_version ]"
                docker rmi "$repo:$current_version"  2>/dev/null
                
                echo "Check disk patition ..."
                df -h /var/lib/docker

                #OLD_IMAGE_ID=$(docker images --quiet "${repo}" | cut -c1-6)
                #if [ -n "${OLD_IMAGE_ID}" ]; then
                #    docker images -q --filter "dangling=true" | grep "^${OLD_IMAGE_ID}" | xargs -r docker rmi
                #fi                
                
                echo "Loading a new image [$tar_file]."
                docker load < "$tar_file" 2>&1 
                result=0

                if [[ "$repo" == *"hassio-supervisor"* ]]; then
                    # IMPORTANT: tag to latest
                    docker tag "${repo}:${tag}" "${repo}:latest"

                    CONFIG_FILE="${CONFIG_DIR}/config.json"
                    if [ -e "$CONFIG_FILE" ]; then
                        sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
                    fi

                    if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
                        # IMPORTANT
                        systemctl restart hassio-supervisor.service
                    fi
                elif [[ "$repo" == *"homeassistant"* ]]; then
                    CONFIG_FILE="${CONFIG_DIR}/homeassistant.json"
                    if [ -e "$CONFIG_FILE" ]; then
                        sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
                    fi
                elif [[ "$repo" == *"hassio-cli"* ]]; then
                    CONFIG_FILE="${CONFIG_DIR}/cli.json"
                    if [ -e "$CONFIG_FILE" ]; then
                        sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
                    fi

                    if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
                        # IMPORTANT: hassio-cli ~== /usr/bin/ha
                        systemctl restart hassio-supervisor.service
                    fi                   
                elif [[ "$repo" == *"hassio-audio"* ]]; then
                    CONFIG_FILE="${CONFIG_DIR}/audio.json"
                    if [ -e "$CONFIG_FILE" ]; then
                        sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
                    fi
                elif [[ "$repo" == *"hassio-dns"* ]]; then
                    CONFIG_FILE="${CONFIG_DIR}/dns.json"
                    if [ -e "$CONFIG_FILE" ]; then
                        sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
                    fi
                elif [[ "$repo" == *"hassio-multicast"* ]]; then
                    CONFIG_FILE="${CONFIG_DIR}/multicast.json"
                    if [ -e "$CONFIG_FILE" ]; then
                        sed -i "s/\"version\": \".*\"/\"version\": \"${tag}\"/" "$CONFIG_FILE"
                    fi
                fi
            else
                echo "Current image version [ $repo:$current_version ] is up-to-date or newer. skip current image tar."
            fi
        fi
    done

    # ha supervisor update
    # ha core update
    # ha addons core_matter_server update

    return $result
}

# Function: Install Home Assistant related deb packages
install_ha_debs() {
    echo "Finding and installing Home Assistant related deb packages..."

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
}

# Main program starts
echo "Starting Docker and Home Assistant installation..."

# LED Green blink
/lib/thirdreality/hubv3-monitor.py set mqtt_paring

#TODO
install_normal_debs

# Check if Docker is installed
if ! check_docker_installed; then
    echo "Docker is not installed, starting Docker installation..."
    install_docker_debs
else
    echo "Docker is already installed, skipping Docker installation step"
fi

# Check again if Docker is installed
if check_docker_installed; then
    echo "Docker installation successful, starting to load Docker images..."

    if [ -e "/lib/systemd/system/thirdreality-health-checker.service" ]; then
        /usr/bin/systemctl stop thirdreality-health-checker.service
    fi

    load_docker_images
    status=$?

    if [ -e "/lib/systemd/system/thirdreality-health-checker.service" ]; then
        /usr/bin/systemctl start thirdreality-health-checker.service
    fi

    if [ "$status" -eq 0 ]; then
        docker images
        #cleanup_old_images
        if [ -e "/etc/systemd/system/hassio-supervisor.service" ]; then
            systemctl stop hassio-supervisor.service
        fi
    else
        echo "Failed to load Docker images or none found."
    fi
else
    echo "Docker installation failed, cannot proceed with subsequent steps"
    /lib/thirdreality/hubv3-monitor.py set mqtt_pared
    exit 0
fi

# Install Home Assistant related deb packages
echo "Starting Home Assistant installation..."
install_ha_debs

echo "Installation complete!"

# LED Restore
/lib/thirdreality/hubv3-monitor.py set mqtt_pared
exit 0