#!/bin/bash

current_dir=$(pwd)

enable_homeassistant=yes
enable_cn_version=yes

if [ ! -d "$current_dir/userpatches" ]; then
    mkdir -p $current_dir/userpatches/overlay/

    if [ -d "$current_dir/custom/" ]; then
        cp $current_dir/custom/config-hubv3-images.conf $current_dir/userpatches
        cp $current_dir/custom/config-jethubj100-images.conf $current_dir/userpatches
		cp $current_dir/custom/customize-image.sh $current_dir/userpatches
        cp $current_dir/custom/*.deb $current_dir/userpatches/overlay/
    fi

    if [[ $enable_homeassistant == yes ]]; then
        echo "Download docker deb and docker image tar ..."
    fi
fi

rm -rf $current_dir/output/images

if [[ $enable_cn_version == yes ]]; then
    # HubV3b
    $(pwd)/compile.sh hubv3-images BOARD=trhubv3 BRANCH=current RELEASE=bookworm \
        BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_ONLY=no KERNEL_CONFIGURE=no \
        COMPRESS_OUTPUTIMAGE=sha,gpg,img INSTALL_HEADERS=no WIREGUARD=no \
        DOWNLOAD_MIRROR=china \
        NO_APT_CACHER=yes \
        BUILD_DOCKER=${enable_homeassistant}
else
    # HubV3
    $(pwd)/compile.sh hubv3-images BOARD=trhubv3 BRANCH=current RELEASE=bookworm \
        BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_ONLY=no KERNEL_CONFIGURE=no \
        COMPRESS_OUTPUTIMAGE=sha,gpg,img INSTALL_HEADERS=no WIREGUARD=no \
        BUILD_DOCKER=no
fi

IMG_FILE=$(find "$current_dir/output/images" -maxdepth 1 -type f -name "*.img")

if [[ -n "$IMG_FILE" ]]; then
    echo "Enter convert directory Armbian_Convert ..."
    cd $current_dir/tools/Armbian_Convert/; ./build.sh
    cd $current_dir
    IMGBURN=$(find ./tools -maxdepth 4 -type f -name "*.burn.img")
    echo "IMGBURN=${IMGBURN}"    
fi
