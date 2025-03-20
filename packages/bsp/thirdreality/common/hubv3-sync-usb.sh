#!/bin/bash

# maintainer: guoping.liu@thirdreality.com

LC_ALL=en_US.UTF-8

DEBIAN_FRONTEND=noninteractive
APT_LISTCHANGES_FRONTEND=none
MACHINE=odroid-n2
TIMEOUT=1200

export LC_ALL DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND MACHINE

work_dir="/mnt"

while getopts "d:" opt; do
  case ${opt} in
    d )
      work_dir=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-d directory]"
      exit 1
      ;;
  esac
done

echo "Using directory: ${work_dir}"

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

    deb_files=$(find "$work_dir" -maxdepth 1 -name "*.deb" -type f)

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
        fi
    done

    # Attempt to fix any potential broken dependencies
    echo "Attempting to fix broken dependencies..."
    sudo apt-get install -f -y
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
        deb_file=$(find "$work_dir" -maxdepth 1 -name "$deb_pattern" -type f | head -n 1)
        
        if [ -n "$deb_file" ]; then
            echo "Installing: $deb_file"
            dpkg -i "$deb_file" || apt-get install -f -y
        else
            echo "Package not found: $deb_pattern"
        fi
    done
}

#!/bin/bash

# Function: Load Docker images
load_docker_images() {
    echo "Finding and loading Docker images..."
    local result=1

    # Find all .tar files, "-maxdepth 1" is very important, 
    # because you don't know what the users will place in the USB Stick
    tar_files=$(find "$work_dir" -maxdepth 1 -name "*.tar" -type f)
    
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
            echo "No 'repositories' file found in [ $tar_file ], skipping..."
            continue
        fi

        # Extract repository and tag from the JSON content
        repo=$(echo "$repositories" | jq -r 'keys[0]')
        tag=$(echo "$repositories" | jq -r '.[] | keys[0]')

        echo "Processing Current image: [ $tar_file ] --> $repo:$tag"

        if [ "$tag" == "latest" ]; then
            # latest is a tag, just skip it
            echo "Skip image: [ $tar_file ] with tag 'latest'"
            continue
        fi        

        # Load if the repo contains '-addon-'
        if [ "$repo" == *"-addon-"* ]; then
            echo "Loading addon image: [ $tar_file ]"
            docker load -i "$tar_file"

            result=0
            continue
        fi
        
        # Get current image version if exists
        current_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repo:" | awk -F ":" '{print $2}')
        
        if [ -z "$current_version" ]; then
            echo "No existing image found for [ $repo ], loading a new image."
            docker load -i "$tar_file"
            if [[ "$repo" == *"hassio-supervisor"* ]]; then
                docker tag "${repo}:${tag}" "${repo}:latest"
            fi

            result=0
        else
            echo "Found exist image, version $current_version "
            # Compare versions
            if [[ "$current_version" < "$tag" ]]; then
                echo "Found newer version for [ $repo ], loading a new image..."
                
                # Stop container(s) running the current version, if any
                container_ids=$(docker ps --filter "ancestor=$repo:$current_version" --format "{{.ID}}")
                if [ ! -z "$container_ids" ]; then
                    echo "Stopping containers: $container_ids"
                    docker stop $container_ids
                fi
                
                # Load the new image
                docker load -i "$tar_file"
                result=0

                # Remove the old image
                echo "Removing old image: [ $repo:$current_version ]"
                docker rmi "$repo:$current_version"

                # Update version in configuration files if necessary
                if [[ "$repo" == *"hassio-supervisor"* ]]; then
                    docker tag "${repo}:${tag}" "${repo}:latest"
                    if [ -e "/var/lib/homeassistant/config.json" ]; then
                        echo "Updating version in /var/lib/homeassistant/config.json"
                        sed -i "s/\"version\": \".*\"/\"version\": \"$current_version\"/" /var/lib/homeassistant/config.json

                        if [ -e "/usr/bin/ha" ]; then
                            echo "Restart hassio-supervisor ..."
                            /usr/bin/ha supervisor restart || {
                                echo "Warning: Failed to restart hassio-supervisor."
                            }
                        fi
                    fi
                elif [[ "$repo" == *"homeassistant"* ]]; then
                    if [ -e "/var/lib/homeassistant/homeassistant.json" ]; then
                        echo "Updating version in /var/lib/homeassistant/homeassistant.json"
                        sed -i "s/\"version\": \".*\"/\"version\": \"$current_version\"/" /var/lib/homeassistant/homeassistant.json

                        if [ -e "/usr/bin/ha" ]; then
                            echo "Restart homeassistant ..."
                            /usr/bin/ha core restart || {
                                echo "Warning: Failed to restart homeassistant."
                            }
                        fi
                    fi
                elif [[ "$repo" == *"hassio-audio"* ]]; then

                    if [ -e "/usr/bin/ha" ]; then
                        /usr/bin/ha audio restart || {
                            echo "Warning: Failed to restart hassio-audio."
                        }
                    fi
                elif [[ "$repo" == *"hassio-dns"* ]]; then

                    if [ -e "/usr/bin/ha" ]; then
                        /usr/bin/ha dns restart || {
                            echo "Warning: Failed to restart hassio-dns."
                        }
                    fi
                elif [[ "$repo" == *"hassio-multicast"* ]]; then

                    if [ -e "/usr/bin/ha" ]; then
                        /usr/bin/ha multicast restart || {
                            echo "Warning: Failed to restart hassio-multicast."
                        }
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

# Function: Clean up old versions of Docker images
cleanup_old_images() {
    echo "Cleaning up old versions of Docker images..."
    
    # Define repositories to check
    repositories=(
        "ghcr.io/home-assistant/odroid-n2-homeassistant"
        "ghcr.io/home-assistant/aarch64-hassio-supervisor"
        "homeassistant/aarch64-addon-matter-server"
        "ghcr.io/home-assistant/aarch64-hassio-dns"
        "ghcr.io/home-assistant/aarch64-hassio-cli"
        "ghcr.io/home-assistant/aarch64-hassio-multicast"
        "ghcr.io/home-assistant/aarch64-hassio-audio"
        "ghcr.io/home-assistant/aarch64-hassio-observer"
    )
    
    for repo in "${repositories[@]}"; do
        echo "Checking repository: $repo"
        
        # Get all image IDs and tags for this repository
        images=$(docker images --format "{{.ID}} {{.Repository}}:{{.Tag}}" | grep "^[^ ]* $repo:" || true)
        
        if [ -z "$images" ]; then
            echo "  No images found for $repo"
            continue
        fi
        
        # Extract unique image IDs
        image_ids=$(echo "$images" | awk '{print $1}' | sort | uniq)
        
        # If only one image ID, no need to clean up
        if [ $(echo "$image_ids" | wc -l) -le 1 ]; then
            echo "  $repo has only one version, no cleanup needed"
            continue
        fi
        
        echo "  Multiple versions of $repo found, keeping the latest version"
        
        # Get the latest version image ID (assuming tags are sorted alphabetically, latest is last)
        latest_id=$(echo "$images" | sort -k2 | tail -n1 | awk '{print $1}')
        
        # Delete old versions
        for id in $image_ids; do
            if [ "$id" != "$latest_id" ]; then
                echo "  Deleting old version image: $id"
                docker rmi $id || true
            fi
        done
    done
}

# Function: Install Home Assistant related deb packages
install_ha_debs() {
    echo "Finding and installing Home Assistant related deb packages..."

    os_agent_deb_file=$(find "$work_dir" -maxdepth 1 -name "os-agent_*.deb" -type f | head -n 1)
    if [ -n "$os_agent_deb_file" ]; then
        echo "Installing: $os_agent_deb_file"
        DEBIAN_FRONTEND=noninteractive dpkg -i "$os_agent_deb_file"
    else
        echo "No os-agent.deb file found."
    fi

    if [ -e "/usr/bin/ha" ]; then
        echo "homeassistant-supervised is already installed, skipping homeassistant-supervised installation step"
        return
    fi

    supervised_deb_file=$(find "$work_dir" -maxdepth 1 -name "homeassistant-supervised*.deb" -type f | head -n 1)
    if [ -n "${supervised_deb_file}" ]; then
        echo "Installing: $supervised_deb_file"

        rm -rf "${work_dir}/homeassistant-supervised/"

        echo "Updating: $supervised_deb_file"

        dpkg-deb -R ${supervised_deb_file} "${work_dir}/homeassistant-supervised/"

        #/etc/NetworkManager/NetworkManager.conf, fixed it for W155S1 driver.
        TARGET_FILE="${work_dir}/homeassistant-supervised/DEBIAN/postinst"
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

        dpkg-deb -b "${work_dir}/homeassistant-supervised" "${work_dir}/homeassistant-supervised-modified.deb"

        echo "Install ${work_dir}/homeassistant-supervised-modified.deb ..."
        DEBIAN_FRONTEND=noninteractive MACHINE=odroid-n2 dpkg -i "${work_dir}/homeassistant-supervised-modified.deb"

        rm -rf "${work_dir}/homeassistant-supervised-modified.deb"
        rm -rf "${work_dir}/homeassistant-supervised"

        if [ -f "/lib/systemd/system/thirdreality-health-checker.service" ]; then
            /usr/bin/systemctl start thirdreality-health-checker.service
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
        cleanup_old_images
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