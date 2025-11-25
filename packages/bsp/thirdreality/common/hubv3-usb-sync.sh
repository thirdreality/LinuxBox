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

DEBUG_ZHA_DIR="/mnt/R3Debug/zha_quirks"
DEBUG_Z2M_DIR="/mnt/R3Debug/z2m_converters"
DEBUG_OTA_DIR="/mnt/R3Debug/zigpy_local_ota"
DEBUG_FIRMWARE_DIR="/mnt/R3Debug/firmware"

CONFIG_DIR="/var/lib/homeassistant"

set -e

# Ensure lock file is removed when script exits,
# and perform additional error handling

on_exit() {
    local exit_code=$?
    
    # Remove the lock file
    #rm -f "${LOCKFILE}"
    
    # Custom actions before the script exits
    echo "Running cleanup tasks..."
    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led clear || true
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
    
    "openhab_"
    
    "linux-image-current-meson64_"
)


update_z2m_quirks_for_debug()
{
    if [ ! -d "$DEBUG_Z2M_DIR" ]; then
        echo 0 >&2
        echo 0
        return 0
    fi

    # Check js file count
    local js_files_count=$(find "$DEBUG_Z2M_DIR" -maxdepth 1 -name "*.js" -type f | wc -l)

    # If js file count is 1 or less, do nothing
    if [ "$js_files_count" -le 1 ]; then
        echo 0 >&2
        echo 0
        return 0
    fi

    local target_dir="/opt/zigbee2mqtt/data/external_converters"
    
    # Check if Z2M data directory exists
    local z2m_data_dir="/opt/zigbee2mqtt/data"
    if [ ! -d "$z2m_data_dir" ]; then
        echo "[DEBUG-Z2M] Zigbee2MQTT data directory not found: $z2m_data_dir" >&2
        echo 0 >&2
        echo 0
        return 0
    fi
    
    echo "[DEBUG-Z2M] Found $js_files_count *.js files in $DEBUG_Z2M_DIR" >&2
    echo "[DEBUG-Z2M] Copying *.js files to: $target_dir" >&2
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Copy all js files to target directory
    find "$DEBUG_Z2M_DIR" -maxdepth 1 -name "*.js" -type f -exec cp {} "$target_dir"/ \;

    echo "[DEBUG-Z2M] z2m converters sync completed, total js files: $js_files_count" >&2
    
    # Return total js file count
    echo "$js_files_count"
    return 0
}

