#!/bin/bash

current_dir=$(pwd)

board="trhubv3"
destination=""
r3version="v1.03.01.03"

# 显示使用说明的函数
usage() {
    echo "Usage: $0 [-b board:trhubv3|trhubv3b|linuxbox] -d [cn|us|kr] -r [revision]"
    exit 1
}

while getopts ":b:d:r:v:" opt; do
    case ${opt} in
        b)
            if [[ "$OPTARG" == "trhubv3" || "$OPTARG" == "trhubv3b" || "$OPTARG" == "linuxbox" ]]; then
                board=$OPTARG
            else
                echo "Invalid board type: $OPTARG"
                usage
            fi
            ;;
        d)
            if [[ "$OPTARG" == "cn" || "$OPTARG" == "us" || "$OPTARG" == "kr" ]]; then
                # TODO
                destination="china"
            else
                echo "Invalid destination: $OPTARG"
                usage
            fi
            ;;
        r)
            r3version=$OPTARG
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
echo "** Board selected: [ $board ]"
echo "** Destination selected: [ $destination ]"
echo "** R3 Version selected: [ $r3version ]"
echo "** VERSION_ID calculated: [ $r3_version_id ]"

URL_APPARMOR_PROFILE="https://version.home-assistant.io/apparmor.txt"

if [ ! -d "$current_dir/userpatches" ]; then
    mkdir -p $current_dir/userpatches/overlay/
    mkdir -p $current_dir/userpatches/overlay/docker-deb/

    if [ -d "$current_dir/custom/" ]; then
        cp $current_dir/custom/config-hubv3-images.conf $current_dir/userpatches
        cp $current_dir/custom/config-jethubj100-images.conf $current_dir/userpatches
		cp $current_dir/custom/customize-image.sh $current_dir/userpatches
        #cp $current_dir/custom/*.deb $current_dir/userpatches/overlay/
        cp $current_dir/custom/bl706_cache $current_dir/userpatches/overlay/ -R
    fi
else
    if [ -e "$current_dir/userpatches/overlay/hassio-supervisor~" ]; then
        mv "$current_dir/userpatches/overlay/hassio-supervisor~" "$current_dir/userpatches/overlay/hassio-supervisor"
    fi

    if [ -e "$current_dir/userpatches/overlay/homeassistant-config.tar.gz~" ]; then
        mv "$current_dir/userpatches/overlay/homeassistant-config.tar.gz~" "$current_dir/userpatches/overlay/homeassistant-config.tar.gz"
    fi

    if [ -e "$current_dir/userpatches/overlay/docker-deb~" ]; then
        mv "$current_dir/userpatches/overlay/docker-deb~" "$current_dir/userpatches/overlay/docker-deb"
    fi

    if [ -e "$current_dir/userpatches/overlay/hassio-supervisor" ]; then
        mv "$current_dir/userpatches/overlay/hassio-supervisor" "$current_dir/userpatches/overlay/hassio-supervisor~"
    fi

    if [ -e "$current_dir/userpatches/overlay/homeassistant-config.tar.gz" ]; then
        mv "$current_dir/userpatches/overlay/homeassistant-config.tar.gz" "$current_dir/userpatches/overlay/homeassistant-config.tar.gz~"
    fi

    if [ -e "$current_dir/userpatches/overlay/docker-deb" ]; then
        mv "$current_dir/userpatches/overlay/docker-deb" "$current_dir/userpatches/overlay/docker-deb~"
    fi
fi

rm -rf $current_dir/output/images

$(pwd)/compile.sh hubv3-images BOARD=${board} BRANCH=current RELEASE=bookworm R3VERSION=${r3version} R3VERSION_ID=${r3_version_id} \
        BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_ONLY=no KERNEL_CONFIGURE=no \
        COMPRESS_OUTPUTIMAGE=sha,gpg,img INSTALL_HEADERS=no WIREGUARD=no \
        UBOOT_MIRROR=github \
        DOWNLOAD_MIRROR=${destination}

IMG_FILE=$(find "$current_dir/output/images" -maxdepth 1 -type f -name "*.img")

if [[ -n "$IMG_FILE" ]]; then
    echo "Enter convert directory Armbian_Convert ..."

    UBOOT=`find ${current_dir}/cache/sources/u-boot/ -name u-boot.bin -type f -print -quit`
    IMAGE=`find ${current_dir}/output/images -name '*.img' -type f -print -quit`

    echo "UBOOT: ${UBOOT}"
    echo "Image: ${IMAGE}"

    mkdir -p $current_dir/tools/Armbian_Convert/output

    $current_dir/tools/Armbian_Convert/convert.sh ${IMAGE} ${board} armbian no ${UBOOT}

    IMGBURN=$(find ${current_dir}/tools -maxdepth 8 -type f -name "*.burn.img")

    if [[ -n "$IMGBURN" && -f "$IMGBURN" ]]; then
        mkdir -p ${current_dir}/output/images/
        mv "$IMGBURN" ${current_dir}/output/images/
        IMGBURN=$(find ${current_dir}/output -maxdepth 4 -type f -name "*.burn.img")
        # 重命名 .burn.img 为 .${r3version}.img
        new_imgburn="${IMGBURN/.burn.img/.${r3version}.img}"
        mv "$IMGBURN" "$new_imgburn"
        echo "File build: $new_imgburn"
    else
        echo "Fail: No burn.img file exist."
    fi 
fi
