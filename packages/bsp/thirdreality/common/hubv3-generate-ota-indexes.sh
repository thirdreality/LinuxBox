#!/bin/bash
# hubv3-generate-ota-indexes.sh
# Generate OTA index files for both ZHA (zigpy) and Z2M formats
 
set -e  # Exit immediately on error
 
# ==================== Configuration Section ====================
# OTA_DIR will be set in main() function (default: current directory, or from command line argument)
ZIGPY_INDEX="local_index.json"
Z2M_INDEX="local_z2m_index.json"
 
# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
 
# ==================== Function Definitions ====================
 
# Print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
 
print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}
 
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
 
# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    # jq is always required
    if ! command -v jq &> /dev/null; then
        print_error "jq not installed, please install: sudo apt-get install jq"
        return 1
    fi
    
    # python3 is required for parsing OTA headers
    if ! command -v python3 &> /dev/null; then
        print_error "python3 not installed, please install: sudo apt-get install python3"
        return 1
    fi
    
    return 0
}
 
# Generate zigpy format index (local_index.json)
generate_zigpy_index() {
    print_info "Generating zigpy format index ($ZIGPY_INDEX)..."
    
    cd "$OTA_DIR"
    
    # Check for .ota files
    if ! ls *.ota 1> /dev/null 2>&1; then
        print_warn "No .ota files found in directory"
        return 1
    fi
    
    # Build firmwares array
    json_entries=""
    
    for ota in *.ota; do
        if [ -f "$ota" ]; then
            print_info "  Processing: $ota"
            
            # Get file size
            file_size=$(stat -c%s "$ota" 2>/dev/null || stat -f%z "$ota" 2>/dev/null || echo "0")
            
            # Calculate SHA3-256 for zigpy checksum using Python (most reliable method)
            sha3_256=$(python3 - "$ota" <<'PY'
import hashlib
import sys

if len(sys.argv) < 2:
    sys.exit(1)

path = sys.argv[1]
try:
    with open(path, 'rb') as f:
        data = f.read()
    sha3_hash = hashlib.sha3_256(data).hexdigest()
    print(sha3_hash)
except Exception as e:
    sys.exit(1)
PY
)
            
            if [ -z "$sha3_256" ]; then
                print_warn "    Failed to calculate SHA3-256, using empty checksum"
                sha3_256=""
            fi
            
            # Parse OTA header using python3
            ota_meta=$(python3 - "$ota" <<'PY'
import struct
import sys

if len(sys.argv) < 2:
    sys.exit(0)

path = sys.argv[1]
try:
    with open(path, "rb") as f:
        header = f.read(32)
    if len(header) < 18:
        sys.exit(0)
    
    # Extract manufacturer, image_type, file_version
    manufacturer, image_type = struct.unpack("<HH", header[10:14])
    (file_version,) = struct.unpack("<I", header[14:18])
    
    # Output: manufacturer image_type file_version
    print(f"{manufacturer} {image_type} {file_version}")
except Exception as e:
    sys.exit(0)
PY
)
            
            manufacturer=""
            image_type=""
            file_version=""
            
            if [ -n "$ota_meta" ]; then
                manufacturer=$(echo "$ota_meta" | awk '{print $1}')
                image_type=$(echo "$ota_meta" | awk '{print $2}')
                file_version=$(echo "$ota_meta" | awk '{print $3}')
            else
                print_warn "    Failed to parse OTA header"
            fi
            
            # Create JSON entry for zigpy format
            if [ -n "$sha3_256" ]; then
                checksum_value="sha3-256:$sha3_256"
            else
                checksum_value="sha3-256:"
                print_warn "    Using empty SHA3-256 checksum"
            fi
            
            entry=$(jq -n \
                --arg path "$ota" \
                --arg fileVersion "${file_version:-0}" \
                --arg fileSize "$file_size" \
                --arg imageType "${image_type:-0}" \
                --arg manufacturerId "${manufacturer:-0}" \
                --arg checksum "$checksum_value" \
                '{
                    path: $path,
                    file_version: ($fileVersion | tonumber),
                    file_size: ($fileSize | tonumber),
                    image_type: ($imageType | tonumber),
                    manufacturer_id: ($manufacturerId | tonumber),
                    checksum: $checksum,
                    min_hardware_version: 0,
                    max_hardware_version: 65520
                }')
            
            if [ -z "$json_entries" ]; then
                json_entries="$entry"
            else
                json_entries="$json_entries,$entry"
            fi
            
            print_info "    SHA3-256: ${sha3_256:0:16}..."
        fi
    done
    
    # Build final JSON with firmwares array
    jq -n --argjson firmwares "[$json_entries]" '{firmwares: $firmwares}' > "$ZIGPY_INDEX"
    
    if [ $? -eq 0 ]; then
        print_info "Zigpy index generated successfully: $OTA_DIR/$ZIGPY_INDEX"
        return 0
    else
        print_error "Failed to generate zigpy index"
        return 1
    fi
}