update_zha_quirks_for_debug()
{
    # If $DEBUG_ZHA_DIR exists, copy all *.py files under it to
    # /var/lib/homeassistant/homeassistant/zha_quirks.
    # Proceed only if the target directory exists.
    if [ ! -d "$DEBUG_ZHA_DIR" ]; then
        echo 0 >&2
        echo 0
        return 0
    fi

    # Check how many *.py files are in $DEBUG_ZHA_DIR directory
    local py_files_count=$(find "$DEBUG_ZHA_DIR" -maxdepth 1 -name "*.py" -type f | wc -l)
    
    if [ "$py_files_count" -eq 0 ]; then
        #echo "[DEBUG-ZHA] No *.py files found in $DEBUG_ZHA_DIR, skipping"
        echo 0 >&2
        echo 0
        return 0
    fi

    echo "[DEBUG-ZHA] Found $py_files_count *.py files in $DEBUG_ZHA_DIR" >&2

    # Set the target directory to the new path
    local zha_target_dir="/var/lib/homeassistant/homeassistant/zha_quirks"
    
    # Create target directory if it doesn't exist
    mkdir -p "$zha_target_dir"

    echo "[DEBUG-ZHA] Copying *.py files to: $zha_target_dir" >&2
    # Copy all *.py files to target directory
    find "$DEBUG_ZHA_DIR" -maxdepth 1 -name "*.py" -type f -exec cp {} "$zha_target_dir"/  \;

    # Update Home Assistant configuration
    local ha_cfg="/var/lib/homeassistant/homeassistant/configuration.yaml"
    if [ ! -f "$ha_cfg" ]; then
        echo "[DEBUG-ZHA] Home Assistant configuration file not found: $ha_cfg" >&2
        echo "$py_files_count"
        return 0
    fi

    # Check if custom_quirks_path configuration already exists with the correct path
    if grep -qE "custom_quirks_path:" "$ha_cfg"; then
        # Check if the path is correct
        if grep -qE "custom_quirks_path:.*zha_quirks" "$ha_cfg"; then
            echo "[DEBUG-ZHA] ZHA configuration already exists with correct custom_quirks_path in $ha_cfg" >&2
        else
            # Path exists but is different, update it
            echo "[DEBUG-ZHA] ZHA configuration exists but with different custom_quirks_path, updating..." >&2
            # Create a backup
            cp "$ha_cfg" "$ha_cfg.backup.$(date +%Y%m%d_%H%M%S)" || true
            # Update the path using sed
            sed -i 's|custom_quirks_path:.*|custom_quirks_path: /var/lib/homeassistant/homeassistant/zha_quirks|g' "$ha_cfg"
            echo "[DEBUG-ZHA] Updated custom_quirks_path to correct value" >&2
        fi
    else
        # Need to add custom_quirks_path configuration
        echo "[DEBUG-ZHA] Adding ZHA quirks configuration to $ha_cfg" >&2
        
        # Check if zha: section already exists
        if grep -qE "^[[:space:]]*zha:" "$ha_cfg"; then
            # zha: section exists, append quirks config under it
            # Create a backup
            cp "$ha_cfg" "$ha_cfg.backup.$(date +%Y%m%d_%H%M%S)" || true
            
            # Find the line number of zha: and insert quirks config after it
            # Use awk to add the configuration with proper indentation
            awk '/^[[:space:]]*zha:/ && !done { print; print "  enable_quirks: true"; print "  custom_quirks_path: /var/lib/homeassistant/homeassistant/zha_quirks"; done=1; next } 1' "$ha_cfg" > "$ha_cfg.tmp" && mv "$ha_cfg.tmp" "$ha_cfg"
            echo "[DEBUG-ZHA] Added quirks configuration to existing zha: section" >&2
        else
            # zha: section doesn't exist, create new one
            {
                echo ""
                echo "zha:"
                echo "  enable_quirks: true"
                echo "  custom_quirks_path: /var/lib/homeassistant/homeassistant/zha_quirks"
            } >> "$ha_cfg"
            echo "[DEBUG-ZHA] Created new zha: section with quirks configuration" >&2
        fi
    fi

    echo "[DEBUG-ZHA] zhaquirks sync completed" >&2
    
    # Output total *.py file count and return 0
    echo "$py_files_count"
    return 0
}

