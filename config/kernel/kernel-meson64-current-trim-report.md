# Linux Kernel 5.10 (meson64-current) Trim Report for TRHub V3B / LinuxBox

**Date:** 2026-03-17
**Target:** ThirdReality HubV3B / LinuxBox (Amlogic A113X, meson-axg, 2GB RAM)
**Base config:** `config/kernel/linux-meson64-current.config`
**Reference:** `kernel-linuxbox-hubv3a-trim-report.md` (6.6 kernel, validated on HubV3A)

## Platform Constraints

- **CPU:** Amlogic A113X (meson-axg), quad-core ARM Cortex-A53
- **WiFi/BT:** Amlogic W1 chip (private out-of-tree driver, needs CFG80211 + MAC80211)
- **Audio:** USB sound card only (no AXG onboard I2S/TDM/SPDIF/PDM)
- **Ethernet:** None
- **Display:** None (headless hub)
- **Storage:** eMMC + USB mass storage

## Summary

| Metric | Value |
|--------|-------|
| Configs enabled before | 6053 |
| Configs enabled after | **5112** |
| Configs disabled | **949** |
| Value changes (m→y) | **5** (ZRAM, DM_VERITY, DM_BUFIO, DM_BIO_PRISON, DM_PERSISTENT_DATA) |
| Diff file | `linux-meson64-current-trim.diff` (2789 lines) |
| Estimated kernel image reduction | **~8–10 MB** |
| Estimated runtime memory savings | **~80–100 MB** |

## Disabled by Category

| # | Category | Count | Risk |
|---|----------|-------|------|
| 1 | ACPI | 32 | Low |
| 2 | EFI | 14 | Low |
| 3 | NUMA / HugeTLB / THP | 5 | Low |
| 4 | BPF_SYSCALL | 2 | Low |
| 5 | DRM / Display / Panel / Bridge | ~100 | Low |
| 6 | Framebuffer / Backlight | ~60 | Low |
| 7 | HDMI / CEC / Media / Video / DVB | ~460 | Low |
| 8 | Sound: SND_SOC codecs (all) | ~175 | Low |
| 9 | Sound: SND_MESON_* (AXG onboard) | 18 | Low |
| 10 | Sound: SND_PCI / SND_HDA | ~5 | Low |
| 11 | Security: SELinux / SMACK / TOMOYO | ~20 | Medium |
| 12 | Netfilter: nftables (NFT_*) | ~43 | Medium |
| 13 | Traffic Control: NET_SCH / NET_CLS | ~47 | Medium |
| 14 | Filesystem: XFS/BTRFS/F2FS/ReiserFS/JFS/GFS2/OCFS2/NILFS2 | ~35 | Low |
| 15 | Filesystem: NFS/NFSD/CEPH/AFS/9P | ~35 | Low |
| 16 | DM: non-essential (RAID/MIRROR/CACHE/THIN/CLONE/...) | ~21 | Medium |
| 17 | MD RAID (all) | ~11 | Low |
| 18 | Ethernet: all vendors + drivers | ~70 | Low |
| 19 | WLAN vendors (all — W1 uses out-of-tree) | ~13 | Low |
| 20 | USB Serial (trim, keep CH341/CP210X/FTDI/PL2303/F8153X/WWAN/OPTION/QT2/DEBUG) | ~43 | Low |
| 21 | USB Net (all) | ~28 | Low |
| 22 | HID drivers (non-generic) | ~115 | Low |
| 23 | I2C: non-Meson controllers | ~55 | Low |
| 24 | SPI: non-Meson controllers | ~25 | Low |
| 25 | FB_TFT (staging) | ~30 | Low |
| **Total** | | **~1260** | |

## Key Design Decisions

### Aligned with 6.6 Trim Report (already validated)
- No ACPI (ARM embedded, not x86)
- No NUMA / HUGETLB / Transparent Hugepages
- No EFI
- No SELinux / SMACK / TOMOYO (disable all heavy LSMs; keep AppArmor)
- No XFS / BTRFS / F2FS / ReiserFS / JFS / GFS2 / OCFS2
- No nftables (iptables only)
- No BPF_SYSCALL
- No DRM / Framebuffer / HDMI / CEC / Media
- No SoC audio codecs, no Meson onboard audio, no PCI audio
- Minimal I2C (only Meson), minimal SPI (only Meson)
- No PCI I2C controllers, no USB-to-I2C adapters
- USB serial: keep common chips (CH341/CP210X/FTDI/PL2303/F8153X), disable rare ones
- No USB net
- No Ethernet (A113X hub has no Ethernet)