# Generate Z2M format index (local_z2m_index.json)
generate_z2m_index() {
    print_info "Generating Z2M format index ($Z2M_INDEX)..."
    
    cd "$OTA_DIR"
    
    # Check for .ota files
    if ! ls *.ota 1> /dev/null 2>&1; then
        print_warn "No .ota files found in directory"
        return 1
    fi
    
    # Build JSON array
    json_entries=""
    
    for ota in *.ota; do
        if [ -f "$ota" ]; then
            print_info "  Processing: $ota"
            
            # Calculate SHA512 for Z2M
            sha512=$(sha512sum "$ota" | cut -d' ' -f1)
            
            # Parse OTA header using python3
            ota_meta=$(python3 - "$ota" <<'PY'
import struct
import sys

if len(sys.argv) < 2:
    sys.exit(0)

path = sys.argv[1]
try:
    with open(path, "rb") as f:
        header = f.read(32)
    if len(header) < 18:
        sys.exit(0)
    
    # Extract manufacturer, image_type, file_version
    manufacturer, image_type = struct.unpack("<HH", header[10:14])
    (file_version,) = struct.unpack("<I", header[14:18])
    
    # Output: manufacturer image_type file_version
    print(f"{manufacturer} {image_type} {file_version}")
except Exception as e:
    sys.exit(0)
PY
)
            
            manufacturer=""
            image_type=""
            file_version=""
            
            if [ -n "$ota_meta" ]; then
                manufacturer=$(echo "$ota_meta" | awk '{print $1}')
                image_type=$(echo "$ota_meta" | awk '{print $2}')
                file_version=$(echo "$ota_meta" | awk '{print $3}')
            else
                print_warn "    Failed to parse OTA header"
            fi
            
            # Create JSON entry for Z2M format
            entry=$(jq -n \
                --arg url "$ota" \
                --arg imageType "${image_type:-0}" \
                --arg manufacturerCode "${manufacturer:-0}" \
                --arg fileVersion "${file_version:-0}" \
                --arg sha512 "$sha512" \
                '{
                    url: $url,
                    imageType: ($imageType | tonumber),
                    manufacturerCode: ($manufacturerCode | tonumber),
                    fileVersion: ($fileVersion | tonumber),
                    sha512: $sha512
                }')
            
            if [ -z "$json_entries" ]; then
                json_entries="$entry"
            else
                json_entries="$json_entries,$entry"
            fi
            
            print_info "    SHA512: ${sha512:0:16}..."
        fi
    done
    
    # Build final JSON array
    echo "[$json_entries]" | jq '.' > "$Z2M_INDEX"
    
    if [ $? -eq 0 ]; then
        print_info "Z2M index generated successfully: $OTA_DIR/$Z2M_INDEX"
        return 0
    else
        print_error "Failed to generate Z2M index"
        return 1
    fi
}

# Generate both index files
generate_indexes() {
    print_info "Generating OTA index files..."
    
    cd "$OTA_DIR"
    
    # Generate zigpy index
    if ! generate_zigpy_index; then
        return 1
    fi
    
    # Generate Z2M index
    if ! generate_z2m_index; then
        return 1
    fi
    
    print_info "Both index files generated successfully"
    return 0
}
 
