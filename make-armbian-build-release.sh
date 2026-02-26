#!/bin/bash

set -e

# Define a cleanup function to be executed upon receiving a SIGINT
cleanup() {
    echo -e "\n\e[1;33m[HUBV3] INFO: Script interrupted. Cleaning up...\e[0m"
    # Add any cleanup commands you might need here, like removing temporary files
    exit 1
}

# Trap SIGINT (Ctrl+C) to run the cleanup function
trap cleanup SIGINT

print_info() { echo -e "\e[1;34m[HUBV3] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[HUBV3] ERROR:\e[0m $1"; }

# Record start time
start_time=$(date +%s)

check_command() {
  if ! command -v "$1" > /dev/null 2>&1; then
    sudo apt update && sudo apt install "$2" -y
  fi
}

# Directories setup
current_dir=$(pwd)
print_info "Working directory is '$current_dir'"
echo "Usage: $0 [-b board:trhubv3|trhubv3b|trhubv3a|linuxbox] -d [cn|us|kr] -r [revision]"


board="trhubv3"
destination=""
r3version="v2.14.01.21"

usage() {
    echo "Usage: $0 [-b board:trhubv3|trhubv3b|trhubv3a|linuxbox] -d [cn|us|kr] -r [revision]"
    exit 1
}

while getopts ":b:d:r:v:h" opt; do
    case ${opt} in
        b)
            if [[ "$OPTARG" == "trhubv3" || "$OPTARG" == "trhubv3b" || "$OPTARG" == "trhubv3a" || "$OPTARG" == "linuxbox" ]]; then
                board=$OPTARG
            else
                echo "Invalid board type: $OPTARG"
                usage
            fi
            ;;
        d)
            if [[ "$OPTARG" == "cn" ]]; then
                # TODO
                destination="china"
            elif [[ "$OPTARG" == "us" || "$OPTARG" == "kr" ]]; then
                # TODO
                destination=""                
            else
                echo "Invalid destination: $OPTARG"
                usage
            fi
            ;;
        r)
            r3version=$OPTARG
            ;;
        h)
            usage
            exit 0
            ;;            
        \?)
            echo "Invalid option: -$OPTARG"
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument."
            usage
            ;;
    esac
done

if [ -z "$board" ]; then
    echo "board name required."
    usage
fi

# 默认用 r3version
ver_no_v=${r3version#v}
IFS='.' read -r major minor patch build <<< "$ver_no_v"
r3_version_id=$((10#$major * 1000000 + 10#$minor * 10000 + 10#$patch * 100 + 10#$build))

# 输出参数
print_info "Board selected: [ $board ]"
print_info "Destination selected: [ $destination ]"
print_info "Release Version selected: [ $r3version ]"
print_info "VERSION_ID calculated: [ $r3_version_id ]"


# Check Git installation
print_info "$(/usr/bin/git version)"
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000


rm -rf ${current_dir}/userpatches > /dev/null 2>&1
rm -rf ${current_dir}/output > /dev/null 2>&1
rm -rf ${current_dir}/.tmp > /dev/null 2>&1

# User patches setup
#cd "$work_dir/armbian-os"
if [ ! -d "userpatches" ]; then
  print_info "Init userpatches ..."
  mkdir -pv userpatches
  rsync -av vendor.repo/userpatches/. userpatches/
fi

echo "24.11" > userpatches/VERSION

print_info "ImageOS: ${ImageOS}"

# Determine loop device if needed
if [ -z "${ImageOS}" ]; then
  USE_FIXED_LOOP_DEVICE=$(echo ${RUNNER_NAME} | rev | cut -d"-" -f1 | rev | sed 's/^0*//' | sed -e 's/^/\/dev\/loop/')
fi

print_info "param: ${USE_FIXED_LOOP_DEVICE}"

print_info "Start building ..."

#if [ -d "$current_dir/cache/sources/linux-kernel-worktree/" ]; then
#
#fi

if [ -d "$current_dir/.tmp" ]; then
  rm -rf $current_dir/.tmp
fi

if [ -d "$current_dir/output" ]; then
  rm -rf $current_dir/output/info
  rm -rf $current_dir/output/logs
  rm -rf $current_dir/output/packages-hashed
  rm -rf $current_dir/output/images
  rm -rf $current_dir/output/debs/linux-image-*
fi

if [ -d "$current_dir/cache/sources/LinuxBox_Supervisor" ]; then
  rm -rf $current_dir/cache/sources/LinuxBox_Supervisor
fi

mkdir -p $current_dir/output/images

# Clean up linux-kernel-worktree before compilation
if [ -d "$current_dir/cache/sources/linux-kernel-worktree/6.6__meson64__arm64" ]; then
  print_info "Cleaning up linux-kernel-worktree with make clean..."
  cd "$current_dir/cache/sources/linux-kernel-worktree/6.6__meson64__arm64"
  make clean
  cd "$current_dir"
  print_info "Cleanup completed."
fi

export KERNEL_REUSE_LOCAL=yes

./compile.sh BETA=no BOARD=${board} HOST=linuxbox BRANCH=current BUILD_DESKTOP=no BUILD_MINIMAL=no RELEASE=bookworm \
    R3VERSION_ID=$r3_version_id R3VERSION=$r3version REVISION=24.11 REVISION="24.11"  IMAGE_VERSION=24.11 \
    linuxbox-images USE_FIXED_LOOP_DEVICE="$USE_FIXED_LOOP_DEVICE" \
    MAKE_FOLDERS="archive" SHOW_DEBIAN=yes SHARE_LOG=no ALLOW_ROOT=yes KERNEL_GIT=shallow \
    UPLOAD_TO_OCI_ONLY=no NETWORKING_STACK="network-manager" EXTRAWIFI=no  \
    COMPRESS_OUTPUTIMAGE="sha,img"

#ARTIFACT_IGNORE_CACHE=yes

print_info "Armbian build finished."

# Check required tools installation
check_command "dtc" "device-tree-compiler"
check_command "cc" "build-essential cpp"
check_command "zip" "zip"

# Find output files
UBOOTDEB=$(find output | grep linux-u-boot | head -n 1)
IMG=$(find output | grep -e  ".*images.*Armbian.*\.img$" | grep -v "\.img\." | head -n 1)

print_info "Uboot.deb: ${UBOOTDEB}"
print_info "Image: ${IMG}"

cd "${current_dir}/amlogic-tools.repo"

DEB="../${UBOOTDEB}"
dpkg -x "$DEB" output
UBOOT=$(find output/usr/lib -name u-boot.nosd.bin | head -n 1)
print_info "UBOOT: ${UBOOT}"

print_info "Start convert image ..."
EVALCMD='BETA=no BOARD=${board} BRANCH=current BUILD_DESKTOP=no BUILD_MINIMAL=no RELEASE=bookworm EXTRAWIFI=no REVISION=24.11'
eval "$EVALCMD"

# Rename image file before conversion
IMG_DIR=$(dirname "../${IMG}")
IMG_BASENAME=$(basename "${IMG}")

# Extract kernel version from original filename (e.g., 6.6.120)
KERNEL_VERSION=$(echo "${IMG_BASENAME}" | grep -oP '\d+\.\d+\.\d+' | head -n 1)

# Determine board name for new filename
case ${board} in
  trhubv3)
    BOARD_NAME="hubv3"
    ;;
  trhubv3b)
    BOARD_NAME="hubv3b"
    ;;
  trhubv3a)
    BOARD_NAME="hubv3a"
    ;;
  *)
    BOARD_NAME="${board}"
    ;;