### New Decisions (beyond 6.6 report)
- SND_MESON_AXG_* disabled — confirmed no AXG onboard audio hardware
- All NET_VENDOR_* + associated drivers disabled — confirmed no Ethernet
- All WLAN_VENDOR_* disabled — W1 uses out-of-tree driver
- FB_TFT staging drivers disabled — no LCD/TFT display

### Configs Preserved (must keep)

| Config | Reason |
|--------|--------|
| `CONFIG_SOUND=m` | Sound subsystem |
| `CONFIG_SND=m` | ALSA core |
| `CONFIG_SND_USB=y` | USB sound subsystem |
| `CONFIG_SND_USB_AUDIO=m` | USB Audio class driver |
| `CONFIG_SND_USB_AUDIO_USE_MEDIA_CONTROLLER=y` | Media controller |
| `CONFIG_USB_AUDIO=m` | USB gadget audio |
| `CONFIG_CFG80211=y` | WiFi configuration (W1 dependency) |
| `CONFIG_MAC80211=y` | WiFi mac80211 (W1 dependency) |
| `CONFIG_WIRELESS=y` | Wireless subsystem |
| `CONFIG_BT=y` | Bluetooth |
| `CONFIG_PREEMPT=y` | Full preemption |
| `CONFIG_I2C_MESON=y` | Meson I2C |
| `CONFIG_SPI_MESON_SPICC=y` | Meson SPI |
| `CONFIG_SPI_MESON_SPIFC=y` | Meson SPI flash |
| `CONFIG_SERIAL_MESON=y` | Meson UART |
| `CONFIG_PINCTRL_MESON_AXG=y` | AXG pin control |
| `CONFIG_PINCTRL_MESON_AXG_PMX=y` | AXG pin mux |
| `CONFIG_MMC_MESON_GX=y` | eMMC/MMC |
| `CONFIG_USB=y` | USB host |
| `CONFIG_USB_XHCI_HCD=y` | USB 3.0 host |
| `CONFIG_USB_DWC3=y` | DesignWare USB3 |
| `CONFIG_USB_DWC2=y` | DesignWare USB2 |
| `CONFIG_USB_DWC3_MESON_G12A=y` | Meson USB3 glue |
| `CONFIG_USB_STORAGE=y` | USB mass storage |
| `CONFIG_EXT4_FS=y` | ext4 |
| `CONFIG_FAT_FS=y` | FAT |
| `CONFIG_VFAT_FS=y` | VFAT |
| `CONFIG_SQUASHFS=y` | SquashFS |
| `CONFIG_OVERLAY_FS=y` | OverlayFS |
| `CONFIG_FUSE_FS=y` | FUSE |
| `CONFIG_TMPFS=y` | tmpfs |
| `CONFIG_EROFS_FS=m` | EROFS (may need =y if used as rootfs) |
| `CONFIG_SWAP=y` | Swap support |
| `CONFIG_ZSWAP=y` | Compressed swap cache |
| `CONFIG_ZRAM=m → y` | zram (boot-critical) |
| `CONFIG_DM_VERITY=m → y` | dm-verity (boot-critical) |
| `CONFIG_DM_CRYPT=m` | Disk encryption |
| `CONFIG_SECURITY_APPARMOR=y` | Container LSM |
| `CONFIG_SECURITY_YAMA=y` | ptrace restrictions |
| `CONFIG_USB_SERIAL=m` | USB serial framework |
| `CONFIG_USB_SERIAL_GENERIC=y` | Generic USB serial |
| `CONFIG_USB_SERIAL_SIMPLE=m` | Simple USB serial |
| `CONFIG_USB_SERIAL_CH341=m` | CH340/CH341 USB-UART |
| `CONFIG_USB_SERIAL_CP210X=m` | CP210x USB-UART |
| `CONFIG_USB_SERIAL_FTDI_SIO=m` | FTDI USB-UART |
| `CONFIG_USB_SERIAL_F8153X=m` | F8153x USB-UART |
| `CONFIG_USB_SERIAL_PL2303=m` | PL2303 USB-UART |
| `CONFIG_USB_SERIAL_WWAN=m` | USB WWAN serial |
| `CONFIG_USB_SERIAL_OPTION=m` | Option USB serial |
| `CONFIG_USB_SERIAL_QT2=m` | QT2 USB serial |
| `CONFIG_USB_SERIAL_DEBUG=m` | USB serial debug |
| `CONFIG_HID=y` | HID core (USB Audio HID) |
| `CONFIG_HID_GENERIC=y` | Generic HID |
| `CONFIG_USB_HID=m` | USB HID |
| `CONFIG_PHY_MESON_AXG_PCIE=y` | AXG PHY |
| `CONFIG_PHY_MESON_AXG_MIPI_PCIE_ANALOG=y` | AXG analog PHY |
| `CONFIG_PHY_MESON_GXL_USB2=y` | USB2 PHY |
| `CONFIG_PHY_MESON_G12A_USB2=y` | USB2 PHY |
| `CONFIG_PHY_MESON_G12A_USB3_PCIE=y` | USB3 PHY |
| `CONFIG_COMMON_CLK_AXG=y` | AXG clock |
| `CONFIG_MESON_GXBB_WATCHDOG=m` | Watchdog |

