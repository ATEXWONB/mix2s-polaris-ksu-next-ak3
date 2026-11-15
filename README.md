# mix2s-polaris-ksu-next-ak3

给 **小米 MIX 2S (polaris / sdm845)** 的 **LineageOS 22.2（Linux 4.9.337）** 内核适配编译的 **KernelSU-Next v3.4.2** AnyKernel3 卡刷包，附完整一键编译脚本。

> 4 系内核怎么能没有 KSU 呢？

## ⚠️ 编译环境

| | |
|---|---|
| **推荐** | Ubuntu 22.04 / 24.04，x86_64，虚拟机或实体机，4 核 8G 以上 |
| **不建议** | Termux / proot / chroot —— 内核编译需要完整 glibc 和系统调用，bionic libc 会各种报错，而且极慢 |
| **磁盘** | 至少 15 GB 空闲（内核源码 1 GB + 工具链 3 GB + 编译中间产物 4~6 GB） |

脚本会自动检测 Termux/proot 并直接拒绝编译。

---

## 预编译发行版

Release 页：[v3.4.2-33355-polaris-los22.2](https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3/releases/tag/v3.4.2-33355-polaris-los22.2)

| 文件 | 大小 | 说明 |
|---|---|---|
| [KernelSU-Next-33355-polaris-LOS22.2-AK3.zip](https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3/releases/download/v3.4.2-33355-polaris-los22.2/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip) | 18.7 MB | AK3 卡刷包（刷内核） |
| [KernelSU_Next_v3.4.2_33355-release.apk](https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3/releases/download/v3.4.2-33355-polaris-los22.2/KernelSU_Next_v3.4.2_33355-release.apk) | 16.7 MB | KSU 管理器 APK（装这个授权 root） |

SHA256：
```
AK3 : e357009611a9e8c204f71bcf71dbdf3cb43cfe3a4e42cdc8ce11a38cd166439c
APK : 774a5511f7034a4930e881114e202319cbdc34c5aaaa5c7c6b6d2902364e4c58
```

### 刷机步骤

1. 下载 AK3 zip 放手机存储
2. 进 Recovery（OrangeFox / TWRP），安装 → 选中 zip → 刷入
3. 重启进系统
4. 安装同页的 KSU 管理器 APK，打开确认显示「已安装 / 工作中」

> 本包只替换 boot 的内核段（`Image.gz-dtb`，内含 26 个平台 DTB），不动 ramdisk，不改 boot header，保留原厂 DTB 布局。
> 刷之前建议先备份当前 boot 分区。

---

## 设备 / 编译信息

| 项目 | 值 |
|---|---|
| 设备 | Xiaomi Mi MIX 2S（polaris） |
| SoC | Qualcomm SDM845 |
| ROM | LineageOS 22.2 |
| 内核 | Linux 4.9.337（msm-4.9，LineageOS `android_kernel_xiaomi_sdm845` lineage-22.2） |
| KSU | KernelSU-Next v3.4.2（versionCode 33355） |
| Hook 模式 | manual hook（`CONFIG_KSU_MANUAL_HOOK=y`，KPROBES 关闭） |
| 编译链 | NDK r21e clang 9.0.9 + AOSP GCC 4.9 binutils |
| defconfig | `vendor/xiaomi/mi845_defconfig` + `config/polaris.config` |

---

## 一键编译

```bash
# 1. 装基础依赖
sudo apt update
sudo apt install -y build-essential libncurses-dev bison flex libssl-dev \
     libelf-dev zip unzip python3 git curl bc

# 2. 拉仓库
git clone https://github.com/ATEXWONB/mix2s-polaris-ksu-next-ak3.git
cd mix2s-polaris-ksu-next-ak3

# 3. 下依赖（内核 166MB + AK3 + GCC4.9 + NDK 1.1GB，约 1.4GB；KSU 源码已随仓库提供）
bash setup.sh

# 4. 一键集成 + 编译 + 打包
bash build.sh
```

产物：`dist/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip`

### 国内网络

GitHub 直连不稳时，可以给脚本一个代理：

```bash
PROXY=socks5h://127.0.0.1:1080 bash setup.sh
```

`setup.sh` 内置了镜像兜底顺序：直连 → `gh-proxy.com` → `ghfast.top` → `ghproxy.net`，且下载中断会断点续传。NDK 走 `dl.google.com`（国内一般较快），失败会打印手动下载地址。

---

## 仓库结构

```
mix2s-polaris-ksu-next-ak3/
├── setup.sh                          # 下载内核源码 / AK3 / 工具链（带检测+断点续传+镜像兜底）
├── build.sh                          # 集成 + 编译 + 打包，全程校验
├── ksu-src/kernel/                   # KernelSU-Next 内核侧源码（legacy 分支 + 4.9 适配，已随仓库固定）
├── patches/
│   └── ksu-next-4.9-lineage-22.2.patch   # KSU 内核补丁（hook / Kconfig / 头文件 shim / defconfig）
├── scripts/
│   ├── apply_ksu.py                  # 应用补丁 + 部署 KSU 源码 + 建软链 + 校验（幂等）
│   └── rebuild_boot.py               # 可选：直接把 Image.gz-dtb 塞回 boot.img
├── config/
│   └── polaris.config                # polaris 设备专属配置（触摸/指纹/机型）
└── ak3/
    └── anykernel.sh                  # polaris 专用 AnyKernel3 脚本
```

