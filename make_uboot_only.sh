#!/bin/bash

#maintainer: guoping.liu@thirdreality.com

#中文: 这是一个简单的脚本，用户可以每次只编译uboot，然后重新打包一个burn image，全程自动化。
#English: TODO

print_info() { echo -e "\e[1;34m[ThirdReality] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[ThirdReality] ERROR:\e[0m $1"; }

current_dir=$(pwd)

# toolchain list below:
#./cache/toolchain/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc
#./cache/toolchain/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc

uboot_dir=${current_dir}/cache/sources/u-boot/v2022.07/
gcc_dir=${current_dir}/cache/toolchain/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin
amlogic_boot_fip_dir=${current_dir}/cache/sources/amlogic-boot-fip
convert_tools_dir=${current_dir}/tools/Armbian_Convert
convert_hubv3_dir=${current_dir}/tools/Armbian_Convert/src/hubv3

mkdir -p ${current_dir}/hubv3-boot-fip

print_info "Utility tool for rebuild uboot.bin, and rebuild the burn image ..."


print_info "Begin to rebuild uboot.bin"


export CROSS_COMPILE=${gcc_dir}/aarch64-none-linux-gnu-
cd ${uboot_dir};  make clean; make trhub_v3_defconfig; make

if [ -e "${uboot_dir}/u-boot.bin" ]; then
    print_info "Begin to make boot fip for uboot.bin"
    print_info "Check original uboot.bin: ${uboot_dir}/u-boot.bin ..."
    md5sum ${uboot_dir}/u-boot.bin
    rm -rf ${current_dir}/hubv3-boot-fip/*
    cd ${amlogic_boot_fip_dir}
    ./build-fip.sh jethub-j100 ${uboot_dir}/u-boot.bin ${current_dir}/hubv3-boot-fip

    ls -l ${current_dir}/hubv3-boot-fip
else
    print_error "uboot/u-boot.bin is Not exist."
    exit 1
fi

if [ -e "${current_dir}/hubv3-boot-fip/u-boot.bin" ]; then
    print_info "Check files in ${current_dir}/hubv3-boot-fip."
    cd ${current_dir}/hubv3-boot-fip
    md5sum ./*

    print_info "DDR.USB is a u-boot.bin.usb.bl2 and UBOOT.USB is a u-boot.bin.usb.tpl from Amlogic versions of u-boot."

    print_info "Sync u-boot.bin to u-boot.armbian.bin ..."
    cp ${current_dir}/hubv3-boot-fip/u-boot.bin $convert_hubv3_dir/u-boot.armbian.bin

    print_info "Sync u-boot.bin.usb.bl2 to DDR.USB ..."
    cp ${current_dir}/hubv3-boot-fip/u-boot.bin.usb.bl2 $convert_hubv3_dir/DDR.USB

    print_info "Sync u-boot.bin.usb.tpl to UBOOT.USB ..."
    cp ${current_dir}/hubv3-boot-fip/u-boot.bin.usb.tpl $convert_hubv3_dir/UBOOT.USB

    print_info "Check files in $convert_hubv3_dir."
    cd $convert_hubv3_dir
    md5sum ./*
else
    print_error "fip/u-boot.bin is Not exist."
    exit 1
fi

UBOOT=$convert_hubv3_dir/u-boot.armbian.bin
IMAGE=`find ${current_dir}/output/images -name '*.img' -type f -print -quit`

if [ -e ${IMAGE} ]; then
    print_info "UBOOT: ${UBOOT}"
    print_info "Image: ${IMAGE}"

    cd $convert_tools_dir
    $convert_tools_dir/convert.sh ${IMAGE} v3 armbian no ${UBOOT}

    cd $current_dir
    IMGBURN=$(find ./tools -maxdepth 4 -type f -name "*.burn.img")
    print_info "IMGBURN=${IMGBURN}"
else
    print_info "origin image is Not exist."
    exit 1
fi
