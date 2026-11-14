#!/usr/bin/env bash
# setup.sh -- 下载编译小米 MIX 2S (polaris) KSU-Next 内核所需的全部依赖
#
# 用法:
#   bash setup.sh
#
# 可选环境变量:
#   PROXY=socks5h://127.0.0.1:1080   为 git/curl 指定代理
#   KERNEL_DIR=kernel                内核源码目录名(默认 kernel)
#
# 已在服务器实测: 下载 -> 补丁 -> 编译 -> 打包 AK3 全流程可跑通。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

KERNEL_DIR="${KERNEL_DIR:-kernel}"
KERNEL_BRANCH="lineage-22.2"

GH_KERNEL="https://github.com/LineageOS/android_kernel_xiaomi_sdm845"
GH_AK3="https://github.com/osm0sis/AnyKernel3"
GH_GCC64="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9"
GH_GCC32="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9"

# 直连 + 国内加速镜像，按顺序尝试
MIRRORS=(
  ""
  "https://gh-proxy.com/"
  "https://ghfast.top/"
  "https://ghproxy.net/"
)

say()  { printf '%s\n' "$*"; }
ok()   { printf '  [OK]   %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
die()  { printf '\n[错误] %s\n' "$*" >&2; exit 1; }

# 如果指定了 PROXY，让 git / curl 都走它
if [ -n "${PROXY:-}" ]; then
  export http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="$PROXY"
  export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" ALL_PROXY="$PROXY"
fi

say "=========================================="
say "  KernelSU-Next v3.4.2 (33355) - Mi MIX 2S (polaris)"
say "  LineageOS 22.2 / Linux 4.9.337"
say "=========================================="
say ""

# ==========================================================
# 0. 环境检测
# ==========================================================
say "[0/5] 环境检测"

if [ -d "/data/data/com.termux" ] || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]; then
  die "检测到 Termux 环境。内核编译需要完整 glibc，请改用 Ubuntu 虚拟机或实体机。"
fi

if [ -f /proc/1/comm ] && [ "$(cat /proc/1/comm 2>/dev/null)" = "proot" ]; then
  warn "检测到 proot 环境，编译可能失败；推荐 Ubuntu 虚拟机/实体机。"
fi

if ! command -v ldconfig >/dev/null 2>&1; then
  warn "未检测到 ldconfig（可能不是标准 glibc 环境），继续但可能失败。"
fi

case "$(uname -m)" in
  x86_64|amd64) : ;;
  *) die "本工具链仅支持 x86_64 主机，当前: $(uname -m)" ;;
esac

MISSING=""
for c in git curl tar make python3 zip unzip bc bison flex gcc patch; do
  command -v "$c" >/dev/null 2>&1 || MISSING="$MISSING $c"
done
if [ -n "$MISSING" ]; then
  say "  缺少命令:$MISSING"
  if command -v apt-get >/dev/null 2>&1; then
    say "  正在 apt 安装编译依赖..."
    sudo apt-get update -qq
    sudo apt-get install -y build-essential libncurses-dev bison flex libssl-dev \
         libelf-dev zip unzip python3 git curl bc ca-certificates
    command -v zip >/dev/null 2>&1 || die "依赖安装失败，请手动执行 README 中的 apt 命令。"
  else
    die "缺少命令:$MISSING，请先安装（非 Debian 系请自行安装等价包）。"
  fi
fi
ok "环境检测通过 ($(nproc) 线程, $(free -m 2>/dev/null | awk 'NR==2{printf "%.0f", $2/1024}') GB 内存)"
say ""

# ==========================================================
# 工具函数
# ==========================================================