### Value Changes

| Config | Old | New | Reason |
|--------|-----|-----|--------|
| `CONFIG_ZRAM` | m | y | Boot-critical for /var |
| `CONFIG_DM_VERITY` | m | y | Boot-critical for rootfs verification |
| `CONFIG_DM_BUFIO` | m | y | DM dependency |
| `CONFIG_DM_BIO_PRISON` | m | y | DM dependency |
| `CONFIG_DM_PERSISTENT_DATA` | m | y | DM dependency |

### Memory Optimization

| Parameter | Old | New | Savings |
|-----------|-----|-----|---------|
| CMA_SIZE_MBYTES | 128 | 4 | ~124 MB |
| CMA_AREAS | 7 | 4 | Reduced overhead |
| NODES_SHIFT | 2 | 0 | No NUMA |
| TRANSPARENT_HUGEPAGE | y | disabled | ~2-4 MB |
| HUGETLBFS | y | disabled | Minor |

## Detailed Disable Lists

### Category 1: ACPI (32 items)

```
CONFIG_ACPI=y
CONFIG_ACPI_GENERIC_GSI=y
CONFIG_ACPI_CCA_REQUIRED=y
CONFIG_ACPI_SPCR_TABLE=y
CONFIG_ACPI_AC=y
CONFIG_ACPI_BATTERY=y
CONFIG_ACPI_BUTTON=y
CONFIG_ACPI_FAN=y
CONFIG_ACPI_PROCESSOR_IDLE=y
CONFIG_ACPI_MCFG=y
CONFIG_ACPI_CPPC_LIB=y
CONFIG_ACPI_PROCESSOR=y
CONFIG_ACPI_IPMI=m
CONFIG_ACPI_HOTPLUG_CPU=y
CONFIG_ACPI_THERMAL=y
CONFIG_ACPI_TABLE_UPGRADE=y
CONFIG_ACPI_CONTAINER=y
CONFIG_ACPI_HED=y
CONFIG_ACPI_REDUCED_HARDWARE_ONLY=y
CONFIG_ACPI_NUMA=y
CONFIG_ACPI_APEI=y
CONFIG_ACPI_APEI_GHES=y
CONFIG_ACPI_APEI_SEA=y
CONFIG_ACPI_APEI_MEMORY_FAILURE=y
CONFIG_ACPI_APEI_EINJ=y
CONFIG_ACPI_WATCHDOG=y
CONFIG_ACPI_IORT=y
CONFIG_ACPI_GTDT=y
CONFIG_ACPI_PPTT=y
CONFIG_ACPI_CPPC_CPUFREQ=m
CONFIG_ACPI_I2C_OPREGION=y
CONFIG_ACPI_ALS=m
```

### Category 2: EFI (14 items)

```
CONFIG_EFI_STUB=y
CONFIG_EFI=y
CONFIG_EFI_ESRT=y
CONFIG_EFI_VARS_PSTORE=m
CONFIG_EFI_PARAMS_FROM_FDT=y
CONFIG_EFI_RUNTIME_WRAPPERS=y
CONFIG_EFI_GENERIC_STUB=y
CONFIG_EFI_ARMSTUB_DTB_LOADER=y
CONFIG_EFI_GENERIC_STUB_INITRD_CMDLINE_LOADER=y
CONFIG_EFI_BOOTLOADER_CONTROL=m
CONFIG_EFI_CAPSULE_LOADER=y
CONFIG_EFI_EARLYCON=y
CONFIG_EFI_CUSTOM_SSDT_OVERLAYS=y
CONFIG_EFIVAR_FS=m
```

### Category 3: NUMA / HugeTLB / THP (5 items)

```
CONFIG_NUMA=y
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y
CONFIG_HUGETLBFS=y
CONFIG_HUGETLB_PAGE=y
```

### Category 4: BPF (2 items)

```
CONFIG_BPF_SYSCALL=y
CONFIG_CGROUP_BPF=y
```

