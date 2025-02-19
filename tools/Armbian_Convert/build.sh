#!/bin/bash

current_dir=$(pwd)

UBOOT=`find ../../cache/sources/u-boot/ -name u-boot.bin -type f -print -quit`
IMAGE=`find ../../output/images -name '*.img' -type f -print -quit`


echo "UBOOT: ${UBOOT}"
echo "Image: ${IMAGE}"

$current_dir/convert.sh ${IMAGE} d1 armbian ${UBOOT}


