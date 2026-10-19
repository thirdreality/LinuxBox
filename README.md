<p align="center">
  <a href="#build-framework">
  <img src="https://3reality.com/wp-content/uploads/2025/07/1-1.png" alt="LinuxBox" width="360">
  </a><br>
  <strong>Armbian Linux Build Framework For ThirdReality LinuxBox Dev Edition</strong><br>
<br>

Armbian source code for Third Reality Linux Box Dev Edition.

[ Buy it on Third Reality Shop](https://3reality.com/product/linux-box-dev-edition/)

</p>


## Table of contents

- [Compile firmware](#compile-firmware)
- [Flash firmware](#flash-firmware)
- [Tricks](#tricks-for-using-linuxbox)
- [Upstream Armbian README](README-armbian.md)

## WIKI content
- [How-to-Compile-firmware](https://github.com/thirdreality/LinuxBox/wiki/How-to-Compile-firmware)
- [How-to-burn-the-image-to-LinuxBox](https://github.com/thirdreality/LinuxBox/wiki/How-to-burn-the-image-to-LinuxBox)

## Relative Project
- [LinuxBox Finder: A set of tools for configuring Linux Box via BLE.](https://github.com/thirdreality/LinuxBox_Finder)
- [LinuxBox Installer: HomeAssistant Installer for Third Reality Linux Box Dev Edition](https://github.com/thirdreality/LinuxBox-Installer)
- [LinuxBox Supervisor: supervisor For LinuxBox](https://github.com/thirdreality/LinuxBox_Supervisor)

## Compile firmware

This branch is based on Armbian 24.11 with Linux kernel 6.6.120 and Debian bookworm.

### Download

```bash
git clone git@github.com:thirdreality/LinuxBox.git -b hubv3-6.6.120
```

### Build environment

The build runs on the Armbian build framework, so the host must meet its requirements:

- x86_64 / aarch64 machine
- at least 2GB of memory and ~35GB of disk space
- Ubuntu Jammy 22.04.x for native building, or any Docker capable Linux for containerised building
- Superuser rights (configured sudo or root access)
- An up-to-date system (outdated Docker binaries, for example, can cause trouble)

On the first run, `compile.sh` installs the missing host dependencies automatically.

For details of the generic Armbian build framework, see [README-armbian.md](README-armbian.md).

### Compile

Run in the root directory of the repository.

```bash
cd LinuxBox; ./make-armbian-build-release.sh -b hubv3
```

Options:

- `-b` board: `hubv3` or `hubv3l` (default `hubv3`)
- `-r` release version, e.g. `v2.14.01.55` (default is the version in the script)

The compiled generated firmware is located:

`output/images/thirdreality_<board>_armbian_24.11_bookworm_6.6.120_v2.x.x.burn.img.zip`

Here is a pre-compiled image. If you don't have time to compile the image yourself and don't mind if it's slightly outdated, you can give it a try:

- hubv3:
- hubv3l:

More detail information please check [How-to-Compile-firmware](https://github.com/thirdreality/LinuxBox/wiki/How-to-Compile-firmware)


## Flash firmware

To prepare the burning environment on the computer:
1. Download and extract the file [Aml_Burn_Tool.zip](https://github.com/thirdreality/HA-Box/releases/download/Assets/Aml_Burn_Tool.zip).
2. If this is your first time using the tool, click on `Setup_Aml_Burn_Tool_V3.1.0.exe` to install necessary drivers.
3. Next, navigate to the `v2` folder and run `Aml_Burn_Tool.exe`.
4. Unzip the compiled `*.burn.img.zip` and load the `*.burn.img` firmware file.
5. Click on `Start` to initiate the burn process.
6. Press and hold the button circled in the image below, then connect the black line to your computer and start flashing. You can release the button when you start flashing.


<img width="400" alt="4368c63836c626d6132a6575918a2d9" src="https://github.com/user-attachments/assets/915d959e-3857-4868-a4ed-088bace91c03" />


More detail information please check the wiki: [How-to-burn-the-image-to-LinuxBox](https://github.com/thirdreality/LinuxBox/wiki/How-to-burn-the-image-to-LinuxBox)


## Tricks for using LinuxBox

### HomeAssistant

Thirdreality dev team supply a new way to install home assistant core in 8-10 minutes.

Check it in WIKI: [Tricks-for-Homeassistant](https://github.com/thirdreality/LinuxBox/wiki/Tricks-for-Homeassistant)


## License

This software is published under the GPL-2.0 License license.