### Category 5–7: DRM / Framebuffer / HDMI / Media

Too many to list individually (~620 items). Key top-level switches:

```
CONFIG_DRM=y → disable (cascades to all DRM_*)
CONFIG_FRAMEBUFFER_CONSOLE=y → disable
CONFIG_FB_TFT=m → disable (cascades to all FB_TFT_*)
CONFIG_BACKLIGHT_CLASS_DEVICE=y → disable (cascades to all BACKLIGHT_*)
CONFIG_MEDIA_SUPPORT → disable (cascades to all VIDEO_*, DVB_*, CEC_*)
```

### Category 8–10: Sound (non-USB, ~198 items)

All `CONFIG_SND_SOC_*` codecs (lines 6301–6474), all `#CONFIG_SND_MESON_*` (already commented, keep as-is), all `#CONFIG_SND_SOC_ROCKCHIP*`, `#CONFIG_SND_SOC_XILINX*` (already commented).

Active items to disable:
```
CONFIG_SND_SOC_AC97_CODEC=m through CONFIG_SND_SIMPLE_CARD=m
(approximately 175 individual SND_SOC_* codec modules)
```

### Category 11: Security — SELinux / SMACK / TOMOYO (~20 items)

```
CONFIG_SECURITY_SELINUX=y (+ 7 sub-items)
CONFIG_SECURITY_SMACK=y (+ 2 sub-items)
CONFIG_SECURITY_TOMOYO=y (+ 4 sub-items)
CONFIG_AUDIT=y
CONFIG_AUDITSYSCALL=y
CONFIG_SECURITY_NETWORK_XFRM=y
```

### Category 12: nftables (~43 items)

```
CONFIG_NF_TABLES=m (+ NF_TABLES_INET, _NETDEV, _IPV4, _ARP, _IPV6, _BRIDGE)
CONFIG_NFT_NUMGEN=m through CONFIG_NFT_BRIDGE_REJECT=m (36 items)
```

### Category 13: Traffic Control (~47 items)

```
CONFIG_NET_SCH_CBQ=m through CONFIG_NET_SCH_ETS=m (~32 items)
CONFIG_NET_CLS_BASIC=m through CONFIG_NET_CLS_MATCHALL=m (~14 items)
```

### Category 14–15: Filesystems (~70 items)

```
CONFIG_REISERFS_FS=m (+ 4 sub)
CONFIG_JFS_FS=m (+ 3 sub)
CONFIG_XFS_FS=m (+ 4 sub)
CONFIG_GFS2_FS=m (+ 1 sub)
CONFIG_OCFS2_FS=m (+ 4 sub)
CONFIG_BTRFS_FS=y (+ 1 sub) ← NOTE: currently built-in!
CONFIG_F2FS_FS=y (+ 5 sub) ← NOTE: currently built-in!
CONFIG_NILFS2_FS=m
CONFIG_NFS_FS=m (+ 18 sub-items)
CONFIG_NFSD=m (+ 9 sub-items)
CONFIG_CEPH_FS=m (+ 3 sub)
CONFIG_AFS_FS=m (+ 1 sub)
CONFIG_9P_FS=m (+ 3 sub)
```

### Category 16–17: DM / MD RAID (~32 items)

MD RAID (all):
```
CONFIG_BLK_DEV_MD=m, CONFIG_MD_LINEAR/RAID0/RAID1/RAID10/RAID456/MULTIPATH/FAULTY/CLUSTER
CONFIG_RAID6_PQ=y
```

DM (non-essential):
```
CONFIG_DM_THIN_PROVISIONING=m
CONFIG_DM_CACHE=m, CONFIG_DM_CACHE_SMQ=m
CONFIG_DM_SNAPSHOT=m
CONFIG_DM_MIRROR=m
CONFIG_DM_RAID=m
CONFIG_DM_MULTIPATH=m, _QL=m, _ST=m
CONFIG_DM_ERA=m, CONFIG_DM_CLONE=m
CONFIG_DM_DUST=m, CONFIG_DM_FLAKEY=m
CONFIG_DM_SWITCH=m, CONFIG_DM_LOG_WRITES=m
CONFIG_DM_WRITECACHE=m, CONFIG_DM_INTEGRITY=m
CONFIG_DM_ZONED=m, CONFIG_DM_UNSTRIPED=m
CONFIG_DM_LOG_USERSPACE=m
CONFIG_DM_DEBUG=y
```

### Category 18: Ethernet (~70 items)

