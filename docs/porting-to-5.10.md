# 移植清单:hubv3-6.6.y → hubv3 (5.10.x)

把 `hubv3-6.6.y` 分支最近一批改动移植到 `hubv3`(5.10.x 内核)分支的对照清单。

- **源分支**:`hubv3-6.6.y`
- **目标分支**:`hubv3`(5.10.x,基于**较老版本**的 Armbian 构建框架)
- **提交范围**:`68fe60987^..c7159ef6a`(共 9 个提交)

---

## ⚠️ 两个分支的关键框架差异(先读这个)

1. **分区/挂载逻辑文件不同**
   - 6.6.y(新框架):`lib/functions/image/partitioning.sh`
   - 5.10.x(老框架):`lib/debootstrap.sh`
   - 结论:任何针对 `partitioning.sh` 的改动**不能直接 cherry-pick**,要手动改到 `lib/debootstrap.sh`。

2. **ext4 默认 commit 值不同**
   - 6.6.y:`commit=120`(在 partitioning.sh)
   - 5.10.x:`commit=600`(在 `lib/debootstrap.sh` 第 483 行,`mountopts[ext4]=',commit=600,errors=remount-ro'`)
   - 5.10.x 默认更激进,掉电窗口更大,改成 `commit=30` 更有必要。

3. **版本号体系不同**
   - 两分支版本号各自独立,`make-armbian-build-release.sh` 里的版本号**不要照搬**,按 5.10.x 分支自己的规则设。

4. **好消息**:5.10.x 的 `lib/debootstrap.sh` 也支持 `format_partitions` 扩展 hook(第 708 行)和 `BOOTFS_TYPE`/`BOOTSIZE`(第 519 行),所以只读 /boot 方案(#4)的 hook 逻辑可以工作。

---

## 逐提交清单

图例:✅ 可 cherry-pick / ⚠️ 需手动调整 / ⛔ 不要照搬

### 1. `68fe60987` feat: Preinstall mosquitto and Node.js 24 — ✅
- 文件:`vendor.repo/userpatches/customize-image.sh`(NodeSource 24.x 装在 `InstallForHubV3()`)、`config/boards/{linuxbox,trhubv3,trhubv3b}.conf`、`.github/workflows/{build-images,build-linuxbox}.yml`、`make-armbian-build-release.sh`。
- 注意:改 `vendor.repo/userpatches/customize-image.sh`(**不是** `userpatches/`,后者构建时被覆盖)。
- 注意:5.10.x 的 board conf 里 PACKAGE_LIST 变量名/内容可能不同,核对后再加 mosquitto。

### 2. `5cf808f7e` fix: Harden eMMC against power-loss — ⚠️ 拆两半
- **a) `config/bootscripts/boot-trhub.cmd`**:`data=writeback → data=ordered`。文件两分支都有,但 hubv3 版有文案差异且无 #4 的 prefix 块,**建议手动改这一行**而非 cherry-pick。
- **b) commit 值**:⛔ 不能 pick `partitioning.sh`。改 **`lib/debootstrap.sh` 第 483 行**:
  `mountopts[ext4]=',commit=600,errors=remount-ro'` → `commit=30`。

### 3. `3a9f6c4f7` feat: trhubv3 加 libprotobuf-lite32 + libjsoncpp25 — ✅
- 文件:`config/boards/trhubv3.conf`(PACKAGE_LIST_BOARD)。核对 5.10.x 的包列表后追加。

### 4. `9a0000122` feat: 独立只读 /boot 分区 — ⚠️ 核心,注意框架 hook
- 文件:`amlogic-tools.repo/bins/image.armbian.cfg`、`amlogic-tools.repo/dts/partition_arm.dtsi`、`config/bootscripts/boot-trhub.cmd`、`config/sources/families/trhub.conf`、`make-armbian-build-release.sh`。
- `amlogic-tools.repo/*`:内核无关,可直接用。
- `trhub.conf` 的 `BOOTFS_TYPE=ext4`/`BOOTSIZE=128` + `format_partitions__trhub_boot_ro()` hook:5.10.x 框架支持(debootstrap.sh 第 519、708 行),可用。**移植后务必验证 hook 真的被触发**(打印日志确认 fstab 里 /boot 变 ro)。
- `boot-trhub.cmd` 的 prefix 自动检测块:手动加。
- 版本号那行:见 #5,别照搬。

### 5. `a55e0813c` chore: 版本号 v2.14.01.40 — ⛔ 跳过
- `make-armbian-build-release.sh`。按 5.10.x 分支自己的版本号规则设,不要照搬。

### 6. `ba0ad4639` fix: 只预加载 aml_sdio — ⚠️ 核对变量名
- 文件:`config/boards/{trhubv3,trhubv3a}.conf`(`MODULES_CURRENT="aml_sdio"`)。
- 注意:5.10.x 分支若用不同变量名(如 `MODULES` 而非 `MODULES_CURRENT`,取决于 KERNEL_TARGET 命名),要对应调整。

### 7. `5bf977245` fix: factory-reset 保留 nodejs/mosquitto — ✅
- 文件:`packages/bsp/thirdreality/common/factory-reset.sh`。BSP 脚本,内核无关。

