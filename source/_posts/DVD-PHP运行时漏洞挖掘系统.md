---
title: DVD--PHP运行时漏洞挖掘系统(说明文档)
date: 2020-06-13 20:16:46
tags:
---

<h1 align="center">Welcome to DVD 👋</h1>  

{% raw %}
<h3 align="center">一个功能强大的 PHP 运行时漏洞挖掘系统</h3>  
<div align="center">
    <img alt="releases" src="https://img.shields.io/badge/releases-v1.0.0-blue.svg?style=flat-square&longCache=true">
    <img alt="target" src="https://img.shields.io/badge/target-PHP__VERSION ≥ 7 -green">
    <img alt="update" src="https://img.shields.io/badge/update-June-blue">
    <img alt="license" src="https://img.shields.io/badge/license-GUN-green">
</div>
{% endraw %} 
  
## ✨  环境搭建

**在使用之前，请务必阅读并同意 [License](https://github.com/59lx/dvd/blob/master/LICENSE) 文件中的条款，否则请勿安装使用本工具。**

1. 首先需要编译 `trace` 扩展，进入作品代码的` phpext` 目录，将测试目标机器中的 PHP 配置文件 `php.ini` 的绝对路径作为运行参数，运行该目录下的 `setup.py`，此命令将 `trace` 扩展劫持的函数与提前包含的 `entrance.php` 等配置信息导入到目标配置文件当。

   ```bash
   python setup.py [php.ini 文件的绝对路径]
   ```

2. 安装自动化测试需要的第三库，`webdriver` 等驱动。

   ```bash
   pip install selenium
   ```

   `webdriver` 的下载见 `autotest` 目录的 `README.md` 文件。

   > 使用者可以根据常用浏览器下载不同类型的 webdriver

3. 进入到作品 `front` 目录，使用作品提供的已编译的 php 启动漏洞报告平台。

   ```bash
   ../php -S localhost:[任意空闲端口] ./public/router.php
   ```

4. 修改模糊测试服务端的地址。将作品中 `fuzzer` 目录中的 `Server.php` 移动到本地 web 目录，然后根据本地访问 web 目录的地址进行配置，修改 `config` 目录中的 `DVD_FUZZER_DSN` 项，fuzzer 默认通信用户名，密码为 admin 和 password，可以根据需要进行修改。

   ```php
   define('DVD_FUZZER_DSN','http://admin:password@127.0.0.1/Server.php');
   ```

5. 重启一下 apache 服务器，不同运行平台的命令不同，下面给出 Mac 下的重启命令。

   ```bash
   sudo apachectl -k restart
   ```
  
## 🛠 检测能力

- XSS漏洞检测

利用语义分析的方式检测XSS漏洞

  

- SQL 注入检测

支持各种类型的 sql 注入

  

- 命令/代码注入检测

支持 shell 命令注入、PHP 代码执行。

  

- XML 实体注入检测

  

- 文件上传检测 

集成了单独的 UFU 漏洞检测模块

  

- ssrf 检测

  

- 重定向漏洞检测 

  

- 反序列化漏洞检测

  

- 多种文件类漏洞检测

文件读取，文件写入，文件包含，文件删除等漏洞都具有很好的支持。



- 动态特性导致的代码执行漏洞检测

Hook 底层 opcode，具有捕捉动态特性漏洞的能力。


  
## ⚡️ 检测使用

直接点击测试功能点，或者使用作品提供的自动化测试组件进行针对性的自动化测试代码的编写, 集成代码后运行 `main` 目录下的 `run.py`。

```bash
python run.py
```


  
## 📝 其他

如有问题可以联系作者，联系方式 email : click1799@163.com 

详细演示视频地址：[点击进入演示视频](https://blog.c1ick.xyz/2020/06/13/DVD-PHP运行时漏洞挖掘系统-演示视频/)



