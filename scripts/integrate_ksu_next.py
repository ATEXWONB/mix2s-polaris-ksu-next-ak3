#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 KernelSU-Next v3.4.2（manual hook 模式）集成进 msm-4.9 树。

做四件事：
 1) 用 KSU-Next 源码替换 kernel/KernelSU/kernel
 2) 摘掉 v0.9.5 遗留的 hook 点（vfs_read / devpts / input）
 3) 补 legacy 需要的 2 个 hook 点（setresuid / sys_reboot）
 4) 补 8 个 4.9 缺失的头文件 shim

使用前运行 setup.sh 下载好依赖，然后直接 python3 scripts/integrate_ksu_next.py
"""
import os, shutil, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K = os.path.join(ROOT, 'kernel')               # LineageOS 内核源码
LC = os.path.join(ROOT, 'KSU-Next', 'kernel')  # KSU-Next v3.4.2 kernel/ 目录

TS = time.strftime('%Y%m%d-%H%M%S')
BK = os.path.join(ROOT, 'backup', 'pre-v3-%s' % TS)
BAD = os.path.join(BK, 'patched')
os.makedirs(BAD, exist_ok=True)

fails = []

def read(p):
    with open(p, 'r', encoding='utf-8', errors='surrogateescape') as f:
        return f.read()

def write(p, s):
    with open(p, 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.write(s)

def backup(rel):
    src = os.path.join(K, rel)
    dst = os.path.join(BAD, rel.replace('/', '_'))
    if os.path.exists(src) and not os.path.exists(dst):
        shutil.copy2(src, dst)

def sub(rel, old, new, tag):
    p = os.path.join(K, rel)
    backup(rel)
    s = read(p)
    if old not in s:
        fails.append('%s: 锚点未找到 -> %s' % (rel, tag))
        return False
    if s.count(old) != 1:
        fails.append('%s: 锚点出现 %d 次（应为 1）-> %s' % (rel, s.count(old), tag))
        return False
    write(p, s.replace(old, new, 1))
    print('  [OK] %-28s %s' % (rel, tag))
    return True

print('== 1) 替换 KernelSU 源码为 KSU-Next v3.4.2 ==')
live = os.path.join(K, 'KernelSU', 'kernel')
if os.path.isdir(live):
    shutil.move(live, os.path.join(BK, 'KernelSU-kernel-old'))
os.makedirs(os.path.dirname(live), exist_ok=True)
shutil.copytree(LC, live)
if os.path.exists(os.path.join(live, 'Makefile')):
    os.remove(os.path.join(live, 'Makefile'))
shutil.copy2(os.path.join(live, 'Kbuild'), os.path.join(live, 'Makefile'))
print('  KSU-Next 源码 -> %s' % live)

print('== 2) 摘除 legacy 中不存在的 hook 点 ==')

sub('fs/exec.c',
'''#ifdef CONFIG_KSU
extern bool ksu_execveat_hook __read_mostly;
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,
\t\t\t\tvoid *envp, int *flags);
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,
\t\t\t\t void *argv, void *envp, int *flags);
#endif''',
'''#ifdef CONFIG_KSU
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,
\t\t\t\tvoid *envp, int *flags);
#endif''', 'exec.c extern 精简')

sub('fs/exec.c',
'''#ifdef CONFIG_KSU
\tif (unlikely(ksu_execveat_hook))
\t\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
\telse
\t\tksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);
#endif''',
'''#ifdef CONFIG_KSU
\t/* v3.4.2: ksu_handle_execveat 内部已同时处理 ksud 与 sucompat */
\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
#endif''', 'exec.c 调用统一')

sub('fs/read_write.c',
'''#ifdef CONFIG_KSU
extern int ksu_handle_vfs_read(struct file **file_ptr);
#endif''',
'', 'read_write.c 删 extern')

sub('fs/read_write.c',
'''#ifdef CONFIG_KSU
\tksu_handle_vfs_read(&file);
#endif''',
'', 'read_write.c 删调用')

sub('fs/devpts/inode.c',
'''#ifdef CONFIG_KSU
extern int ksu_handle_devpts(struct inode *);
#endif''',
'', 'devpts 删 extern')

sub('fs/devpts/inode.c',
'''#ifdef CONFIG_KSU
\tksu_handle_devpts(dentry->d_inode);
#endif''',
'', 'devpts 删调用')

sub('drivers/input/input.c',
'''#ifdef CONFIG_KSU
extern bool ksu_input_hook __read_mostly;
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code,
\t\t\t\tint *value);
#endif''',
'', 'input.c 删 extern')

sub('drivers/input/input.c',
'''#ifdef CONFIG_KSU
\tif (unlikely(ksu_input_hook))
\t\tksu_handle_input_handle_event(&type, &code, &value);
#endif

''', '', 'input.c 删调用')

print('== 3) 补 legacy 需要的 hook 点 ==')

sub('kernel/sys.c',
'''	retval = security_task_fix_setuid(new, old, LSM_SETID_RES);''',
'''#ifdef CONFIG_KSU
\t{
\t\textern int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid);
\t\tksu_handle_setresuid(from_kuid_munged(current_user_ns(), old->uid),
\t\t\t\t     from_kuid_munged(current_user_ns(), new->uid));
\t}
#endif
\tretval = security_task_fix_setuid(new, old, LSM_SETID_RES);''', 'sys.c 加 setresuid hook')

sub('kernel/reboot.c',
'''SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
\t\tvoid __user *, arg)
{
\tstruct pid_namespace *pid_ns = task_active_pid_ns(current);''',
'''SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
\t\tvoid __user *, arg)
{
#ifdef CONFIG_KSU
\t{
\t\textern int ksu_handle_sys_reboot(int magic1, int magic2,
\t\t\t\t\t\t unsigned int cmd, void __user **arg);
\t\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
\t}
#endif
\tstruct pid_namespace *pid_ns = task_active_pid_ns(current);''', 'reboot.c 加 sys_reboot hook')

print('== 4) 补 4.9 缺失头文件 shim ==')
SHIMS = {
    'linux/compiler_types.h': '#include <linux/compiler.h>',
    'linux/hex.h': '#include <linux/kernel.h>',
    'linux/pgtable.h': '#include <asm/pgtable.h>',
    'linux/sched/signal.h': '#include <linux/sched.h>',
    'linux/sched/task.h': '#include <linux/sched.h>',
    'linux/sched/task_stack.h': '#include <linux/sched.h>',
    'linux/sched/types.h': '#include <linux/sched.h>',
    'linux/sched/user.h': '#include <linux/sched.h>',
}
for rel, body in SHIMS.items():
    p = os.path.join(K, 'include', rel)
    if os.path.exists(p):
        print('  [SKIP] 已存在 %s' % rel)
        continue
    os.makedirs(os.path.dirname(p), exist_ok=True)
    guard = '__KSU_SHIM_' + rel.replace('/', '_').replace('.', '_').upper()
    write(p, '/* 4.9 backport shim added for KernelSU-Next integration */\n'
             '#ifndef %s\n#define %s\n%s\n#endif\n' % (guard, guard, body))
    print('  [ADD] include/%s -> %s' % (rel, body))

print()
if fails:
    print('!! 有 %d 处失败：' % len(fails))
    for f in fails:
        print('   -', f)
    sys.exit(1)
print('全部补丁应用成功。备份目录: %s' % BK)
