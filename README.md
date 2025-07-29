<p align="center">
  <a href="#build-framework">
  <img src=".github/armbian-logo.png" alt="Armbian logo" width="144">
  </a><br>
  <strong>Armbian Linux Build Framework</strong><br>
<br>

Armbian source code for Third Reality Linux Box Dev Edition.
</p>


## Table of contents

- [Compile firmware](#compile-firmware)
- [Flash firmware](#flash-firmware)
- [Tricks](#tricks-for-using-linuxbox)

## WIKI content
- [How-to-Compile-firmware](https://github.com/thirdreality/LinuxBox/wiki/How-to-Compile-firmware)
- [How-to-burn-the-image-to-LinuxBox](https://github.com/thirdreality/LinuxBox/wiki/How-to-burn-the-image-to-LinuxBox)

## Relative Project
- [LinuxBox Finder: A set of tools for configuring Linux Box via BLE.](https://github.com/thirdreality/LinuxBox_Finder)
- [LinuxBox Installer: HomeAssistant Installer for Third Reality Linux Box Dev Edition](https://github.com/thirdreality/LinuxBox-Installer)
- [LinuxBox Supervisor: supervisor For LinuxBox](https://github.com/thirdreality/LinuxBox_Supervisor)

## Compile firmware

### Download

```bash
git clone git@github.com:thirdreality/LinuxBox.git -b hubv3
```

### Compile

Run in the root directory of Armbian.

```bash
cd LinuxBox; ./make_armbian_for_hubv3.sh
```

The compiled generated firmware is located:

`output/images/Armbian_22.11.0-xxx.burn.img`

Here is a pre-compiled image. If you don't have time to compile the image yourself and don't mind if it's slightly outdated, you can give it a try:
[linuxbox-image-5.10.240-v1.0.0](https://assets.3reality.com/product/hubv3/Armbian_22.11.0-trunk_Trhubv3_bookworm_current_5.10.240.v1.0.0.img)


More detail information please check [How-to-Compile-firmware](https://github.com/thirdreality/LinuxBox/wiki/How-to-Compile-firmware)


## Flash firmware

To prepare the burning environment on the computer:
1. Download and extract the file [Aml_Burn_Tool.zip](https://github.com/thirdreality/HA-Box/releases/download/Assets/Aml_Burn_Tool.zip).
2. If this is your first time using the tool, click on `Setup_Aml_Burn_Tool_V3.1.0.exe` to install necessary drivers.
3. Next, navigate to the `v2` folder and run `Aml_Burn_Tool.exe`.
4. Load the compiled `**.img` firmware file.
5. Click on `Start` to initiate the burn process.
6. Press and hold the button circled in the image below, then connect the black line to your computer and start flashing. You can release the button when you start flashing.


<img width="400" alt="4368c63836c626d6132a6575918a2d9" src="https://github.com/user-attachments/assets/915d959e-3857-4868-a4ed-088bace91c03" />


More detail information please check the wiki: [How-to-burn-the-image-to-LinuxBox](https://github.com/thirdreality/LinuxBox/wiki/How-to-burn-the-image-to-LinuxBox)


## Tricks for using LinuxBox

### HomeAssistant

Thirdreality dev team supply a new way to install home assistant core in 8-10 minutes.

Check it in WIKI: [Tricks-for-Homeassistant](https://github.com/thirdreality/LinuxBox/wiki/Tricks-for-Homeassistant)


### OpenHab

To be continue ...







## License

This software is published under the GPL-2.0 License license.



