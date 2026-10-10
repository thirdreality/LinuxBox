# amlogic-tools

Convert an Armbian SD image of a ThirdReality HubV3 board into an Amlogic
USB Burning Tool image.

```
./convert.sh <image> <v3|v3a|v3b|v3l> <armbian|haos> [compress] <u-boot.bin>
```

| Variant | Board | USB loaders | amlogic-dt-id |
|---|---|---|---|
| v3, v3b | HubV3 / HubV3B, DDR4 2GB | `bins/hubv3` | `axg_hubv3_v1` |
| v3l, v3a | HubV3L / HubV3A, DDR3 2 ranks 1GB | `bins/hubv3l` | `axg_hubv3l_v1` |

`bins/*/DDR.USB` and `UBOOT.USB` are `u-boot.bin.usb.bl2` and
`u-boot.bin.usb.tpl` built from the Amlogic OpenLinux SDK 2025r1 boards
`axg_hubv3_v1` / `axg_hubv3l_v1`. Their `checkhw()` name must equal the
`amlogic-dt-id` in `dts/`, and it must have exactly three `_` fields because
`dtbtools/dtbTool.c` only parses `soc_platform_variant`.

`tools/aml_image_v2_packer_new` is the Amlogic packer, identical to the SDK copy.

## Partition layout

`bins/image.<armbian|haos>.cfg` is the packer config; the matching partition
table is `dts/partition_<arm|haos>.dtsi`. For Armbian this is a separate
128 MiB `boot` (part-1) plus `rootfs` (part-2); the boot size must match
`BOOTSIZE` in `config/sources/families/trhub.conf`.

## Regenerating the USB loaders

Build the board's u-boot in the SDK build copy (see the SDK `README_HUBV3.MD`
for the docker command), then copy the two loader files:

```
make -C output/axg_hubv3_a64_k54_release  uboot-dirclean uboot
make -C output/axg_hubv3l_a64_k54_release uboot-dirclean uboot

cp output/axg_hubv3_a64_k54_release/images/u-boot.bin.usb.bl2  bins/hubv3/DDR.USB
cp output/axg_hubv3_a64_k54_release/images/u-boot.bin.usb.tpl  bins/hubv3/UBOOT.USB
cp output/axg_hubv3l_a64_k54_release/images/u-boot.bin.usb.bl2 bins/hubv3l/DDR.USB
cp output/axg_hubv3l_a64_k54_release/images/u-boot.bin.usb.tpl bins/hubv3l/UBOOT.USB
```

Check `strings UBOOT.USB | grep axg_hubv3` shows the expected dt-id. These
loaders only run in RAM during USB burning; the bootloader written to eMMC is
the mainline u-boot passed as `<u-boot.bin>`.

## Origin

Derived from [jethome-tools](https://github.com/jethome-iot/jethome-tools) by
JetHome. JetHub boards and JetHome-built loaders have been removed.