esac

# Construct new filename: thirdreality_hubv3_armbian_bookworm_current_24.11_v2.14.01.21.img
NEW_IMG_NAME="thirdreality_${BOARD_NAME}_armbian_${REVISION}_${RELEASE}_6.6.120_${r3version}.img"
NEW_IMG_PATH="${IMG_DIR}/${NEW_IMG_NAME}"

# Rename the image file
print_info "Renaming image file:"
print_info "  From: ${IMG_BASENAME}"
print_info "  To: ${NEW_IMG_NAME}"
mv "../${IMG}" "${NEW_IMG_PATH}"

# Update IMG variable to use new path
IMG="${NEW_IMG_PATH:3}"  # Remove "../" prefix

case ${BOARD} in
  trhubv3)
    ./convert.sh ../${IMG} v3 armbian compress output/usr/lib/linux*/u-boot.nosd.bin
    SUPPORTED="V3,V3B"
    ;;
  trhubv3b)
    ./convert.sh ../${IMG} v3b armbian compress output/usr/lib/linux*/u-boot.nosd.bin
    SUPPORTED="V3,V3B"
    ;;
  trhubv3a)
    ./convert.sh ../${IMG} v3a armbian compress output/usr/lib/linux*/u-boot.nosd.bin
    SUPPORTED="V3,V3A,V3B"
    ;;
  jethubj100)
    ./convert.sh ../${IMG} d1 armbian compress output/usr/lib/linux*/u-boot.nosd.bin
    SUPPORTED="D1,D1P"
    ;;
  jethubj200)
    ./convert.sh ../${IMG} d2 armbian compress output/usr/lib/linux*/u-boot.nosd.bin
    SUPPORTED="D2"
    ;;
  jethubj80)
    ./convert.sh ../${IMG} h1 armbian compress output/usr/lib/linux*/u-boot.nosd.bin
    SUPPORTED="H1"
    ;;
  *)
    print_error "Unsupported board ${BOARD}"
    print_error "Error in convert: Unsupported board ${BOARD}" >> GITHUB_STEP_SUMMARY
    exit 200
    ;;
esac

rm -rf ${current_dir}/amlogic-tools.repo/output/usr

IMGBURN=$(find ${current_dir}/amlogic-tools.repo/output | grep -e  "thirdreality.*burn.img.zip$" | head -n 1)
print_info "IMGBURN: [ ${IMGBURN} ]"

[ -z "${IMGBURN}" ] && exit 50

mv ${IMGBURN} $current_dir/output/images

# Delete original .img file after conversion
#print_info "Removing original image file: ${IMG}"
#rm -f ../${IMG}

CHANNEL="release"

# Get the correct imageburn path after moving
IMGBURN_FILENAME=$(basename ${IMGBURN})
IMGBURN_NEWPATH="$current_dir/output/images/${IMGBURN_FILENAME}"

print_info "board=${BOARD} brd=${BOARD:6} branch=${BRANCH} channel=${CHANNEL} release=${RELEASE} supported=${SUPPORTED}"
print_info "image=[ ${IMG} ]"
print_info "imageburn=[ ${IMGBURN_NEWPATH} ]"



# Record end time
end_time=$(date +%s)

# Calculate elapsed time in seconds
elapsed_time=$((end_time - start_time))

# Convert elapsed time to a more readable format
minutes=$(( (elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))

print_info "Armbian build finished."
print_info "Build completed in ${minutes} minutes, and ${seconds} seconds."



