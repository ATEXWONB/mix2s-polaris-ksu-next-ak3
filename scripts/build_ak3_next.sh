#!/bin/bash
# 在服务器上构建 polaris 可用的 AnyKernel3 刷机包
# 使用前修改下方 W 路径
set -e

# ===== 修改为你的实际路径 =====
W=/root/ksu-build
# ================================

cd "$W"
TS=$(date +%Y%m%d-%H%M%S)
BK=dist/backup-$TS
mkdir -p "$BK"

echo "== 备份旧产物 =="
[ -f dist/boot-ksu.img ] && cp -a dist/boot-ksu.img "$BK/boot-ksu.img.bad"
echo "backup -> $BK"; ls -la "$BK"

echo "== 放置编译好的内核段 =="
ls -l dist/Image.gz-dtb.next

echo "== 构建干净 AK3 工作目录 =="
AK3DIR=dist/ak3-polaris
rm -rf "$AK3DIR"
cp -a AnyKernel3 "$AK3DIR"
rm -rf "$AK3DIR/.git" "$AK3DIR/.github" "$AK3DIR/README.md"
mkdir -p "$AK3DIR/patch" "$AK3DIR/ramdisk"
cp dist/Image.gz-dtb.next "$AK3DIR/Image.gz-dtb"

cat > "$AK3DIR/anykernel.sh" <<'AK3EOF'
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
properties() {
'
kernel.string=KernelSU-Next v3.4.2 (33355) / Linux 4.9.337 for Xiaomi Mi MIX 2S (polaris)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=polaris
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables (polaris = Xiaomi MIX 2S, A-only, boot header v1 + appended DTB)
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install —— 只替换内核段（Image.gz-dtb 已含 26 个平台 DTB），不改 ramdisk
dump_boot;
write_boot;
## end boot install
AK3EOF

echo "== 打包 zip =="
cd "$AK3DIR"
OUT_ZIP="$W/dist/KernelSU-Next-33355-polaris-LOS22.2-AK3.zip"
rm -f "$OUT_ZIP"
zip -r9 "$OUT_ZIP" . -x '*.git*' -x '*/.*' > /dev/null
cd "$W"
echo "== 结果 =="
ls -l "$OUT_ZIP"
unzip -l "$OUT_ZIP" | head -14
echo "--- 包内 anykernel.sh 关键行 ---"
unzip -p "$OUT_ZIP" anykernel.sh | grep -nE 'BLOCK=|device.name1|kernel.string|dump_boot|write_boot'
echo "--- 包内内核段校验 ---"
mkdir -p /tmp/ak3chk && rm -rf /tmp/ak3chk/* && unzip -o -q "$OUT_ZIP" Image.gz-dtb -d /tmp/ak3chk
sha256sum /tmp/ak3chk/Image.gz-dtb dist/Image.gz-dtb.next