# Show statistics
show_statistics() {
    print_info "===== Generation Statistics ====="
     
    cd "$OTA_DIR"
     
    # OTA file count
    ota_count=$(ls -1 *.ota 2>/dev/null | wc -l)
    echo "  OTA files count: $ota_count"
     
    # ZIGPY index (for ZHA)
    if [ -f "$ZIGPY_INDEX" ]; then
        zigpy_count=$(jq 'length' "$ZIGPY_INDEX")
        zigpy_size=$(ls -lh "$ZIGPY_INDEX" | awk '{print $5}')
        echo "  ZIGPY index: $ZIGPY_INDEX ($zigpy_count entries, $zigpy_size)"
    else
        echo "  ZIGPY index: Not generated"
    fi
     
    # Z2M index
    if [ -f "$Z2M_INDEX" ]; then
        z2m_count=$(jq 'length' "$Z2M_INDEX")
        z2m_size=$(ls -lh "$Z2M_INDEX" | awk '{print $5}')
        echo "  Z2M index: $Z2M_INDEX ($z2m_count entries, $z2m_size)"
    else
        echo "  Z2M index: Not generated"
    fi
     
    echo ""
    echo "  Directory: $OTA_DIR"
     
    print_info "================================="
}
 
# Show configuration examples
show_config_examples() {
    print_info "===== Configuration Examples ====="
     
    echo ""
    echo "Home Assistant ZHA Configuration (configuration.yaml):"
    echo "---"
    cat << EOF
zha:
  zigpy_config:
    ota:
      extra_providers:
        - type: z2m_local
          index_file: /var/lib/homeassistant/homeassistant/zigpy_local_ota/$ZIGPY_INDEX
EOF
    echo "---"
     
    echo ""
    echo "Zigbee2MQTT Configuration (configuration.yaml):"
    echo "---"
    cat << EOF
ota:
  zigbee_ota_override_index_location: /opt/zigbee2mqtt/data/$Z2M_INDEX
EOF
    echo "---"
     
    print_info "=================================="
}
 
# Backup old indexes
backup_old_indexes() {
    cd "$OTA_DIR"
     
    timestamp=$(date +%Y%m%d_%H%M%S)
     
    if [ -f "$ZIGPY_INDEX" ]; then
        cp "$ZIGPY_INDEX" "${ZIGPY_INDEX}.backup_${timestamp}"
        print_info "Backed up: ${ZIGPY_INDEX}.backup_${timestamp}"
    fi
     
    if [ -f "$Z2M_INDEX" ]; then
        cp "$Z2M_INDEX" "${Z2M_INDEX}.backup_${timestamp}"
        print_info "Backed up: ${Z2M_INDEX}.backup_${timestamp}"
    fi
}
 
# Show usage information
show_usage() {
    echo "Usage: $0 [OTA_DIRECTORY]"
    echo ""
    echo "Generate OTA index files for both ZHA (zigpy) and Z2M formats"
    echo ""
    echo "Arguments:"
    echo "  OTA_DIRECTORY    Directory containing .ota files (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use current directory"
    echo "  $0 /mnt/R3Debug/zigpy_local_ota      # Use specified directory"
    exit 0
}

# ==================== Main Process ====================

main() {
    # Parse command line arguments
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
    fi
    
    # Set OTA_DIR from argument or use default
    if [ -n "$1" ]; then
        if [ ! -d "$1" ]; then
            print_error "Directory does not exist: $1"
            exit 1
        fi
        # Convert to absolute path
        OTA_DIR="$(cd "$1" && pwd)"
        print_info "Using OTA directory: $OTA_DIR"
    else
        OTA_DIR="$(pwd)"
        print_info "Using default OTA directory (current): $OTA_DIR"
    fi
    
    echo "========================================"
    echo "  OTA Index File Generator"
    echo "  Generate ZHA (zigpy) and Z2M format indexes"
    echo "========================================"
    echo ""
     
    # Backup old indexes first
    backup_old_indexes
     
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
     
    # Generate both index files
    generate_indexes
     
    echo ""
    # Show statistics
    show_statistics
     
    echo ""
    # Show configuration examples
    show_config_examples
     
    echo ""
    print_info "All done!"
    print_info "Please add the configuration to Home Assistant or Zigbee2MQTT as needed"
}
 
# Run main process
main "$@"