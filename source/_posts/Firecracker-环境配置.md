---
title: Firecracker 环境配置
date: 2022-06-19 11:28:29
tags: 安全容器
author: click
---
![](https://b3logfile.com/bing/20220518.jpg?imageView2/1/w/960/h/540/interlace/1/q/100)

<a name="nLCRy"></a>

# 主机配置

- ubuntu 18.04 物理机
- x86_64 架构
  <a name="Em4hc"></a>

# 前期准备

- 增加 `/dev/kvm` 权限，`sudo setfacl -m u:${USER}:rw /dev/kvm`
- 检查系统符合要求去运行 Firecracker，运行项目源码中 `tools/devtool checkenv`
  - 出现的 `WARNING`暂时不知道有什么影响![image.png](https://b3logfile.com/file/2022/06/solo-fetchupload-13256995363828070405-86a7ff60.png)
    <a name="b0BgP"></a>

# 获取 Firecracker 二进制文件

获取与机器架构对应的最新的 firecracker 二进制文件：

```shell
release_url="https://github.com/firecracker-microvm/firecracker/releases"
latest=$(basename $(curl -fsSLI -o /dev/null -w  %{url_effective} ${release_url}/latest))
arch=`uname -m`
curl -L ${release_url}/download/${latest}/firecracker-${latest}-${arch}.tgz \
| tar -xz
```

将解压的文件夹中的 firecracker 二进制文件改名：

```shell
cd release-${latest}-$(uname -m)
mv firecracker-${latest}-$(uname -m) firecracker
```

或者选择[从源码编译](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md#building-from-source)
<a name="jljeG"></a>

# 运行 Firecracker

> NOTE: 在生产环境中，Firecracker 被设计成在沙盒中安全运行，由 `jailer` 程序精心设置。 我们的集成测试套件也是这样实现的。然而，如果你只想看到 Firecracker 启动一个 Linux 客户机，你可以按如下操作。

1. 确认已拥有可运行的 `firecracker` 二进制文件（上一步下载的）
2. 需要解压好的 linux kernel 二进制文件和一个 ext4 文件映像（用来作为 rootfs）<br />x86_64 示例文件：[kernel](https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin)、[rootfs](https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/rootfs/bionic.rootfs.ext4)
3. 打开两个 shell：一个用来运行 Firecracker，另一个用来控制它（通过向 API socket 写内容）

在 shell1 中：

- 确认没有已有的 firecracker API socket

```shell
rm -f /tmp/firecracker.socket
```

- 启动 Firecracker

```shell
./firecracker --api-sock /tmp/firecracker.socket
```

在 shell2 中：

- 设置客户机内核（我的物理机架构是 x86_64）

```shell
kernel_path="....../hello-vmlinux.bin"

curl --unix-socket /tmp/firecracker.socket -i\
  -X PUT 'http://localhost/boot-source'  \
  -H 'Accept: application/json'          \
  -H 'Content-Type: application/json'    \
  -d "{
         \"kernel_image_path\": \"${kernel_path}\",
         \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off\"
  }"
```

- 设置客户机 rootfs

```shell
rootfs_path="....../hello-rootfs.ext4"

curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT 'http://localhost/drives/rootfs' \
  -H 'Accept: application/json'           \
  -H 'Content-Type: application/json'     \
  -d "{
        \"drive_id\": \"rootfs\",
        \"path_on_host\": \"${rootfs_path}\",
        \"is_root_device\": true,
        \"is_read_only\": false
   }"
```

- 启动客户机

```shell
curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT 'http://localhost/actions'       \
  -H  'Accept: application/json'          \
  -H  'Content-Type: application/json'    \
  -d '{
      "action_type": "InstanceStart"
   }'
```

4. 返回 shell1，将看到进入了一个新 shell，提示登录到客户机器。如果用的 `hello-rootfs.ext4` 映像，则用户名密码均为 `root`。
5. 可以在客户机器中使用 `reboot` 命令，将会优雅的关闭 firecracker，这是因为 firecracker 并没有实现客户机电源管理。

> NOTE: 默认的 microVM 将会使用 1 vCPU 和 128 MiB RAM。如果你想定制其大小，可以在发出 `InstanceStart` 调用之前，通过 API command 修改

```shell
curl --unix-socket /tmp/firecracker.socket -i  \
  -X PUT 'http://localhost/machine-config' \
  -H 'Accept: application/json'            \
  -H 'Content-Type: application/json'      \
  -d '{
      "vcpu_count": 2,
      "mem_size_mib": 1024
  }'
```

<a name="bOwgq"></a>

## 不发送 API requests 来配置 microVM

如果你不想通过使用 API socket 来启动一个客户机，你可以通过传递参数 `--config-file` 给 Firecracker 进程来实现。使用其启动 Firecracker 的命令像下面这样：

```shell
./firecracker --api-sock /tmp/firecracker.socket --config-file <path_to_the_configuration_file>
```

`path_to_the_configuration_file` 应该是一个 json 文件的路径，该文件存储了所有 microVM 资源的配置。其必须包含客户机 `kernel` 和 `rootfs` 的配置，因为他们是必须的，其他所有资源都是可选的。<br />因为使用此配置方法也将直接启动 microVM，因此需要在该 json 中指定所有所需的启动前（`pre-boot`）可配置资源。资源的名称可以从 `src/api_server/swagger/firacracker.yaml` 中查看，其字段的名称和使用 API requests 配置时相同。`test/framwork/vm_config.json` 是一个配置文件的示例。在机器启动后，你仍然可以使用 socket 来发送 API requests 发送启动后（`post-boot`）操作的 API 请求。

<a name="HyZWD"></a>

# Links

- [深度解析 AWS Firecracker 原理篇 – 虚拟化与容器运行时技术](https://aws.amazon.com/cn/blogs/china/deep-analysis-aws-firecracker-principle-virtualization-container-runtime-technology/)
- [深度解析 AWS Firecracker 实战篇 – 一起动手点炮竹](https://aws.amazon.com/cn/blogs/china/in-depth-analysis-of-aws-firecracker/)
- [Firecracker](https://github.com/firecracker-microvm/firecracker)
- [Getting Started with Firecracker](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)

<a name="jWuOb"></a>

# Todo

- Firecracker 介绍及使用
- Firecracker 配合容器运行时实现安全容器


