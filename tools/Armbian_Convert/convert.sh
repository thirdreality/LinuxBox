#!/bin/bash

source lib.sh

if [ $# -lt 3 ]; then
    echo Usage:
    echo "	$0 <input> <h1|d1> <type> [compress uboot]"
    echo
    echo "		input		- input image"
    echo "		h1|d1|j80|j100	- select controller D1 or H1"
    echo "		type		- partition type. supported: haos, armbian"
    echo "		compress	- 'compress' or 'no' output to zip"
    echo "		uboot		- path to u-boot binary"
    exit
fi

if [[ "$2" == "h1" || "$2" == "j80" ]]; then
  DTS="meson-gxl-s905w-jethome-jethub-j80.dts"
  CNAME="j80"
elif [[ "$2" == "d1" || "$2" == "j100" ]]; then
  DTS="meson-axg-jethome-jethub-j100.dts"
  CNAME="j100"
else
  echo "ERROR: unknown controller"
  exit
fi

if [[ "$3" == "haos" ]]; then
  DTI="partition_haos.dtsi"
  CPART="haos"
elif [[ "$3" == "armbian" ]]; then
  DTI="partition_arm.dtsi"
  CPART="armbian"
else
  echo "ERROR: unknown partition table"
  exit
fi

if [[ "$4" == "compress" ]]; then
    COMPRESS=yes
fi

if [[ -e "$5" ]]; then
    UBOOT="$5"
else
    UBOOT="src/$CNAME/u-boot.$CPART.bin"
fi

echo "UBOOT set to ${UBOOT}"

[[ ! -e $1 ]] && echo No file found && exit
echo "Selected $CNAME controller with $CPART partition table"


INPUT=$(readlink -f $1)
TMP=$(mktemp -d)
DTB="$TMP/${DTS::-4}.dtb"
EXT="${INPUT:${#INPUT}-3:3}"
if [[ ".xz" == "${EXT}" ]]; then
    INPUTE="${INPUT::-3}"
    echo "Found compressed image. Decompress $INPUTE$EXT"
    INPUT="$TMP/$(basename $INPUTE)"
    xzcat "${INPUTE}${EXT}" >"$INPUT"
fi

mkdir -p output
OUTIMG=$(basename $INPUT)
OUEXT="${OUTIMG:${#OUTIMG}-4:4}"
if [[ ".img" == "${OUEXT}" ]]; then
    OUTIMGE="${OUTIMG::-4}"
    OUTIMG="${OUTIMGE}.burn${OUEXT}"
else
    OUTIMG="${OUTIMG}.burn"
fi

cp "dts/$DTS" "$TMP/$DTS"
cp "dts/$DTI" "$TMP/$DTI"
sed -i "s/partition.dtsi/$DTI/g" "$TMP/$DTS"

cpp -nostdinc -I dts -I dts/include -undef -x assembler-with-cpp "$TMP/$DTS" "$TMP/$DTS.preprocess"
dtc -I dts -O dtb -p 0x1000 -qqq "$TMP/$DTS.preprocess" -o "$DTB"
FDISK=$(/usr/sbin/fdisk -l "$INPUT" | grep -P -A 100 "Device.+Boot.+Start.+End.+Sectors.+Size.+Id.+Type" | sed -- "s/\*//g" | grep "$INPUT"| grep -v Extended)

echo +! Device	! Start	! End	! Sectors	! Size	! Id	! Type	!-
i=1
while read -r line; do
    read -r Device Start End Sectors Size Id Type <<<$line
    Device=$(echo $(basename $Device) | sed --  "s/$(basename $INPUT)//g")
    echo +! $Device	! $Start	! $End	! $Sectors	! $Size	! $Id	! $Type	!-
    extract_partition "$INPUT" $Start $Sectors "$TMP/part-$i.img"
    i=$((i + 1))
done <<< "$FDISK"

cp "src/$CNAME/platform.conf" "$TMP"

cc -o $TMP/dtbTool dtbtools/dtbTool.c
$TMP/dtbTool -o "$TMP/_aml_dtb.PARTITION" "$TMP"

cp "src/$CNAME/image.$CPART.cfg" "$TMP/image.cfg"
echo cp "$UBOOT" "$TMP/u-boot.bin"
cp "$UBOOT" "$TMP/u-boot.bin"

md5sum "$UBOOT"
md5sum "$TMP/u-boot.bin"

cp "src/$CNAME/DDR.USB" "$TMP"
cp "src/$CNAME/UBOOT.USB" "$TMP"


echo "aml_image_v2_packer_new $TMP"

cat "$TMP/image.cfg"

./tools/aml_image_v2_packer_new -r "$TMP/image.cfg" "$TMP" output/$OUTIMG

if [[ "$COMPRESS" == "yes" ]]; then
    cd output
    zip "$OUTIMG.zip" "$OUTIMG"
    cd ..
    rm "output/$OUTIMG"
    #xz --threads=0 "output/$OUTIMG"
fi

rm -rf $TMP
