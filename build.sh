#!/usr/bin/env bash
# build.sh -- 一键集成 KSU-Next + 编译内核 + 打包 AnyKernel3 卡刷包
#
# 用法:
#   bash build.sh
#
# 前置: 先运行 bash setup.sh 把内核源码 / KSU-Next / 工具链 准备好。
#
# 产物: dist/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

K="$ROOT/kernel"
# 编译中间产物目录，可用 OUT_DIR 环境变量指到更大的磁盘
OUT="${OUT_DIR:-$ROOT/out}"
DIST="$ROOT/dist"
LOGS="$ROOT/logs"
KERNEL_BRANCH="${KERNEL_BRANCH:-lineage-22.2}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGS/build-$STAMP.log"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  [OK]   %s\n' "$*"; }
die()  { printf '\n[错误] %s\n' "$*" >&2; exit 1; }

mkdir -p "$OUT" "$DIST" "$LOGS" "$ROOT/backup"

say "=========================================="
say "  KSU-Next v3.4.2 - Mi MIX 2S (polaris)"
say "  LineageOS 22.2 / Linux 4.9.337"
say "=========================================="
say ""

# ==========================================================
# 0. 前置检查
# ==========================================================
say "[0/6] 前置检查"

[ -f "$K/Makefile" ] || die "内核源码不存在: $K  请先运行 bash setup.sh"
[ -d "$ROOT/ksu-src/kernel" ] || die "仓库内的 ksu-src/kernel 缺失（仓库不完整，请重新 clone）"
[ -d "$ROOT/AnyKernel3/tools" ] || die "AnyKernel3 不存在  请先运行 bash setup.sh"
[ -f "$ROOT/patches/ksu-next-4.9-lineage-22.2.patch" ] || die "补丁文件缺失: patches/"
[ -f "$ROOT/config/polaris.config" ] || die "config/polaris.config 缺失"
[ -f "$ROOT/ak3/anykernel.sh" ] || die "ak3/anykernel.sh 缺失"

CC_BIN="$ROOT/toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
[ -x "$CC_BIN" ] || die "NDK clang 不存在  请先运行 bash setup.sh"
[ -x "$ROOT/toolchain/gcc49/bin/aarch64-linux-android-gcc" ] || die "GCC 4.9 aarch64 不存在  请先运行 bash setup.sh"
[ -x "$ROOT/toolchain/gcc49-arm/bin/arm-linux-androideabi-gcc" ] || die "GCC 4.9 arm 不存在  请先运行 bash setup.sh"

JOBS="$(nproc)"
[ "$JOBS" -gt 1 ] || JOBS=1
ok "前置检查通过 ($JOBS 线程编译)"
say ""

# ==========================================================
# 1. 集成 KSU-Next
# ==========================================================
say "[1/6] 集成 KernelSU-Next v3.4.2"
python3 "$ROOT/scripts/apply_ksu.py" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  die "KSU-Next 集成失败，详见 $LOG"
fi
say ""

# ==========================================================
# 2. 配置内核
# ==========================================================
say "[2/6] 配置内核 (vendor/xiaomi/mi845_defconfig + polaris)"

export ARCH=arm64 SUBARCH=arm64
export CROSS_COMPILE="$ROOT/toolchain/gcc49/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$ROOT/toolchain/gcc49-arm/bin/arm-linux-androideabi-"
export PATH="$ROOT/toolchain/gcc49/bin:$ROOT/toolchain/gcc49-arm/bin:$PATH"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-workbuddy}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-kubuild}"
export LC_ALL=C

MF=(O="$OUT" ARCH=arm64 CC="$CC_BIN" CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE="$CROSS_COMPILE" CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32"
    KSU_VERSION_OVERRIDE=33355 KSU_VERSION_TAG_OVERRIDE=v3.4.2)

rm -f "$OUT/.config"
say "  make mi845_defconfig"
make -C "$K" "${MF[@]}" vendor/xiaomi/mi845_defconfig >>"$LOG" 2>&1
[ -f "$OUT/.config" ] || die "defconfig 生成失败，详见 $LOG"

cat "$ROOT/config/polaris.config" >> "$OUT/.config"
# 明确关掉 kprobes（4.9 + qualcomm 不建议用 kprobe hook）, 走 manual hook
sed -i 's/^CONFIG_KPROBES=y/# CONFIG_KPROBES is not set/' "$OUT/.config"
sed -i 's/^CONFIG_KSU_MANUAL_HOOK is not set/CONFIG_KSU_MANUAL_HOOK=y/' "$OUT/.config"
# 4.9 树上开着 -Werror 容易被 KSU 的 warning 顶掉
sed -i 's/^CONFIG_CC_WERROR=y/# CONFIG_CC_WERROR is not set/' "$OUT/.config"

say "  make olddefconfig"
make -C "$K" "${MF[@]}" olddefconfig >>"$LOG" 2>&1
[ -f "$OUT/.config" ] || die "olddefconfig 失败，详见 $LOG"

