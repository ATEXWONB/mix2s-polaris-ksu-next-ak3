#!/usr/bin/env bash
# build.sh - 一键集成 KSU-Next + 编译内核 + 打包 AK3
# 用法: bash build.sh
#
# 警告: 不建议在 Termux / proot 中编译！

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

K="$ROOT/kernel"
OUT="$ROOT/out"
DIST="$ROOT/dist"
LOGS="$ROOT/logs"

mkdir -p "$OUT" "$DIST" "$LOGS" "$ROOT/backup"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOGS/build-$STAMP.log"

echo "=========================================="
echo "  KSU-Next v3.4.2 for Mi MIX 2S (polaris)"
echo "  LineageOS 22.2 / Linux 4.9.337"
echo "=========================================="
echo ""

# ========== 前置检查 ==========
echo "[前置检查]"

# 检查内核源码
if [ ! -d "$K" ]; then
    echo "[错误] 内核源码不存在！请先运行 bash setup.sh"
    exit 1
fi

# 检查 KSU-Next 源码
if [ ! -d "$ROOT/KSU-Next/kernel" ]; then
    echo "[错误] KernelSU-Next 源码不存在！请先运行 bash setup.sh"
    exit 1
fi

# 检查 AnyKernel3
if [ ! -d "$ROOT/AnyKernel3" ]; then
    echo "[错误] AnyKernel3 不存在！请先运行 bash setup.sh"
    exit 1
fi

# 检查工具链
if [ ! -x "$ROOT/toolchain/gcc49/bin/aarch64-linux-android-gcc" ]; then
    echo "[错误] GCC 4.9 aarch64 未就绪！请先运行 bash setup.sh"
    exit 1
fi
if [ ! -x "$ROOT/toolchain/gcc49-arm/bin/arm-linux-androideabi-gcc" ]; then
    echo "[错误] GCC 4.9 arm 未就绪！请先运行 bash setup.sh"
    exit 1
fi
if [ ! -x "$ROOT/toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
    echo "[错误] NDK r21e clang 未就绪！请先运行 bash setup.sh"
    exit 1
fi

# 检查配置文件
if [ ! -f "$ROOT/config/polaris.config" ]; then
    echo "[错误] config/polaris.config 不存在！"
    exit 1
fi
if [ ! -f "$ROOT/ak3/anykernel.sh" ]; then
    echo "[错误] ak3/anykernel.sh 不存在！"
    exit 1
fi

echo "[前置检查] 全部通过"
echo ""

# ========== 环境变量 ==========
export ARCH=arm64 SUBARCH=arm64
export CROSS_COMPILE="$ROOT/toolchain/gcc49/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$ROOT/toolchain/gcc49-arm/bin/arm-linux-androideabi-"
export PATH="$ROOT/toolchain/gcc49/bin:$ROOT/toolchain/gcc49-arm/bin:$PATH"
export KBUILD_BUILD_USER=workbuddy
export KBUILD_BUILD_HOST=ksu-build
export LC_ALL=C

CC_BIN="$ROOT/toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"

MF="O=$OUT ARCH=arm64 CC=$CC_BIN CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32"

# ========== Step 1: 集成 KSU-Next ==========
echo "[1/4] 检查 KernelSU-Next 集成状态..."

# 检测是否已经集成过（检查 Kbuild 中是否有 ksu_handle_setresuid）
if grep -q "ksu_handle_setresuid" "$K/kernel/sys.c" 2>/dev/null; then
    echo "  KSU-Next 已集成，跳过"
else
    echo "  正在集成 KSU-Next v3.4.2..."
    python3 "$ROOT/scripts/integrate_ksu_next.py" 2>&1 | tee -a "$LOG"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "[错误] KSU-Next 集成失败！请查看日志: $LOG"
        exit 1
    fi
fi
echo ""

# ========== Step 2: defconfig ==========
echo "[2/4] 配置内核 defconfig..."
cd "$K"

# 清理旧的 .config 确保干净
echo "  清理旧配置..."
rm -f "$OUT/.config"

make $MF vendor/xiaomi/mi845_defconfig 2>&1 | tee -a "$LOG"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "[错误] mi845_defconfig 失败！"
    exit 1
fi

# 追加 polaris 专属配置
cat "$ROOT/config/polaris.config" >> "$OUT/.config"

# 强制 manual hook 模式 + 关闭 CC_WERROR
sed -i 's/^# CONFIG_KSU_MANUAL_HOOK is not set/CONFIG_KSU_MANUAL_HOOK=y/' "$OUT/.config"
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$OUT/.config" || echo 'CONFIG_KSU_MANUAL_HOOK=y' >> "$OUT/.config"
sed -i 's/^CONFIG_CC_WERROR=y/# CONFIG_CC_WERROR is not set/' "$OUT/.config"

make $MF olddefconfig 2>&1 | tee -a "$LOG"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "[错误] olddefconfig 失败！"
    exit 1
fi

# 验证关键配置
echo "  关键配置:"
grep -E '^CONFIG_KSU|KPROBES|MANUAL_HOOK' "$OUT/.config" | tee -a "$LOG"

if ! grep -q '^CONFIG_KSU=y$' "$OUT/.config"; then
    echo "[错误] CONFIG_KSU 未启用！"
    exit 1
fi
if ! grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$OUT/.config"; then
    echo "[错误] CONFIG_KSU_MANUAL_HOOK 未启用！"
    exit 1
fi
echo ""

# ========== Step 3: 编译 ==========
echo "[3/4] 编译内核 (使用 $(nproc) 线程)..."

echo "  编译 DTB..."
make $MF dtbs -j"$(nproc)" 2>&1 | tee -a "$LOG"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "[错误] DTB 编译失败！"
    exit 1
fi

echo "  编译 Image.gz-dtb..."
make $MF Image.gz-dtb -j"$(nproc)" 2>&1 | tee -a "$LOG"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "[错误] 内核编译失败！"
    exit 1
fi

cp -f "$OUT/arch/arm64/boot/Image.gz-dtb" "$DIST/Image.gz-dtb"
ls -lh "$DIST/Image.gz-dtb" | tee -a "$LOG"
echo ""

# ========== Step 4: 打包 AK3 ==========
echo "[4/4] 打包 AnyKernel3 卡刷包..."

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

if [ ! -f "$ZIP_OUT" ]; then
    echo "[错误] AK3 打包失败！"
    exit 1
fi

echo ""
echo "=========================================="
echo "  编译成功!"
echo "  产物: $ZIP_OUT"
ls -lh "$ZIP_OUT"
echo "  SHA256: $(sha256sum "$ZIP_OUT" | awk '{print $1}')"
echo ""
echo "  将 zip 传到手机，Recovery 刷入即可"
echo "  日志: $LOG"
echo "=========================================="