# 带镜像兜底的 git clone
# $1=github url(不带.git) $2=目标目录 $3=ref $4=refs 类型(heads|tags)
fetch_repo() {
  local url="$1" dest="$2" ref="${3:-}" rtype="${4:-heads}" m tmp
  for m in "${MIRRORS[@]}"; do
    rm -rf "$dest"
    if [ -n "$ref" ]; then
      if git clone --depth=1 --single-branch -b "$ref" "${m}${url}.git" "$dest" 2>/dev/null; then
        return 0
      fi
    else
      if git clone --depth=1 "${m}${url}.git" "$dest" 2>/dev/null; then
        return 0
      fi
    fi
  done

  # tarball 兜底
  warn "git clone 全部失败，改用 tarball 下载: $url"
  tmp="$(mktemp -d)"
  for m in "${MIRRORS[@]}"; do
    if curl -fL --retry 3 --connect-timeout 20 --max-time 1800 \
         -o "$tmp/a.tar.gz" "${m}${url}/archive/refs/${rtype}/${ref}.tar.gz"; then
      if tar -xzf "$tmp/a.tar.gz" -C "$tmp" 2>/dev/null; then
        rm -rf "$dest"
        mv "$tmp"/*/ "$dest" 2>/dev/null && rm -rf "$tmp" && return 0
      fi
    fi
  done
  rm -rf "$tmp"
  return 1
}

# ==========================================================
# 1. 内核源码
# ==========================================================
say "[1/5] 内核源码 (LineageOS sdm845 $KERNEL_BRANCH)"

kernel_ok() {
  [ -f "$KERNEL_DIR/Makefile" ] || return 1
  grep -qE '^VERSION = 4$' "$KERNEL_DIR/Makefile" || return 1
  grep -qE '^PATCHLEVEL = 9$' "$KERNEL_DIR/Makefile" || return 1
  [ -d "$KERNEL_DIR/arch/arm64/configs/vendor/xiaomi" ] || return 1
  return 0
}

if kernel_ok; then
  ok "内核源码已存在且版本匹配 ($KERNEL_DIR)"
else
  if [ -e "$KERNEL_DIR" ]; then
    warn "已有 $KERNEL_DIR 但版本/内容不匹配，重新下载..."
    rm -rf "$KERNEL_DIR"
  fi
  say "  下载内核源码 (约 166 MB)..."
  tmp="$(mktemp -d)"
  got=1
  for m in "${MIRRORS[@]}"; do
    say "    <- ${m}${GH_KERNEL} (branch $KERNEL_BRANCH)"
    if curl -fL --retry 3 -C - --connect-timeout 20 --max-time 3600 \
         -o "$tmp/k.tar.gz" "${m}${GH_KERNEL}/archive/refs/heads/${KERNEL_BRANCH}.tar.gz"; then
      if tar -xzf "$tmp/k.tar.gz" -C "$tmp" 2>/dev/null; then
        rm -rf "$KERNEL_DIR"
        mv "$tmp"/*/ "$KERNEL_DIR" 2>/dev/null && got=0 && break
      fi
    fi
  done
  rm -rf "$tmp"
  if [ "$got" -ne 0 ]; then
    # 最后尝试 git clone
    fetch_repo "$GH_KERNEL" "$KERNEL_DIR" "$KERNEL_BRANCH" heads || die "内核源码下载失败，请检查网络或使用 PROXY 环境变量。"
  fi
  kernel_ok || die "内核源码下载后校验失败（不是 4.9 的 sdm845 树）。"
  ok "内核源码就绪: $(grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' "$KERNEL_DIR/Makefile" | tr '\n' ' ')"
fi
say ""

# ==========================================================
# 2. AnyKernel3
# ==========================================================
say "[2/5] AnyKernel3 模板"

ak3_ok() { [ -f "AnyKernel3/anykernel.sh" ] && [ -f "AnyKernel3/tools/ak3-core.sh" ]; }

if ak3_ok; then
  ok "AnyKernel3 已存在"
else
  rm -rf AnyKernel3
  say "  下载 AnyKernel3..."
  fetch_repo "$GH_AK3" "AnyKernel3" master heads || die "AnyKernel3 下载失败。"
  ak3_ok || die "AnyKernel3 下载后校验失败。"
  ok "AnyKernel3 就绪"
fi
say ""

# ==========================================================
# 4. 交叉工具链
# ==========================================================
say "[3/5] 交叉工具链 (GCC 4.9 binutils + NDK r21e clang)"
mkdir -p toolchain

gcc_ok() { # $1=dir $2=bin前缀
  [ -x "$1/bin/$2-gcc" ] || return 1
  # 不写成管道 + grep -q（pipefail 下 SIGPIPE 会误判）
  local ver
  ver="$("$1/bin/$2-gcc" --version 2>/dev/null | head -1)"
  case "$ver" in
    *4.9*) return 0 ;;
    *) return 1 ;;
  esac
}

if gcc_ok toolchain/gcc49 aarch64-linux-android; then
  ok "GCC 4.9 aarch64: 已就绪"