All `CONFIG_NET_VENDOR_*` (63 vendors) plus:
```
CONFIG_STMMAC_ETH=y, CONFIG_STMMAC_PLATFORM=y
CONFIG_DWMAC_GENERIC=m, CONFIG_DWMAC_MESON=m, CONFIG_DWMAC_ROCKCHIP=m, CONFIG_DWMAC_INTEL_PLAT=m
CONFIG_E1000E=y, CONFIG_IGB=y, CONFIG_IGB_HWMON=y, CONFIG_IGBVF=y
CONFIG_BNX2=m, CONFIG_BNX2X=m, CONFIG_BNXT=m (+ sub-items)
CONFIG_MESON_GXL_PHY=m
CONFIG_MDIO_BUS_MUX_MESON_G12A=y
```

### Category 19: WLAN Vendors (~13 items)

```
CONFIG_WLAN_VENDOR_ATMEL=y
CONFIG_WLAN_VENDOR_BROADCOM=y
CONFIG_WLAN_VENDOR_CISCO=y
CONFIG_WLAN_VENDOR_INTEL=y
CONFIG_WLAN_VENDOR_INTERSIL=y
CONFIG_WLAN_VENDOR_MARVELL=y
CONFIG_WLAN_VENDOR_MICROCHIP=y
CONFIG_WLAN_VENDOR_RALINK=y
CONFIG_WLAN_VENDOR_RSI=y
CONFIG_WLAN_VENDOR_ST=y
CONFIG_WLAN_VENDOR_TI=y
CONFIG_WLAN_VENDOR_ZYDAS=y
CONFIG_WLAN_VENDOR_QUANTENNA=y
CONFIG_MAC80211_HWSIM=m
CONFIG_USB_NET_RNDIS_WLAN=m
```

### Category 20: USB Serial (trim ~43, keep 10)

Kept (matching 6.6 .config):
```
CONFIG_USB_SERIAL=m
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_SERIAL_SIMPLE=m
CONFIG_USB_SERIAL_CH341=m       ← CH340/CH341
CONFIG_USB_SERIAL_CP210X=m      ← Silicon Labs CP210x
CONFIG_USB_SERIAL_FTDI_SIO=m    ← FTDI FT232/FT2232
CONFIG_USB_SERIAL_F8153X=m      ← F8153x
CONFIG_USB_SERIAL_PL2303=m      ← Prolific PL2303
CONFIG_USB_SERIAL_WWAN=m        ← WWAN modem
CONFIG_USB_SERIAL_OPTION=m      ← Option modem
CONFIG_USB_SERIAL_QT2=m         ← Quatech
CONFIG_USB_SERIAL_DEBUG=m       ← Debug
```

Disabled (~43 rare/unused serial adapters):
AIRCABLE, ARK3116, BELKIN, WHITEHEAT, DIGI_ACCELEPORT, CYPRESS_M8,
EMPEG, VISOR, IPAQ, IR, EDGEPORT, EDGEPORT_TI, F81232, GARMIN, IPW,
IUU, KEYSPAN_PDA, KEYSPAN, KLSI, KOBIL_SCT, MCT_U232, METRO,
MOS7720, MOS7840, MXUPORT, NAVMAN, OTI6858, QCAUX, QUALCOMM,
SPCP8X5, SAFE, SIERRAWIRELESS, SYMBOL, TI, CYBERJACK, XIRCOM,
OMNINET, OPTICON, XSENS_MT, WISHBONE, SSU100, UPD78F0730

### Category 21–24: USB Net / HID / I2C / SPI

See diff file for complete item lists.

## Risk Assessment

| Risk Level | Categories | Mitigation |
|------------|------------|------------|
| **Low** | ACPI, EFI, DRM, Display, Media, Ethernet, USB Serial/Net, HID, FS, I2C, SPI | Already validated on 6.6 / HubV3A |
| **Medium** | Security (LSM), Netfilter (nftables), DM, Traffic Control | Test container/Docker functionality after trim |
| **High** | None identified | — |

## Notes

1. **BTRFS and F2FS are currently =y (built-in)** — verify no partition uses these formats before disabling
2. **NFS is used by `PACKAGE_LIST_BOARD` (nfs-common)** — if NFS mount is needed at runtime, keep `CONFIG_NFS_FS=m`
3. **EROFS_FS** is currently =m — change to =y if used as root partition (same as 6.6 report)
4. **SND_MESON_AXG_*** are already commented out in 5.10 config — no change needed, just documenting
5. **W1 WiFi driver** is out-of-tree, only needs CFG80211 + MAC80211 framework
6. **AppArmor** is kept for Docker/container support
7. **iptables** (`IP_NF_*`, `IP6_NF_*`, `NETFILTER_XT_*`) are kept — only nftables removed
