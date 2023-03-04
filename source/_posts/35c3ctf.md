---
title: 35c3CTF namespace sandbox 分析
date: 2022-10-1 20:03:21
tags: TODO
author: click
---
## 题目
*这个题目是 CVE-2019-5736 的同类思路，漏洞也是收到这道题目启发发现的*

题目链接：[https://github.com/LevitatingLion/ctf-writeups/tree/master/35c3ctf/pwn_namespaces](https://github.com/LevitatingLion/ctf-writeups/tree/master/35c3ctf/pwn_namespaces)
题目给出一个 Dockerfile 和一个 namespaces 二进制执行文件

```dockerfile
FROM tsuro/nsjail
COPY challenge/namespaces /home/user/chal
#这一句是模拟题解 flag 文件
#COPY tmpflag /flag 
CMD /bin/sh -c "/usr/bin/setup_cgroups.sh && cp /flag /tmp/flag && chmod 400 /tmp/flag && chown user /tmp/flag && su user -c '/usr/bin/nsjail -Ml --port 1337 --chroot / -R /tmp/flag:/flag -T /tmp --proc_rw -U 0:1000:1 -U 1:100000:1 -G 0:1000:1 -G 1:100000:1 --keep_caps --cgroup_mem_max 209715200 --cgroup_pids_max 100 --cgroup_cpu_ms_per_sec 100 --rlimit_as max --rlimit_cpu max --rlimit_nofile max --rlimit_nproc max -- /usr/bin/stdbuf -i0 -o0 -e0 /usr/bin/maybe_pow.sh /home/user/chal'"
```

## TL;DR

- 题目程序的 Run_elf() 功能没有加入 sandbox 的 net ns
- 通过一个 unix socket 连接两个沙盒中进程，并通过其将一个沙盒的 root 目录文件描述符发送给另一个沙盒
- 使用这个外界文件描述符逃逸 chroot
- 在新的 sandbox 创建过程中，用一个指向`/` 的符号连接替换将要 chroot 的目标目录，由此获得一个unchroot 的进程**（TOCTOU）**
- 创建一个新的 ns 获得 capabilities
- 使用 bind 挂载伪造一个`/proc/$pid/ns` 目录，从而在一个新加入的进程降权前控制它 ???
- 注入 shellcode 到上述新加入进程中，读取`flag`

## 分析题目

关注其进行了以下步骤：

1. 将题目中的 namespaces 文件拷贝到 /home/user/chal
2. 执行一段 shell 命令
   1. 设定 cgroups 限制（不重要）
   2. 将镜像中的 /flag 拷贝到 /tmp/flag
   3. 设置 /tmp/flag 权限 r--
   4. 设置 /tmp/flag 属主为 user (id 为 1000)
   5. 启动一个 nsjail 服务，监听 1337 端口来执行 maybe_pow.sh，具体参数解释如下  

```shell
su user -c # 以 user 用户执行
/usr/bin/nsjail 
    -Ml --port 1337 # 监听 1337 port
    --chroot / # 没有切换根目录
    -R /tmp/flag:/flag # 将 /tmp/flag 只读方式绑定挂载到 /flag
    -T /tmp # 在 /tmp 处挂载一个 tmpfs
    --proc_rw # 将 procfs 挂载为可读写模式
    -U 0:1000:1 # 隔离环境内的 UID/GID 0和1 分别映射为环境外的 1000 和 100000
    -U 1:100000:1 
    -G 0:1000:1 
    -G 1:100000:1 
    --keep_caps # 保留所有 capablities
    --cgroup_mem_max 209715200 
    --cgroup_pids_max 100 
    --cgroup_cpu_ms_per_sec 100 
    --rlimit_as max 
    --rlimit_cpu max 
    --rlimit_nofile max 
    --rlimit_nproc max 
    -- /usr/bin/stdbuf -i0 -o0 -e0 /usr/bin/maybe_pow.sh /home/user/chal # 设置 input/output/error 输出无缓冲
```

maybe_pow.sh 中的内容为: (这里的 pow... 均不重要，只关注 exec "$@")，结合上面的参数也就是执行 /home/user/chal

```shell
#!/bin/bash

if [ -f /pow ]; then # 如果 /pow 存在
  POW="$(cat /pow)"  # POW = /pow 的内容
  if [ ${POW} != 0 ]; then # 如果 $POW 变量 != 0
    if ! /usr/bin/pow.py ask "${POW}"; then # 如果 "pow.py ask $POW" 执行返回值 == 0, 脚本退出
      echo 'pow fail'
      exit 1
    fi
  fi
fi

exec "$@" # 执行传入的参数
```

这里通过 docker 将题目搭建起来，(因为需要设置 cgroups 限制，所以使用 --privileged 参数)。访问 1337 端口，发现其类似于 docker run/exec 的功能：
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-3286347138440346285-CMF5H7Q.png)

## namespaces 可执行文件逻辑

~~通过逆向，~~其主要逻辑为：
**main():**
主线程，给出命令提示 1\2\3，分别跳入对应线程，收到 >=3 则退出

