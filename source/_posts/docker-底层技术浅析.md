---
title: docker 底层技术浅析
date: 2022-06-15 11:26:52
tags: docker
author: click
---
# 1. 演进

对于统一开发、测试、生产环境的渴望，要远远早于 docker 的出现。先了解一下在 docker 出现之前出现过哪些解决方案。
<a name="oO2J5"></a>

## 1.1 vagrant

vagrant 是较早的解决环境配置不统一的技术方案。它使用 Ruby 语言编写，由 HashCorp 公司在 2010 年 1 月发布。Vagrant 的底层是虚拟机，最开始选用的是 virtualbox。一个个已经配置好的虚拟机被称作 box。用户可以自由在虚拟机内部安装依赖库和软件服务，并将 box 发布。通过简单的命令，就能够拉取 box，将环境搭建起来。

```bash
# 拉取一个 Ubuntu12.04 的 box
$ vagrant init hashicorp/precise32

# 运行该虚拟机 （不用指定 id 吗？）
$ vagrant up

# 查看当前本地都有哪些 box
$ vargrant box list
```

如果需要运行多个服务，也可以通过编写 vagrantfile，将相互依赖的服务仪器运行，颇有如今 docker-compose 的味道。

```yaml
config.vm.define("web") do |web|web.vm.box = "apache"
end
config.vm.define("db") do |db|db.vm.box = "mysql"
end
```

![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-3368046689546614721-ad47e31b.jpeg)
<a name="uBGoi"></a>

## 1.2 LXC（LinuX Container）

在 2008 年，Linux 2.6.24 将 cgroups 特性合入了主干。Linux Container 是 Canonical 公司基于 namespace 和 cgroups 等技术，瞄准容器世界而开发的一个项目，目标就是要创造出运行在 Linux 系统中，并且隔离性良好的容器环境。当然它最早也就出现于 ubuntu 上。<br />2013 年，在 PyCon 大会上 Docker 正式面世。当时的 docker 是在 ubuntu 12.04 上开发实现的，只是基于 LXC 之上的一个工具，屏蔽掉了 LXC 的使用细节（类似于 vagrant 屏蔽了底层虚拟机），让用户可以一句 docker run 命令行便创建出自己的容器环境。
<a name="cjxL7"></a>

# 2. 技术发展

容器技术是操作系统层面的虚拟化技术，可以概括为使用 Linux 内核的 cgroup，namespace 等拘束，对进程进行的封装隔离。早在 docker 之前，Linux 就已经提供了今天 docker 所使用的那些基础技术。docker 一夜之间火爆全球，但技术上的积累并不是瞬间完成的。这里摘取几个关键技术节点进行介绍：<br />![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-6836497827291524143-5b9697f3.jpeg)
<a name="slwvw"></a>

## 2.1 chroot

软件主要分为系统软件和应用软件，而容器中运行的程序并非系统软件。容器中的进程实质上是运行在宿主机上，与宿主机上的其他进程共用一个内核。而每个应用软件运行都需要有必要的环境，包括一些 lib 库依赖之类的。所以，为了避免不同应用程序的 lib 库依赖冲突，很自然的会想到是否可以把它们进行隔离，让他们看到的库是不一样的。<br />1979 年，chroot 系统调用首次问世。这里举一个例子来说明，在 home 目录下准备好一个 alpine 系统的 rootfs，如下（宿主机并不是 alpine 系统）：<br />![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-7209472752910074291-6bdb1bd3.jpeg)<br />在该目录下执行：

```bash
$ chroot rootfs/ /bin/bash (相对于新的 root 目录)
```

然后将 /etc/os-release 打印出来，就看到是  "Alpine Linux", 说明新运行的 bash 跟宿主机上的 rootfs 隔离了。<br />![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-9710951476021714217-2f1c8404.jpeg)
<a name="NPpNE"></a>

## 2.1 namespace

简单来说 namespace 是由 Linux 内核提供的，用于进程间资源隔离的一种技术，是的 a，b 进程可以看到 S 资源；而 c 进程看不到。它是在 2002 年 Linux 2.4.19 开始加入内核的特性，到 2013 年 Linux 3.8 中 user namespace 的引入，对于我们现在所熟知的容器所需的全部 namespace 就都实现了。<br />Linux 提供了多种 namespace，用于对多种不同资源进行隔离。容器的实质是一组进程，但与直接在宿主机执行的进程不同，容器进程运行在属于自己的独立的 namespace。因此容器可以拥有自己的 root 文件系统、自己的网络配置、自己的进程空间、深知自己的用户 ID 空间。<br />这里举一个例子，来直观的看到 namespace 的存在：在宿主机上，执行：ls -l /proc/self/ns 看到的就是当前进程所在的 namespace。

![1654604620817.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-15418666421631518126-3fbb38c6.png)

使用 unshare 命令，运行一个 bash，让它使用一个新的 pid namespace：

```bash
$ unshare --pid --fork --mount-proc bash
```

然后运行 ps -a，看看当前 pid namespace 下的进程：

