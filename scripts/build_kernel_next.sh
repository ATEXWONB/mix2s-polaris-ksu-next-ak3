#!/bin/bash
# 编译 msm-4.9.337 + KernelSU-Next v3.4.2 (manual hook)
# 使用前修改下方 W 路径为你的工作目录
set -o pipefail

# ===== 修改为你的实际路径 =====
W=/root/ksu-build
# ================================

K=$W/kernel
OUT=$W/out
DIST=$W/dist
LOGS=$W/logs
STAMP=$(date +%Y%m%d-%H%M%S)
LOG=$LOGS/build-next-$STAMP.log
STATUS=$LOGS/all.status

mkdir -p "$LOGS" "$DIST"

export ARCH=arm64 SUBARCH=arm64
export CROSS_COMPILE=$W/toolchain/gcc49/bin/aarch64-linux-android-
export CROSS_COMPILE_ARM32=$W/toolchain/gcc49-arm/bin/arm-linux-androideabi-
export PATH=$W/toolchain/gcc49/bin:$W/toolchain/gcc49-arm/bin:$PATH
export KBUILD_BUILD_USER=workbuddy
export KBUILD_BUILD_HOST=ksu-build
export LC_ALL=C
CC_BIN=$W/toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang

# KSU_VERSION_OVERRIDE 对应 KernelSU-Next 内部版本号
export KSU_VERSION_OVERRIDE=33355
export KSU_VERSION_TAG_OVERRIDE=v3.4.2

MF="O=$OUT ARCH=arm64 CC=$CC_BIN CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 KSU_VERSION_OVERRIDE=33355 KSU_VERSION_TAG_OVERRIDE=v3.4.2"

echo "ALL_START $STAMP" > "$STATUS"

cd "$K" || exit 1
{
  echo "=== [$STAMP] defconfig (mi845 + polaris) ==="
  make $MF vendor/xiaomi/mi845_defconfig
  cat "$K/arch/arm64/configs/vendor/xiaomi/polaris.config" >> "$OUT/.config"
  make $MF olddefconfig

  echo "=== 强制 manual hook 模式 + 关 CC_WERROR ==="
  sed -i 's/^# CONFIG_KSU_MANUAL_HOOK is not set/CONFIG_KSU_MANUAL_HOOK=y/' "$OUT/.config"
  grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$OUT/.config" || echo 'CONFIG_KSU_MANUAL_HOOK=y' >> "$OUT/.config"
  sed -i 's/^CONFIG_CC_WERROR=y/# CONFIG_CC_WERROR is not set/' "$OUT/.config"
  grep -E '^CONFIG_KSU|KPROBES|CONFIG_CC_WERROR' "$OUT/.config"
  grep -q '^CONFIG_KSU=y$' "$OUT/.config" || { echo "BUILD_RC=2 KSU_MISSING"; exit 2; }
  grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$OUT/.config" || { echo "BUILD_RC=3 MANUAL_HOOK_MISSING"; exit 3; }

  echo "=== dtbs ==="
  make $MF dtbs -j$(nproc)
  echo "=== Image.gz-dtb ==="
  make $MF Image.gz-dtb -j$(nproc)
  echo "BUILD_RC=$?"
} >> "$LOG" 2>&1

BRC=$(grep -oE 'BUILD_RC=[0-9]+' "$LOG" | tail -1 | cut -d= -f2)
[ -z "$BRC" ] && BRC=99
echo "BUILD_RC=$BRC" >> "$STATUS"
echo "BUILD_LOG=$LOG" >> "$STATUS"

if [ "$BRC" != "0" ]; then
  echo "ALL_FAILED_BUILD" >> "$STATUS"
  exit 1
fi

ls -l "$OUT/arch/arm64/boot/Image.gz-dtb" >> "$LOG" 2>&1
cp -f "$OUT/arch/arm64/boot/Image.gz-dtb" "$DIST/Image.gz-dtb.next"
echo "=== 内核编译完成，输出: $DIST/Image.gz-dtb.next ==="
