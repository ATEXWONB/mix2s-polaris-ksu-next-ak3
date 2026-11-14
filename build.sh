#!/usr/bin/env bash
# build.sh - 一键集成 KSU-Next + 编译内核 + 打包 AK3
# 用法: bash build.sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

K="$ROOT/kernel"
OUT="$ROOT/out"
DIST="$ROOT/dist"
LOGS="$ROOT/logs"

mkdir -p "$OUT" "$DIST" "$LOGS"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOGS/build-$STAMP.log"

echo "=========================================="
echo" KSU-Next for Mi MIX 2S (polaris) - Build"
echo "=========================================="

# ---- 环境变量 ----
export ARCH=arm64 SUBARCH=arm64
export CROSS_COMPILE="$ROOT/toolchain/gcc49/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$ROOT/toolchain/gcc49-arm/bin/arm-linux-androideabi-"
export PATH="$ROOT/toolchain/gcc49/bin:$ROOT/toolchain/gcc49-arm/bin:$PATH"
export KBUILD_BUILD_USER=workbuddy
export KBUILD_BUILD_HOST=ksu-build
export LC_ALL=C

CC_BIN="$ROOT/toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"

MF="O=$OUT ARCH=arm64 CC=$CC_BIN CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32"

# ---- Step 1: 集成 KSU-Next ----
echo "[1/4] 集成 KernelSU-Next v3.4.2..."
python3 "$ROOT/scripts/integrate_ksu_next.py" 2>&1 | tee -a "$LOG"

# ---- Step 2: defconfig ----
echo "[2/4] 配置内核 defconfig..." | tee -a "$LOG"
cd "$K"
make $MF vendor/xiaomi/mi845_defconfig 2>&1 | tee -a "$LOG"

# 追加 polaris 专属配置
cat "$ROOT/config/polaris.config" >> "$OUT/.config"

# 强制 manual hook 模式 + 关闭 CC_WERROR
sed -i 's/^# CONFIG_KSU_MANUAL_HOOK is not set/CONFIG_KSU_MANUAL_HOOK=y/' "$OUT/.config"
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$OUT/.config" || echo 'CONFIG_KSU_MANUAL_HOOK=y' >> "$OUT/.config"
sed -i 's/^CONFIG_CC_WERROR=y/# CONFIG_CC_WERROR is not set/' "$OUT/.config"

make $MF olddefconfig 2>&1 | tee -a "$LOG"

grep -E '^CONFIG_KSU|KPROBES|MANUAL_HOOK' "$OUT/.config" | tee -a "$LOG"

# ---- Step 3: 编译 ----
echo "[3/4] 编译内核 (使用 $(nproc) 线程)..." | tee -a "$LOG"
make $MF dtbs -j"$(nproc)" 2>&1 | tee -a "$LOG"
make $MF Image.gz-dtb -j"$(nproc)" 2>&1 | tee -a "$LOG"

cp -f "$OUT/arch/arm64/boot/Image.gz-dtb" "$DIST/Image.gz-dtb"
ls -lh "$DIST/Image.gz-dtb" | tee -a "$LOG"

# ---- Step 4: 打包 AK3 ----
echo "[4/4] 打包 AnyKernel3 卡刷包..." | tee -a "$LOG"
AK3DIR="$DIST/ak3-polaris"
rm -rf "$AK3DIR"
cp -a "$ROOT/AnyKernel3" "$AK3DIR"
rm -rf "$AK3DIR/.git" "$AK3DIR/.github" "$AK3DIR/README.md"
mkdir -p "$AK3DIR/patch" "$AK3DIR/ramdisk"
cp "$DIST/Image.gz-dtb" "$AK3DIR/Image.gz-dtb"
cp "$ROOT/ak3/anykernel.sh" "$AK3DIR/anykernel.sh"

cd "$AK3DIR"
ZIP_OUT="$ROOT/dist/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip"
rm -f "$ZIP_OUT"
zip -r9 "$ZIP_OUT" . -x '*.git*' -x '*/.*' > /dev/null

echo ""
echo "=========================================="
echo " 编译完成!"
echo " 产物: $ZIP_OUT"
ls -lh "$ZIP_OUT"
echo " SHA256: $(sha256sum "$ZIP_OUT" | awk '{print $1}')"
echo ""
echo " 将 zip 传到手机，Recovery 刷入即可"
echo "=========================================="