![1654604758295.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-7827240163250903055-8e8d02ce.png)

在此 bash 上执行：ls -l /proc/self/ns ，会发现当前 bash 进程所在的 pid namespace 与之前是不相同的：

![1654604876859.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-12668088839410624057-99dda1ed.png)

docker 也是借助 namespace 技术，来实现对系统资源的相互隔离，可以用容器中进程所属 namespace 来进行验证。
<a name="r6Th4"></a>

## 2.2 cgroups

cgroups 是为了实现虚拟化而采取的资源管理机制，决定哪些分配给容器的资源可被我们管理，分配给容器去使用的资源的多少。例如可以设定一个 memory 使用上线，一旦进程组（容器）使用的内存达到限额再去申请内存，就会发出 OOM（out of memory），这样就不会因为某个进程消耗的内存过大而影响到其他进程的运行。<br />这里举一个例子，运行一个 alpine 容器，限制只能使用前 2 个 cpu，且只能使用 1.5 个核：

```bash
$ docker run --rm -it --cpus "1.5" --cpuset-cpus 0,1 alpine
```

然后再开启一个新的终端，先看看系统上有哪些资源是可以通过 cgroups 控制的：

```bash
$ cat /proc/cgroups
```

![1654606397909.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-10079020369395101021-c894ec2a.png)

最左边一侧就是 cgroups 中所设置的子系统，分别可以限制对应类型的资源。<br />找到刚刚运行的 alpine 镜像的 cgroups 配置：

```bash
# docker inspect --> Return low-level information on Docker objects
# docker ps -ql  --> -q, --quiet           Only display container IDs
#								 --> -l, --latest          Show the latest created container (includes all states)
$ cat /proc$(docker inspect --format='{{.State.Pid}}' $(docker ps -ql))/cgroup
```

![1654607326206.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-4626382324028178144-5ac1d20f.png)

（这里的 cgroup 的目录中的 `/` 是宿主机 cgroup 挂载点相应子系统目录，如 `/sys/fs/cgroup/cpu/` 等）<br />这样就可以看到这个容器的资源配置了。先验证 cpu 的用量是否为 1.5 个核：

```bash
$ cat /sys/fs/cgroup/cpu,cpuacct/docker/f823e0cd58e5fecc97c36e03717c14a0bb1d061e705397cf92b0026c00fc6f77/cpu.cfs_period_us
```

输出 100000，可以认为是单位，然后再看配额：

```bash
$ cat /sys/fs/cgroup/cpu,cpuacct/docker/f823e0cd58e5fecc97c36e03717c14a0bb1d061e705397cf92b0026c00fc6f77/cpu.cfs_quota_us
```

输出 150000，与单位相除正好是设置的 1.5 个核，接着言珩是否使用的是前两个核心：

```bash
$ cat /sys/fs/cgroup/cpuset/docker/f823e0cd58e5fecc97c36e03717c14a0bb1d061e705397cf92b0026c00fc6f77/cpuset.cpus
```

输出 0-1，与设置相同。<br />现在验证一下此限制有没有生效，在 alpine 容器终端中，执行一个死循环：

```shell
i=0; while true; do i=i+i; done
```

观察当前的 cpu 用量：（此图仅用做说明，id/name 是不对应的）<br />![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-3453586173134073238-71cb80db.jpeg)

接近 1，但为什么不是 1.5？因为运行的死循环只能跑在一个核上，所以我们再打开一个终端，进入到 alpine 镜像中，同样执行死循环的指令，看到 cpu 用量稳定在了 1.5，说明资源的使用量确实完成了限制。

![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-5978130998896660236-2ca2fc44.jpeg)

如果单单就隔离性来说，vagrant 也已经做到了，那么为什么是 docker 火爆？是因为它允许用户将容器环境打包成为一个镜像进行分发，而且镜像是分层增量构建的，者可以大大降低用户使用的门槛。（我觉得是代价的问题吧，容器相比于虚拟机代价大大降低，再加上分层文件系统，使得 docker 对资源的利用率更高）
<a name="fOk8o"></a>

# 3. 存储

image 是 docker 部署的基本单位，它包含了程序文件，以及这个程序以来的资源的环境。docker image 是以一个 mount 点挂载到容器内部的。容器可以近似理解为镜像的运行实例，默认情况下也算是在镜像层的基础上增加了一个可写层。所以，一般情况下如果你在容器内做出的修改，均包含在这个可写层中。
<a name="RHvbd"></a>

## 3.1 联合文件系统（UFS）

Union File System 从字面意思上来理解就是“联合文件系统”。它将多个物理位置不同的文件目录联合起来，挂载到某一个目录下，形成一个抽象的文件系统。<br />![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-6906230848474702701-5f56cabb.jpeg)<br />如上图，从右侧以 UFS 的视角来看，lowerdir 和 upperdir 是两个不同的目录，UFS 将二者合并起来，得到 merged 层展示给调用方。从左侧的 docker 角度来理解，lowerdir 就是镜像，upperdir 就相当于是容器默认的可写层。在运行的容器中修改了文件，可以使用 docker commit 指令保存成为一个新镜像。（也就是把 merged 变成了 lowerdir）
<a name="Vo5PU"></a>

