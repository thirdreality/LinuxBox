#!/bin/bash
# hubv3-generate-ota-indexes.sh
# Generate OTA index files for both zigpy and Z2M formats
 
set -e  # Exit immediately on error
 
# ==================== Configuration Section ====================
VENV_PATH="/srv/homeassistant/bin/activate"
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
    
    # Check if VENV_PATH exists
    if [ -f "$VENV_PATH" ]; then
        print_info "Home Assistant virtual environment found: $VENV_PATH"
        return 0
    else
        print_warn "Virtual environment not found: $VENV_PATH"
        print_warn "Will generate simple Z2M index only (requires jq)"
        return 1
    fi
}
 
# Activate virtual environment and generate zigpy index
generate_zigpy_index() {
    print_info "Generating zigpy format index ($ZIGPY_INDEX)..."
     
    cd "$OTA_DIR"
     
    # Activate virtual environment
    source "$VENV_PATH"
     
    # Check for .ota files
    if ! ls *.ota 1> /dev/null 2>&1; then
        print_warn "No .ota files found in directory"
        return 1
    fi
     
    # Generate index using zigpy tool
    # --ota-url-root uses relative path (filename only)
    zigpy ota generate-index --ota-url-root="" ./*.ota > "$ZIGPY_INDEX"
     
    if [ $? -eq 0 ]; then
        print_info "zigpy index generated successfully, removing leading slash from binary_url..."
         
        # Remove leading slash from binary_url
        jq '[.[] | .binary_url = (.binary_url | ltrimstr("/"))]' "$ZIGPY_INDEX" > "${ZIGPY_INDEX}.tmp" && mv "${ZIGPY_INDEX}.tmp" "$ZIGPY_INDEX"
         
        if [ $? -ne 0 ]; then
            print_error "Failed to remove leading slash"
            return 1
        fi
         
        # Format JSON (optional)
        if command -v python3 &> /dev/null; then
            python3 -m json.tool "$ZIGPY_INDEX" > "${ZIGPY_INDEX}.tmp" && mv "${ZIGPY_INDEX}.tmp" "$ZIGPY_INDEX"
        fi
         
        print_info "zigpy index processing completed: $OTA_DIR/$ZIGPY_INDEX"
        return 0
    else
        print_error "Failed to generate zigpy index"
        return 1
    fi
}
 
# Convert to Z2M format
convert_to_z2m() {
    print_info "Converting to Z2M format ($Z2M_INDEX)..."
     
    cd "$OTA_DIR"
     
    if [ ! -f "$ZIGPY_INDEX" ]; then
        print_error "zigpy index file not found, cannot convert"
        return 1
    fi
     
    # Convert format using jq, remove leading slash from binary_url
    jq '[.[] | {
        url: (.binary_url | ltrimstr("/")),
        imageType: .image_type,
        manufacturerCode: .manufacturer_id,
        fileVersion: .file_version,
        sha512: ""
    }]' "$ZIGPY_INDEX" > "$Z2M_INDEX"
     
    if [ $? -ne 0 ]; then
        print_error "JSON conversion failed"
        return 1
    fi
     
    print_info "Z2M index framework generated successfully"
}
 
# Calculate and populate SHA512
calculate_sha512() {
    print_info "Calculating SHA512 checksums..."
     
    cd "$OTA_DIR"
     
    for ota in *.ota; do
        if [ -f "$ota" ]; then
            print_info "  Processing: $ota"
             
            # Calculate SHA512
            sha512=$(sha512sum "$ota" | cut -d' ' -f1)
             
            # Update sha512 value in Z2M index
            jq --arg url "$ota" --arg sha "$sha512" \
               '(.[] | select(.url == $url) | .sha512) = $sha' \
               "$Z2M_INDEX" > "${Z2M_INDEX}.tmp"
             
            if [ $? -eq 0 ]; then
                mv "${Z2M_INDEX}.tmp" "$Z2M_INDEX"
                print_info "    SHA512: ${sha512:0:16}..."
            else
                print_error "    Failed to update SHA512"
                rm -f "${Z2M_INDEX}.tmp"
            fi
        fi
    done
     
    # Format final JSON
    if command -v python3 &> /dev/null; then
        python3 -m json.tool "$Z2M_INDEX" > "${Z2M_INDEX}.tmp" && mv "${Z2M_INDEX}.tmp" "$Z2M_INDEX"
    fi
     
    print_info "SHA512 calculation completed"
}

# Generate simple Z2M index (only url and sha512)
generate_simple_z2m_index() {
    print_info "Generating simple Z2M format index ($Z2M_INDEX)..."
    
    cd "$OTA_DIR"
    
    # Check for .ota files
    if ! ls *.ota 1> /dev/null 2>&1; then
        print_warn "No .ota files found in directory"
        return 1
    fi
    
    # Build JSON array
    json_input="["
    first=true
    
    for ota in *.ota; do
        if [ -f "$ota" ]; then
            print_info "  Processing: $ota"
            
            # Calculate SHA512
            sha512=$(sha512sum "$ota" | cut -d' ' -f1)
            
            manufacturer=""
            image_type=""
            file_version=""
            
            # Try to parse OTA header using python3
            if command -v python3 >/dev/null 2>&1; then
                ota_meta=$(python3 - "$ota" <<'PY'
import struct
import sys

if len(sys.argv) < 2:
    # No path provided, output nothing
    sys.exit(0)

path = sys.argv[1]
try:
    with open(path, "rb") as f:
        header = f.read(32)
    if len(header) < 18:
        # Header too short, do not output anything
        sys.exit(0)
    manufacturer, image_type = struct.unpack("<HH", header[10:14])
    (file_version,) = struct.unpack("<I", header[14:18])
    # Single line, space separated
    print(f"{manufacturer} {image_type} {file_version}")
except Exception:
    # On any error, output nothing so shell side can fall back
    sys.exit(0)
PY
)
                if [ -n "$ota_meta" ]; then
                    manufacturer=$(echo "$ota_meta" | awk '{print $1}')
                    image_type=$(echo "$ota_meta" | awk '{print $2}')
                    file_version=$(echo "$ota_meta" | awk '{print $3}')
                else
                    print_warn "Failed to parse OTA header for $ota, will not fill manufacturerCode/imageType/fileVersion"
                fi
            else
                print_warn "python3 not found, will not fill manufacturerCode/imageType/fileVersion"
            fi
            
            # Add comma if not first item
            if [ "$first" = false ]; then
                json_input="${json_input},"
            fi
            first=false
            
            if [ -n "$manufacturer" ] && [ -n "$image_type" ] && [ -n "$file_version" ]; then
                # Full Z2M entry with metadata
                json_input="${json_input}{\"url\":\"$ota\",\"imageType\":$image_type,\"manufacturerCode\":$manufacturer,\"fileVersion\":$file_version,\"sha512\":\"$sha512\"}"
            else
                # Fallback: only url + sha512
                json_input="${json_input}{\"url\":\"$ota\",\"sha512\":\"$sha512\"}"
            fi
            
            print_info "    SHA512: ${sha512:0:16}..."
        fi
    done
    
    json_input="${json_input}]"
    
    # Write to file using jq for proper formatting and validation
    echo "$json_input" | jq '.' > "$Z2M_INDEX"
    
    if [ $? -eq 0 ]; then
        print_info "Simple Z2M index generated successfully: $OTA_DIR/$Z2M_INDEX"
        return 0
    else
        print_error "Failed to generate simple Z2M index"
        return 1
    fi
}
 
# Show statistics
show_statistics() {
    print_info "===== Generation Statistics ====="
     
    cd "$OTA_DIR"
     
    # OTA file count
    ota_count=$(ls -1 *.ota 2>/dev/null | wc -l)
    echo "  OTA files count: $ota_count"
     
    # zigpy index
    if [ -f "$ZIGPY_INDEX" ]; then
        zigpy_count=$(jq 'length' "$ZIGPY_INDEX")
        zigpy_size=$(ls -lh "$ZIGPY_INDEX" | awk '{print $5}')
        echo "  zigpy index: $ZIGPY_INDEX ($zigpy_count entries, $zigpy_size)"
    else
        echo "  zigpy index: Not generated"
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
    echo "1. Home Assistant ZHA Configuration (configuration.yaml):"
    echo "---"
    cat << EOF
zha:
  zigpy_config:
    ota:
      extra_providers:
        - type: zigpy_local
          index_file: $OTA_DIR/local_index.json
EOF
    echo "---"
     
    echo ""
    echo "2. Zigbee2MQTT Configuration (configuration.yaml):"
    echo "---"
    cat << EOF
ota:
  zigbee_ota_override_index_location: $OTA_DIR/local_z2m_index.json
EOF
    echo "---"
     
    echo ""
    echo "3. ZHA Configuration using both formats:"
    echo "---"
    cat << EOF
zha:
  zigpy_config:
    ota:
      extra_providers:
        # Use Z2M community repository
        - type: z2m_local
          index_file: /path/to/zigbee-OTA/index.json
        # Use custom firmware (zigpy format)
        - type: zigpy_local
          index_file: $OTA_DIR/local_index.json
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
    echo "Generate OTA index files for both zigpy and Z2M formats"
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
    echo "  Generate both zigpy and Z2M formats"
    echo "========================================"
    echo ""
     
    # Backup old indexes first
    backup_old_indexes
     
    # Check dependencies - jq is always required
    if ! command -v jq &> /dev/null; then
        print_error "jq not installed, please install: sudo apt-get install jq"
        exit 1
    fi
     
    # Check if VENV_PATH exists to determine workflow
    if [ -f "$VENV_PATH" ]; then
        # VENV_PATH exists - use full workflow with zigpy
        print_info "Home Assistant virtual environment found: $VENV_PATH"
        print_info "Using full workflow (zigpy + Z2M)"
        
        # Generate zigpy index
        if generate_zigpy_index; then
            # Convert to Z2M format
            if convert_to_z2m; then
                # Calculate SHA512
                calculate_sha512
            fi
        fi
    else
        # VENV_PATH does not exist - use simple Z2M only
        print_warn "Virtual environment not found: $VENV_PATH"
        print_info "Using simple Z2M workflow (no zigpy)"
        
        # Generate simple Z2M index
        generate_simple_z2m_index
    fi
     
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