#!/usr/bin/env bash
# setup.sh - 自动下载编译所需的所有依赖
# 用法: bash setup.sh
#
# 警告: 不建议在 Termux / proot / chroot 环境中编译！
#       推荐使用 Ubuntu 22.04+ 虚拟机或实体机。

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "=========================================="
echo "  KSU-Next v3.4.2 for Mi MIX 2S (polaris)"
echo "  LineageOS 22.2 / Linux 4.9.337"
echo "=========================================="
echo ""
echo "[警告] 不建议在 Termux / proot / chroot 中编译！"
echo "       推荐 Ubuntu 22.04+ 虚拟机或实体机。"
echo ""

# ========== 环境检测 ==========
echo "[环境检测]"

# 检测 Termux
if [ -d "/data/data/com.termux" ] || [ "$PREFIX" = "/data/data/com.termux/files/usr" ]; then
    echo "[错误] 检测到 Termux 环境！内核编译需要完整 glibc，"
    echo "       Termux 的 bionic libc 会导致各种编译错误。"
    echo "       请使用 Ubuntu 虚拟机或实体机。"
    exit 1
fi

# 检测 proot
if [ -f "/proc/1/comm" ] && [ "$(cat /proc/1/comm)" = "proot" ]; then
    echo "[警告] 检测到 proot 环境，可能会出现编译问题。"
    read -p "是否继续? (y/N) " ans
    [ "$ans" != "y" ] && exit 1
fi

# 检测必需命令
MISSING=""
for cmd in git wget unzip make gcc python3 zip bc bison flex; do
    command -v $cmd &>/dev/null || MISSING="$MISSING $cmd"
done
if [ -n "$MISSING" ]; then
    echo "[缺少依赖] 正在安装: $MISSING"
    sudo apt update && sudo apt install -y build-essential libncurses-dev bison flex libssl-dev libelf-dev zip python3 git wget unzip bc
fi
echo "[环境检测] 通过"
echo ""

# ========== 镜像配置 ==========
# 国内用户取消注释使用清华镜像
# KERNEL_REPO="https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/android_kernel_xiaomi_sdm845.git"
KERNEL_REPO="https://github.com/LineageOS/android_kernel_xiaomi_sdm845.git"
KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
KERNEL_BRANCH="lineage-22.2"
KSU_TAG="v3.4.2"

# ========== 1. 内核源码 ==========
echo "[1/5] 检查 LineageOS sdm845 内核源码..."
if [ -d "kernel/.git" ]; then
    cd kernel
    REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if echo "$REMOTE" | grep -q "sdm845"; then
        echo "  内核源码已存在"
        git fetch origin $KERNEL_BRANCH 2>/dev/null && git checkout $KERNEL_BRANCH 2>/dev/null || true
    else
        echo "  remote 不匹配，重新克隆..."
        cd ..; rm -rf kernel
        git clone --depth=1 -b $KERNEL_BRANCH $KERNEL_REPO kernel
    fi
    cd $ROOT
else
    echo "  克隆内核源码 (约980MB)..."
    git clone --depth=1 -b $KERNEL_BRANCH $KERNEL_REPO kernel
fi
echo ""

# ========== 2. KernelSU-Next ==========
echo "[2/5] 检查 KernelSU-Next v3.4.2..."
if [ -d "KSU-Next/.git" ]; then
    cd KSU-Next
    TAG=$(git describe --tags 2>/dev/null || echo "")
    if echo "$TAG" | grep -q "v3.4.2"; then
        echo "  KSU-Next 已是 $TAG"
    else
        echo "  版本不匹配 ($TAG)，切换到 $KSU_TAG..."
        git fetch origin --tags 2>/dev/null
        git checkout $KSU_TAG 2>/dev/null || { cd ..; rm -rf KSU-Next; git clone --depth=1 -b $KSU_TAG $KSU_REPO KSU-Next; }
    fi
    cd $ROOT
else
    echo "  克隆 KernelSU-Next $KSU_TAG..."
    git clone --depth=1 -b $KSU_TAG $KSU_REPO KSU-Next
fi
echo ""

# ========== 3. AnyKernel3 ==========
echo "[3/5] 检查 AnyKernel3..."
if [ -d "AnyKernel3/.git" ]; then
    echo "  AnyKernel3 已存在"
else
    git clone --depth=1 $AK3_REPO AnyKernel3
fi
echo ""

# ========== 4. 工具链 ==========
mkdir -p toolchain
echo "[4/5] 检查工具链..."

# GCC 4.9 aarch64
if [ -x "toolchain/gcc49/bin/aarch64-linux-android-gcc" ]; then
    echo "  GCC 4.9 aarch64: 已就绪"
else
    echo "  下载 GCC 4.9 aarch64..."
    rm -rf toolchain/gcc49
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 toolchain/gcc49
fi

# GCC 4.9 arm
if [ -x "toolchain/gcc49-arm/bin/arm-linux-androideabi-gcc" ]; then
    echo "  GCC 4.9 arm: 已就绪"
else
    echo "  下载 GCC 4.9 arm..."
    rm -rf toolchain/gcc49-arm
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 toolchain/gcc49-arm
fi

# NDK r21e
if [ -x "toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
    echo "  NDK r21e clang: 已就绪"
else
    echo "  下载 Android NDK r21e (约1.1GB)..."
    cd toolchain
    wget -c https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zip
    unzip -q android-ndk-r21e-linux-x86_64.zip
    mv android-ndk-r21e ndk-r21e
    rm -f android-ndk-r21e-linux-x86_64.zip
    cd $ROOT
fi
echo ""

# ========== 5. 输出目录 ==========
mkdir -p out dist logs backup

echo "=========================================="
echo "  Setup 完成!"
echo "  内核: $ROOT/kernel"
echo "  KSU:  $ROOT/KSU-Next"
echo "  AK3:  $ROOT/AnyKernel3"
echo "  工具链: $ROOT/toolchain"
echo ""
echo "  下一步: bash build.sh"
echo "=========================================="
