#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 KernelSU-Next v3.4.2 (manual hook 模式) 集成进 msm-4.9 (LineageOS 22.2 sdm845) 内核树。

做的事：
  1) patch -p1 应用 patches/ksu-next-4.9-lineage-22.2.patch
     （hook 点、Kconfig/Makefile 挂载、4.9 缺失头文件 shim、defconfig 打开 CONFIG_KSU）
  2) 把 KSU-Next/kernel 复制到 kernel/KernelSU/kernel
  3) 建立 kernel/drivers/kernelsu -> ../KernelSU/kernel 软链接
  4) 校验集成结果

幂等：重复运行会检测到已集成并直接跳过。补丁失败时不会留下半成品（先 --dry-run 再实际应用）。

用法：
    python3 scripts/apply_ksu.py              # 集成 ROOT/kernel
    python3 scripts/apply_ksu.py --check      # 只检查是否已集成，不修改
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K = os.path.join(ROOT, 'kernel')
KSU_SRC = os.path.join(ROOT, 'ksu-src', 'kernel')   # 本仓库内置的 KSU 源码（非 GKI 4.9 适配版）
PATCH = os.path.join(ROOT, 'patches', 'ksu-next-4.9-lineage-22.2.patch')
# manual hook 专用：把 fs/read_write.c 的 vfs_read 接到 KSU，使 init 读取 init.rc
# 时注入 KERNEL_SU_RC，ksud post-fs-data 因此在 zygote 启动前执行（模块/zygisk 首启即生效）
PATCH_VFS_READ = os.path.join(ROOT, 'patches', 'ksu-vfs-read-hook.patch')

RED, GRN, YLW, RST = '\033[31m', '\033[32m', '\033[33m', '\033[0m'


def log(msg):
    print(msg)


def ok(msg):
    log(GRN + '  [OK]   ' + msg + RST)


def warn(msg):
    log(YLW + '  [WARN] ' + msg + RST)


def die(msg):
    print(RED + '\n[错误] ' + msg + RST, file=sys.stderr)
    sys.exit(1)


def read(p):
    with open(p, 'r', encoding='utf-8', errors='surrogateescape') as f:
        return f.read()


def kernel_version(kdir):
    """返回 (major, patchlevel)"""
    mk = os.path.join(kdir, 'Makefile')
    if not os.path.isfile(mk):
        return None
    major = patch = None
    for line in read(mk).splitlines()[:20]:
        if line.startswith('VERSION ='):
            major = int(line.split('=')[1].strip())
        elif line.startswith('PATCHLEVEL ='):
            patch = int(line.split('=')[1].strip())
    return (major, patch) if major and patch else None


def already_integrated():
    """三个特征都要满足才算已集成"""
    fexec = os.path.join(K, 'fs', 'exec.c')
    if not os.path.isfile(fexec) or 'ksu_handle_execveat' not in read(fexec):
        return False
    frw = os.path.join(K, 'fs', 'read_write.c')
    if not os.path.isfile(frw) or 'ksu_handle_vfs_read' not in read(frw):
        return False
    if not os.path.exists(os.path.join(K, 'KernelSU', 'kernel', 'Kbuild')):
        return False
    if not os.path.islink(os.path.join(K, 'drivers', 'kernelsu')):
        return False
    dfc = os.path.join(K, 'arch', 'arm64', 'configs', 'vendor', 'xiaomi', 'mi845_defconfig')
    if not os.path.isfile(dfc) or 'CONFIG_KSU=y' not in read(dfc):
        return False
    return True


def run(cmd, cwd=None):
    """返回 (rc, stdout+stderr)"""
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True)
    return p.returncode, p.stdout