else
  warn "GCC 4.9 aarch64: 缺失或版本不符，重新下载"
  rm -rf toolchain/gcc49
  fetch_repo "$GH_GCC64" toolchain/gcc49 "" heads \
    || git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 toolchain/gcc49 \
    || die "GCC 4.9 aarch64 下载失败。"
  gcc_ok toolchain/gcc49 aarch64-linux-android || die "GCC 4.9 aarch64 下载后校验失败。"
  ok "GCC 4.9 aarch64: 已就绪"
fi

if gcc_ok toolchain/gcc49-arm arm-linux-androideabi; then
  ok "GCC 4.9 arm: 已就绪"
else
  warn "GCC 4.9 arm: 缺失或版本不符，重新下载"
  rm -rf toolchain/gcc49-arm
  fetch_repo "$GH_GCC32" toolchain/gcc49-arm "" heads \
    || git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 toolchain/gcc49-arm \
    || die "GCC 4.9 arm 下载失败。"
  gcc_ok toolchain/gcc49-arm arm-linux-androideabi || die "GCC 4.9 arm 下载后校验失败。"
  ok "GCC 4.9 arm: 已就绪"
fi

NDK_BIN="toolchain/ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
ndk_ok() {
  [ -x "$NDK_BIN" ] || return 1
  local ver
  ver="$("$NDK_BIN" --version 2>/dev/null | head -1)"
  case "$ver" in
    *"clang version 9"*) return 0 ;;
    *) return 1 ;;
  esac
}

if ndk_ok; then
  ok "NDK r21e clang: 已就绪"
else
  warn "NDK r21e: 缺失或版本不符，重新下载 (约 1.1 GB)"
  NDK_ZIP="android-ndk-r21e-linux-x86_64.zip"
  NDK_URL="https://dl.google.com/android/repository/$NDK_ZIP"
  rm -rf toolchain/ndk-r21e
  if ! curl -fL --retry 3 -C - --connect-timeout 20 --max-time 3600 -o "toolchain/$NDK_ZIP" "$NDK_URL"; then
    rm -f "toolchain/$NDK_ZIP"
    warn "dl.google.com 下载失败，请手动下载后放到 toolchain/ 下："
    say  "  $NDK_URL"
    say  "  然后执行: bash setup.sh 重新运行"
    exit 1
  fi
  say "  解压 NDK..."
  unzip -q "toolchain/$NDK_ZIP" -d toolchain/ || die "NDK 解压失败（压缩包可能不完整，请删除 toolchain/$NDK_ZIP 后重试）。"
  mv "toolchain/android-ndk-r21e" "toolchain/ndk-r21e"
  rm -f "toolchain/$NDK_ZIP"
  ndk_ok || die "NDK r21e 安装后校验失败。"
  ok "NDK r21e clang: 已就绪"
fi
say ""

# ==========================================================
# 5. 编译产物自检（真实编译一个小文件，确认工具链可用）
# ==========================================================
say "[4/5] 工具链自检"
TMPC="$(mktemp -d)"
cat > "$TMPC/t.c" <<'EOF'
int ksu_probe(void) { return 42; }
EOF
export PATH="$ROOT/toolchain/gcc49/bin:$ROOT/toolchain/gcc49-arm/bin:$PATH"
if "$ROOT/$NDK_BIN" --target=aarch64-linux-gnu -c "$TMPC/t.c" -o "$TMPC/t.o" 2>"$TMPC/err.txt" \
   && "$ROOT/toolchain/gcc49/bin/aarch64-linux-android-objdump" -d "$TMPC/t.o" >/dev/null 2>&1; then
  ok "clang + binutils 编译测试通过"
else
  cat "$TMPC/err.txt" 2>/dev/null
  rm -rf "$TMPC"
  die "工具链自检失败，请查看上面的错误。"
fi
rm -rf "$TMPC"
say ""

# ==========================================================
# 6. 输出目录
# ==========================================================
say "[5/5] 准备输出目录"
mkdir -p out dist logs backup
ok "out/ dist/ logs/ backup/ 已就绪"
say ""

say "=========================================="
say "  Setup 完成!"
say "  内核:   $ROOT/$KERNEL_DIR"
say "  KSU:    $ROOT/ksu-src  (仓库内置)"
say "  AK3:    $ROOT/AnyKernel3"
say "  工具链: $ROOT/toolchain"
say ""
say "  下一步: bash build.sh"
say "=========================================="