# 关键配置校验，缺什么就补什么再重新 olddefconfig
fix_cfg() { # $1=期望行
  grep -qxF "$1" "$OUT/.config" || { say "  补加配置: $1"; echo "$1" >> "$OUT/.config"; NEED_RECONF=1; }
}
NEED_RECONF=0
grep -q '^CONFIG_KSU=y$' "$OUT/.config" || { echo 'CONFIG_KSU=y' >> "$OUT/.config"; NEED_RECONF=1; }
fix_cfg 'CONFIG_KSU_MANUAL_HOOK=y'
fix_cfg '# CONFIG_KPROBES is not set'
if [ "$NEED_RECONF" -eq 1 ]; then
  make -C "$K" "${MF[@]}" olddefconfig >>"$LOG" 2>&1
fi

say "  关键配置:"
grep -E '^CONFIG_KSU|^# CONFIG_KPROBES|^# CONFIG_KSU_DEBUG' "$OUT/.config" | sed 's/^/    /'

grep -q '^CONFIG_KSU=y$' "$OUT/.config" || die "CONFIG_KSU 未启用"
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$OUT/.config" || die "CONFIG_KSU_MANUAL_HOOK 未启用（本次构建必须是 manual hook 模式）"
ok "内核配置就绪"
say ""

# ==========================================================
# 3. 编译 DTB
# ==========================================================
say "[3/6] 编译设备树 (dtbs)"
make -C "$K" "${MF[@]}" dtbs -j"$JOBS" >>"$LOG" 2>&1
if [ $? -ne 0 ]; then
  tail -40 "$LOG" | sed 's/^/    /'
  die "DTB 编译失败，完整日志: $LOG"
fi
ok "dtbs 完成"
say ""

# ==========================================================
# 4. 编译内核
# ==========================================================
say "[4/6] 编译内核 Image.gz-dtb (约 10~40 分钟，依赖 CPU)"
START="$(date +%s)"
make -C "$K" "${MF[@]}" Image.gz-dtb -j"$JOBS" >>"$LOG" 2>&1
RC=$?
END="$(date +%s)"
if [ $RC -ne 0 ]; then
  tail -60 "$LOG" | sed 's/^/    /'
  die "内核编译失败，完整日志: $LOG"
fi
IMG="$OUT/arch/arm64/boot/Image.gz-dtb"
[ -f "$IMG" ] || die "编译结束但没有 $IMG"
cp -f "$IMG" "$DIST/Image.gz-dtb"
ok "内核编译完成，用时 $(( (END-START)/60 )) 分，产物 $(du -h "$DIST/Image.gz-dtb" | cut -f1)"
say ""

# ==========================================================
# 5. 打包 AnyKernel3
# ==========================================================
say "[5/6] 打包 AnyKernel3 卡刷包"
AK3DIR="$DIST/ak3-polaris"
rm -rf "$AK3DIR"
cp -a "$ROOT/AnyKernel3" "$AK3DIR"
rm -rf "$AK3DIR/.git" "$AK3DIR/.github" "$AK3DIR/README.md" "$AK3DIR/LICENSE" 2>/dev/null
mkdir -p "$AK3DIR/patch"
cp -f "$DIST/Image.gz-dtb" "$AK3DIR/Image.gz-dtb"
cp -f "$ROOT/ak3/anykernel.sh" "$AK3DIR/anykernel.sh"
# 记录本次构建信息，方便用户核对
{
  echo "KSU-Next v3.4.2 (33355) / Linux 4.9.337"
  echo "device: Xiaomi Mi MIX 2S (polaris)"
  echo "rom: LineageOS 22.2"
  echo "kernel tree: LineageOS android_kernel_xiaomi_sdm845 $KERNEL_BRANCH"
  echo "hook mode: manual (no kprobes)"
  echo "built at: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "host: $(uname -srm), jobs: $JOBS"
} > "$AK3DIR/build-info.txt"

ZIP_OUT="$DIST/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip"
rm -f "$ZIP_OUT"
( cd "$AK3DIR" && zip -r9 "$ZIP_OUT" . -x '*.git*' -x '*/.*' >/dev/null )
[ -f "$ZIP_OUT" ] || die "AK3 打包失败"

# 校验 zip 内容（不用管道 + grep -q，避免 pipefail 下 SIGPIPE 误判）
ZIPLIST="$(unzip -Z1 "$ZIP_OUT")" || die "zip 无法读取"
printf '%s\n' "$ZIPLIST" | grep -q '^Image\.gz-dtb$' || die "zip 内缺少 Image.gz-dtb"
printf '%s\n' "$ZIPLIST" | grep -q '^anykernel\.sh$' || die "zip 内缺少 anykernel.sh"
ok "AK3 卡刷包就绪"
say ""

# ==========================================================
# 6. 结果
# ==========================================================
say "[6/6] 完成"
SHA="$(sha256sum "$ZIP_OUT" | awk '{print $1}')"
SIZE="$(stat -c %s "$ZIP_OUT")"
say "=========================================="
say "  产物: ${ZIP_OUT#$ROOT/}"
say "  大小: $SIZE bytes ($(du -h "$ZIP_OUT" | cut -f1))"
say "  SHA256: $SHA"
say "  日志: ${LOG#$ROOT/}"
say ""
say "  刷入: Recovery -> 安装 -> 选择该 zip -> 重启"
say "  管理器: Release 里的 KernelSU_Next_v3.4.2_33355-release.apk"
say "=========================================="
