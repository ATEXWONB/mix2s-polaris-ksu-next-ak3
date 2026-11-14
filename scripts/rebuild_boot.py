#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用官方 boot.img 作模板，仅替换内核段，重建出结构 100% 对齐的 boot 镜像

用法:
  python3 rebuild_boot.py <官方boot.img> <新Image.gz-dtb> <输出.img> [--no-footer]

结构处理（严格照抄 avbtool add_hash_footer 产物布局）:
  [header 4096][kernel][pad][ramdisk][pad]  -> data_end
  [embedded vbmeta blob][zeros][AVBf footer 64B @ 分区末尾]
"""
import sys, os, struct, zlib, hashlib

PAGE = 4096

def align(n, p=PAGE):
    return (n + p - 1) & ~(p - 1)

def gz_stream_and_dtb(blob):
    """把 kernel blob 拆成 gzip 流 + 尾部追加 DTB，返回 (gz_bytes, dtb_bytes, img)"""
    o = zlib.decompressobj(16 + zlib.MAX_WBITS)
    img = o.decompress(blob) + o.flush()
    gz_len = len(blob) - len(o.unused_data)
    return blob[:gz_len], blob[gz_len:], img

def get_dtb_blob(blob):
    """从 kernel blob 里取出纯 DTB 区（跳过 gz 流后可能的填充字节）"""
    gz, tail, img = gz_stream_and_dtb(blob)
    m = tail.find(b'\xd0\x0d\xfe\xed')
    return tail[m:] if m >= 0 else tail

def main():
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    tpl_path, new_kernel_path, out_path = sys.argv[1:4]
    with_footer = '--no-footer' not in sys.argv

    tpl = open(tpl_path, 'rb').read()
    ks_t, ps, rs = struct.unpack_from('<I', tpl, 8)[0], struct.unpack_from('<I', tpl, 36)[0], struct.unpack_from('<I', tpl, 16)[0]
    print('模板: %s  (%d bytes, page=%d, kernel=%d, ramdisk=%d)' % (os.path.basename(tpl_path), len(tpl), ps, ks_t, rs))

    tpl_kernel = tpl[ps:ps + ks_t]
    tpl_dtb = get_dtb_blob(tpl_kernel)
    ramdisk = tpl[ps + align(ks_t, ps): ps + align(ks_t, ps) + rs]
    print('  模板 DTB 区: %d 字节, FDT 数 %d' % (len(tpl_dtb), tpl_dtb.count(b'\xd0\x0d\xfe\xed')))

    newblob = open(new_kernel_path, 'rb').read()
    gz, dtb, img = gz_stream_and_dtb(newblob)
    print('新内核: %s  (%d bytes) -> gz流 %d, 自带DTB区 %d, 解压 %d' %
          (os.path.basename(new_kernel_path), len(newblob), len(gz), len(dtb), len(img)))

    # 关键：丢弃新内核里可能带填充的 DTB 区，改用模板的 DTB 区（内容与官方逐字节一致）
    kernel = gz + tpl_dtb
    print('重建内核段: gz %d + 模板DTB %d = %d 字节 (原 %d)' % (len(gz), len(tpl_dtb), len(kernel), ks_t))

    # ---- 组装 header ----
    header = bytearray(tpl[:ps])
    struct.pack_into('<I', header, 8, len(kernel))          # kernel_size
    sha = hashlib.sha1()
    sha.update(kernel); sha.update(bytes(align(len(kernel), ps) - len(kernel)))
    sha.update(ramdisk); sha.update(bytes(align(len(ramdisk), ps) - len(ramdisk)))
    digest = sha.digest()
    header[0x240:0x260] = digest + bytes(0x20 - len(digest))
    header = bytes(header)

    body = bytearray()
    body += header
    body += kernel
    pad = align(len(kernel), ps) - len(kernel)
    body += bytes(pad)
    body += ramdisk
    pad = align(len(ramdisk), ps) - len(ramdisk)
    body += bytes(pad)
    data_end = len(body)
    img_digest = hashlib.sha256(bytes(body)).hexdigest()
    print('boot 数据段 = %d 字节 (data_end)' % data_end)

    out = bytearray(body)
    if with_footer:
        embedded = tpl[align(data_end, ps):]
        foff = len(tpl) - 64
        out += bytes(len(tpl) - 64 - len(out))
        footer = bytearray(tpl[foff:foff + 64])
        struct.pack_into('>Q', footer, 12, data_end)        # original_image_size
        struct.pack_into('>Q', footer, 20, len(body))       # vbmeta_offset
        struct.pack_into('>I', footer, 28, len(embedded))   # vbmeta_size
        out += bytes(footer)
    else:
        if len(out) < len(tpl):
            out += bytes(len(tpl) - len(out))
        out = out[:len(tpl)]

    out = bytes(out[:len(tpl)])
    open(out_path, 'wb').write(out)
    print('写出: %s (%d bytes)' % (out_path, len(out)))
    print('sha256 =', hashlib.sha256(out).hexdigest())
    print('boot数据 sha256 =', img_digest)

    # ---- 自检 ----
    d = open(out_path, 'rb').read()
    ks2, ps2 = struct.unpack_from('<I', d, 8)[0], struct.unpack_from('<I', d, 36)[0]
    ram_off = ps2 + align(ks2, ps2)
    ok = True
    checks = [
        ('magic ANDROID!', d[:8] == b'ANDROID!'),
        ('kernel 位于 page 边界', d[ps2:ps2 + 2] == b'\x1f\x8b'),
        ('kernel 与重建段一致', d[ps2:ps2 + ks2] == kernel),
        ('kernel 尾部紧跟 FDT 魔数', d[ps2 + ks2 - len(tpl_dtb):ps2 + ks2 - len(tpl_dtb) + 4] == b'\xd0\x0d\xfe\xed'),
        ('DTB 区与模板逐字节一致', d[ps2:ps2 + ks2][-len(tpl_dtb):] == tpl_dtb),
        ('ramdisk 与模板一致', d[ram_off:ram_off + rs] == ramdisk),
        ('文件尺寸与原版一致', len(d) == len(tpl)),
    ]
    if with_footer:
        checks.append(('AVBf footer 在位', d[-64:-60] == b'AVBf'))
    for name, v in checks:
        print('  [%s] %s' % ('OK ' if v else 'FAIL', name))
        ok = ok and v
    print('RESULT:', 'ALL_OK' if ok else 'CHECK_FAILED')

if __name__ == '__main__':
    main()