**Start_sandbox():**
选项1对应处理函数

1. Fork 一个新进程使用全新的 namespace
   1. 将父 user namespace 中的 userid 1 映射到新 user namespace 中的 userid 1（低权限用户)
   2. 父进程返回主循环，子进程继续执行
2. 读取用户提供的 init 二进制文件，将其加载到 memfd 中
3. 创建目录 /tmp/chroots/$idx，(**mode 777**)，idx 是已创建 sandbox 的数量

**这两步中间需要 TOCTOU**

4. chroot 到上述目录
5. 通过 setresuid()/setresgid() 改变用户/用户组到 1（降权）
6. 执行来自 memfd 的 init 二进制文件

**Run_elf():**
选项2对应处理函数

1. 用户给定一个沙盒序号，并发送一段数据作为将要执行的 elf 文件
2. 创建一个子进程
   1. 父进程返回主循环，子进程继续执行
3. 子进程根据用户给定的沙盒序号找到沙盒内的初始进程（上面 start 输入的 elf 程序）
4. 依次打开并加入 /proc/[初始进程PID]/ns/ 下的**user、mnt、pid、uts、ipc 和 cgroup 命名空间（没有 net）**
   [其中，在加入 pid 命名空间后执行了一次 fork，真正切换到目标 pid 命名空间（因为 pid namespace 比较特殊，当前进程的 pid namespace 并不会改变，只有子进程才会）, fork 后的父进程退出]
5. 子进程（新的 pid ns）根据沙盒序号找到 /tmp/chroots/[沙盒序号]/，切换根目录到这里
6. 通过 setresuid()/setresgid() 降权为 1 号用户
7. 执行来自 memfd 的 elf 文件

从 Run_elf() 处理逻辑中，很明显发现第 4 步依次加入 init process 的 ns 过程中，漏掉了 net ns，这会导致所有新加入的 process（包含不同沙盒中）共享所有网络接口和堆栈。

## chroot 逃逸

上面的流程中可以看到，对于文件系统的隔离，sandbox 启用了新的 mnt ns，但没有在其中挂载新的根目录，只是使用了 chroot 来达到隔离的效果，而对于 chroot 的逃逸，只需要构造一个 chroot 之外的文件描述符即可（然后通过 openat 等借助文件描述符 + 相对地址的方式），这里有三种思路：

- 在 chroot 环境中嵌套一个 chroot，同时保留一个第二层 chroot 之外的文件描述符
- 打开一个文件描述符，等待该文件被移出 chroot 环境，此时该文件描述符满足要求
- 从外界传入一个 chroot 环境外的文件描述符

由于共享的 net ns，所以这里我们采用思路三，通过 unix socket 传递一个 chroot 环境外的文件描述符，来实现 chroot 逃逸。
这里我们无法通过 socket file 来实现通信，但可以通过绑定一个 unix domain socket 到抽象 socket 命名空间里的一个名称来实现通信。具体来说，使用 `SCM_RIGHTS` 类的 ancillary messages 实现发送文件描述符。
此时，新加入的 process 已经可以通过 `../` 访问到 chroot 环境之外的文件，但由于经过了降权 (0->1)，所以并不能直接读取 `/flag`。

> abstract socket namespace 允许我们将套接字绑定到文件系统上不可见的名称，和这里的 namespace 沙箱所指的 namespace 不是同一类。

## 彻底逃逸 chroot

上一步中，我们已经可以访问到 chroot 环境外的文件，但对于 chroot 环境的其他限制（不能创建新的 user ns，从而创建一个高权限空间（新的 namespace 中的 all cap + root））并没有解除。（因为 /proc/$$/root 不是当前 mnt ns 下的文件系统根目录）。
这里的沙盒父目录 `/tmp/chroots/` 权限是 `777`，是一个很明显的权限过松情况，配合上一步可以操作到 chroot 环境外文件的效果，可以将 /tmp/chroots/[sandbox_id]/ 目录删除，替换成一个指向 `/` 的符号链接，

## 遇到的问题:

> 如果在沙盒1中打开当前进程根目录发送给沙盒2，那么沙盒2中的进程就能够以这个文件描述符加上相对路径调用 openat 打开沙盒外的文件

_为什么不能通过沙盒2的文件描述符来访问，沙盒1就可以?_
这是一个经典的 chroot 逃逸，分析见下节。

> 接着它加入的pid命名空间实际上属于init的子进程

_init 的子进程和 init 进程不是同一个 pid ns 吗?_
根据后面描述的 ptrace 要求来看，这里的子进程应该新建了一个 pid ns。

> 1. 这样一来，init 子进程就能够在这个pid命名空间下借助ptrace向未降权的 run_elf 进程注入代码并执行了。
> 2. 为了ptrace，init 进程必须新建一个 pid 命名空间

_ptrace 的条件?_
To be able to ptrace the process, it has to be in the same pid namespace as us and we have to have the CAP_SYS_PTRACE capability.

