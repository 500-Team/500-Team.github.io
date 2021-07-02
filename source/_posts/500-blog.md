---
title: 500 blog
date: 2021-05-27 17:20:15
tags: blog
author: click
---
## 搭建说明

500 团队博客现在使用 github page + hexo 部署，主题 even.

### 新注册了
+ 团队 github 账号(`500-Team`)
+ 团队博客域名(`500team.cn`)
+ cloudflare CDN 账号

### 相关配置
+ 博客对应仓库为 `500-Team.github.io`，绑定域名为 `500team.cn` ，使用 cloudflare CDN 实现博客在国内的加速访问，(主要为了加速其中图片的访问)。
+  `500-Team.github.io` 共两个分支，分别为 `master` 和 `gh-pages`。在每次提交文章时，`tools/syn` 脚本会将两个分支均进行拉取了推送，以解决多人协同问题。
+ `master` 分支为 hexo 文章源文件分支，`gh-pages` 分支为文章发布内容分支。
+ `500team.cn` 部署了 https，使用 cloudflare 自签名证书。

考虑到博客维护的问题，本博客的所有功能都托管在第三方(Github、cloudflare等)，仅域名需要每年续费。

## 使用说明

博客关联在团队 github 仓库下，成员 github 账号将被邀请到团队博客仓库的协作者中，以获得博客修改权限。

### 部署

```shell
# 克隆 master 分支到本地，重命名为 blog 
git clone -b master https://github.com/500-Team/500-Team.github.io.git blog
# npm 安装组件
npm install
# 测试部署效果
hexo s
```

### 发布文章

```shell
# 新建文章文件
hexo new "文章名"

# 编辑文章文件，由于协同问题尽量不要修改其他人文章，在两人同时修改同一份文件的情况下会出现冲突
# 可以在 md 文件头部 tag: 下一行增加 author: xxx 来标注文章作者
vim ./source/_post/文章名.md (或者使用 markdown 编辑器写)

# 生成文章发布内容 (可以生成前先用 hexo s 在本地预览)
hexo g 

# 同步提交 (!!!注意!!! 执行脚本时，工作目录处于blog根目录下，也就是包含source、_config.yml等文件的位置)
./tools/syn 
```

出现 `[Done] already to publish.` 即完成同步和推送。完成后访问 `500team.cn` 即可看到文章，由于 CDN 的缓存机制，可能会有一分钟内的延迟。

### 删除文章 (尽可能不用)

删除文章时因为无法确定是未同步还是删除，所以需要删除文章时需要在删除 master 分支和 .deploy_git 文件夹(gh-pages分支)内容后，手动 `pull`、`add`、`commit`、`push`，需要注意在 `pull` 和 `push` 时分别指定对应分支。

```shell
首先删除 blog/source 下和 blog/.deploy_git 下的内容

# master branch
git pull origin master
git add .
git commit -m "delete ..."
git push origin master

# gh-pages branch
git pull origin gh-pages
git add .
git commit -m "delete ..."
git push origin gh-pages
```

### RSS 订阅

订阅链接为 `https://500team.cn/atom.xml`，类型 `atom`，mac 推荐的 rss 阅读器 `Reeder`。

## TODO

+ 优化向文章中插入图片的方法
+ 文章评论功能