# Helper function: Update ZHA OTA configuration
update_zha_ota_config()
{
    local updated=0
    
    if [ ! -f "$DEBUG_OTA_DIR/local_index.json" ]; then
        echo "$updated"
        return 0
    fi

    echo "[DEBUG-OTA-ZHA] Found local_index.json in $DEBUG_OTA_DIR" >&2

    local ota_dir="/var/lib/homeassistant/homeassistant/zigpy_local_ota"
    mkdir -p "$ota_dir"
    
    # Copy local_index.json
    if install -m 0644 "$DEBUG_OTA_DIR/local_index.json" "$ota_dir/local_index.json"; then
        updated=1
        echo "[DEBUG-OTA-ZHA] Successfully copied local_index.json to $ota_dir" >&2
    else
        echo "[DEBUG-OTA-ZHA] Failed to copy local_index.json" >&2
    fi
    
    # Copy all *.ota files
    shopt -s nullglob
    local ota_files_count=0
    for f in "$DEBUG_OTA_DIR"/*.ota; do
        install -m 0644 "$f" "$ota_dir/"
        ota_files_count=$((ota_files_count + 1))
    done
    shopt -u nullglob

    if [ "$ota_files_count" -gt 0 ]; then
        echo "[DEBUG-OTA-ZHA] Copied $ota_files_count *.ota files to $ota_dir" >&2
    fi

    # Update Home Assistant configuration
    local ha_cfg="/var/lib/homeassistant/homeassistant/configuration.yaml"
    if [ ! -f "$ha_cfg" ]; then
        echo "[DEBUG-OTA-ZHA] Home Assistant configuration file not found: $ha_cfg" >&2
        echo "$updated"
        return 0
    fi

    # Check if OTA providers are already configured
    if grep -qE "extra_providers.*zigpy_local|index_file:.*zigpy_local_ota" "$ha_cfg"; then
        echo "[DEBUG-OTA-ZHA] ZHA OTA providers already configured in $ha_cfg" >&2
        echo "$updated"
        return 0
    fi

    echo "[DEBUG-OTA-ZHA] Adding local OTA providers for ZHA to $ha_cfg" >&2
    
    # Create a backup
    cp "$ha_cfg" "$ha_cfg.backup.$(date +%Y%m%d_%H%M%S)" || true
    
    # Check if zha: section already exists
    if grep -qE "^[[:space:]]*zha:" "$ha_cfg"; then
        # zha: section exists, append OTA config under it
        awk '
        /^[[:space:]]*zha:/ && !done {
            print
            print "  zigpy_config:"
            print "    ota:"
            print "      extra_providers:"
            print "        - type: zigpy_local"
            print "          index_file: '"$ota_dir"'/local_index.json"
            done=1
            next
        }
        { print }
        ' "$ha_cfg" > "$ha_cfg.tmp" && mv "$ha_cfg.tmp" "$ha_cfg"
        
        echo "[DEBUG-OTA-ZHA] Added OTA configuration to existing zha: section" >&2
    else
        # zha: section doesn't exist, create new one
        {
            echo ""
            echo "zha:"
            echo "  zigpy_config:"
            echo "    ota:"
            echo "      extra_providers:"
            echo "        - type: zigpy_local"
            echo "          index_file: $ota_dir/local_index.json"
        } >> "$ha_cfg"
        echo "[DEBUG-OTA-ZHA] Created new zha: section with OTA configuration" >&2
    fi

    echo "[DEBUG-OTA-ZHA] ZHA OTA configuration updated successfully" >&2
    echo "$updated"
    return 0
}

# Helper function: Update Z2M OTA configuration
update_z2m_ota_config()
{
    local updated=0
    
    if [ ! -f "$DEBUG_OTA_DIR/local_z2m_index.json" ]; then
        echo "$updated"
        return 0
    fi

    echo "[DEBUG-OTA-Z2M] Found local_z2m_index.json in $DEBUG_OTA_DIR" >&2

    local z2m_data_dir="/opt/zigbee2mqtt/data"
    local z2m_cfg="$z2m_data_dir/configuration.yaml"
    
    # Check if Z2M data directory exists
    if [ ! -d "$z2m_data_dir" ]; then
        echo "[DEBUG-OTA-Z2M] Zigbee2MQTT data directory not found: $z2m_data_dir" >&2
        echo "$updated"
        return 0
    fi
    
    # Copy local_z2m_index.json to Z2M data directory
    if [ -f "$DEBUG_OTA_DIR/local_z2m_index.json" ]; then
        cp "$DEBUG_OTA_DIR/local_z2m_index.json" "$z2m_data_dir/"
        echo "[DEBUG-OTA-Z2M] Copied local_z2m_index.json to $z2m_data_dir" >&2
        updated=1
    else
        echo "[DEBUG-OTA-Z2M] local_z2m_index.json not found in $DEBUG_OTA_DIR" >&2
        echo "$updated"
        return 0
    fi
    
    # Copy all *.ota files to Z2M data directory
    local ota_files_copied=0
    shopt -s nullglob
    for f in "$DEBUG_OTA_DIR"/*.ota; do
        if [ -f "$f" ]; then
            cp "$f" "$z2m_data_dir/"
            ota_files_copied=$((ota_files_copied + 1))
        fi
    done
    shopt -u nullglob
    
    if [ "$ota_files_copied" -gt 0 ]; then
        echo "[DEBUG-OTA-Z2M] Copied $ota_files_copied *.ota files to $z2m_data_dir" >&2
    fi
    
    # Update Z2M configuration.yaml if it exists
    if [ -f "$z2m_cfg" ]; then
        # Check if zigbee_ota_override_index_location is already configured
        if grep -qE "zigbee_ota_override_index_location:" "$z2m_cfg"; then
            echo "[DEBUG-OTA-Z2M] Z2M OTA override index already configured in $z2m_cfg" >&2
            echo "$updated"
            return 0
        fi
        
        echo "[DEBUG-OTA-Z2M] Adding OTA configuration to $z2m_cfg" >&2
        
        # Create a backup
        cp "$z2m_cfg" "$z2m_cfg.backup.$(date +%Y%m%d_%H%M%S)" || true
        
        # Check if ota: section exists
        if grep -qE "^[[:space:]]*ota:" "$z2m_cfg"; then
            # ota: section exists, add zigbee_ota_override_index_location under it
            awk '
            /^[[:space:]]*ota:/ && !done {
                print
                getline
                if ($0 !~ /zigbee_ota_override_index_location:/) {
                    print "  zigbee_ota_override_index_location: local_z2m_index.json"
                }
                print
                done=1
                next
            }
            { print }
            ' "$z2m_cfg" > "$z2m_cfg.tmp" && mv "$z2m_cfg.tmp" "$z2m_cfg"
            
            echo "[DEBUG-OTA-Z2M] Added OTA override index to existing ota: section" >&2
        else
            # ota: section doesn't exist, create new one
            {
                echo "ota:"
                echo "  zigbee_ota_override_index_location: local_z2m_index.json"
            } >> "$z2m_cfg"
            echo "[DEBUG-OTA-Z2M] Created new ota: section with override index configuration" >&2
        fi
    else
        echo "[DEBUG-OTA-Z2M] Z2M configuration.yaml not found: $z2m_cfg, skipping configuration update" >&2
    fi
    
    echo "[DEBUG-OTA-Z2M] Z2M OTA configuration updated successfully" >&2
    echo "$updated"
    return 0
}

# Main OTA update function
update_ota_for_debug()
{
    local total_updated=0
    
    if [ ! -d "$DEBUG_OTA_DIR" ]; then
        echo 0 >&2
        echo 0
        return 0
    fi

    # Update ZHA OTA configuration
    local zha_updated
    zha_updated=$(update_zha_ota_config)
    total_updated=$((total_updated + zha_updated))
    
    # Update Z2M OTA configuration
    local z2m_updated
    z2m_updated=$(update_z2m_ota_config)
    total_updated=$((total_updated + z2m_updated))
    
    echo "$total_updated" >&2
    echo "$total_updated"
    return 0
}

update_firmware_for_debug()
{
    if [ ! -d "$DEBUG_FIRMWARE_DIR" ]; then
        return 0
    fi

    local fw_dir="/usr/lib/firmware/bl706/partition_1m_images"
    local flasher_bin="/usr/lib/firmware/bl706/bl706_func.sh"

    # Handle Zigbee firmware
    if [ -f "$DEBUG_FIRMWARE_DIR/blz_whole_img.bin" ]; then
        echo "[DEBUG-FW] Update Zigbee firmware image"

        if [ -e "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor led sys_firmware_updating  || true
        fi

        install -m 0644 "$DEBUG_FIRMWARE_DIR/blz_whole_img.bin" "$fw_dir/blz_whole_img.bin"

        local ha_running="no"
        local z2m_running="no"
        systemctl is-active --quiet home-assistant.service && ha_running="yes" || true
        systemctl is-active --quiet zigbee2mqtt.service && z2m_running="yes" || true

        if [ "$ha_running" = "yes" ]; then
            echo "[DEBUG-FW] Stopping Home Assistant service for Zigbee firmware update..." >&2
            systemctl stop home-assistant.service || true
        fi
        if [ "$z2m_running" = "yes" ]; then
            echo "[DEBUG-FW] Stopping Zigbee2MQTT service for Zigbee firmware update..." >&2
            systemctl stop zigbee2mqtt.service || true
        fi

        if [ -x "$flasher_bin" ]; then
            "$flasher_bin" flash blz || true
        else
            echo "[DEBUG-FW][WARN] Flasher binary not found or not executable: $flasher_bin" >&2
        fi

        if [ -x "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor zigbee info || true
        fi

        if [ "$ha_running" = "yes" ]; then
            echo "[DEBUG-FW] Starting Home Assistant service after Zigbee firmware update..." >&2
            systemctl start home-assistant.service || true
        fi
        if [ "$z2m_running" = "yes" ]; then
            echo "[DEBUG-FW] Starting Zigbee2MQTT service after Zigbee firmware update..." >&2
            systemctl start zigbee2mqtt.service || true
        fi
    fi

    # Handle Thread firmware
    if [ -f "$DEBUG_FIRMWARE_DIR/thread_whole_img.bin" ]; then
        echo "[DEBUG-FW] Update Thread firmware image"
        
        if [ -e "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor led sys_firmware_updating  || true
        fi

        install -m 0644 "$DEBUG_FIRMWARE_DIR/thread_whole_img.bin" "$fw_dir/thread_whole_img.bin"

        local otbr_running="no"
        systemctl is-active --quiet otbr-agent.service && otbr_running="yes" || true

        if [ "$otbr_running" = "yes" ]; then
            echo "[DEBUG-FW] Stopping OTBR agent service for Thread firmware update..." >&2
            systemctl stop otbr-agent.service || true
        fi

        if [ -x "$flasher_bin" ]; then
            "$flasher_bin" flash thread || true
        else
            echo "[DEBUG-FW][WARN] Flasher binary not found or not executable: $flasher_bin" >&2
        fi

        if [ -x "/usr/local/bin/supervisor" ]; then
            /usr/local/bin/supervisor thread info || true
        fi

        if [ "$otbr_running" = "yes" ]; then
            echo "[DEBUG-FW] Starting OTBR agent service after Thread firmware update..." >&2
            systemctl start otbr-agent.service || true
        fi
    fi
}

update_etc_for_install()
{
    local debug_etc_dir="${WORK_DIR}/etc"
    
    # Check if directory exists
    if [ ! -d "$debug_etc_dir" ]; then
        return 0
    fi
    
    # Check if there are files in the directory (excluding subdirectories)
    local files_count=$(find "$debug_etc_dir" -maxdepth 1 -type f | wc -l)
    
    if [ "$files_count" -eq 0 ]; then
        echo "[DEBUG-ETC] No files found in $debug_etc_dir, skipping" >&2
        return 0
    fi
    
    echo "[DEBUG-ETC] Found $files_count file(s) in $debug_etc_dir" >&2
    echo "[DEBUG-ETC] Copying files to /etc..." >&2
    
    # Copy all files to /etc directory
    if cp -f "$debug_etc_dir"/* /etc/ 2>/dev/null; then
        echo "[DEBUG-ETC] Successfully copied all files to /etc" >&2
    else
        echo "[DEBUG-ETC] Failed to copy files to /etc" >&2
        return 1
    fi
    
    return 0
}


update_blueprints_for_debug()
{
    local bp_root="${DEBUG_DIR}/blueprints"
    local ha_bp_root="/var/lib/homeassistant/homeassistant/blueprints"

    if [ ! -d "$bp_root" ]; then
        return 0
    fi

    mkdir -p "$ha_bp_root"

    # Helper: copy a category (automation/script)
    copy_bp_category() {
        local category="$1"
        local src_dir="$bp_root/$category"
        local dst_dir="$ha_bp_root/$category"

        if [ ! -d "$src_dir" ]; then
            return 0
        fi

        # Count total files under src_dir; skip if empty
        local total_files
        total_files=$(find "$src_dir" -type f | wc -l)
        if [ "$total_files" -eq 0 ]; then
            return 0
        fi

        mkdir -p "$dst_dir"

        echo "[DEBUG-BP] Syncing blueprints category '$category' from $src_dir -> $dst_dir (files=$total_files)" >&2

        # 1) Copy files directly under category
        find "$src_dir" -mindepth 1 -maxdepth 1 -type f -name "*.y*ml" -print0 2>/dev/null | xargs -0r -I{} cp "{}" "$dst_dir/" || true

        # 2) Copy non-empty immediate subdirectories under category
        local subdir
        while IFS= read -r subdir; do
            [ -z "$subdir" ] && continue
            local sc
            sc=$(find "$subdir" -type f | wc -l)
            if [ "$sc" -gt 0 ]; then
                echo "[DEBUG-BP] Copying blueprint dir: $subdir -> $dst_dir" >&2
                cp -r "$subdir" "$dst_dir/" || true
            fi
        done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
    }

    # Prefer structured categories if present
    copy_bp_category automation
    copy_bp_category script

    # If there are legacy subdirectories directly under blueprints/, copy them to root
    # to maintain backward compatibility
    local legacy_dirs
    legacy_dirs=$(find "$bp_root" -mindepth 1 -maxdepth 1 -type d \( -name automation -o -name script \) -prune -o -type d -print 2>/dev/null | tr '\n' '\n')
    if [ -n "$legacy_dirs" ]; then
        local d
        while IFS= read -r d; do
            [ -z "$d" ] && continue
            local lc
            lc=$(find "$d" -type f | wc -l)
            if [ "$lc" -gt 0 ]; then
                echo "[DEBUG-BP] Copying legacy blueprint dir: $d -> $ha_bp_root" >&2
                cp -r "$d" "$ha_bp_root/" || true
            fi
        done <<EOF
$legacy_dirs
EOF
    fi

    return 0
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

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_firmware_updating  || true
    fi    

    current_version=$(dpkg-query -W -f='${Version}\n' "${package_name}" 2>/dev/null || true)    
    if [ -n "$current_version" ]; then
        deb_version=$(dpkg-deb --info "${deb_file}" | grep Version | awk '{print $2}')
        
        echo "${package_name} is installed (version: ${current_version}), deb version: ${deb_version}"
        
        if dpkg --compare-versions "$deb_version" gt "$current_version"; then
            echo "+ ${deb_file}. " | wall
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
        echo "+ ${deb_file}. " | wall
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
        update_firmware_for_debug
        return 0
    fi

    echo "Attempting to install board firmware debs..."

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/local/bin/supervisor led sys_firmware_updating  || true
    fi

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
        # Legacy compatibility: If installation is successful, install dependencies
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

install_linux_image_deb() {
    if [ ! -d "$WORK_DIR" ]; then
        return 0
    fi

    echo "Attempting to install linux-image kernel deb..."

    # Find linux-image deb file
    linux_image_deb_file=$(find "$WORK_DIR" -maxdepth 1 -name "linux-image-current-meson64_*.deb" -type f | head -n 1)
    
    if [ -n "$linux_image_deb_file" ]; then
        echo "Found linux-image deb: $linux_image_deb_file"
        
        # Get deb version number
        deb_version=$(dpkg-deb --info "${linux_image_deb_file}" | grep Version | awk '{print $2}')
        echo "Linux-image deb version: $deb_version"
        
        local need_reboot=false
        
        # Check if already installed
        if dpkg -l | grep -q "^ii\s*linux-image-current-meson64"; then
            # Get installed version number
            installed_version=$(dpkg-query -W -f='${Version}\n' "linux-image-current-meson64" 2>/dev/null || true)
            echo "Installed version: $installed_version"
            
            # Compare version numbers, install if deb version is greater than installed version
            if dpkg --compare-versions "$deb_version" gt "$installed_version"; then
                echo "Newer kernel version available. Installing: $linux_image_deb_file"
                if DEBIAN_FRONTEND=noninteractive dpkg -i "$linux_image_deb_file"; then
                    echo "Kernel installation completed."
                    apt-mark manual "linux-image-current-meson64" || echo "Warning: Failed to mark kernel as manual" >&2
                    need_reboot=true
                else
                    echo "Warning: Failed to install $linux_image_deb_file" >&2
                fi
            else
                echo "Installed kernel version is up-to-date. No installation needed."
            fi
        else
            # Not installed before, install directly
            echo "linux-image-current-meson64 is not installed. Installing: $linux_image_deb_file"
            if DEBIAN_FRONTEND=noninteractive dpkg -i "$linux_image_deb_file"; then
                echo "Kernel installation completed."
                apt-mark manual "linux-image-current-meson64" || echo "Warning: Failed to mark kernel as manual" >&2
                need_reboot=true
            else
                echo "Warning: Failed to install $linux_image_deb_file" >&2
            fi
        fi
        
        # If kernel was installed, sync multiple times and reboot
        if [ "$need_reboot" = true ]; then
            echo "Kernel updated, preparing to reboot system..."
            echo "Syncing filesystem multiple times to ensure NAND cache is flushed..."
            
            # Multiple sync calls to handle NAND cache issues
            for i in {1..5}; do
                echo "Sync $i/5..."
                /usr/bin/sync
                sleep 1
            done
            
            echo "Filesystem sync completed. Rebooting system in 3 seconds..."
            sleep 3
            /sbin/reboot
            exit 0
        fi
    else
        echo "No linux-image deb file found in $WORK_DIR"
    fi
    
    return 0
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

is_backup_capable() {
    if dpkg -l | grep -q "^ii\s*thirdreality-hacore"; then
        return 0
    fi
    if dpkg -l | grep -q "^ii\s*thirdreality-zigbee-mqtt"; then
        return 0
    fi
    return 1
}

perform_backup_if_ready() {
    local backup_dir="/mnt/R3Backup"
    local flag_primary="$backup_dir/.enable-backup"
    local flag_alt="$backup_dir/.enable_backup"

    if [ ! -d "$backup_dir" ] || [ ! -x "/usr/local/bin/supervisor" ]; then
        return 0
    fi

    if [ ! -f "$flag_primary" ] && [ ! -f "$flag_alt" ]; then
        return 0
    fi

    if is_backup_capable; then
        /usr/local/bin/supervisor led clear || true
        echo "Found .enable-backup flag, forcing backup..."
        echo "System found .enable-backup flag, forcing backup..." | wall
        /usr/local/bin/supervisor setting backup || true
        rm -f "$flag_primary" "$flag_alt"
        echo "Backup completed, .enable-backup flag removed"
        /usr/local/bin/supervisor led clear || true
    else
        echo "Backup flag detected but required packages not installed; deferring backup."
    fi
}

validate_config() {
    local backup_dir="/mnt/R3Backup"
    local flag_primary="$backup_dir/.enable-backup"
    local flag_alt="$backup_dir/.enable_backup"

    if [ ! -d "$backup_dir" ]; then
        return 0
    fi

    if [ ! -f "$flag_primary" ] && [ ! -f "$flag_alt" ]; then
        return 0
    fi

    if is_backup_capable; then
        return 0
    fi

    echo "Warning: Backup flag present but required packages are missing. Removing flag..."
    rm -f "$flag_primary" "$flag_alt"
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
    perform_backup_if_ready

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
        #install_zigpy_handler_debs
    fi

    # install all debs, leaving room for future upgrades
    install_extra_debs

    if [ -e "/usr/local/bin/supervisor" ]; then
        /usr/bin/sync
        /usr/local/bin/supervisor led clear || true
    fi

    # Auto restore functionality
    if [ -d "/mnt/R3Backup" ] && [ -e "/usr/local/bin/supervisor" ]; then
        perform_backup_if_ready
        
        # Check if .enable-restore exists - force restore if flag is present
        if [ -f "/mnt/R3Backup/.enable-restore" ] || [ -f "/mnt/R3Backup/.enable_restore" ]; then
            setting_files=$(find "/mnt/R3Backup" -maxdepth 1 -name "setting_*.tar.gz" -type f 2>/dev/null || true)
            if [ -n "$setting_files" ]; then
                /usr/local/bin/supervisor led sys_firmware_updating  || true
                echo "Found .enable-restore flag, attempting to restore..."
                echo "System found .enable-restore flag, attempting to restore..." | wall
                /usr/local/bin/supervisor setting restore || true
                /usr/local/bin/supervisor led clear || true
                echo "Restore completed, .enable-restore flag removed"
                rm -f "/mnt/R3Backup/.enable-restore" "/mnt/R3Backup/.enable_restore"
            else
                echo "Warning: .enable-restore flag found but no setting files available"
                rm -f "/mnt/R3Backup/.enable-restore" "/mnt/R3Backup/.enable_restore"
            fi
        fi
    fi

    # Update OTA configurations
    local zha_ota_updated=0
    local z2m_ota_updated=0
    if [ -d "$DEBUG_OTA_DIR" ]; then
        zha_ota_updated=$(update_zha_ota_config)
        z2m_ota_updated=$(update_z2m_ota_config)
    fi

    # Update /etc configuration files (DEBUG feature)
    update_etc_for_install
    
    # Update Home Assistant blueprints from debug directory (DEBUG feature)
    update_blueprints_for_debug
    
    # Force filesystem sync
    /usr/bin/sync

    # Update zhaquirks and get the count of processed *.py files
    local zha_py_files_count
    zha_py_files_count=$(update_zha_quirks_for_debug)

    # Force filesystem sync
    /usr/bin/sync

    # Update z2mquirks and get the count of processed *.js files
    local z2m_js_files_count
    z2m_js_files_count=$(update_z2m_quirks_for_debug)

    # Force filesystem sync
    /usr/bin/sync
    
    # If ZHA files or OTA index were updated and home-assistant.service is running, restart Home Assistant
    if { [ "$zha_py_files_count" -gt 0 ] || [ "$zha_ota_updated" -gt 0 ]; } && systemctl is-active --quiet home-assistant.service; then
        echo "[MAIN] Processed ZHA quirks=$zha_py_files_count, OTA updates=$zha_ota_updated" >&2
        echo "[MAIN] Restarting Home Assistant service to apply changes..." >&2
        systemctl restart home-assistant.service || true
        echo "[MAIN] Home Assistant service restarted successfully" >&2
    fi
    
    # If Z2M files or OTA were processed and zigbee2mqtt.service is running, restart Zigbee2MQTT
    if { [ "$z2m_js_files_count" -gt 0 ] || [ "$z2m_ota_updated" -gt 0 ]; } && systemctl is-active --quiet zigbee2mqtt.service; then
        echo "[MAIN] Processed Z2M converters=$z2m_js_files_count, OTA updates=$z2m_ota_updated" >&2
        echo "[MAIN] Restarting Zigbee2MQTT service to apply changes..." >&2
        systemctl restart zigbee2mqtt.service || true
        echo "[MAIN] Zigbee2MQTT service restarted successfully" >&2
    fi
    
    # Rename R3Debug directory if it exists
    if [ -d "$DEBUG_DIR" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local new_debug_dir="${DEBUG_DIR}_${timestamp}"
        echo "[MAIN] Renaming $DEBUG_DIR to $new_debug_dir" >&2
        mv "$DEBUG_DIR" "$new_debug_dir" || true
        echo "[MAIN] Debug directory renamed successfully" >&2

        /usr/bin/sync
    fi

    # install linux kernel image (must be before other packages, will reboot if updated)
    install_linux_image_deb    
}


main_procedure

exit 0