## 3.2 docker 镜像的存储管理

有了 UFS 的分层概念，我们就很好理解这样的一个简单 Dockerfile：

```dockerfile
FROM alpine
COPY foo /foo
COPY bar /bar
```

在 build 时的输出所代表的含义了。<br />![640.jpg](https://b3logfile.com/file/2022/06/solo-fetchupload-6701124898825516247-62e45ebd.jpeg)<br />但是使用 docker pull 拉取的镜像文件，在本地机器上存储在哪，又是如何管理的？这里实际操作认证一下。在宿主机上确认当前 docker 所使用的存储驱动（默认是 overlay2）

```shell
$ docker info --format '{{.Driver}}'
```

以及镜像下载后的存储路径（默认存储在 /var/lib/docker）：

```shell
$ docker info --format '{{.DockerRootDir}}'
```

![1654656955257.png](https://b3logfile.com/file/2022/06/solo-fetchupload-17614840827613677612-a84ef112.png)<br />关注 image 和 overlay2 目录。前者是存放镜像信息的地方，后者则是存放具体每一分层的文件内容。（这里的 165536.165536 是开启 userremap 之后的隔离目录，以后讲一下）我们先深入看一下 image 目录结构：

```bash
$ tree -L 2 /var/lib/docker/image/
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-12377888107490950142-b25a6fcf.png)<br />留心这个 imagedb 目录，接下来以 alpine 镜像为例子，看看 docker 是如何管理镜像的：

```shell
$ docker pull alpine
$ docker image ls alpine
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-17804854460151312179-25c3b3d8.png)

```shell
$ tree -L 2 /var/lib/docker/image/overlay2/imagedb/content/ | grep c059
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-16821512220598905282-ae2e4b30.png)<br />多了一个名为镜像 ID 的文件，是一个 json 格式的文件，这里包含了该镜像的参数信息：

```shell
$ jq . /var/lib/docker/image/overlay2/imagedb/content/sha256/[id]
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-3219872537536606357-183b9670.png)<br />看看讲一个镜像运行起来之后有什么变化，开启一个 alpine 容器：

```shell
$ docker run --rm -d alpine sleep 600
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-14735661835711599890-5b60acff.png)<br />找到它的 overlay2 挂载点（MergedDir）：(从宿主机上 mount 也能看到这条挂载点 信息)

```shell
$ docker inspect --format='{{.GraphDriver.Data}}' $(docker ps -ql) | grep Merged
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-11672385172917191791-5c1deb85.png)

```shell
$ mount | grep e68b
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-10128252885329280348-b59f14db.png)

```shell
$ ls /var/lib/docker/overlay2/d4239d20eddd324f8facaa1b12973f2c30c4343f1c4b907d0639b7b198df2b5e/merged/
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-1138473452603451198-30866c26.png)<br />![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-16933189416052931160-57025052.png)<br />可以验证一下容器所使用的这种分层存储的文件系统：

1. 查看当前容器实例与原始镜像相比，有哪些修改：

```shell
# 输出为空，还没有修改
$ docker diff $(docker ps -ql)
```

2. 在容器实例的 `/` 下创建一个 `test.txt` 文件：

```shell
$ docker exec -it $(docker ps -ql) /bin/sh -c 'echo "Hello Click" > test.txt'
```

3. 查看与原始镜像的修改：

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-13276013217623677958-efb5e392.png)

4. 查看容器对应 UFS 各层文件的变化：
   1. 查看容器在 Merged 层 MergedDir 目录的变化（新增了刚刚创建的 test.txt）：

```shell
$ ls /var/lib/docker/overlay2/e68b24c0414b8e8af8e782a3d8b2f49ed2c3cda295e423ad176bc3820d73536f/merged/
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-234116233964797327-e1d64868.png)

2. 查看容器在镜像层之上增加的可写层 UpperDir 目录的变化（有且仅有 test.txt）：

```shell
$ ls /var/lib/docker/overlay2/e68b24c0414b8e8af8e782a3d8b2f49ed2c3cda295e423ad176bc3820d73536f/diff/
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-17066357415079316551-e644edeb.png)

3. 查看容器使用的镜像层 LowerDir 目录：_（这里回答了之前提出的 镜像的实际内容的存储位置 ）_

```shell
# 读出镜像层包含的 UFS 层
$ cat /var/lib/docker/overlay2/e68b24c0414b8e8af8e782a3d8b2f49ed2c3cda295e423ad176bc3820d73536f/lower
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-16801783490443095281-c25abc76.png)<br />查看一下这些分层，可以看到仅包含 UFS 中低层的原始镜像文件，不包含新增的文件：

```shell
$ ls /var/lib/docker/overlay2/l/WPPXU6IXWFXRU5562K62QHJSII
$ ls /var/lib/docker/overlay2/l/C7O7MVM4YRQGYTWKHJHTMKKCK3
```

![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-4224894619566441865-91fc06fd.png)
