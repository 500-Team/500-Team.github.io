---
title: proc magic link 处理逻辑分析
date: 2022-03-04 18:13:16
tags:
author: click
---
_/proc/self/exe 为例，内核版本 4.14.151_

## 内核中的处理流程

我将所有 /proc 下这类伪文件的读取涉及到的内容分成了三个阶段，分别是 create，open，read 阶段。create 是在系统初始化时为伪文件的操作声明一些处理函数或者 data；open 阶段主要包括根据目录 lookup，以及将 create 中声明的函数赋给所打开的 inode 结构体的 op 指针上；craete 阶段主要就是调用前面所注册的处理函数或者访问所注册的 data 内容。

### create 阶段

此文件的注册项在 `tid_base_stuff[]` 数组中：

```c
static const struct pid_entry tid_base_stuff[] = {
    ...
    LNK("exe",       proc_exe_link),
    ...
    }
```

这里关于 `LNK` 宏的定义：

```c
#define LNK(NAME, get_link)                             \
        NOD(NAME, (S_IFLNK|S_IRWXUGO),                  \
            &proc_pid_link_inode_operations, NULL,      \
            { .proc_get_link = get_link } )

#define NOD(NAME, MODE, IOP, FOP, OP) {         \
        .name = (NAME),                         \
        .len  = sizeof(NAME) - 1,               \
        .mode = MODE,                           \
        .iop  = IOP,                            \
        .fop  = FOP,                            \
        .op   = OP,                             \
}
```

将其完全展开为：

```c
struct pid_entry {
    .name = "exe",
    .len  = sizeof("exe") - 1,
    .mode = (S_IFLNK|S_IRWXUGO),
    .iop  = &proc_pid_link_inode_operations,
    .fop  = NULL,
    .op   = { .proc_get_link = proc_exe_link }
}
```

### open 阶段

接下来看一下，proc 文件打开的调用流程：

```c
static struct dentry *proc_root_lookup(struct inode * dir, struct dentry * dentry, unsigned int flags)
{
    // 对于 /proc/<pid>/ 下的文件，会调用此函数
    if (!proc_pid_lookup(dir, dentry, flags))
        return NULL;
    
    // 查找其他文件
    return proc_lookup(dir, dentry, flags);
}

struct dentry *proc_pid_lookup(struct inode *dir, struct dentry * dentry, unsigned int flags)
{
    int result = -ENOENT;
    struct task_struct *task;
    unsigned tgid;
    struct pid_namespace *ns;

    // 取出要进入的 pid(这里的变量名 tgid 并不准确，这里是以线程为实体的)
    tgid = name_to_int(&dentry->d_name);
    if (tgid == ~0U)
        goto out;

    // 取出此 /proc 挂载时的 pid ns
    ns = dentry->d_sb->s_fs_info;
    rcu_read_lock();
    // 取出对应 task_struct
    task = find_task_by_pid_ns(tgid, ns);
    if (task)
        get_task_struct(task);
    rcu_read_unlock();
    if (!task)
        goto out;

    // 会将 proc_tgid_base_inode_operation 赋值给目录 inode->i_op
    result = proc_pid_instantiate(dir, dentry, task, NULL);
    put_task_struct(task);
out:
    return ERR_PTR(result);
}
```

`proc_tgid_base_inode_operation` 的内容为：

```c
static const struct inode_operations proc_tgid_base_inode_operations = {
    // 对其目录下文件查找时则会调用 proc_tgid_base_lookup
    .lookup     = proc_tgid_base_lookup,
    .getattr    = pid_getattr,
    .setattr    = proc_setattr,
    .permission = proc_pid_permission,
};
```

在 `proc_tgid_base_lookup()` 中最终会调用 `proc_pident_instantiate()` 来构造对应文件的 `inode` 和 `proc_inode`
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-13837556882866983591-0jLrHh2.png)

```c
const struct inode_operations proc_pid_link_inode_operations = {
    .readlink   = proc_pid_readlink,
    .get_link   = proc_pid_get_link,
    .setattr    = proc_setattr,
};
```

### read 阶段

这里由于是符号链接文件，所以是一个 `readlink` 动作。linux 文件系统在获取链接文件时，会调用 `inode->op->get_link()`，所以对应到 `/proc/<pid>/exe` 则是 `proc_pid_get_link()`:
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-14929494736103633446-MQf2bvh.png)
继续跳入到 `proc_exe_link()` 可以看到，直接从 `task_struct->mm` 中取出 task 的执行文件句柄 `struct file`，这里没有任何 mnt 或 chroot 限制：
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-10371927861497632516-HfL6mhT.png)
再回头关注一下 `proc_pid_get_link()` 中的 `nd_jump_link()`，_这应该是造成 magic links 特殊性的所在吧_，它将刚才获取的结果传入：
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-6830618879581833496-KbgWUA7.png)
感觉**这里直接将目标文件的 inode 取了出来**，而不是与常规符号链接文件一样，读出所保存的 link 目录字符串，再从文件系统中进行解析。
内核中对于 `LOOKUP_JUMPED` 的解释：
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-11492132095999872800-D2PzqXP.png)


## 简单的思考

可以看到伪文件的打开过程中会有一部分函数是通用函数，比如 `proc_root_lookup`, `proc_pid_readlink`...，这些函数可以用来分析 proc 文件系统的通用特点，比如符号链接读取不是字符串内容而是处理函数，lookup 过程..。
但是对于某个单独文件，我们要分析它们的某些特征的时候，这些通用函数是应该跳过的（类似于 web 框架函数），我们重点关注的部分应该是与单一文件相关的最终处理函数（类似于**业务函数**），如何定位这些最终处理函数是我在分析伪文件系统时候要解决的地方。
这些定位方法会和文件系统特点相关，比如在 proc 文件系统中定位的方法在 sys 下就不一定好用了。

