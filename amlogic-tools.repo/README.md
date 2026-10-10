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
