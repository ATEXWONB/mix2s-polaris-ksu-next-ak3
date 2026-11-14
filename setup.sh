#!/usr/bin/env bash
# setup.sh - 自动下载编译所需的所有依赖
# 用法: bash setup.sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "=========================================="
echo" KSU-Next for Mi MIX 2S (polaris) - Setup"
echo "=========================================="

# ---- 1. 内核源码 (LineageOS sdm845 lineage-22.2) ----
if [ ! -d "kernel/.git" ]; then
  echo "[1/5] 克隆 LineageOS sdm845 内核源码..."
  # 国内用户可改用清华镜像:
  # git clone https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/android_kernel_xiaomi_sdm845.git -b lineage-22.2 kernel
  git clone https://github.com/LineageOS/android_kernel_xiaomi_sdm845.git -b lineage-22.2 kernel
  cd kernel && git checkout lineage-22.2 && cd ..
else
  echo "[1/5] 内核源码已存在，跳过"
fi

# ---- 2. KernelSU-Next v3.4.2 ----
if [ ! -d "KSU-Next/.git" ]; then
  echo "[2/5] 克隆 KernelSU-Next v3.4.2..."
  git clone https://github.com/KernelSU-Next/KernelSU-Next.git -b v3.4.2 KSU-Next
else
  echo "[2/5] KSU-Next 已存在，跳过"
fi

# ---- 3. AnyKernel3 ----
if [ ! -d "AnyKernel3/.git" ]; then
  echo "[3/5] 克隆 AnyKernel3..."
  git clone https://github.com/osm0sis/AnyKernel3.git AnyKernel3
else
  echo "[3/5] AnyKernel3 已存在，跳过"
fi

# ---- 4. 工具链 ----
mkdir -p toolchain

if [ ! -d "toolchain/gcc49" ]; then
  echo "[4/5] 下载 AOSP GCC 4.9 aarch64..."
  git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 toolchain/gcc49
fi

if [ ! -d "toolchain/gcc49-arm" ]; then
  echo "[4/5] 下载 AOSP GCC 4.9 arm..."
  git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 toolchain/gcc49-arm
fi

if [ ! -d "toolchain/ndk-r21e" ]; then
  echo "[4/5] 下载 Android NDK r21e (约1.1GB)..."
  wget -c https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zip
  unzip -q android-ndk-r21e-linux-x86_64.zip -d toolchain/
  mv toolchain/android-ndk-r21e toolchain/ndk-r21e
  rm -f android-ndk-r21e-linux-x86_64.zip
fi

# ---- 5. 准备输出目录 ----
mkdir -p out dist logs

echo ""
echo "=========================================="
echo " Setup 完成!"
echo " 内核源码: $ROOT/kernel"
echo " KSU-Next: $ROOT/KSU-Next"
echo " 工具链:   $ROOT/toolchain"
echo ""
echo "下一步: bash build.sh"
echo "=========================================="