### 8. `a6a0e66e1` fix: usb-sync 工具健壮性 — ✅(但依赖 #4)
- 文件:`packages/bsp/thirdreality/common/hubv3-usb-sync.sh`。
- 注意:其中"内核 OTA 时 remount /boot rw"只有在 #4(只读 /boot)也移植后才有意义。**#4 和 #8 必须成对**。

### 9. `c7159ef6a` feat: resetupwifi 分级恢复 — ✅(但 reload 依赖驱动)
- 文件:`packages/bsp/thirdreality/common/setupNetwork/resetupwifi.sh`。
- 注意:`reload` 级别依赖 W1 驱动的 `set_usb_wifi_power`(rmmod/insmod 触发芯片 power-cycle)。确认 5.10.x 的 `jethome-0011` WiFi 驱动补丁有同样逻辑,移植后重新验证。
- `auto` 升级到 `reload` 的钩子当前是注释状态(`run_auto` 里),硬件测试通过后再打开。

---

## 建议流程

1. 先 cherry-pick 纯通用项:#1、#3、#7、#8、#9(#3/#6 可能因包列表差异有小冲突,手动解决)。
2. 手动处理框架相关项:
   - #2b:`lib/debootstrap.sh` 的 `commit=600 → 30`。
   - #2a:`boot-trhub.cmd` 的 `data=ordered`(手动改一行)。
   - #4:amlogic-tools 直接用;`trhub.conf` hook + `boot-trhub.cmd` prefix 块手动加;**验证 hook 触发**。
3. #5 版本号:按 5.10.x 规则重设,不照搬。
4. #6:核对 board conf 的 MODULES 变量名。
5. 全部完成后编译一版,烧录验证:
   - `mount | grep -E ' / |/boot'` → /boot 只读、rootfs `commit=30,data=ordered`;
   - 冷启动不卡 90s;
   - (可选)`resetupwifi.sh reload` 验证 WiFi 芯片 power-cycle。

## 成对/依赖关系
- **#4 ↔ #8**:只读 /boot 和 usb-sync 的 remount 必须一起。
- **#9 依赖** 5.10.x 的 W1 驱动补丁有 `set_usb_wifi_power`。
- **#1 ↔ #7**:预装 nodejs/mosquitto 和 factory-reset 保留它们,逻辑上配套。

---

## 5.10.x (hubv3 分支) 实际移植记录

已在 `hubv3` 分支完成移植。以下记录**实际情况与上文预期的差异**,供后续参考。

### 关键路径差异(与上文 amlogic-tools 预期不同)
- 打包工具在 **`tools/Armbian_Convert/`**(不是 `amlogic-tools.repo/`,后者在 5.10.x 为空占位):
  - 分区表:`tools/Armbian_Convert/dts/partition_arm.dtsi`
  - image cfg:`tools/Armbian_Convert/src/j100/image.armbian.cfg`(trhubv3/v3b/linuxbox 的 CNAME 都是 `j100`)
  - convert 脚本:`tools/Armbian_Convert/convert.sh`
- 编译入口:**`make_armbian_for_hubv3.sh`**(不是 6.6.y 的 `make-armbian-build-release.sh`),它调用 `tools/Armbian_Convert/convert.sh`
- 分区/mount 逻辑:`lib/debootstrap.sh`(ext4 默认 `commit=600`)
- nodejs:已在被 git 跟踪的 **`custom/customize-image.sh`**(`InstallForHubV3`),**无需移植**
- 5.10.x **没有** `trhubv3a.conf`、**没有** `vendor.repo/`

### 各项实际处理方式
- **#2**:`lib/debootstrap.sh` `commit=600→30` + `boot-trhub.cmd` `data=writeback→ordered`
- **#4**:`tools/Armbian_Convert/dts/partition_arm.dtsi`(双分区) + `src/j100/image.armbian.cfg`(part-1→boot, part-2→rootfs) + `boot-trhub.cmd`(prefix 自动检测) + `trhub.conf`(BOOTFS_TYPE/BOOTSIZE + `format_partitions__trhub_boot_ro` hook)。已确认 `debootstrap.sh` 支持 bootpart 创建、写 `/boot` fstab 条目、`rootdev=UUID`(rootfs 在 p2 也能启动)
- **#7**:`factory-reset.sh` 两分支分叉严重(235 行),用 6.6.y 完整版覆盖对齐;#8/#9 干净 cherry-pick
- **#1/#3/#6**:board conf 手动加(保留 5.10.x 的音频库 libflac/opus/soxr/vorbis),加 mosquitto + libjsoncpp25(仅 trhubv3) + `MODULES_CURRENT="aml_sdio"`
- **#5**:跳过(版本机制不同)

### 仍需硬件验证(5.10.x 特有)
1. `format_partitions__trhub_boot_ro` hook 是否被老框架 extension manager 调用 → 烧录后 `mount | grep /boot` 看是否 `ro`
2. u-boot **v2022.07**(比 6.6.y 的 v2023.10 老)的 prefix 自动检测 → 能否找到 kernel/dtb 正常启动
