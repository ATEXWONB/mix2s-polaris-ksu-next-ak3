# mix2s-polaris-ksu-next-ak3

为 **小米 MIX 2S (polaris / sdm845)** 在 **LineageOS 22.2** (Linux 4.9.337) 上适配编译的 **KernelSU-Next v3.4.2** AnyKernel3 卡刷包。

> 4 系内核怎么能没有 KSU 呢？本仓库记录了从 LineageOS 内核源码集成 KernelSU-Next、编译内核、打包 AK3 卡刷包的完整流程，并附带已编译好的发行版。

## 设备信息

| 项目 | 值 |
|---|---|
| 设备 | Xiaomi Mi MIX 2S (polaris) |
| SoC | Qualcomm SDM845 |
| ROM | LineageOS 22.2 |
| 内核版本 | Linux 4.9.337 (msm-4.9) |
| KSU 版本 | KernelSU-Next v3.4.2 (33355, manual hook) |
| 编译器 | Android NDK clang r21e (9.0.9) + AOSP GCC 4.9 binutils |
| 补丁模式 | CONFIG_KSU_MANUAL_HOOK=y (无 kprobes) |

## 发行版下载

**[点此下载 AK3 卡刷包](https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3/releases/download/v3.4.2-33355-polaris-los22.2/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip)**

或浏览 [Releases](https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3/releases) 页面。

| 文件 | 大小 | SHA256 |
|---|---|---|
| KernelSU-Next-33355-polaris-LOS22.2-AK3.zip | 18,733,994 bytes | `e357009611a9e8c204f71bcf71dbdf3cb43cfe3a4e42cdc8ce11a38cd166439c` |

### 刷机方法

1. 下载 AK3 zip 到手机存储
2. 重启到 Recovery (OrangeFox/TWRP)
3. 选择「安装」→ 选中 zip → 滑动刷入
4. 重启系统
5. 安装 KernelSU-Next 管理器 APK（从 [KernelSU-Next releases](https://github.com/KernelSU-Next/KernelSU-Next/releases) 下载对应版本）

> 本卡刷包只替换 boot 内核段 (Image.gz-dtb)，不修改 ramdisk，保留官方 DTB（26 个 FDT blob）。

## 自行编译

### 前置环境

- Ubuntu 20.04/22.04 x86_64
- 安装编译依赖：
```bash
sudo apt install -y build-essential libncurses-dev bison flex libssl-dev libelf-dev zip python3 git
```

### 目录布局

建议工作目录结构：
```
ksu-build/
├── kernel/              # LineageOS 22.2 内核源码 (msm-4.9)
├── toolchain/
│   ├── gcc49/           # AOSP GCC 4.9 aarch64 交叉编译器
│   ├── gcc49-arm/       # AOSP GCC 4.9 arm 32-bit 交叉编译器
│   └── ndk-r21e/        # Android NDK r21e (clang)
├── scripts/             # 本仓库 scripts/ 目录
├── AnyKernel3/          # osm0sis AnyKernel3 模板
├── src/boot.img         # 官方/当前 ROM 的 boot.img (作模板)
├── out/                 # 内核编译输出 (make O=out)
└── dist/                # 打包产物
```

### 步骤 1：获取内核源码

```bash
# LineageOS 22.2 sdm845 内核
mkdir -p ksu-build && cd ksu-build
git clone https://github.com/LineageOS/android_kernel_xiaomi_sdm845 kernel
cd kernel && git checkout lineage-22.2
```

### 步骤 2：获取工具链

```bash
# AOSP GCC 4.9 (在 ksu-build/ 下)
# aarch64-linux-android-4.9
git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 toolchain/gcc49
# arm-linux-androideabi-4.9
git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 toolchain/gcc49-arm

# Android NDK r21e (提供 clang)
wget https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zipunzip android-ndk-r21e-linux-x86_64.zip -d toolchain/
mv toolchain/android-ndk-r21e toolchain/ndk-r21e
```

### 步骤 3：集成 KernelSU-Next

```bash
# 克隆 KernelSU-Next v3.4.2
git clone https://github.com/KernelSU-Next/KernelSU-Next -b v3.4.2 /path/to/KernelSU-Next

# 运行集成脚本（修改 scripts/integrate_ksu_next.py 中的 K 和 LC 路径）
# scripts/integrate_ksu_next.py 会：
#   1. 替换 kernel/KernelSU/kernel 为 KSU-Next 源码
#   2. 摘除 v0.9.5 遗留的 hook 点
#   3. 补 legacy 需要的 setresuid / sys_reboot hook
#   4. 补 8 个 4.9 内核缺失的头文件 shim
python3 scripts/integrate_ksu_next.py
```

### 步骤 4：编译内核

```bash
# 修改 scripts/build_kernel_next.sh 中的 W 路径后执行
bash scripts/build_kernel_next.sh
```

脚本做了什么：
1. `make vendor/xiaomi/mi845_defconfig` + 追加 `polaris.config`
2. 强制开启 `CONFIG_KSU_MANUAL_HOOK=y`，关闭 `CONFIG_CC_WERROR`
3. `make dtbs` + `make Image.gz-dtb -j$(nproc)`
4. 输出到 `out/arch/arm64/boot/Image.gz-dtb`

### 步骤 5：打包 AK3 卡刷包

```bash
# 修改 scripts/build_ak3_next.sh 中的路径后执行
bash scripts/build_ak3_next.sh
```

脚本会：
1. 复制 AnyKernel3 模板到 `dist/ak3-polaris/`
2. 放入编译好的 `Image.gz-dtb`
3. 写入 polaris 专用的 `anykernel.sh`（设备校验、boot 分区路径）
4. 打包为 `dist/KernelSU-Next-<ver>-polaris-LOS22.2-AK3.zip`

### 关于 boot.img 重建（可选）

如果你想直接修补 boot.img 而不是用 AK3：
```bash
python3 scripts/rebuild_boot.py <官方boot.img> <新Image.gz-dtb> <输出.img>
```
该脚本以官方 boot.img 为模板，仅替换内核段（gzip 部分），保留原 ramdisk 和 DTB，严格对齐 page 和 AVB footer。

## 仓库结构

```
├── README.md                  # 本文件
├── scripts/
│   ├── integrate_ksu_next.py  # KSU-Next 源码集成 + hook 补丁脚本
│   ├── build_kernel_next.sh   # 内核编译脚本 (defconfig + make Image.gz-dtb)
│   ├── build_ak3_next.sh      # AK3 卡刷包打包脚本
│   └── rebuild_boot.py        # boot.img 重建工具（仅替换内核段）
└── ak3/
    └── anykernel.sh           # polaris 专用 AnyKernel3 配置
```

## 致谢

- [KernelSU](https://github.com/tiann/KernelSU) - 原作者 tiann
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) - Next 分支
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) - osm0sis
- [LineageOS](https://github.com/LineageOS) - LOS 22.2 内核源码

## License

- KernelSU-Next: GPL-3.0 (见 KSU-Next 仓库)
- AnyKernel3: MIT (见 AK3 仓库)
- 本仓库脚本与配置: MIT