1. 调试进程要和被调试进程在一个 pid ns 中（被调试应该可以有更下层的 pid ns，会被映射到上层 pid ns 中）
2. 调试者需要有 CAP_SYS_PTRACE

> chroot 过的进程不被允许创建新的 user 命名空间来获得 CAP_SYS_ADMIN 权限

_不允许创建新的 user ns 还是创建后不能获得 cap_sys_admin? 创建新的 user ns 会获得哪些 cap?_
[prevents entering a user namespace from inside a chroot](https://unix.stackexchange.com/questions/442996/what-rule-prevents-entering-a-user-namespace-from-inside-a-chroot)
chroot 前后，cap_sys_admin 不会变化。
chroot 过的进程不允许创建新的 user namespace。众所周知，在具有 CAP_SYS_CHROOT 的情况下，chroot 逃逸非常轻松（通过嵌套一个 chroot），而新的 user ns 会将全部 cap 赋予一个普通 uid（外部视角来看），这会导致一个普通用户逃逸 chroot。
同时可以在 `man 2 clone`，`man 2 unshare` 中看到对应描述：

> EPERM (since Linux 3.9)
> CLONE_NEWUSER was specified in the flags mask and the
> caller is in a chroot environment (i.e., the caller's root
> directory does not match the root directory of the mount
> namespace in which it resides).

[https://tinylab.org/user-namespace/](https://tinylab.org/user-namespace/)
新创建一个 user namespace 会重新规划这个 ns 的 capability 能力，和这个 user namespace 父辈的 capability 能力无关。在新 user namespace 中 uid 0 等于 root 默认拥有所有 capability，普通用户的 capability 是在 exec() 时由 task->real_cred->cap_inheritable + file capability 综合而成。

## 相关知识

### chroot 逃逸

[https://github.com/earthquake/chw00t](https://github.com/earthquake/chw00t)
chroot 逃逸的成因是使用一个 root_path 之外的文件描述符，对其使用 .. 相对路径，可以越过 root_path 的限制。因为该描述符在进程的 root_path(从 /proc/xxx/root 中查看指向 "/../") 之外，所以原始的 root dir 是这个进程能找到的下一个 root barrier，使用 .. 可以一直跳到此 root barrier 为止。
至于为什么不能从 docker container 中逃逸到宿主机，除了执行权限等因素外，是因为在 container 视图的 mount 树中，overlay 挂载点是其 root 节点（从/proc/xx/root 中查看指向 "/"），作用相当于一个 root barrier。（这里需要看源码深入分析下）
而题目这里只使用了 chroot 来切换 root 目录，虽然也进入了新的 mnt ns，但并没有挂载新的根目录（需要了解一下 docker run 的流程，pivot_root的安全性）
[chroot 和 pivot_root](https://unix.stackexchange.com/questions/456620/how-to-perform-chroot-with-linux-namespaces)
对于其源码分析和 mnt namespace 隔离的情况，需要看一下内核 lookup/openat 文件打开流程相关的函数

chroot 的 man page：
![image.png](https://b3logfile.com/file/2023/03/solo-fetchupload-7011856655724033912-FY9x1Yz.png)
最经典的情况：chroot 对具有 CAP_SYS_CHROOT 的进程/用户是不存在限制的，可以通过简单的二次 chroot(目的也是**获得一个 chroot 外的文件描述符**) 来逃逸。

### ptrace 注入

ptrace 的条件：

> To be able to ptrace the process, it has to be in the same pid namespace as us and we have to have the CAP_SYS_PTRACE capability.

1. 调试进程要和被调试进程在一个 pid ns 中（被调试应该可以有更下层的 pid ns，会被映射到上层 pid ns 中）
2. 调试者需要有 CAP_SYS_PTRACE

## 我的思考

+ 依次打开、加入、打开、加入 /proc/[init 进程 pid]/ns/ 下的 namespace 是不正常的，感觉很少有这种情况吧，因为 setns 加入到新的 mnt ns 之后，进程的根文件系统会变化到容器的不可信环境中。_会吗？实验一下
倒是有可能有这种情况，依次调用 setns_

- 能不能先在容器外打开文件描述符，然后进入 ns (mnt)后，再访问呢?

## TODO

- linux 文件知识，做下笔记
- 实验未 chroot 时能不能通过新建。。
可以，新建 usernamespace 不需要任何 cap，创建好的 user ns 中的 root（被映射的）会带有所有 cap
- 实验 chroot 之后能不能通过新建 usernamespace 来获得 sys_cap_admin
不能, [https://unix.stackexchange.com/questions/442996/what-rule-prevents-entering-a-user-namespace-from-inside-a-chroot](https://unix.stackexchange.com/questions/442996/what-rule-prevents-entering-a-user-namespace-from-inside-a-chroot)
- ptrace 条件，为什么需要新建 pid ns
(1) 调试进程要和被调试进程在一个 pid ns 中（被调试应该可以有更下层的 pid ns，会被映射到上层 pid ns 中）
(2) 调试者需要有该 pid ns 中的 CAP_SYS_PTRACE
- 分析题解代码