def main():
    check_only = '--check' in sys.argv

    log('== KSU-Next v3.4.2 集成 (msm-4.9 / manual hook) ==')

    if not os.path.isdir(K):
        die('内核源码目录不存在: %s\n   请先运行 bash setup.sh' % K)

    ver = kernel_version(K)
    if not ver or ver != (4, 9):
        die('内核版本不是 4.9（当前: %s），本补丁只适用于 msm-4.9。' % (ver,))
    ok('内核版本 4.9.x 确认')

    if not os.path.isfile(PATCH):
        die('补丁文件缺失: %s' % PATCH)
    ok('补丁文件: %s (%d 行)' % (os.path.relpath(PATCH, ROOT), len(read(PATCH).splitlines())))

    if already_integrated():
        ok('检测到已集成 KSU-Next，跳过')
        return

    if check_only:
        log(YLW + '[检查模式] 尚未集成。' + RST)
        sys.exit(2)

    if not os.path.isdir(KSU_SRC):
        die('KSU 源码缺失: %s\n   仓库不完整，请重新 clone（ksu-src/ 目录必须存在）' % KSU_SRC)

    # ---- 1) 补丁：先 dry-run 再实际应用 ----
    log('  1) 应用内核补丁...')
    rc, out = run(['patch', '-p1', '--dry-run', '--forward', '-i', PATCH], cwd=K)
    if rc != 0:
        print(out)
        die('补丁 dry-run 失败：内核树可能不是 lineage-22.2 原版，或补丁已应用（请 git checkout 回干净树后重试）。')
    rc, out = run(['patch', '-p1', '--forward', '-i', PATCH], cwd=K)
    if rc != 0:
        print(out)
        die('补丁应用失败。')
    ok('补丁应用完成')

    # ---- 1b) vfs_read hook（manual hook 模式下 init.rc 注入的关键）----
    log('  1b) 应用 vfs_read hook 补丁...')
    if not os.path.isfile(PATCH_VFS_READ):
        die('补丁文件缺失: %s' % PATCH_VFS_READ)
    rc, out = run(['patch', '-p1', '--dry-run', '--forward', '-i', PATCH_VFS_READ], cwd=K)
    if rc != 0:
        print(out)
        die('vfs_read 补丁 dry-run 失败：fs/read_write.c 与预期不一致。')
    rc, out = run(['patch', '-p1', '--forward', '-i', PATCH_VFS_READ], cwd=K)
    if rc != 0:
        print(out)
        die('vfs_read 补丁应用失败。')
    ok('vfs_read hook 已接入')

    # 清理 patch 备份文件
    for dirpath, _dirnames, filenames in os.walk(K):
        for fn in filenames:
            if fn.endswith(('.orig', '.rej')):
                try:
                    os.remove(os.path.join(dirpath, fn))
                except OSError:
                    pass

    # ---- 2) 部署 KSU 源码 ----
    log('  2) 部署 KSU-Next 源码...')
    dst = os.path.join(K, 'KernelSU', 'kernel')
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copytree(KSU_SRC, dst, symlinks=True)
    # 内核 Kbuild 要求同名 Makefile；KSU-Next 源码里 Kbuild 才是真身
    kbuild = os.path.join(dst, 'Kbuild')
    makefile = os.path.join(dst, 'Makefile')
    if os.path.isfile(kbuild):
        shutil.copy2(kbuild, makefile)
    ok('KSU 源码 -> kernel/KernelSU/kernel')

    # ---- 3) drivers/kernelsu 软链接 ----
    log('  3) 建立 drivers/kernelsu 软链接...')
    link = os.path.join(K, 'drivers', 'kernelsu')
    if os.path.islink(link) or os.path.exists(link):
        if os.path.islink(link):
            os.remove(link)
        else:
            die('drivers/kernelsu 已存在且不是软链接，请手动检查后删除。')
    os.symlink('../KernelSU/kernel', link)
    ok('drivers/kernelsu -> ../KernelSU/kernel')

    # ---- 4) 校验 ----
    log('  4) 校验集成结果...')
    checks = [
        ('fs/exec.c hook', 'ksu_handle_execveat', os.path.join(K, 'fs', 'exec.c')),
        ('fs/read_write.c hook', 'ksu_handle_vfs_read', os.path.join(K, 'fs', 'read_write.c')),
        ('kernel/sys.c hook', 'ksu_handle_setresuid', os.path.join(K, 'kernel', 'sys.c')),
        ('kernel/reboot.c hook', 'ksu_handle_sys_reboot', os.path.join(K, 'kernel', 'reboot.c')),
        ('drivers/Makefile', 'CONFIG_KSU', os.path.join(K, 'drivers', 'Makefile')),
        ('drivers/Kconfig', 'drivers/kernelsu', os.path.join(K, 'drivers', 'Kconfig')),
        ('mi845_defconfig', 'CONFIG_KSU=y', os.path.join(K, 'arch', 'arm64', 'configs',
                                                       'vendor', 'xiaomi', 'mi845_defconfig')),
    ]
    bad = []
    for name, needle, path in checks:
        if not os.path.isfile(path) or needle not in read(path):
            bad.append(name)
        else:
            ok(name)
    if bad:
        die('集成校验失败: %s' % ', '.join(bad))

    log('')
    log(GRN + 'KSU-Next v3.4.2 集成完成。' + RST)


if __name__ == '__main__':
    main()
