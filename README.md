# 🧩 LNMP 一键安装脚本

**Linux · Nginx · MySQL/MariaDB · PHP · 内核调优**

![License](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2F13%20%7C%20Ubuntu%2022--25-green.svg)
![Build](https://img.shields.io/badge/Installer-一键安装-orange.svg)

> 可控 · 可编译 · 可维护  
> 本脚本支持一键编译安装 **Nginx + PHP + MySQL/MariaDB**，可选 Redis / Memcached / Node.js / Pure-FTPD / phpMyAdmin，并自动完成 BBR/FQ、THP、sysctl 等优化。

---

# 📑 目录

- [0. 概述](#0-概述)  
  - [0.1 核心特性](#01-核心特性)  
  - [0.2 目录结构](#02-目录结构)
- [1. 安装方法](#1-安装方法)
  - [1.1 获取脚本](#11-获取脚本)
  - [1.2 交互式安装](#12-交互式安装)
- [2. 常用命令](#2-常用命令)
- [3. SSH 密钥登录一键配置](#3-ssh-密钥登录一键配置)
- [4. 源码下载失败与离线安装](#4-源码下载失败与离线安装)
- [5. 闭源 Loader 使用说明](#5-闭源-loader-使用说明)
- [6. 开源协议](#6-开源协议)

---

# 0. 概述

本脚本适用于：

- **Debian 12 / 13**
- **Ubuntu 22 / 23 / 24 / 25**

提供完整的 LNMP 自动编译安装及系统调优：

- 源码编译 **Nginx（含 HTTP/3-QUIC、WebDAV、Brotli、stream）**
- 源码编译 **PHP 7.4–8.5**（含扩展预置框架）
- 源码编译 **MySQL 5.7–8.2 或 MariaDB 10.6–10.11**
- 提供 Redis、Memcached、Node.js、Pure-FTPD、phpMyAdmin（可选）
- 启用 BBR/FQ、关闭 THP、sysctl 优化
- 统一目录结构 `/usr/local/*` + `/data/wwwroot/*`

---

# 0.1 核心特性

- **Nginx 最新稳定版 + OpenSSL（开启 QUIC）**
- **PHP 7.4–8.5 全版本源码编译**
- **MySQL/MariaDB 二选一，自动初始化数据目录**
- **PHP 扩展编译框架预置（redis、imagick、apcu、swoole、yaf 等）**
- 下载失败自动提示人工补齐
- 闭源 Loader（ionCube / ZendGuardLoader / SourceGuardian）仅占位提醒
- 所有组件均由 **systemd** 管理
- 目录与日志统一规范
- 自动化安全配置（禁用危险函数、限制目录、fastcgi 安全规则）

---

# 0.2 目录结构

```text
/usr/local/nginx/
  └── conf/
      ├── nginx.conf
      ├── vhost/
      ├── rewrite/
      └── ssl/

 /usr/local/phpX.Y/
   ├── bin/php
   ├── sbin/php-fpm
   ├── etc/

 /usr/local/mysql/
 /usr/local/mariadb/

 /usr/local/redis/
 /usr/local/memcached/
 /usr/local/pureftpd/

 /usr/local/src/               # 源码下载/编译目录

 /data/wwwroot/
   └── default/
 /data/wwwlogs/
 /data/mysql/
 /data/redis/
```

---

# 1. 安装方法

## 1.1 获取脚本

```bash
apt update -y
apt install -y curl

curl -fL https://example.com/lnmp.sh -o lnmp.sh
chmod +x lnmp.sh
```

说明：  
脚本建议在全新系统执行；如系统已有自编译的 Nginx/PHP/MySQL，请务必备份配置与数据。

---

## 1.2 交互式安装

```bash
bash lnmp.sh
```

交互内容包括：

- 国内源 / 官方源选择
- Swap 检查（低内存自动提示创建）
- 安装编译依赖（build-essential 等）
- 选择安装组件（Nginx / PHP / MySQL / MariaDB / Redis / Memcached 等）
- 编译参数自动处理
- 自动生成 systemd 启动服务
- 自动生成 php.ini、nginx.conf、my.cnf
- 自动写入 BBR/FQ、THP 关闭、sysctl 优化

---

# 2. 常用命令

下列命令均统一通过：

```bash
bash lnmp.sh <command>
```

| 功能说明 | 命令 |
|---------|------|
| 安装（重新进入交互） | `bash lnmp.sh install` |
| 查看所有服务状态 | `bash lnmp.sh status` |
| 重启所有 LNMP 服务 | `bash lnmp.sh restart` |
| 创建虚拟主机 | `bash lnmp.sh vhost` |
| 设置默认站点 | `bash lnmp.sh default` |
| SSH 密钥登录配置 | `bash lnmp.sh sshkey` |
| 系统调优工具 | `bash lnmp.sh tool` |
| 卸载 LNMP | `bash lnmp.sh remove` |

---

# 3. SSH 密钥登录一键配置

执行：

```bash
bash lnmp.sh sshkey
```

脚本将自动完成：

- 生成 ED25519 私钥与公钥  
- 写入 `/root/.ssh/authorized_keys`  
- 自动设置权限  
- 自动关闭密码登录  
- 自动重启 SSH 服务  

生成的密钥文件：

```
/root/.ssh/lnmp_ed25519
/root/.ssh/lnmp_ed25519.pub
```

可直接下载至本地使用。

---

# 4. 源码下载失败与离线安装

由于官方源不可用、网络限制、GitHub 限速等情况，脚本支持 **下载失败自动记录** 和 **离线安装**。

## 4.1 主组件下载失败记录

失败记录文件：

```
/tmp/lnmp_download_failed.txt
```

处理方式：

1. 在有网络的环境手动下载相应包  
2. 上传到服务器目录：  

```
/usr/local/src/
```

3. 再次执行脚本：

```
bash lnmp.sh
```

脚本会检测到文件已存在，不会重复下载，直接进入编译流程。

---

## 4.2 PHP 扩展下载失败记录

扩展失败记录：

```
/tmp/php_ext_download_failed.txt
```

处理方式同上：  
下载扩展 → 上传到 `/usr/local/src/php-ext/` → 重新执行脚本。

---

# 5. 闭源 Loader 使用说明

以下 Loader 均不会自动下载（因涉及商业版权）：

- **ZendGuardLoader**
- **ionCube Loader**
- **SourceGuardian Loader**

脚本会提示：

- 需要手动下载  
- 需要对应 PHP 版本  
- 需要放在正确目录  

放置目录：

```
/usr/local/phpX.Y/lib/php/extensions/
```

启用方式（php.ini 中加入）：

```
zend_extension=/usr/local/phpX.Y/lib/php/extensions/loader.so
```

脚本执行时会准确提示对应 PHP 版本的路径。

---

# 6. 开源协议

本项目遵循：

**GNU General Public License v3.0**

你可以自由：

- 使用  
- 修改  
- 商用  
- 二次发布  

但需保持 GPLv3 协议要求，例如保持开放源码条款等。

---

# 🎉 安装完成后的建议操作

```bash
bash lnmp.sh default
bash lnmp.sh vhost
bash lnmp.sh restart
```

分别用于：

- 设置默认站点  
- 创建新站点  
- 重启所有服务便于生效  

---
---

# 🔧 Nginx 配置说明（内置模板）

脚本会自动生成以下目录及模板文件：

```
/usr/local/nginx/conf/nginx.conf
/usr/local/nginx/conf/vhost/
├── default.conf
/usr/local/nginx/conf/rewrite/
```

主要特性：

- 启用 HTTP/2、HTTP/3（QUIC）
- 启用 Gzip + Brotli（可选）
- FastCGI 规则自动配置
- 默认站点 `/data/wwwroot/default`
- 默认日志 `/data/wwwlogs/default_access.log`

## Nginx 默认 server 示例

```nginx
server {
    listen 80;
    listen 443 ssl http2;
    server_name _;

    root /data/wwwroot/default;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm.sock;
        include fastcgi.conf;
    }

    access_log /data/wwwlogs/default_access.log;
}
```

你可以通过指令创建站点：

```bash
bash lnmp.sh vhost
```

---

# 🔧 PHP 配置说明

脚本自动生成：

```
/usr/local/phpX.Y/etc/php.ini
/usr/local/phpX.Y/etc/php-fpm.conf
/usr/local/phpX.Y/etc/php-fpm.d/www.conf
```

主要特性：

- 自动启用 OPcache  
- 自动启用禁用函数列表  
- 自动开启常用扩展  
- 日志路径自动写入 `/data/wwwlogs/`

PHP-FPM 监听路径：

```
/run/php-fpm.sock
```

---

# 🔧 MySQL / MariaDB 配置说明

脚本会自动生成：

```
/etc/my.cnf
/data/mysql/   # 数据目录
/usr/local/mysql/ 或 /usr/local/mariadb/
```

并自动执行：

- 初始化数据库  
- 设置 root 本地密码  
- 写入 systemd  
- 字符集默认 utf8mb4  
- 优化缓冲区/连接数

---

# 🔧 Redis / Memcached / Pure-FTPD

如在安装中选择：

- Redis 将安装至 `/usr/local/redis/`，数据目录 `/data/redis/`
- Memcached 安装至 `/usr/local/memcached/`
- Pure-FTPD 源码编译安装至 `/usr/local/pureftpd/`

均具有自动生成 systemd 服务与配置。

---

# 🧩 Node.js 管理方式

Node.js 使用 APT 安装，自动配置适配版本：

```
apt install -y nodejs npm
```

如需使用 nvm，可手动安装，不冲突。

---

# 📁 最终目录树参考

```text
/usr/local/
  ├── nginx/
  ├── php7.4/
  ├── php8.0/
  ├── php8.1/
  ├── php8.2/
  ├── mysql/
  ├── mariadb/
  ├── redis/
  ├── memcached/
  └── pureftpd/

 /usr/local/src/           # 所有源码下载位置
 /data/wwwroot/            # 网站目录
 /data/wwwlogs/            # 日志目录
 /data/mysql/              # MySQL 数据
 /data/redis/              # Redis 数据
```

---

# 🧾 更新日志（可自行增减）

```
v1.0
- 支持 Debian 12/13、Ubuntu 22–25
- 全组件源码编译
- PHP 常用扩展框架
- Nginx HTTP/3 + Brotli
- MySQL/MariaDB 二选一
- 新增 sshkey 一键配置
- 新增 offline 失败记录机制
```

---

# 📌 维护与贡献

欢迎提交 PR、Issue，或提出新功能建议。  
如需商业定制，可与作者联系。

---

# 🎉 感谢使用 LNMP Installer

如需添加：

- 一键 HTTPS/SSL（Let's Encrypt）  
- 完整 Web 管理面板  
- 更多数据库（PostgreSQL 等）  
- Docker 版本

请随时提出需求！


