#!/bin/bash

current_dir=$(pwd)

if [ ! -d "$current_dir/userpatches" ]; then
    mkdir -p $current_dir/userpatches/overlay/

    if [ -d "$current_dir/custom/" ]; then
        cp $current_dir/custom/config-hubv3-images.conf $current_dir/userpatches
		cp $current_dir/custom/customize-image.sh $current_dir/userpatches
        cp $current_dir/custom/*.deb $current_dir/userpatches/overlay/
    fi
fi

rm -rf $current_dir/output/images
$(pwd)/compile.sh hubv3-images BOARD=jethubj100 BRANCH=current RELEASE=bookworm \
    BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_ONLY=no KERNEL_CONFIGURE=no \
    COMPRESS_OUTPUTIMAGE=sha,gpg,img INSTALL_HEADERS=no WIREGUARD=no NO_APT_CACHER=yes

IMG_FILE=$(find "$current_dir/output/images" -maxdepth 1 -type f -name "*.img")

if [[ -n "$IMG_FILE" ]]; then
    echo "Enter convert directory Armbian_Convert ..."
    cd $current_dir/tools/Armbian_Convert/; ./build_j100.sh
    cd $current_dir
    IMGBURN=$(find ./tools -maxdepth 4 -type f -name "*.burn.img")
    echo "IMGBURN=${IMGBURN}"    
fi