## 集成方式（和别的 KSU 内核包有什么不同）

LineageOS 的 msm-4.9 树没有 GKI，也没有可用的 kprobe hook，所以走 **manual hook**：

1. `patches/ksu-next-4.9-lineage-22.2.patch` 打 19 处改动：
   - `fs/exec.c`：`ksu_handle_execveat` 挂到 `do_execveat_common`
   - `kernel/sys.c`：`ksu_handle_setresuid`
   - `kernel/reboot.c`：`ksu_handle_sys_reboot`
   - `fs/open.c` / `fs/stat.c` / `fs/namespace.c` / `fs/internal.h`：kernelsu 需要的内部接口导出
   - `security/selinux/*`：KSU su 域与策略hook
   - `drivers/Kconfig` + `drivers/Makefile`：挂载 `drivers/kernelsu`
   - `include/linux/{compiler_types,hex,pgtable,seccomp}.h` + 5 个 `sched/*.h` shim：4.9 缺的 5.x 头文件
   - `mi845_defconfig`：`CONFIG_KSU=y`
2. `ksu-src/kernel`（仓库内置的 legacy 分支源码，已做 4.9 兼容：`compiler_types.h` 等按内核版本条件包含）复制到 `kernel/KernelSU/kernel`
3. `kernel/drivers/kernelsu` 软链到 `../KernelSU/kernel`

`apply_ksu.py` 是幂等的：已集成会跳过；补丁先用 `--dry-run` 校验，失败不会留半成品。

## 实测记录

本仓库的脚本不是「写完就扔」——是在实际编译机上跑通的：

- `setup.sh`：在只有内核源码 + 工具链的机器上跑，正确识别已有依赖并跳过；故意删掉 NDK 后重跑，能自动重新下载并断点续传。
- `apply_ksu.py` + 补丁：对 GitHub 原始 `lineage-22.2` 树应用后，与人工集成成功并已编译出可用内核的树**逐字节一致**（19 个文件 diff 全 OK）。
- `build.sh`：从干净树出发，`dtbs` + `Image.gz-dtb` + AK3 打包全流程跑通，产物可刷机（见 Release）。


## 开机后管理器「未运行」延迟的修复

现象：硬重启后立刻打开管理器显示「未集成 / 未运行」，约 1~2 分钟后才显示 root 工作中。

原因：内核要先「认定」哪个包是管理器（`ksu_manager_appid`），认定方式是扫描 `/data/app` 校验 APK 签名。早期启动 `/data/app` 尚不可读（SELinux / fscrypt 未就绪），扫描失败后每 **15 秒**重试一次（最多 20 次），管理器必须等某次重试成功后才被认定，于是表现成开机后一两分钟才「有 root」。

修复（已包含在 `ksu-src/`，`bootfix` 卡刷包即此版本）：

1. `manager/throne_tracker.c`：重试间隔 `15s → 2s`，上限 `20 → 100` 次，SELinux 一就绪即可认定；
2. 新增 `ksu_throne_kick()`：管理器调用 `get_info` 查询时若尚未认定，立刻触发一次扫描（1 秒限流），不必干等定时器；
3. `supercall/dispatch.c`：`do_get_info` / `do_get_info_legacy` 接入上述 kick。

自查：开机后 `su -c 'dmesg | grep -i throne'`，应看到 `throne: kick scan by userspace` 和很快结束的 `throne: retry manager search #N`。
## 开机后模块 / Zygisk Next 不生效（必须软重启）的修复

现象：冷启动后模块（Zygisk Next / LSPosed 等）没有加载，得做一次软重启（只重启系统进程）才正常。

原因：manual hook 构建（无 kprobes）下，`init.rc` 注入原本依赖 kprobe 拦截 `read()`；kprobes 关闭后这段失效，`KERNEL_SU_RC` 永远注入不进去 —— 于是 `ksud post-fs-data` 不再由 init 在 post-fs-data 阶段执行，而是退回到「zygote 第一次 exec 时才触发」的兜底路径。模块挂载因此晚于 zygote 启动，Zygisk 类模块首启抓不到，只能软重启补一次。

修复（`patches/ksu-vfs-read-hook.patch` + `apply_ksu.py` 已内置）：

- 在 `fs/read_write.c` 的 `vfs_read()` 接入 `ksu_handle_vfs_read()`（KSU 源码里本就预留了这个 manual hook 接入点）；
- init 读取 `init.rc` 时即注入 `KERNEL_SU_RC`，init 在 `on post-fs-data` 阶段就 `exec /data/adb/ksud post-fs-data`；
- 模块在 zygote 启动之前完成挂载，Zygisk Next / LSPosed 冷启动即可生效，无需软重启。

自查：`su -c 'dmesg | grep -iE "init.rc|post-fs-data|module mounted"'`，应能看到 `read init.rc, comm: init` 与 `post-fs-data triggered`、`module mounted`。
## 致谢

- [KernelSU](https://github.com/tiann/KernelSU) / [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [LineageOS](https://github.com/LineageOS/android_kernel_xiaomi_sdm845)

## License

KernelSU-Next: GPL-3.0 ｜ AnyKernel3: MIT ｜ 本仓库脚本与配置: MIT
