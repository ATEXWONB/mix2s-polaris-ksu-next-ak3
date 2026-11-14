# mix2s-polaris-ksu-next-ak3

为 **小米 MIX 2S (polaris / sdm845)** 在 **LineageOS 22.2** (Linux 4.9.337) 上适配编译的 **KernelSU-Next v3.4.2** AnyKernel3 卡刷包。

> 4 系内核怎么能没有 KSU 呢？本仓库一键拉取源码、自动集成 KSU-Next、编译内核、打包 AK3 卡刷包。

## ⚠️ 编译环境要求

**推荐**: Ubuntu 22.04+ 虚拟机或实体机 (x86_64)

**不建议**: Termux / proot / chroot —— 内核编译需要完整 glibc，Termux 的 bionic libc 会导致各种编译错误，且性能极差。

---

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

## 预编译发行版下载

**[点此下载 AK3 卡刷包](https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3/releases/download/v3.4.2-33355-polaris-los22.2/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip)**

| 文件 | 大小 | SHA256 |
|---|---|---|
| KernelSU-Next-33355-polaris-LOS22.2-AK3.zip | 18,733,994 bytes | `e357009611a9e8c204f71bcf71dbdf3cb43cfe3a4e42cdc8ce11a38cd166439c` |

### 刷机方法

1. 下载 AK3 zip 到手机存储
2. 重启到 Recovery (OrangeFox/TWRP)
3. 选择「安装」→ 选中 zip → 滑动刷入
4. 重启系统
5. 安装 KernelSU-Next 管理器 APK（从 [KSU-Next releases](https://github.com/KernelSU-Next/KernelSU-Next/releases/tag/v3.4.2) 下载 `KernelSU_Next_v3.4.2_33355-release.apk`）

> 本卡刷包只替换 boot 内核段 (Image.gz-dtb)，不修改 ramdisk，保留官方 DTB（26 个 FDT blob）。

---

## 一键编译

### 前置环境

```bash
sudo apt update && sudo apt install -y build-essential libncurses-dev bison flex libssl-dev libelf-dev zip python3 git wget unzip
```

### 两步编译

```bash
# 1. 克隆本仓库
git clone https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3.git
cd mix2s-polaris-ksu-next-ak3

# 2. 一键下载所有依赖（内核源码 + KSU-Next + 工具链，约3GB）
bash setup.sh

# 3. 一键集成 + 编译 + 打包
bash build.sh
```

编译完成后，产物在 `dist/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip`。

> **国内用户**：`setup.sh` 中的 git clone 可改用清华镜像加速：
> ```bash
> git clone https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/android_kernel_xiaomi_sdm845.git -b lineage-22.2 kernel
> ```

---

## 仓库结构

```
mix2s-polaris-ksu-next-ak3/
├── README.md                       # 本文件
├── setup.sh                        # 一键下载依赖（内核/KSU-Next/工具链/AK3）
├── build.sh                        # 一键集成+编译+打包
├── config/
│   └── polaris.config              # polaris 设备专属 defconfig 追加项
├── scripts/
│   ├── integrate_ksu_next.py      # KSU-Next v3.4.2 源码集成 + hook 补丁
│   └── rebuild_boot.py            # boot.img 重建工具（可选，直接修补boot镜像）
└── ak3/
    └── anykernel.sh                # polaris 专用 AnyKernel3 配置
```

### setup.sh 做了什么

1. 检测环境（拒绝 Termux/proot）
2. 克隆 [LineageOS sdm845 内核](https://github.com/LineageOS/android_kernel_xiaomi_sdm845) (lineage-22.2)
3. 克隆 [KernelSU-Next v3.4.2](https://github.com/KernelSU-Next/KernelSU-Next)
4. 克隆 [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
5. 下载 AOSP GCC 4.9 (aarch64 + arm) 交叉编译器
6. 下载 Android NDK r21e (提供 clang)

> 已有依赖自动检测跳过，版本不匹配自动重新下载。

### build.sh 做了什么

1. 前置检查（内核/工具链/配置文件是否就绪）
2. 检测 KSU 是否已集成，已集成则跳过
3. `make vendor/xiaomi/mi845_defconfig` + 追加 `polaris.config`
4. 强制 `CONFIG_KSU_MANUAL_HOOK=y`，关闭 `CONFIG_CC_WERROR`
5. `make dtbs` + `make Image.gz-dtb -j$(nproc)`
6. 打包 AnyKernel3 zip

### integrate_ksu_next.py 补丁说明

| 操作 | 说明 |
|---|---|
| 替换源码 | 用 KSU-Next v3.4.2 的 `kernel/` 替换 `kernel/KernelSU/kernel` |
| 摘除 hook | 删除 v0.9.5 遗留的 `vfs_read` / `devpts` / `input` hook（legacy 无实现） |
| 补充 hook | 在 `kernel/sys.c` 加 `setresuid` hook，在 `kernel/reboot.c` 加 `sys_reboot` hook |
| 补 shim | 补 8 个 4.9 内核缺失的头文件 (`compiler_types.h` 等) |

---

## 致谢

- [KernelSU](https://github.com/tiann/KernelSU) - 原作者 tiann
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) - Next 分支
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) - osm0sis
- [LineageOS](https://github.com/LineageOS) - LOS 22.2 内核源码

## License

- KernelSU-Next: GPL-3.0
- AnyKernel3: MIT
- 本仓库脚本与配置: MIT
