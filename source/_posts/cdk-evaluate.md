---
title: CDK 源码阅读笔记（evaluate 部分）
date: 2022-11-30 17:11:25
tags: 
author: click
---

## CDK 功能概述

CDK（Container Duck）是一个为容器环境定制的渗透测试工具，在可控容器内提供，零依赖的常用命令及 Poc/EXP。集成 Docker/K8s 场景特有的逃逸、横向移动、持久化利用方式，插件化管理。
从功能上，CDK 主要有三大模块，分别为：

+ [evaluate](https://github.com/cdk-team/CDK/wiki/CDK-Home-CN#evaluate-%E6%A8%A1%E5%9D%97)：在容器内进行信息收集，评估存在的风险点
+ [exploit](https://github.com/cdk-team/CDK/wiki/CDK-Home-CN#exploit-%E6%A8%A1%E5%9D%97)：在发现风险点的基础上，运行零依赖的 poc/exp/其他利用方式
+ [tool](https://github.com/cdk-team/CDK/wiki/CDK-Home-CN#tool-%E6%A8%A1%E5%9D%97)：提供在容器中使用的零依赖工具包（nc，curl，ifconfig...），解决容器镜像裁剪问题

## 学习目标

如果没有目标埋头看的话，很容易忘记要从里面学到什么，陷入没有必要的细节，所以先在这简单总结下想学到的东西：

+ 从信息收集/poc 中学习容器场景的利用细节，补充容器安全知识
+ 总结容器场景下风险的特点，哪些问题在什么时机出现
+ 学习简单 go 项目的架构，补一下 go 相关内容
+ 尝试向 CDK 加自己的内容，交个 PR

## 代码架构

### 源码目录结构

+ CDK/
    + cmd/  （命令行文件）
  + conf/  （build，扫描，利用等过程中会用到的配置内容）
  + pkg/  (项目的一些依赖)（非第三方包，项目作者写的部分）
    + cli/  （解析命令行参数，并按照参数执行子命令）
    + evaluate/  （容器信息收集实现）
    + exploit/  （容器 exploit 实现）
    + tool/  （容器 tool 实现）
    + task/  （注册的一些子命令实现，eg.auto-escape..（像是 docker 的 `reexec` 的注册一样））
    + plugin/
      + interface.go  （为 Task(注册子命令),Exploit(利用方式) 提供接口）
  + go.mod  （使用 go mod 管理包依赖）

### 调用流程

CDK 入口点在 cmd/cdk/cdk.go 的 `main()` 函数：

![](https://b3logfile.com/file/2023/03/solo-fetchupload-14504657500336549418-pCArCV4.png)
`ParseCDKMain()` (pkg/cli/parse.go) 中解析传入的命令行参数：`parseDocopt()`（使用`docopt-go` 库）：
![](https://b3logfile.com/file/2023/03/solo-fetchupload-9956389420549371028-T3bQBSk.png)通过检查 xx 子命令是否存在，调用具体的子命令：

1. auto-escape（自动化逃逸容器并执行命令）：
   ![](https://b3logfile.com/file/2023/03/solo-fetchupload-16467370175702016281-525VHAX.png)
2. evaluate（容器内信息收集）：
   ![](https://b3logfile.com/file/2023/03/solo-fetchupload-7788675113464703599-fKzb5Kd.png)
3. exploit（已有方式的利用）：
   ![](https://b3logfile.com/file/2023/03/solo-fetchupload-6564423730075946747-9fDceWE.png)
4. tools（零依赖工具包）：
   ![](https://b3logfile.com/file/2023/03/solo-fetchupload-2800380943072489387-G1zGQE8.png)

### 功能实现总结

#### evaluate

基础信息：

| 信息类型 | 名称 | 获取途径 |
| --- | --- | --- |
| 系统信息 | current dir | `os.Getwd()` |
|  | current user（username, uid, gid, home-dir） | `user.Current()` |
|  | hostname | `os.Hostname()` |
|  | os/kernel version | 使用 gopsutil 库，对不同操作系统有适配，linux 是获取 /etc/lsb-release，/proc/version |
|  | 带有 SUID 位的二进制文件 | `find /bin/. -perm -4000 -type f` |
|  | 带有 capabilities 的二进制文件 | `getcap -r /bin` |
| 服务 | 敏感环境变量 | 通过 `conf.SensitiveEnvRegex` 在 `os.Environ()` 中正则匹配(ssh_, kubernetes..) |
|  | 敏感服务 | 通过 `conf.SensitiveProcessRegex` 在进程文件名(/proc/pid/stat)中匹配(http, ssh...) |
| 命令和 capabilities | 可用命令 | 通过 `exec.LookPath()` 检查 `conf.LinuxCommandCheckList` 中的常用命令是否可用 |
|  | 进程 capabilities | 通过读取 /proc/self/status 中 CapEff 内容，检查是否为特权容器/超出默认的 Cap，可以用来执行特权操作 |
| 挂载信息 | 可能用来逃逸的挂载 | 通过读取 /proc/self/mountinfo 内容，检查 1. 设备名包含 "/" \|\| 文件类型包含 ext（除了默认挂载文件)  2. 设备名为 lxcfs 的读写挂载，可以用来逃逸(如果将lxcfs的cgroup目录挂了进来) |
| net-ns | 判断是否在 host net 中 | 读 /proc/net/unix 内容，是否存在 /systemd/、/run/user/ 的 unix socket 判断 |
|  | 敏感 unix socket | 读 /proc/net/unix 内容，是否存在 @/containerd-shim/*([CVE-2020-15257](https://xz.aliyun.com/t/8925)) |
| sysctl 变量 | 敏感 sysctl 变量 | /proc/sys/net/ipv4/conf/all/route_localnet(允许外部数据包的源/目的ip为127.0.0.1，导致绑定 localhost 的本地服务被外部访问)
| dns | 通过 dns 的 any 查询，寻找 k8s 中的 service 信息(不受 ns 限制) | 查询 "any.any.svc.cluster.local."，"any.any.svc.cluster.local." 的 SRV 记录(端口和域名信息)，可以获得 service 的 name, namespace, port, endpoints-ip/port...（新版本已经不支持 any 查询了）
| k8s API server | 匿名用户访问 | 通过匿名访问(不带 token) https://[apiserver-ip]:[apiserver-port]/ 确认可访问，继续访问 /api/v1/namespaces 确认是否允许匿名访问查询 |
| k8s ServiceAccount | 容器内 SA 状态 | 通过 pod 中 token 访问 https://[apiserver-ip]:[apiserver-port]/apis/确认可访问，继续访问 /api/v1/namespaces 确认是否具有高权限(这里可以探测的更细一点) |
| 云供应商 metadata API | 检测 CSP 接口状态 | 访问各厂商的 metadata 接口，判断集群所在平台 |
| 内核漏洞 | 检查可能存在的内核漏洞 | 使用 mzet-/linux-exploit-suggester 库提供的检测可能存在的内核漏洞功能 |

进阶信息：

| 信息类型 | 名称 | 获取途径 |
| --- | --- | --- |
| 本地文件信息 | 寻找敏感文件 | `filepath.Walk()` 从根目录遍历搜索有无 `conf.SensitiveFileConf.NameList`（docker socket, containerd socket, containerd-shim socket, .git...） 中的文件） |
| ASLR | ASLR 启用情况 | 读 /proc/sys/kernel/randomize_va_space 判断地址空间随机化（二进制相关不太懂了就）|
| cgroup | cgroup 层级情况 | 对比 /proc/1/cgroup 和 /proc/self/cgroup 文件内容，检查有无不同 cgroup 项（判断是否有子 cgroup 创建？）|

## PR

+ /pkg/evaluate/check_mount_escape.go 检查挂在信息时对默认挂载的过滤
  ![](https://b3logfile.com/file/2023/03/solo-fetchupload-11350212061525450947-eFYLFyO.png)
+ 能否在 evaluate 模块中增加 WhoC 功能来检测 runc 版本？
  whoc 的功能需要容器镜像 entrypoint 可控，或能够执行 `docker exec` 之类的命令，不太符合常见容器使用场景，可以再看一下 5736 在 CDK 中的利用是怎么写的，可以参考一下，说不定能成
+ (2023.2.23) 检测 pod 拥有 sa 权限的细粒度更大一些，获取拥有的敏感权限 (list secret, create pod/exec...)




