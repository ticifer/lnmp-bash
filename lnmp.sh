#!/bin/bash

###########################################
# LNMP Installer — Module 1
# 初始化、系统检测、APT 源切换、
# Docker 源切换、代理配置（HTTP/SOCKS5）
###########################################

# 全局变量
SCRIPT_VER="2025.02"
BASE_DIR="/usr/local/src"
ENABLE_PROXY=0
PROXY_URL=""
SET_PROXY_TYPE=""

# 颜色函数
red(){ echo -e "\e[31m$1\e[0m"; }
green(){ echo -e "\e[32m$1\e[0m"; }
yellow(){ echo -e "\e[33m$1\e[0m"; }
blue(){ echo -e "\e[34m$1\e[0m"; }
white(){ echo -e "\e[97m$1\e[0m"; }

# 日志函数
log_info(){ white "[INFO] $1"; }
log_notice(){ green "[NOTICE] $1"; }
log_warn(){ blue "[WARN] $1"; }
log_error(){ red "[ERROR] $1"; }


###############################################
# 启动模块 1：系统检测 + 代理 + 源切换 + Docker 源 + 基础依赖
###############################################
run_module1() {
    log_info "系统检测完成：$(detect_os 2>/dev/null || echo unknown)"

    # 代理选择（可选）
    if declare -F setup_proxy >/dev/null 2>&1; then
        setup_proxy
    fi

    # APT 源切换（可选）
    if declare -F switch_apt_source >/dev/null 2>&1; then
        switch_apt_source
    fi

    # 基础依赖（必须：后续编译/安装依赖）
    if declare -F install_build_deps >/dev/null 2>&1; then
        install_build_deps
    fi

    # Docker 源切换 / Compose 处理（可选）
    if declare -F switch_docker_source >/dev/null 2>&1; then
        switch_docker_source
    fi

    # Shell 历史增强（可选）
    if declare -F apply_shell_enhance >/dev/null 2>&1; then
        apply_shell_enhance
    fi

    return 0
}

###############################################
# 组件检测函数：已安装则可选择跳过模块
###############################################
is_nginx_installed() {
    # 主路径：/usr/local/nginx/sbin/nginx
    if [[ -x "/usr/local/nginx/sbin/nginx" ]]; then
        return 0
    fi
    # 如果后面你改了 NGINX_INSTALL_DIR，这里可以再扩展
    return 1
}

is_php_installed() {
    # 依赖于 select_php_version 设置好的 PHP_INSTALL_DIR
    if [[ -n "${PHP_INSTALL_DIR:-}" && -x "${PHP_INSTALL_DIR}/bin/php" ]]; then
        return 0
    fi
    return 1
}

is_mysql_installed() {
    # MySQL 源码安装默认：/usr/local/mysql
    if [[ -x "/usr/local/mysql/bin/mysqld" ]]; then
        return 0
    fi
    return 1
}

is_mariadb_installed() {
    if [[ -x "/usr/local/mariadb/bin/mysqld" ]]; then
        return 0
    fi
    return 1
}

detect_docker() {
    if command -v docker >/dev/null 2>&1; then
        DOCKER_INSTALLED=1
        DOCKER_VERSION_STR="$(docker --version 2>/dev/null | head -n1)"
    else
        DOCKER_INSTALLED=0
        DOCKER_VERSION_STR=""
    fi

    # compose 两种形态：docker compose 插件 / docker-compose 二进制
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_MODE="plugin"
        COMPOSE_VERSION_STR="$(docker compose version 2>/dev/null | head -n1)"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_MODE="binary"
        COMPOSE_VERSION_STR="$(docker-compose --version 2>/dev/null | head -n1)"
    else
        COMPOSE_MODE="none"
        COMPOSE_VERSION_STR=""
    fi
}

###############################################
# 系统检测
###############################################
detect_os(){
    # 先通过 /etc/lsb-release 识别 Ubuntu
    if [[ -f /etc/lsb-release ]] && grep -q "DISTRIB_ID=Ubuntu" /etc/lsb-release; then
        OS="ubuntu"
        VER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2)

    # 再兜底识别 Debian
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        # Debian 12/13 正常是类似 12.x / 13.x
        VER=$(cut -d'.' -f1 /etc/debian_version)

    else
        log_error "不支持当前系统，脚本仅支持 Debian 12/13 与 Ubuntu 22-25"
        exit 1
    fi

    log_info "系统检测完成：$OS $VER"
}

###############################################
# APT 源配置
###############################################
switch_apt_source(){
    echo
    yellow "请选择 APT 软件源："
    echo "1) 阿里"
    echo "2) 清华"
    echo "3) 腾讯"
    echo "4) 中科大"
    echo "5) 官方源（自动）"
    read -r -p "请输入数字 1-5: " APT_CHOICE

    case "$APT_CHOICE" in
        1) MIRROR="mirrors.aliyun.com";;
        2) MIRROR="mirrors.tuna.tsinghua.edu.cn";;
        3) MIRROR="mirrors.cloud.tencent.com";;
        4) MIRROR="mirrors.ustc.edu.cn";;
        5) MIRROR="official";;
        *) MIRROR="official";;
    esac

    log_info "已选择 APT 源：$MIRROR"

    if [[ "$MIRROR" == "official" ]]; then
        log_info "使用系统默认官方源，不修改 sources.list"
        apt update
        return
    fi

    cp /etc/apt/sources.list /etc/apt/sources.list.bak

    if [[ "$OS" == "ubuntu" ]]; then
        # 不依赖 lsb_release，直接从 /etc/os-release 取 codename
        UB_VER="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
        cat >/etc/apt/sources.list <<EOF
deb http://${MIRROR}/ubuntu/ ${UB_VER} main restricted universe multiverse
deb http://${MIRROR}/ubuntu/ ${UB_VER}-updates main restricted universe multiverse
deb http://${MIRROR}/ubuntu/ ${UB_VER}-backports main restricted universe multiverse
deb http://${MIRROR}/ubuntu/ ${UB_VER}-security main restricted universe multiverse
EOF

    elif [[ "$OS" == "debian" ]]; then
        if [[ "$VER" == "12" ]]; then DEB_CODENAME="bookworm"; fi
        if [[ "$VER" == "13" ]]; then DEB_CODENAME="trixie"; fi

        cat >/etc/apt/sources.list <<EOF
deb http://${MIRROR}/debian/ ${DEB_CODENAME} main contrib non-free non-free-firmware
deb http://${MIRROR}/debian/ ${DEB_CODENAME}-updates main contrib non-free non-free-firmware
deb http://${MIRROR}/debian/ ${DEB_CODENAME}-backports main contrib non-free non-free-firmware
deb http://${MIRROR}/debian-security/ ${DEB_CODENAME}-security main contrib non-free non-free-firmware
EOF
    fi

    log_info "APT 源已切换到：$MIRROR"
    apt update
}

###############################################
# 统一安装 LNMP 所需编译 / 运行依赖
# 覆盖模块 2–7 的实际依赖
###############################################
install_build_deps(){
    log_info "开始安装 LNMP 所需基础依赖（模块 2–7）"

    # 公共基础依赖（所有模块通用）
    # - 编译工具链 / 常用工具 / 证书 / git 等
    local COMMON_DEPS=(
        build-essential
        gcc
        g++
        make
        automake
        autoconf
        libtool
        pkg-config
        cmake
        curl
        wget
        git
        ca-certificates
        unzip
        zip
        tar
        xz-utils
        software-properties-common
        gnupg
        lsb-release
        bzip2
        lbzip2
    )

    # Nginx + OpenSSL + Brotli + 相关模块（模块 3）
    # - PCRE / Zlib / OpenSSL（dev）
    local NGINX_DEPS=(
        libpcre3-dev
        zlib1g-dev
        libssl-dev
    )

    # PHP 编译依赖（模块 4）
    # - GD / mbstring / intl / LDAP / ZIP / ICU / SQLite / PostgreSQL / Imagick / IMAP 等
    local PHP_DEPS=(
        libxml2-dev
        libsqlite3-dev
        libonig-dev
        libcurl4-openssl-dev
        libjpeg-dev
        libpng-dev
        libwebp-dev
        libfreetype-dev
        libzip-dev
        libicu-dev
        libldap2-dev
        libxslt1-dev
        libpq-dev
        libargon2-dev
        libsodium-dev
        imagemagick
        libmagickwand-dev
        libc-client2007e-dev
        libkrb5-dev
        libmemcached-dev
        libmemcached-tools
    )

    # MySQL / MariaDB 源码依赖（模块 5）
    # - ncurses / readline / aio / bison 等
    local DB_DEPS=(
        libncurses-dev
        libaio-dev
        bison
        libreadline-dev
        libtirpc-dev
    )

    # Redis / Memcached / Pure-FTPD / Node.js / phpMyAdmin（模块 6）
    # - Redis：tcl（测试用）
    # - Memcached：libevent / SASL
    # - Pure-FTPD：OpenSSL 已包含在 NGINX_DEPS 中（libssl-dev）
    local EXTRA_DEPS=(
        tcl
        libevent-dev
        libsasl2-dev
        net-tools
        htop
    )

    # 将上述所有包合并并去重
    local ALL_PKGS=()
    local seen
    for pkg in "${COMMON_DEPS[@]}" "${NGINX_DEPS[@]}" "${PHP_DEPS[@]}" "${DB_DEPS[@]}" "${EXTRA_DEPS[@]}"; do
        seen=0
        for p2 in "${ALL_PKGS[@]}"; do
            if [[ "$p2" == "$pkg" ]]; then
                seen=1
                break
            fi
        done
        if [[ $seen -eq 0 ]]; then
            ALL_PKGS+=("$pkg")
        fi
    done

    # 检查哪些包已安装，只安装缺失的
    local TO_INSTALL=()
    for pkg in "${ALL_PKGS[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            log_info "依赖已安装：$pkg"
        else
            TO_INSTALL+=("$pkg")
        fi
    done

    if (( ${#TO_INSTALL[@]} == 0 )); then
        log_info "所有必需依赖已安装，无需额外安装。"
        return
    fi

    log_info "准备安装以下缺失依赖包："
    echo "  ${TO_INSTALL[*]}"

    if ! apt install -y "${TO_INSTALL[@]}"; then
        log_error "部分依赖安装失败，请检查网络、APT 源或代理设置后重试。"
    else
        log_info "依赖安装完成。"
    fi
}

###############################################
# Docker 源切换 & 加速器
###############################################
switch_docker_source() {
    detect_docker

    if [[ "${DOCKER_INSTALLED:-0}" -eq 1 ]]; then
        log_notice "检测到 Docker 已安装：${DOCKER_VERSION_STR}"
        if [[ "${COMPOSE_MODE:-none}" != "none" ]]; then
            log_notice "检测到 Compose 已安装（${COMPOSE_MODE}）：${COMPOSE_VERSION_STR}"
        else
            log_notice "检测到 Docker 已安装，但 Compose 未安装。"
        fi

        echo
        echo "Docker 已存在，请选择："
        echo "  1) 跳过（推荐）"
        echo "  2) 安装/修复 Docker Compose（不重装 Docker）"
        echo "  3) 重装 Docker + Compose（危险：可能影响现有容器/配置）"
        read -r -p "请输入 1-3（默认 1）: " ans
        ans="${ans:-1}"

        case "$ans" in
            1) log_info "跳过 Docker/Compose 安装步骤。"; return 0;;
            2) INSTALL_MODE="compose_only";;
            3) INSTALL_MODE="reinstall";;
            *) log_info "输入无效，默认跳过。"; return 0;;
        esac
    else
        echo
        echo "未检测到 Docker，是否安装 Docker 与 Docker Compose？"
        echo "  1) 安装"
        echo "  2) 不安装"
        read -r -p "输入 1 或 2（默认 1）: " ans
        ans="${ans:-1}"
        if [[ "$ans" != "1" ]]; then
            log_info "用户选择不安装 Docker/Compose。"
            return 0
        fi
        INSTALL_MODE="install"
    fi

    echo
    yellow "请选择 Docker 官方源或国内镜像："
    echo "1) 阿里"
    echo "2) 清华"
    echo "3) 腾讯"
    echo "4) 官方"
    read -r -p "输入 1-4: " DKSRC

    case "$DKSRC" in
        1) D_SOURCE="https://mirrors.aliyun.com/docker-ce/linux";;
        2) D_SOURCE="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux";;
        3) D_SOURCE="https://mirrors.cloud.tencent.com/docker-ce/linux";;
        4) D_SOURCE="https://download.docker.com/linux";;
        *) D_SOURCE="https://download.docker.com/linux";;
    esac
    log_info "Docker APT 源：$D_SOURCE"

    local DOCKER_OS_ID=""
    if [[ -f /etc/os-release ]]; then
        DOCKER_OS_ID="$(. /etc/os-release && echo "${ID}")"
    fi
    case "$DOCKER_OS_ID" in
        ubuntu|debian) : ;;
        *)
            # 兜底：基于 lsb_release
            if command -v lsb_release >/dev/null 2>&1; then
                local dist
                dist="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
                if [[ "$dist" == "ubuntu" ]]; then
                    DOCKER_OS_ID="ubuntu"
                elif [[ "$dist" == "debian" ]]; then
                    DOCKER_OS_ID="debian"
                else
                    # 再兜底一次：你脚本面向 Debian/Ubuntu，默认 ubuntu
                    DOCKER_OS_ID="ubuntu"
                fi
            else
                DOCKER_OS_ID="ubuntu"
            fi
        ;;
    esac

    # 2) codename（Ubuntu: noble/jammy；Debian: bookworm/bullseye）
    local UB_VER=""
    if [[ -f /etc/os-release ]]; then
        UB_VER="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
    fi
    if [[ -z "$UB_VER" ]]; then
        UB_VER="$(lsb_release -cs 2>/dev/null || true)"
    fi
    if [[ -z "$UB_VER" ]]; then
        log_error "无法识别系统 codename（lsb_release 与 /etc/os-release 均失败）"
        return 0 
    fi

    local REPO_BASE="${D_SOURCE%/}"
    if [[ "$REPO_BASE" == "https://download.docker.com/linux" ]]; then
        REPO_BASE="${REPO_BASE}/${DOCKER_OS_ID}"
    elif [[ "$REPO_BASE" == *"/docker-ce/linux" ]]; then
        REPO_BASE="${REPO_BASE}/${DOCKER_OS_ID}"
    else
        :
    fi
    log_info "Docker Repo Base：${REPO_BASE}"
    log_info "Docker Codename：${UB_VER}"

    apt update
    apt install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg

    if ! curl -fsSL "${REPO_BASE}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "Docker GPG Key 下载失败：${REPO_BASE}/gpg"
        return 0
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg

    if [[ "$INSTALL_MODE" == "reinstall" ]]; then
        log_notice "重装模式：移除可能冲突的旧包..."
        apt remove -y docker docker-engine docker.io containerd runc docker-compose docker-compose-v2 docker-doc podman-docker || true
    fi

    # 6) 写入 docker.list（signed-by 指向 /etc/apt/keyrings/docker.gpg）
    cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${REPO_BASE} ${UB_VER} stable
EOF

    if ! apt update; then
        log_error "Docker APT 源更新失败：${REPO_BASE} ${UB_VER}（网络/代理/源不可用）"
        return 0
    fi

    # 7) compose_only：只装插件
    if [[ "$INSTALL_MODE" == "compose_only" ]]; then
        log_info "仅安装/修复 docker compose 插件..."
        apt install -y docker-compose-plugin || true
        return 0
    fi

    # 8) 安装 Docker CE
    log_info "安装/重装 Docker CE..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true

    # 尽量启动（失败也不阻断）
    systemctl enable --now docker >/dev/null 2>&1 || true

    echo
    yellow "是否配置 Docker 国内镜像加速器？"
    echo "1) 是"
    echo "2) 否"
    read -r -p "选择 1 或 2: " MIRROR_CHOICE

    if [[ "$MIRROR_CHOICE" == "1" ]]; then
        mkdir -p /etc/docker
        cat >/etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://registry.docker-cn.com"
  ]
}
EOF
        systemctl restart docker >/dev/null 2>&1 || true
        log_info "Docker 镜像加速器配置完成"
    fi
}

###############################################
# 代理设置（支持 HTTP / SOCKS5）
###############################################
setup_proxy(){
    echo
    yellow "是否启用代理（解决下载失败）？"
    echo "1) 不启用"
    echo "2) 启用 HTTP 代理（http://host:port）"
    echo "3) 启用 SOCKS5 代理（socks5://host:port）"
    read -p "选择 1-3: " PXY

    case "$PXY" in
        2) SET_PROXY_TYPE="http";;
        3) SET_PROXY_TYPE="socks";;
        *) ENABLE_PROXY=0; return;;
    esac

    read -p "请输入代理地址（格式：host:port）: " PROXY_ADDR
    ENABLE_PROXY=1

    if [[ "$SET_PROXY_TYPE" == "http" ]]; then
        PROXY_URL="http://${PROXY_ADDR}"
    else
        PROXY_URL="socks5://${PROXY_ADDR}"
    fi

    log_info "代理已启用：$PROXY_URL"

    export ALL_PROXY="$PROXY_URL"
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"

    git config --global http.proxy "$PROXY_URL"
    git config --global https.proxy "$PROXY_URL"

    cat >/etc/profile.d/lnmp-proxy.sh <<EOF
export ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
EOF
}

###############################################
# 清理代理
###############################################
cleanup_proxy(){
    if [[ "$ENABLE_PROXY" != "1" ]]; then
        return
    fi

    log_info "正在清理代理设置"

    unset ALL_PROXY
    unset http_proxy
    unset https_proxy

    git config --global --unset http.proxy
    git config --global --unset https.proxy

    rm -f /etc/profile.d/lnmp-proxy.sh

    log_info "代理已清除"
}

###############################################
# Shell 增强：history + 系统高亮（写入 /etc/profile.d/）
###############################################
apply_shell_enhance() {
    cat >/etc/profile.d/history.sh <<'EOF'
# ====== history & prompt enhance ======

# 颜色高亮
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# history 条数
export HISTSIZE=1000000

# 取得登录客户端 IP（无则用 hostname）
USER_IP=$(who -u am i 2>/dev/null | awk '{print $NF}' | sed -e 's/[()]//g')
if [ -z "$USER_IP" ]; then
  USER_IP=$(hostname)
fi

# history 时间格式（带 IP + 用户）
export HISTTIMEFORMAT="%F %T ${USER_IP}:$(whoami) "

# 合并 PROMPT_COMMAND：实时写入 + syslog 记录最后一条命令
__lnmp_log_history_cmd() {
  local msg
  msg=$(history 1 | { read -r x y; echo "$y"; })
  logger "[euid=$(whoami)] $(who am i 2>/dev/null) [$(pwd)] ${msg}"
}
export PROMPT_COMMAND='history -a; __lnmp_log_history_cmd'
EOF

    chmod 644 /etc/profile.d/history.sh
    log_info "Shell 增强已写入 /etc/profile.d/history.sh（新会话生效）"
}

###########################################
# LNMP Installer — Module 2
# 用户 / 目录创建、Swap、内核优化、
# BBR、THP、sysctl、limits
###########################################

###############################################
# 创建 www 用户
###############################################
create_www_user(){
    if ! id www >/dev/null 2>&1; then
        log_info "创建 www 用户"
        useradd -M -s /usr/sbin/nologin www
    else
        log_info "www 用户已存在"
    fi
}

###############################################
# 创建目录结构
###############################################
create_directories(){
    log_info "创建目录结构"

    mkdir -p /data/wwwroot/default
    mkdir -p /data/wwwlogs
    mkdir -p /data/mysql
    mkdir -p /data/redis

    mkdir -p /usr/local/src
    mkdir -p /usr/local/nginx/conf/{vhost,rewrite,ssl}

    chown -R www:www /data/wwwroot /data/wwwlogs
    if ! id redis >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin redis >/dev/null 2>&1 || true
    fi
    chown -R www:www /data/redis
    chmod 750 /data/redis
    chown -R mysql:mysql /data/mysql >/dev/null 2>&1 || true
}

###############################################
# Swap 检测与创建提示
###############################################
check_swap(){
    MEM=$(free -m | awk '/Mem:/ {print $2}')
    SWAP=$(free -m | awk '/Swap:/ {print $2}')

    if [[ $MEM -lt 2000 && $SWAP -lt 1 ]]; then
        yellow "检测到内存较小（${MEM}MB），当前无 SWAP"
        yellow "是否创建 2GB Swap？"
        echo "1) 创建"
        echo "2) 不创建"
        read -p "选择 1 或 2: " SW_CH

        if [[ "$SW_CH" == "1" ]]; then
            log_info "创建 2GB swap 文件"
            dd if=/dev/zero of=/swapfile bs=1M count=2048
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
            green "Swap 创建完成"
        else
            yellow "已跳过 Swap 创建"
        fi
    fi
}

###############################################
# limits.conf 优化
###############################################
optimize_limits(){
    log_info "优化 limits.conf"

    cat >/etc/security/limits.d/99-lnmp.conf <<EOF
* soft nofile 51200
* hard nofile 51200
* soft nproc 65535
* hard nproc 65535
EOF
}

###############################################
# sysctl 优化（启用 BBR + FQ）
###############################################
optimize_sysctl(){
    log_info "配置 sysctl 系统优化 + 启用 BBR/FQ"

    cat >/etc/sysctl.d/99-lnmp.conf <<EOF
fs.file-max = 51200
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1

net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
EOF

    sysctl --system
}

###############################################
# 禁用 THP（Transparent Huge Pages）
###############################################
disable_thp(){
    log_info "禁用透明大页（THP）"

    mkdir -p /etc/systemd/system
    cat >/etc/systemd/system/disable-thp.service <<EOF
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF

    systemctl daemon-reload
    systemctl enable disable-thp
    systemctl start disable-thp
}

###############################################
# 启动模块 2
###############################################
###############################################
# run_module2(): 模块 2 顶层执行段封装（修复：避免脚本加载时直接运行）
###############################################
run_module2() {
log_info "开始执行模块 2：目录/用户/SWAP/内核优化"

create_www_user
create_directories
check_swap
optimize_limits
optimize_sysctl
disable_thp

log_info "执行Nginx+QUIC安装"

###########################################
# LNMP Installer — Module 3
# Nginx + OpenSSL 最新稳定版（含 QUIC）
# Brotli、WebDAV、nginx.conf 模板、systemd
###########################################

NGINX_VERSION=""   # 自动检测稳定版
OPENSSL_URL="https://www.openssl.org/source"
NGINX_SRC_DIR="${BASE_DIR}"
OPENSSL_SRC_DIR="${BASE_DIR}/openssl"
NGINX_INSTALL_DIR="/usr/local/nginx"

# PCRE2 相关变量（自动检测最新版）
PCRE2_VERSION=""
PCRE2_TAR=""
PCRE2_URL=""

###############################################
# 下载源码，带代理自动继承能力
###############################################
download_source(){
    local URL="$1"
    local OUT="$2"

    # 已存在就先做校验，防止上一次下到 HTML/错误页
    if [[ -f "$OUT" ]]; then
        case "$OUT" in
            *.tar.gz|*.tgz)
                if gzip -t "$OUT" >/dev/null 2>&1; then
                    log_info "$OUT 已存在且校验通过，跳过下载"
                    return
                else
                    log_notice "$OUT 已存在，但不是有效的 gzip 压缩包，删除后重新下载"
                    rm -f "$OUT"
                fi
                ;;
            *.tar.bz2|*.tbz|*.tbz2)
                if bzip2 -t "$OUT" >/dev/null 2>&1; then
                    log_info "$OUT 已存在且校验通过，跳过下载"
                    return
                else
                    log_notice "$OUT 已存在，但不是有效的 bzip2 压缩包，删除后重新下载"
                    rm -f "$OUT"
                fi
                ;;
            *)
                if [[ -s "$OUT" ]]; then
                    log_info "$OUT 已存在，跳过下载"
                    return
                else
                    log_notice "$OUT 文件大小为 0，删除后重新下载"
                    rm -f "$OUT"
                fi
                ;;
        esac
    fi

    log_info "下载：$URL -> $OUT"

    if ! curl -L --connect-timeout 30 -o "$OUT" "$URL"; then
        log_notice "下载失败：$URL"
        log_notice "请手动下载并放置到：$OUT"
        echo "$URL" >> /tmp/lnmp_download_failed.txt
    fi
}

###############################################
# 准备目录
###############################################
prepare_nginx_dir(){
    mkdir -p "$NGINX_SRC_DIR"
    cd "$NGINX_SRC_DIR"
}

###############################################
# 自动获取 Nginx 最新稳定版
###############################################
get_latest_nginx() {
    # 如果用户手动指定版本，则直接用
    if [[ -n "$NGINX_VERSION" ]]; then
        log_info "使用用户指定的 Nginx 版本：$NGINX_VERSION"
        return
    fi

    log_info "从官方获取 Nginx 稳定版版本号..."

    local html ver

    if ! html=$(curl -sk https://nginx.org/en/download.html); then
        log_notice "请求 nginx.org 失败，回退使用：1.28.0"
        NGINX_VERSION="1.28.0"
        return
    fi

    # 从 “Stable version” 区块开始，匹配第一个 nginx-x.y.z.tar.gz
    ver=$(printf "%s\n" "$html" | awk '
        /Stable version/ {stable=1}
        stable && match($0, /nginx-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz/, a) {
            print a[1]; exit
        }
    ')

    if [[ -z "$ver" ]]; then
        log_notice "无法自动解析 Nginx 稳定版，回退使用：1.28.0"
        NGINX_VERSION="1.28.0"
    else
        NGINX_VERSION="$ver"
        log_info "检测到 Nginx 稳定版：$NGINX_VERSION"
    fi
}

###############################################
# 获取最新 OpenSSL LTS 3.5.x（自动解析）
###############################################
OPENSSL_URL="https://www.openssl.org/source"

get_latest_openssl() {
    if [[ -n "$OPENSSL_VERSION" ]]; then
        log_info "使用用户指定的 OpenSSL 版本：$OPENSSL_VERSION"
        return
    fi

    log_info "获取 OpenSSL 3.5 LTS 最新版本..."

    local html file

    # 直接抓取下载页 HTML
    if ! html=$(curl -sk "${OPENSSL_URL}/"); then
        # 这一种情况是真正的网络/证书问题，保留 warn
        log_notice "请求 OpenSSL 下载页失败，回退为 openssl-3.5.4.tar.gz"
        file="openssl-3.5.4.tar.gz"
    else
        # 只匹配 3.5.x LTS 的 tar.gz，大小写都兼容
        file=$(printf "%s\n" "$html" | grep -Eio 'openssl-3\.5\.[0-9]+\.tar\.gz' | sort -V | tail -1)

        # 如果列表里没匹配到 3.5.x，就走默认版本，但不再视为告警
        if [[ -z "$file" ]]; then
            log_info "未在下载页解析到 OpenSSL 3.5 LTS 版本，使用默认 openssl-3.5.4.tar.gz"
            file="openssl-3.5.4.tar.gz"
        fi
    fi

    OPENSSL_TAR="$file"
    OPENSSL_VERSION="${file%.tar.gz}"

    log_info "OpenSSL LTS 版本：$OPENSSL_VERSION"

    # 仍然是从官方源下载到 /usr/local/src/
    download_source "${OPENSSL_URL}/${OPENSSL_TAR}" "${NGINX_SRC_DIR}/${OPENSSL_TAR}"
}

###############################################
# 获取最新 PCRE2 稳定版（从 GitHub）
###############################################
get_latest_pcre2() {
    if [[ -n "$PCRE2_VERSION" ]]; then
        log_info "使用用户指定的 PCRE2 版本：$PCRE2_VERSION"
        return
    fi

    log_info "从 GitHub Releases 获取 PCRE2 最新版本..."

    local html tag

    if ! html=$(curl -sk "https://github.com/PCRE2Project/pcre2/releases"); then
        log_notice "请求 PCRE2 Releases 失败，回退为：pcre2-10.47"
        PCRE2_VERSION="pcre2-10.47"
    else
        # 从类似 '/PCRE2Project/pcre2/tree/pcre2-10.47' 中提取 tag 名
        tag=$(printf "%s\n" "$html" \
                | grep -oE 'pcre2-10\.[0-9]+' \
                | sort -V \
                | tail -1)

        if [[ -z "$tag" ]]; then
            log_notice "无法解析 PCRE2 最新版本，回退为：pcre2-10.47"
            PCRE2_VERSION="pcre2-10.47"
        else
            PCRE2_VERSION="$tag"
        fi
    fi

    PCRE2_TAR="${PCRE2_VERSION}.tar.bz2"
    PCRE2_URL="https://github.com/PCRE2Project/pcre2/releases/download/${PCRE2_VERSION}/${PCRE2_TAR}"

    log_info "PCRE2 版本：${PCRE2_VERSION}"
    download_source "${PCRE2_URL}" "/usr/local/src/${PCRE2_TAR}"

    # 解压到 /usr/local/src/${PCRE2_VERSION}
    cd /usr/local/src
    if [[ ! -d "${PCRE2_VERSION}" ]]; then
        tar xf "${PCRE2_TAR}"
    fi
}

###############################################
# 下载 Nginx 及扩展模块
###############################################
download_nginx_modules(){

    # Brotli 模块
    if [[ ! -d "ngx_brotli" ]]; then
        git clone --recursive https://github.com/google/ngx_brotli.git || {
            log_notice "ngx_brotli 下载失败，请手动放入 ${NGINX_SRC_DIR}/ngx_brotli"
            echo "ngx_brotli" >> /tmp/lnmp_download_failed.txt
        }
    fi

    # headers-more 模块
    if [[ ! -d "headers-more-nginx-module" ]]; then
        git clone https://github.com/openresty/headers-more-nginx-module.git || {
            log_notice "headers-more 下载失败，请手动放入 ${NGINX_SRC_DIR}/headers-more-nginx-module"
            echo "headers-more-nginx-module" >> /tmp/lnmp_download_failed.txt
        }
    fi

    # substitutions filter 模块
    if [[ ! -d "ngx_http_substitutions_filter_module" ]]; then
        git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git || {
            log_notice "ngx_http_substitutions_filter_module 下载失败，请手动放入 ${NGINX_SRC_DIR}/ngx_http_substitutions_filter_module"
            echo "ngx_http_substitutions_filter_module" >> /tmp/lnmp_download_failed.txt
        }
    fi

    # cache purge 模块（目录名保留为 ngx_cache_purge-2.3）
    if [[ ! -d "ngx_cache_purge-2.3" ]]; then
        git clone https://github.com/FRiCKLE/ngx_cache_purge.git ngx_cache_purge-2.3 || {
            log_notice "ngx_cache_purge-2.3 下载失败，请手动放入 ${NGINX_SRC_DIR}/ngx_cache_purge-2.3"
            echo "ngx_cache_purge-2.3" >> /tmp/lnmp_download_failed.txt
        }
    fi

    # slowfs cache 模块
    if [[ ! -d "ngx_slowfs_cache-1.10" ]]; then
        git clone https://github.com/FRiCKLE/ngx_slowfs_cache.git ngx_slowfs_cache-1.10 || {
            log_notice "ngx_slowfs_cache-1.10 下载失败，请手动放入 ${NGINX_SRC_DIR}/ngx_slowfs_cache-1.10"
            echo "ngx_slowfs_cache-1.10" >> /tmp/lnmp_download_failed.txt
        }
    fi

    # fancyindex 模块
    if [[ ! -d "ngx-fancyindex" ]]; then
        git clone https://github.com/aperezdc/ngx-fancyindex.git || {
            log_notice "ngx-fancyindex 下载失败，请手动放入 ${NGINX_SRC_DIR}/ngx-fancyindex"
            echo "ngx-fancyindex" >> /tmp/lnmp_download_failed.txt
        }
    fi
}

###############################################
# 检查必须存在的模块 / 组件目录
###############################################
check_nginx_modules_exist(){
    local missing=()

    for d in \
        "ngx_brotli" \
        "headers-more-nginx-module" \
        "ngx_http_substitutions_filter_module" \
        "ngx_cache_purge-2.3" \
        "ngx_slowfs_cache-1.10" \
        "ngx-fancyindex"
    do
        if [[ ! -d "${NGINX_SRC_DIR}/${d}" ]]; then
            missing+=("${NGINX_SRC_DIR}/${d}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_error "以下 Nginx 模块目录缺失，请补充源码或调整脚本下载地址："
        for m in "${missing[@]}"; do
            log_error "  - $m"
        done
        log_error "模块目录补齐后请重新执行安装。"
        exit 1
    fi

    # 检查 PCRE2 源码目录（用于 --with-pcre=../${PCRE2_VERSION}）
    if [[ ! -d "${BASE_DIR}/${PCRE2_VERSION}" ]]; then
        log_error "PCRE2 源码目录缺失：${BASE_DIR}/${PCRE2_VERSION}"
        log_error "请确认 PCRE2 压缩包已正确下载并解压，或手动将源码放到该目录后重试。"
        exit 1
    fi
}


###############################################
# 解压源码
###############################################
extract_sources(){
    # 保证当前在 NGINX_SRC_DIR（即 /usr/local/src）
    prepare_nginx_dir  # 里面已经 mkdir -p 并 cd "$NGINX_SRC_DIR"

    # 1) Nginx
    if [[ ! -f "nginx-${NGINX_VERSION}.tar.gz" ]]; then
        log_error "未找到 Nginx 源码包：${NGINX_SRC_DIR}/nginx-${NGINX_VERSION}.tar.gz"
        exit 1
    fi
    if ! tar xf "nginx-${NGINX_VERSION}.tar.gz"; then
        log_error "解压 nginx-${NGINX_VERSION}.tar.gz 失败，文件可能损坏"
        log_error "建议先执行：rm -f ${NGINX_SRC_DIR}/nginx-${NGINX_VERSION}.tar.gz 后重跑脚本"
        exit 1
    fi

    # 2) OpenSSL
    if [[ -z "$OPENSSL_TAR" ]]; then
        log_error "OPENSSL_TAR 为空，请检查 get_latest_openssl()"
        exit 1
    fi
    if [[ ! -f "${OPENSSL_TAR}" ]]; then
        log_error "未找到 OpenSSL 源码包：${NGINX_SRC_DIR}/${OPENSSL_TAR}"
        exit 1
    fi
    if ! tar xf "${OPENSSL_TAR}"; then
        log_error "解压 ${OPENSSL_TAR} 失败，文件可能损坏"
        log_error "建议先执行：rm -f ${NGINX_SRC_DIR}/${OPENSSL_TAR} 后重跑脚本"
        exit 1
    fi

    # 3) PCRE2（放在 BASE_DIR = /usr/local/src）
    if [[ -n "$PCRE2_TAR" ]]; then
        if [[ ! -f "${BASE_DIR}/${PCRE2_TAR}" ]]; then
            log_error "未找到 PCRE2 源码包：${BASE_DIR}/${PCRE2_TAR}"
            exit 1
        fi
        if ! (cd "${BASE_DIR}" && tar xf "${PCRE2_TAR}"); then
            log_error "解压 ${PCRE2_TAR} 失败，文件可能损坏"
            log_error "建议先执行：rm -f ${BASE_DIR}/${PCRE2_TAR} 后重跑脚本"
            exit 1
        fi
    fi
}


###############################################
# 编译安装 Nginx（支持 QUIC）
###############################################
compile_nginx(){
    check_nginx_modules_exist

    cd "${NGINX_SRC_DIR}/nginx-${NGINX_VERSION}" || {
        log_error "找不到 Nginx 源码目录：${NGINX_SRC_DIR}/nginx-${NGINX_VERSION}"
        exit 1
    }

    # 确认 Nginx 源码目录中存在 ./configure
    if [[ ! -x ./configure ]]; then
        log_error "Nginx 源码目录中缺少 ./configure 脚本，请检查 nginx-${NGINX_VERSION} 解压是否完整"
        exit 1
    fi

    if ! ./configure \
        --prefix=${NGINX_INSTALL_DIR} \
        --user=www \
        --group=www \
        --with-debug \
        --with-cc-opt="-O2 -fstack-protector-strong -Wformat -Werror=format-security" \
        --with-ld-opt="-Wl,-rpath,/usr/local/lib" \
        --with-openssl=${NGINX_SRC_DIR}/${OPENSSL_VERSION} \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-http_gzip_static_module \
        --with-http_auth_request_module \
        --with-http_realip_module \
        --with-http_sub_module \
        --with-file-aio \
        --with-threads \
        --with-http_slice_module \
        --with-http_stub_status_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_addition_module \
        --with-http_dav_module \
        --with-pcre=${NGINX_SRC_DIR}/${PCRE2_VERSION} \
        --with-pcre-jit \
        --add-module=${NGINX_SRC_DIR}/ngx_http_substitutions_filter_module \
        --add-module=${NGINX_SRC_DIR}/ngx_cache_purge-2.3 \
        --add-module=${NGINX_SRC_DIR}/ngx_slowfs_cache-1.10 \
        --add-module=${NGINX_SRC_DIR}/ngx_brotli \
        --add-module=${NGINX_SRC_DIR}/ngx-fancyindex \
        --add-module=${NGINX_SRC_DIR}/headers-more-nginx-module
    then
        log_error "Nginx ./configure 失败"
        exit 1
    fi

    # 编译 Nginx
    if ! make -j"$(nproc)"; then
        log_error "Nginx make 编译失败，尝试执行 make clean 清理构建目录"
        # 不管 clean 成不成功，都不要让这里的失败盖掉前面真正的编译错误
        make clean >/dev/null 2>&1 || log_notice "make clean 执行失败，请手动检查源码目录"
        exit 1
    fi

    # 安装 Nginx
    if ! make install; then
        log_error "Nginx make install 安装失败，尝试执行 make clean 清理构建目录"
        make clean >/dev/null 2>&1 || log_notice "make clean 执行失败，请手动检查源码目录"
        exit 1
    fi

    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx

    log_info "Nginx 已成功安装到 ${NGINX_INSTALL_DIR}"
}

###############################################
# 创建 systemd 服务
###############################################
create_nginx_service(){
    cat >/etc/systemd/system/nginx.service <<EOF
[Unit]
Description=Nginx Web Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx
    systemctl start nginx
}

###############################################
# 生成 Nginx 主配置文件
###############################################
generate_nginx_conf(){

    mkdir -p /data/wwwroot/default

    cat >${NGINX_INSTALL_DIR}/conf/nginx.conf <<'EOF'
user  www www;
worker_processes auto;

error_log /data/wwwlogs/error_nginx.log crit;
pid /usr/local/nginx/logs/nginx.pid;
worker_rlimit_nofile 51200;

events {
    use epoll;
    worker_connections 51200;
    multi_accept on;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server_names_hash_bucket_size 128;
    client_header_buffer_size 32k;
    large_client_header_buffers 4 32k;
    client_max_body_size 1024m;
    client_body_buffer_size 10m;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 120;
    server_tokens off;

    fastcgi_connect_timeout 300;
    fastcgi_send_timeout 300;
    fastcgi_read_timeout 300;
    fastcgi_buffer_size 64k;
    fastcgi_buffers 4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 128k;
    fastcgi_intercept_errors on;

    gzip on;
    gzip_buffers 16 8k;
    gzip_comp_level 6;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        text/xml application/xml application/atom+xml application/rss+xml application/xhtml+xml image/svg+xml
        text/javascript application/javascript application/x-javascript
        text/x-json application/json application/x-web-app-manifest+json
        text/css text/plain text/x-component
        font/opentype application/x-font-ttf application/vnd.ms-fontobject
        image/x-icon;
    gzip_disable "MSIE [1-6]\.(?!.*SV1)";

    brotli on;
    brotli_min_length 20;
    brotli_buffers 16 10k;
    brotli_window 512k;
    brotli_comp_level 6;
    brotli_types
        text/xml application/xml application/atom+xml application/rss+xml application/xhtml+xml image/svg+xml
        text/javascript application/javascript application/x-javascript
        text/x-json application/json application/x-web-app-manifest+json
        text/css text/plain text/x-component
        application/x-shockwave-flash application/pdf video/x-flv
        font/opentype application/x-font-ttf application/vnd.ms-fontobject
        image/jpeg image/gif image/png image/bmp image/x-icon
        application/x-httpd-php;

    log_format quic '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" "$http3"';

    log_format json escape=json '{"@timestamp":"$time_iso8601",'
                               '"server_addr":"$server_addr",'
                               '"remote_addr":"$remote_addr",'
                               '"scheme":"$scheme",'
                               '"request_method":"$request_method",'
                               '"request_uri":"$request_uri",'
                               '"request_length":"$request_length",'
                               '"uri":"$uri",'
                               '"request_time":$request_time,'
                               '"body_bytes_sent":$body_bytes_sent,'
                               '"bytes_sent":$bytes_sent,'
                               '"status":"$status",'
                               '"upstream_time":"$upstream_response_time",'
                               '"upstream_host":"$upstream_addr",'
                               '"upstream_status":"$upstream_status",'
                               '"host":"$host",'
                               '"http_referer":"$http_referer",'
                               '"http_user_agent":"$http_user_agent"'
                               '}';

    server {
        listen 80;
        server_name _;
        add_header alt-svc 'h3=":443"; ma=86400';
        access_log /data/wwwlogs/access_nginx.log combined;
        root   /data/wwwroot/default;
        index  index.php index.html;

        location /nginx_status {
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            deny all;
        }

        location ~ .*\.php$ {
            fastcgi_pass   unix:/run/php-fpm.sock;
            fastcgi_index  index.php;
            include        fastcgi.conf;
        }

        location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
            expires 30d;
            access_log off;
        }

        location ~ .*\.(js|css)?$ {
            expires 7d;
            access_log off;
        }

        location ~ ^/(\.user.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
            deny all;
        }

        location /.well-known {
            allow all;
        }
    }

    include vhost/*.conf;
}
EOF
}

###############################################
# 启动模块 3
###############################################
}

###############################################
# run_module3(): 模块 3 顶层执行段封装（修复：避免脚本加载时直接运行）
###############################################
run_module3() {
log_info "开始执行模块 3：Nginx + QUIC 编译安装"

if is_nginx_installed; then
    log_notice "检测到 Nginx 已安装（/usr/local/nginx/sbin/nginx），本次跳过模块 3。"
    log_notice "如需重新编译，请先备份或删除 /usr/local/nginx 后再单独重跑模块 3。"
else
    prepare_nginx_dir
    get_latest_nginx

    download_source "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
                    "${NGINX_SRC_DIR}/nginx-${NGINX_VERSION}.tar.gz"

    get_latest_openssl
    get_latest_pcre2
    download_nginx_modules
    extract_sources
    compile_nginx
    create_nginx_service
    generate_nginx_conf
fi

log_info "检查系统PHP安装情况并进行处理"

###########################################
# LNMP Installer — Module 4
# PHP 7.4–8.5 源码编译 + FPM
# php.ini + php-fpm.conf + 扩展安装框架
# 闭源 Loader 占位提示
###########################################
PHP_SRC_BASE="${BASE_DIR}/php"
PHP_SRC_DIR="${PHP_SRC_BASE}"              # PHP 源码根目录
PHP_INSTALL_BASE="/usr/local"
PHP_EXT_SRC_DIR="${BASE_DIR}/php-ext"      # PHP 扩展源码目录
PHP_EXT_WORK_DIR="${PHP_EXT_SRC_DIR}/work" # 通用扩展工作目录
PHP_FAILED_EXT_LOG="/tmp/php_ext_download_failed.txt"

###############################################
# 选择是否安装 PHP 及版本
###############################################
select_php_version() {
    echo
    yellow "是否安装 PHP？"
    echo "1) 安装"
    echo "2) 不安装"
    read -p "请输入 1 或 2: " PHP_INSTALL_CH

    if [[ "$PHP_INSTALL_CH" != "1" ]]; then
        INSTALL_PHP=0
        return
    fi

    INSTALL_PHP=1

    echo
    yellow "请选择 PHP 版本 (7.4–8.3)："
    echo "1) PHP 7.4 稳定版  (7.4.33)"
    echo "2) PHP 8.0 稳定版  (8.0.30)"
    echo "3) PHP 8.1 稳定版  (8.1.34)"
    echo "4) PHP 8.2 稳定版  (8.2.30)"
    echo "5) PHP 8.3 稳定版  (8.3.29)"
    echo "6) 自定义版本（用于未来 8.4、8.5 等）"
    read -p "请输入 1-6: " PHP_VER_CH

    case "$PHP_VER_CH" in
        1) PHP_VERSION="7.4.33" ;;
        2) PHP_VERSION="8.0.30" ;;
        3) PHP_VERSION="8.1.34" ;;
        4) PHP_VERSION="8.2.30" ;;
        5) PHP_VERSION="8.3.29" ;;
        6) read -p "请输入完整 PHP 版本号（如 8.4.16 / 8.5.1）: " PHP_VERSION ;;
        *) read -p "输入无效，默认 8.3.29，确认请输入 y 回车: " CONFIRM; PHP_VERSION="8.3.29";;
    esac

    PHP_MAJOR_MINOR=$(echo "$PHP_VERSION" | cut -d'.' -f1-2)
    PHP_INSTALL_DIR="${PHP_INSTALL_BASE}/php${PHP_MAJOR_MINOR}"
    PHP_PREFIX_BIN="${PHP_INSTALL_DIR}/bin"
    PHP_PREFIX_SBIN="${PHP_INSTALL_DIR}/sbin"

    log_info "准备安装 PHP 版本：$PHP_VERSION"
}

select_php_version_only() {
    echo
    yellow "请选择 PHP 版本 (7.4–8.3)："
    echo "1) PHP 7.4 稳定版  (7.4.33)"
    echo "2) PHP 8.0 稳定版  (8.0.30)"
    echo "3) PHP 8.1 稳定版  (8.1.34)"
    echo "4) PHP 8.2 稳定版  (8.2.30)"
    echo "5) PHP 8.3 稳定版  (8.3.29)"
    echo "6) 自定义版本（用于未来 8.4、8.5 等）"
    read -r -p "请输入 1-6: " PHP_VER_CH

    case "$PHP_VER_CH" in
        1) PHP_VERSION="7.4.33" ;;
        2) PHP_VERSION="8.0.30" ;;
        3) PHP_VERSION="8.1.34" ;;
        4) PHP_VERSION="8.2.30" ;;
        5) PHP_VERSION="8.3.29" ;;
        6) read -r -p "请输入完整 PHP 版本号（如 8.4.16 / 8.5.1）: " PHP_VERSION ;;
        *) PHP_VERSION="8.3.29" ;;
    esac

    PHP_MAJOR_MINOR=$(echo "$PHP_VERSION" | cut -d'.' -f1-2)
    PHP_INSTALL_DIR="${PHP_INSTALL_BASE}/php${PHP_MAJOR_MINOR}"
    PHP_PREFIX_BIN="${PHP_INSTALL_DIR}/bin"
    PHP_PREFIX_SBIN="${PHP_INSTALL_DIR}/sbin"

    log_info "准备安装 PHP 版本：$PHP_VERSION"
}
###############################################
# 下载 PHP 源码（从官网）
###############################################
download_php_source() {
    mkdir -p "$PHP_SRC_BASE"
    cd "$PHP_SRC_BASE"

    local TAR="php-${PHP_VERSION}.tar.gz"
    local URL="https://www.php.net/distributions/${TAR}"

    if [[ -f "$TAR" ]]; then
        log_info "PHP 源码包已存在：$TAR"
        return
    fi

    log_info "下载 PHP 源码：$URL"
    if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
        log_error "PHP 源码下载失败：$URL"
        echo "$URL" >> /tmp/lnmp_download_failed.txt
        log_error "请手动下载 $TAR 到 $PHP_SRC_BASE 后重新执行脚本"
        return 1
    fi
}

enable_builtin_php_extensions() {
    # 依赖 php-config / php
    if [[ ! -x "${PHP_PREFIX_BIN}/php-config" ]]; then
        log_notice "未找到 php-config，跳过内置扩展自动启用（fileinfo / imap / ldap）"
        return
    fi

    if [[ ! -x "${PHP_PREFIX_BIN}/php" ]]; then
        log_notice "未找到 php 二进制，跳过内置扩展自动启用"
        return
    fi

    local ext_dir
    ext_dir="$("${PHP_PREFIX_BIN}/php-config" --extension-dir 2>/dev/null || echo "")"
    if [[ -z "$ext_dir" ]]; then
        log_notice "无法获取 PHP 扩展目录，跳过内置扩展自动启用"
        return
    fi

    mkdir -p "${PHP_INSTALL_DIR}/etc/php.d"

    local ext
    for ext in fileinfo imap ldap; do
        # 1) 先看 php -m 里是不是已经有这个扩展（可能是内置到 PHP 二进制）
        if "${PHP_PREFIX_BIN}/php" -m 2>/dev/null | grep -qi "^${ext}$"; then
            log_info "检测到扩展 ${ext} 已在 PHP 中启用（php -m 可见），无需生成额外 ${ext}.ini"
            continue
        fi

        # 2) 再看扩展目录里有没有 .so
        if [[ -f "${ext_dir}/${ext}.so" ]]; then
            echo "extension=${ext}.so" > "${PHP_INSTALL_DIR}/etc/php.d/${ext}.ini"
            log_info "已启用扩展：${ext}（${ext_dir}/${ext}.so）"
        else
            log_notice "未在 ${ext_dir} 找到 ${ext}.so，可能编译时未成功启用或依赖缺失"
        fi
    done
}

###############################################
# 为 PHP 7.4 准备兼容 OpenSSL 1.1.1w
###############################################
prepare_php_legacy_openssl() {
    # 只对 7.4 做兼容处理，其它版本直接返回
    if [[ "${PHP_MAJOR_MINOR}" != "7.4" ]]; then
        return 0
    fi

    local LEGACY_OPENSSL_VER="openssl-1.1.1w"
    local LEGACY_OPENSSL_TAR="${LEGACY_OPENSSL_VER}.tar.gz"
    local LEGACY_OPENSSL_SRC="${BASE_DIR}/${LEGACY_OPENSSL_VER}"
    local LEGACY_OPENSSL_PREFIX="/usr/local/openssl11"

    # 如果已经安装过兼容 OpenSSL，则直接复用
    if [[ -x "${LEGACY_OPENSSL_PREFIX}/bin/openssl" ]]; then
        PHP_OPENSSL_DIR="${LEGACY_OPENSSL_PREFIX}"
        log_info "检测到已安装的兼容 OpenSSL：${PHP_OPENSSL_DIR}"
        return 0
    fi

    mkdir -p "${BASE_DIR}"
    cd "${BASE_DIR}" || {
        log_error "prepare_php_legacy_openssl: 无法进入 ${BASE_DIR}"
        return 1
    }

    if [[ ! -f "${LEGACY_OPENSSL_TAR}" ]]; then
        log_info "下载用于 PHP 7.4 的兼容 OpenSSL 源码：${LEGACY_OPENSSL_TAR}"
        if ! curl -L --connect-timeout 20 -o "${LEGACY_OPENSSL_TAR}" "https://www.openssl.org/source/${LEGACY_OPENSSL_TAR}"; then
            log_error "下载 ${LEGACY_OPENSSL_TAR} 失败，PHP 7.4 可能无法通过 OpenSSL 检查"
            return 1
        fi
    else
        log_info "检测到本地已有 ${LEGACY_OPENSSL_TAR}，跳过下载"
    fi

    if [[ ! -d "${LEGACY_OPENSSL_SRC}" ]]; then
        if ! tar xf "${LEGACY_OPENSSL_TAR}"; then
            log_error "解压 ${LEGACY_OPENSSL_TAR} 失败"
            return 1
        fi
    fi

    cd "${LEGACY_OPENSSL_SRC}" || {
        log_error "prepare_php_legacy_openssl: 无法进入 ${LEGACY_OPENSSL_SRC}"
        return 1
    }

    log_info "开始编译 OpenSSL 1.1.1w（供 PHP 7.4 使用）"
    if ! ./config --prefix="${LEGACY_OPENSSL_PREFIX}" no-shared no-tests; then
        log_error "OpenSSL 1.1.1w ./config 失败"
        return 1
    fi

    if ! make -j"$(nproc)"; then
        log_error "OpenSSL 1.1.1w 编译失败"
        return 1
    fi

    if ! make install_sw; then
        log_error "OpenSSL 1.1.1w 安装失败"
        return 1
    fi

    PHP_OPENSSL_DIR="${LEGACY_OPENSSL_PREFIX}"
    log_info "已将兼容 OpenSSL 安装到：${PHP_OPENSSL_DIR}"
    return 0
}

###############################################
# 编译安装 PHP
###############################################
compile_php() {
    # 1) 进入 PHP 源码目录
    cd "$PHP_SRC_BASE" || {
        log_error "PHP 源码目录不存在：$PHP_SRC_BASE"
        exit 1
    }

    local PHP_TAR="php-${PHP_VERSION}.tar.gz"

    # 2) 确认源码包存在
    if [[ ! -f "${PHP_TAR}" ]]; then
        log_error "未找到 ${PHP_TAR}，请先执行 download_php_source 或检查网络"
        exit 1
    fi

    # 3) 清理旧目录并解压
    rm -rf "php-${PHP_VERSION}"
    if ! tar xf "${PHP_TAR}"; then
        log_error "解压 ${PHP_TAR} 失败"
        exit 1
    fi

    # 4) 进入解压后的源码目录
    cd "php-${PHP_VERSION}" || {
        log_error "进入解压后的 php-${PHP_VERSION} 目录失败"
        exit 1
    }

    # 5) OpenSSL 选项：
    #    - 默认用系统 OpenSSL
    #    - 如果是 PHP 7.4，优先尝试 /usr/local/openssl11
    local PHP_OPENSSL_OPT="--with-openssl"

    if [[ "${PHP_MAJOR_MINOR}" == "7.4" ]]; then
        if prepare_php_legacy_openssl; then
            if [[ -n "${PHP_OPENSSL_DIR:-}" && -d "${PHP_OPENSSL_DIR}" ]]; then
                PHP_OPENSSL_OPT="--with-openssl=${PHP_OPENSSL_DIR}"
                export CPPFLAGS="-I${PHP_OPENSSL_DIR}/include ${CPPFLAGS:-}"
                export LDFLAGS="-L${PHP_OPENSSL_DIR}/lib ${LDFLAGS:-}"
                export PKG_CONFIG_PATH="${PHP_OPENSSL_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
                log_info "PHP 7.4 使用兼容 OpenSSL：${PHP_OPENSSL_DIR}"
            else
                log_notice "prepare_php_legacy_openssl 成功但 PHP_OPENSSL_DIR 未设置，回退系统 OpenSSL"
            fi
        else
            log_notice "准备兼容 OpenSSL 失败，PHP 7.4 将使用系统 OpenSSL（可能出现大量 3.0 deprecated 提示）"
        fi
    fi

    # 6) ./configure
    log_info "开始执行 PHP ./configure（版本：${PHP_VERSION}）"
    if ! ./configure \
        --prefix="${PHP_INSTALL_DIR}" \
        --with-config-file-path="${PHP_INSTALL_DIR}/etc" \
        --with-config-file-scan-dir="${PHP_INSTALL_DIR}/etc/php.d" \
        --enable-fpm \
        --with-fpm-user=www \
        --with-fpm-group=www \
        --enable-mbstring \
        ${PHP_OPENSSL_OPT} \
        --with-zlib \
        --with-curl \
        --enable-bcmath \
        --enable-intl \
        --with-gettext \
        --with-mysqli=mysqlnd \
        --with-pdo-mysql=mysqlnd \
        --enable-pcntl \
        --enable-sockets \
        --enable-sysvmsg \
        --enable-sysvsem \
        --enable-sysvshm \
        --enable-opcache \
        --enable-zip \
        --with-zip \
        --with-ldap \
        --with-password-argon2 \
        --with-sqlite3 \
        --with-pdo-sqlite \
        --with-gd \
        --with-jpeg \
        --with-webp \
        --with-freetype \
        --enable-fileinfo \
        --with-imap \
        --with-imap-ssl \
        --with-kerberos
    then
        log_error "PHP ./configure 失败"
        # 防止脏目录影响下次编译
        make clean >/dev/null 2>&1 || true
        exit 1
    fi

    # 7) 编译
    log_info "开始 make 编译 PHP（并行：$(nproc)）"
    if ! make -j"$(nproc)"; then
        log_error "PHP make 编译失败"
        make clean >/dev/null 2>&1 || true
        exit 1
    fi

    # 8) 安装
    if ! make install; then
        log_error "PHP make install 失败"
        exit 1
    fi

    mkdir -p "${PHP_INSTALL_DIR}/etc/php.d"

    # 9) 建软链接
    ln -sf "${PHP_PREFIX_BIN}/php" /usr/bin/php${PHP_MAJOR_MINOR}
    ln -sf "${PHP_PREFIX_BIN}/php" /usr/bin/php
    ln -sf "${PHP_PREFIX_SBIN}/php-fpm" /usr/sbin/php-fpm${PHP_MAJOR_MINOR}
    ln -sf "${PHP_PREFIX_SBIN}/php-fpm" /usr/sbin/php-fpm

    log_info "PHP ${PHP_VERSION} 编译安装完成，安装目录：${PHP_INSTALL_DIR}"

    # 自动启用内置扩展（fileinfo / imap / ldap）
    enable_builtin_php_extensions
}

###############################################
# 生成 php.ini
###############################################
generate_php_ini() {
    local PHP_INI="${PHP_INSTALL_DIR}/etc/php.ini"

    if [[ -f "php.ini-production" ]]; then
        cp php.ini-production "$PHP_INI"
    else
        touch "$PHP_INI"
    fi

    sed -i 's/;date.timezone =.*/date.timezone = Asia\/Shanghai/' "$PHP_INI"
    sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' "$PHP_INI"

    cat >>"$PHP_INI" <<EOF

[opcache]
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=2

[Session]
session.save_handler = files
session.save_path = "/tmp"

[mbstring]
mbstring.internal_encoding = "UTF-8"
mbstring.language = "Neutral"

; 禁用常见危险函数，可按需要增删
disable_functions = "exec,passthru,shell_exec,system,proc_open,popen,show_source,pcntl_exec"
EOF

    log_info "php.ini 已生成：$PHP_INI"
}

###############################################
# 生成 php-fpm 配置
###############################################
generate_php_fpm_conf() {
    local FPM_CONF_DIR="${PHP_INSTALL_DIR}/etc"
    local FPM_CONF="${FPM_CONF_DIR}/php-fpm.conf"
    local FPM_POOL="${FPM_CONF_DIR}/php-fpm.d/www.conf"

    mkdir -p "${FPM_CONF_DIR}/php-fpm.d"

    if [[ -f "sapi/fpm/php-fpm.conf" ]]; then
        cp "sapi/fpm/php-fpm.conf" "$FPM_CONF"
    fi

    if [[ -f "sapi/fpm/www.conf" ]]; then
        cp "sapi/fpm/www.conf" "$FPM_POOL"
    fi

    # 主配置
    cat >"$FPM_CONF" <<EOF
[global]
pid = /run/php-fpm.pid
error_log = /data/wwwlogs/php-fpm_error.log
log_level = notice

include=${PHP_INSTALL_DIR}/etc/php-fpm.d/*.conf
EOF

    # 池配置
    cat >"$FPM_POOL" <<EOF
[www]
user = www
group = www

listen = /run/php-fpm.sock
listen.owner = www
listen.group = www
listen.mode = 0660

pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 10
pm.max_spare_servers = 35
pm.max_requests = 500

request_terminate_timeout = 300
slowlog = /data/wwwlogs/php-fpm_slow.log

php_admin_value[error_log] = /data/wwwlogs/php-fpm_error.log
php_admin_flag[log_errors] = on

; 按需增加 per-pool 限制
EOF

    log_info "php-fpm 配置已生成（监听：/run/php-fpm.sock）"
}

###############################################
# 创建 php-fpm systemd 服务
###############################################
create_php_fpm_service() {
    cat >/etc/systemd/system/php-fpm.service <<EOF
[Unit]
Description=PHP-FPM
After=network.target

[Service]
Type=simple
ExecStart=${PHP_PREFIX_SBIN}/php-fpm --nodaemonize --fpm-config ${PHP_INSTALL_DIR}/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
ExecStop=/bin/kill -INT \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable php-fpm
    systemctl restart php-fpm

    log_info "php-fpm 已通过 systemd 管理：php-fpm.service"
}

download_with_proxy_and_retry() {
    local url="$1"
    local out="$2"
    local retry="${3:-3}"
    local i

    if [[ -z "$url" || -z "$out" ]]; then
        log_error "download_with_proxy_and_retry: URL 或输出文件为空"
        return 1
    fi

    i=1
    while (( i <= retry )); do
        log_info "下载（第 ${i}/${retry} 次）：${url} -> ${out}"
        if curl -L --connect-timeout 30 -o "$out" "$url"; then
            return 0
        fi
        log_notice "下载失败（第 ${i} 次）：${url}"
        sleep 3
        ((i++))
    done

    return 1
}

###############################################
# 通用 PHP 扩展安装框架（PECL tgz）
###############################################
install_php_ext_generic() {
    local EXT_NAME="$1"        # redis / inotify / apcu / ...
    local EXT_URL="$2"         # https://pecl.php.net/get/redis-5.3.7.tgz
    local EXT_OPT="${3:-}"     # 预留参数（某些扩展可能用到）

    if [[ -z "$EXT_NAME" ]]; then
        log_error "install_php_ext_generic: 未提供扩展名称"
        return 1
    fi

    mkdir -p "${PHP_SRC_DIR}/ext" "${PHP_EXT_WORK_DIR}"

    local EXT_NAME_UPPER
    EXT_NAME_UPPER="$(echo "$EXT_NAME" | tr '[:lower:]' '[:upper:]')"

    # 允许通过环境变量覆盖本地包路径，比如：
    #   export PHP_EXT_REDIS_TAR=/root/redis-5.3.7.tgz
    local EXT_TAR_VAR="PHP_EXT_${EXT_NAME_UPPER}_TAR"
    local EXT_TAR_PATH="${!EXT_TAR_VAR:-}"

    local TAR_NAME
    local SRC_DESC
    local USED_LOCAL=0

    # 1) 优先使用用户提供的本地包
    if [[ -n "$EXT_TAR_PATH" && -f "$EXT_TAR_PATH" ]]; then
        TAR_NAME="${PHP_EXT_WORK_DIR}/${EXT_NAME}.tgz"
        cp -f "$EXT_TAR_PATH" "$TAR_NAME"
        SRC_DESC="本地包 ${EXT_TAR_PATH}"
        USED_LOCAL=1
    elif [[ -n "$EXT_URL" ]]; then
        # 2) 否则使用远程 URL
        TAR_NAME="${PHP_EXT_WORK_DIR}/$(basename "$EXT_URL")"
        SRC_DESC="远程 ${EXT_URL}"
        log_info "准备从远程下载扩展 ${EXT_NAME}：${EXT_URL}"
        if ! download_with_proxy_and_retry "$EXT_URL" "$TAR_NAME"; then
            log_notice "扩展 ${EXT_NAME} 下载失败：${EXT_URL}"
            echo "$EXT_NAME" >> "$PHP_FAILED_EXT_LOG"
            return 1
        fi
    else
        log_notice "扩展 ${EXT_NAME} 未提供下载 URL，也未指定本地 TAR，跳过"
        echo "$EXT_NAME" >> "$PHP_FAILED_EXT_LOG"
        return 1
    fi

    # ⬇⬇⬇ 3) 校验 tar 包体积，必要时从本地退回到远程 URL 重新下载 ⬇⬇⬇
    local SIZE
    SIZE=$(stat -c '%s' "$TAR_NAME" 2>/dev/null || echo 0)

    # 当体积明显过小（一般是 HTML 错误页），尝试一次“本地 -> 远程”的兜底
    if [[ $SIZE -gt 0 && $SIZE -lt 4096 ]]; then
        log_notice "扩展 ${EXT_NAME} 压缩包体积异常（${SIZE} 字节），可能是错误页：$(basename "$TAR_NAME")（来源：${SRC_DESC:-未知}）"

        # 如果当前用的是本地包，并且有远程 URL，则尝试重新从远程下载一次
        if [[ $USED_LOCAL -eq 1 && -n "$EXT_URL" ]]; then
            log_info "尝试改用官方远程包重新下载扩展 ${EXT_NAME}：${EXT_URL}"
            if download_with_proxy_and_retry "$EXT_URL" "$TAR_NAME"; then
                SRC_DESC="远程 ${EXT_URL}"
                SIZE=$(stat -c '%s' "$TAR_NAME" 2>/dev/null || echo 0)
                log_info "扩展 ${EXT_NAME} 重新下载完成，新体积：${SIZE} 字节"
            else
                log_notice "扩展 ${EXT_NAME} 从官方地址重新下载仍失败：${EXT_URL}"
                echo "$EXT_NAME" >> "$PHP_FAILED_EXT_LOG"
                return 1
            fi
        fi
    fi

    # 重新校验一次体积（可能已经重新下载）
    SIZE=$(stat -c '%s' "$TAR_NAME" 2>/dev/null || echo 0)
    if [[ $SIZE -le 0 || $SIZE -lt 4096 ]]; then
        log_notice "扩展 ${EXT_NAME} 压缩包看起来依旧不正常（${SIZE} 字节）：$(basename "$TAR_NAME")（来源：${SRC_DESC:-未知}）"
        mv -f "$TAR_NAME" "${TAR_NAME}.bad.$(date +%s)" 2>/dev/null || true
        echo "$EXT_NAME" >> "$PHP_FAILED_EXT_LOG"
        return 1
    fi

    # 4) 解压并编译安装
    log_info "开始解压并编译安装扩展 ${EXT_NAME}（来源：${SRC_DESC}）"

    (
        cd "$PHP_EXT_WORK_DIR" || exit 1
        rm -rf "${EXT_NAME}-src"
        mkdir -p "${EXT_NAME}-src"
        tar -xf "$TAR_NAME" -C "${EXT_NAME}-src" --strip-components=1

        cd "${EXT_NAME}-src" || exit 1

        if ! "${PHP_PREFIX_BIN}/phpize"; then
            log_error "phpize 失败：扩展 ${EXT_NAME}"
            exit 1
        fi

        if ! ./configure --with-php-config="${PHP_PREFIX_BIN}/php-config" $EXT_OPT; then
            log_error "configure 失败：扩展 ${EXT_NAME}"
            exit 1
        fi

        if ! make -j"$(nproc)" && ! make; then
            log_error "make 失败：扩展 ${EXT_NAME}"
            exit 1
        fi

        if ! make install; then
            log_error "make install 失败：扩展 ${EXT_NAME}"
            exit 1
        fi
    )

    if [[ $? -ne 0 ]]; then
        log_notice "扩展 ${EXT_NAME} 编译 / 安装失败，详细见上方日志"
        echo "$EXT_NAME" >> "$PHP_FAILED_EXT_LOG"
        return 1
    fi

    # 5) 写入扩展 ini
    mkdir -p "${PHP_INSTALL_DIR}/etc/php.d"
    local ini_file="${PHP_INSTALL_DIR}/etc/php.d/${EXT_NAME}.ini"

    # Xdebug 必须作为 Zend 扩展加载
    if [[ "$EXT_NAME" == "xdebug" ]]; then
        echo "zend_extension=${EXT_NAME}.so" > "$ini_file"
        log_info "扩展 ${EXT_NAME} 安装并启用完成（使用 zend_extension）"
    else
        echo "extension=${EXT_NAME}.so" > "$ini_file"
        log_info "扩展 ${EXT_NAME} 安装并启用完成"
    fi
}

###############################################
# Yaf 扩展：使用官方 Git 仓库安装
# 默认仓库：https://github.com/laruence/yaf.git
# 推荐：根据 PHP 版本选择对应稳定 tag（例如：YAF-3.3.7）
###############################################
install_php_ext_yaf_from_git() {
    if [[ ! -x "${PHP_PREFIX_BIN}/phpize" || ! -x "${PHP_PREFIX_BIN}/php-config" ]]; then
        log_notice "跳过 Yaf 安装：未找到 phpize/php-config（PHP 可能未正确安装）"
        echo "php-ext:yaf:missing_phpize" >> "$PHP_FAILED_EXT_LOG"
        return
    fi
    local REPO="${YAF_GIT_REPO:-https://github.com/laruence/yaf.git}"
    local TAG="${YAF_GIT_TAG:-}"   # 例如：YAF-3.3.7（请根据仓库 tag 实际填写）
    local SRC_DIR="${PHP_EXT_SRC_DIR}/yaf-src"

    mkdir -p "$PHP_EXT_SRC_DIR"
    cd "$PHP_EXT_SRC_DIR"

    if [[ -z "$REPO" ]]; then
        log_notice "Yaf 扩展未配置 Git 仓库地址，请设置 YAF_GIT_REPO 后重试。"
        echo "php-ext:yaf:missing_repo" >> "$PHP_FAILED_EXT_LOG"
        return
    fi

    rm -rf "$SRC_DIR"
    log_info "从 Git 仓库拉取 Yaf：$REPO"
    if ! git clone --depth 1 "$REPO" "$SRC_DIR"; then
        log_notice "Yaf 仓库克隆失败：$REPO"
        echo "php-ext:yaf:clone_failed:${REPO}" >> "$PHP_FAILED_EXT_LOG"
        return
    fi

    if [[ -n "$TAG" ]]; then
        log_info "切换到 Yaf 指定 tag：$TAG"
        if ! git -C "$SRC_DIR" fetch --tags >/dev/null 2>&1 || \
           ! git -C "$SRC_DIR" checkout "tags/${TAG}" -b "build-yaf-${TAG}" 2>/dev/null; then
            log_notice "切换 Yaf tag 失败（${TAG}），继续使用默认分支。"
            echo "php-ext:yaf:tag_failed:${TAG}" >> "$PHP_FAILED_EXT_LOG"
        fi
    fi

    cd "$SRC_DIR"

    if ! "${PHP_PREFIX_BIN}/phpize"; then
        log_notice "phpize 失败（Yaf），请检查 PHP 开发头文件。"
        echo "php-ext:yaf:phpize_failed" >> "$PHP_FAILED_EXT_LOG"
        return
    fi

    if ! ./configure --with-php-config="${PHP_PREFIX_BIN}/php-config"; then
        log_notice "Yaf ./configure 失败，请检查依赖。"
        echo "php-ext:yaf:configure_failed" >> "$PHP_FAILED_EXT_LOG"
        return
    fi

    make -j"$(nproc)" && make install

    echo "extension=yaf.so" > "${PHP_INSTALL_DIR}/etc/php.d/yaf.ini"
    log_info "Yaf 扩展安装完成（来源：${REPO}）"
}

###############################################
# 从 Git 安装 Phalcon 扩展（按 PHP 版本选择合适 TAG）
###############################################
###############################################
# 安装 Phalcon 扩展（根据 PHP 版本选择源码目录）
###############################################
###############################################
# 安装 Phalcon 扩展（从 Git 仓库按 PHP 版本编译）
###############################################
install_php_ext_phalcon_from_git() {
    local EXT_NAME="phalcon"

    # 这些变量在前面通用扩展函数里已经用过，这里跟它保持一致
    local PHP_BIN="${PHP_INSTALL_DIR}/bin/php"
    local PHPIZE="${PHP_INSTALL_DIR}/bin/phpize"
    local PHP_CONFIG="${PHP_INSTALL_DIR}/bin/php-config"
    local PHP_EXT_DIR="$("${PHP_CONFIG}" --extension-dir)"

    local PHP_VER_SHORT
    PHP_VER_SHORT="$("${PHP_BIN}" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

    local PHALCON_REPO=${PHALCON_REPO:-"https://github.com/phalcon/cphalcon.git"}
    local SRC_DIR="${PHP_EXT_WORK_DIR}/phalcon-src"

    # === 根据 PHP 版本选择对应的 Phalcon 标签 ===
    local PHALCON_TAG=""

    case "${PHP_VER_SHORT}" in
        7.4)
            # PHP 7.4 对应 Phalcon 4.x（这里选 4.1.2，最后稳定版）
            PHALCON_TAG="v4.1.2"
            ;;
        *)
            # 其他版本暂时不强制映射，仍然用默认分支
            PHALCON_TAG=""
            ;;
    esac

    log_info "准备安装 Phalcon 扩展（PHP ${PHP_VER_SHORT}）"
    log_info "源码仓库：${PHALCON_REPO}"

    # 清理旧源码，避免分支不一致
    rm -rf "${SRC_DIR}"
    mkdir -p "${PHP_EXT_WORK_DIR}"

    if [[ -n "${PHALCON_TAG}" ]]; then
        log_info "为 PHP ${PHP_VER_SHORT} 选择 Phalcon 版本：${PHALCON_TAG}"
        if ! git clone --depth 1 --branch "${PHALCON_TAG}" "${PHALCON_REPO}" "${SRC_DIR}"; then
            log_notice "从 ${PHALCON_REPO} 克隆 Phalcon ${PHALCON_TAG} 失败"
            echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
            return 1
        fi
    else
        log_notice "当前 PHP 版本 ${PHP_VER_SHORT} 未配置 Phalcon 版本映射，将尝试仓库默认分支（通常只支持 PHP 8+），如编译失败需手动调整。"
        if ! git clone --depth 1 "${PHALCON_REPO}" "${SRC_DIR}"; then
            log_notice "从 ${PHALCON_REPO} 克隆 Phalcon 失败"
            echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
            return 1
        fi
    fi

    # 统一使用 ext 目录编译
    local EXT_SRC_DIR="${SRC_DIR}/ext"
    if [[ ! -d "${EXT_SRC_DIR}" ]]; then
        log_notice "未找到 Phalcon 扩展目录：${EXT_SRC_DIR}"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    fi

    log_info "开始使用 phpize 编译 Phalcon（目录：${EXT_SRC_DIR}）"
    cd "${EXT_SRC_DIR}" || {
        log_notice "无法进入目录：${EXT_SRC_DIR}"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    }

    if ! "${PHPIZE}"; then
        log_notice "phpize 失败，Phalcon 编译中止"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    fi

    if ! ./configure --with-php-config="${PHP_CONFIG}"; then
        log_notice "configure 失败，Phalcon 编译中止"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    fi

    if ! make -j"$(nproc 2>/dev/null || echo 1)"; then
        log_notice "make 失败，Phalcon 编译中止"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    fi

    if ! make install; then
        log_notice "make install 失败，Phalcon 安装中止"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    fi

    if [[ ! -f "${PHP_EXT_DIR}/phalcon.so" ]]; then
        log_notice "Phalcon 安装完成但未在 ${PHP_EXT_DIR} 找到 phalcon.so"
        echo "${EXT_NAME}" >> "${PHP_FAILED_EXT_LOG}"
        return 1
    fi

    # 写入 ini
    mkdir -p "${PHP_INSTALL_DIR}/etc/php.d"
    local PHALCON_INI="${PHP_INSTALL_DIR}/etc/php.d/30-phalcon.ini"
    echo "extension=phalcon.so" > "${PHALCON_INI}"

    log_info "Phalcon 扩展安装并启用完成：${PHALCON_INI}"
}

###############################################
# 根据 PHP 版本设置各扩展的“默认版本号”
# 可被环境变量 PHP_EXT_xxx_VERSION / PHP_EXT_xxx_URL 覆盖
###############################################
set_default_pecl_versions() {

    # 先给一个通用兜底（万一 case 没匹配上）
    PECL_REDIS_VERSION=""
    PECL_INOTIFY_VERSION=""
    PECL_APCU_VERSION=""
    PECL_PSR_VERSION=""
    PECL_MEMCACHED_VERSION=""
    PECL_MEMCACHE_VERSION=""
    PECL_MONGODB_VERSION=""
    PECL_XDEBUG_VERSION=""
    PECL_IMAGICK_VERSION=""

    case "$PHP_MAJOR_MINOR" in
        7.4)
            PECL_REDIS_VERSION="5.3.7"
            PECL_INOTIFY_VERSION="3.0.0"
            PECL_APCU_VERSION="5.1.21"
            PECL_PSR_VERSION="1.2.0"
            PECL_MEMCACHED_VERSION="3.1.5"
            PECL_MEMCACHE_VERSION="4.0.5.2"
            PECL_MONGODB_VERSION="1.13.0"
            PECL_XDEBUG_VERSION="3.1.6"
            PECL_IMAGICK_VERSION="3.7.0"
            ;;
        8.0)
            # 这一档支持 PHP 8.0 的稳定版本
            PECL_REDIS_VERSION="5.3.7"
            PECL_INOTIFY_VERSION="3.0.0"
            PECL_APCU_VERSION="5.1.21"
            PECL_PSR_VERSION="1.2.0"
            PECL_MEMCACHED_VERSION="3.1.5"
            PECL_MEMCACHE_VERSION="4.0.5.2"
            PECL_MONGODB_VERSION="1.13.0"
            PECL_XDEBUG_VERSION="3.1.6"
            PECL_IMAGICK_VERSION="3.7.0"
            ;;
        8.1)
            # 对 PHP 8.1 用偏新的版本
            PECL_REDIS_VERSION="6.0.2"
            PECL_INOTIFY_VERSION="3.0.0"
            PECL_APCU_VERSION="5.1.22"
            PECL_PSR_VERSION="1.2.0"
            PECL_MEMCACHED_VERSION="3.2.0"
            PECL_MEMCACHE_VERSION="4.0.5.2"
            PECL_MONGODB_VERSION="1.15.0"
            PECL_XDEBUG_VERSION="3.2.2"
            PECL_IMAGICK_VERSION="3.7.0"
            ;;
        8.2|8.3)
            # 8.2/8.3 用再新一点的组合
            PECL_REDIS_VERSION="6.0.2"
            PECL_INOTIFY_VERSION="3.0.0"
            PECL_APCU_VERSION="5.1.23"
            PECL_PSR_VERSION="1.2.0"
            PECL_MEMCACHED_VERSION="3.2.0"
            PECL_MEMCACHE_VERSION="8.0"     # 这里建议以后你自己放内网包兼容 8.x
            PECL_MONGODB_VERSION="1.16.0"
            PECL_XDEBUG_VERSION="3.3.2"
            PECL_IMAGICK_VERSION="3.7.0"
            ;;
    esac
}

###############################################
# 安装常用 PHP 扩展（根据 PHP 版本自动选 PECL 版本）
###############################################
install_php_extensions() {
    log_info "开始安装常用 PHP 扩展（根据 PHP 版本自动匹配版本）"

    # 每次执行重置失败日志
    : > "$PHP_FAILED_EXT_LOG"

    # 先根据 PHP_MAJOR_MINOR 计算出一批默认版本
    set_default_pecl_versions

    # ====== 计算每个扩展最终使用的「版本号」 ======
    # 优先级：PHP_EXT_xxx_VERSION（环境变量） > PECL_xxx_VERSION（上面函数里按 PHP 版本设置）

    local EXT_REDIS_VERSION="${PHP_EXT_REDIS_VERSION:-$PECL_REDIS_VERSION}"
    local EXT_INOTIFY_VERSION="${PHP_EXT_INOTIFY_VERSION:-$PECL_INOTIFY_VERSION}"
    local EXT_APCU_VERSION="${PHP_EXT_APCU_VERSION:-$PECL_APCU_VERSION}"
    local EXT_PSR_VERSION="${PHP_EXT_PSR_VERSION:-$PECL_PSR_VERSION}"
    local EXT_MEMCACHED_VERSION="${PHP_EXT_MEMCACHED_VERSION:-$PECL_MEMCACHED_VERSION}"
    local EXT_MEMCACHE_VERSION="${PHP_EXT_MEMCACHE_VERSION:-$PECL_MEMCACHE_VERSION}"
    local EXT_MONGODB_VERSION="${PHP_EXT_MONGODB_VERSION:-$PECL_MONGODB_VERSION}"
    local EXT_XDEBUG_VERSION="${PHP_EXT_XDEBUG_VERSION:-$PECL_XDEBUG_VERSION}"
    local EXT_IMAGICK_VERSION="${PHP_EXT_IMAGICK_VERSION:-$PECL_IMAGICK_VERSION}"

    # ====== 根据「版本号」拼 URL；如果版本号为空，就退回到无版本 URL ======
    # 优先级：PHP_EXT_xxx_URL（环境变量显式指定 URL） > 下面自动拼出来的 URL

    local EXT_REDIS_URL
    if [[ -n "$EXT_REDIS_VERSION" ]]; then
        EXT_REDIS_URL="https://pecl.php.net/get/redis-${EXT_REDIS_VERSION}.tgz"
    else
        EXT_REDIS_URL="https://pecl.php.net/get/redis.tgz"
    fi
    EXT_REDIS_URL="${PHP_EXT_REDIS_URL:-$EXT_REDIS_URL}"

    local EXT_INOTIFY_URL
    if [[ -n "$EXT_INOTIFY_VERSION" ]]; then
        EXT_INOTIFY_URL="https://pecl.php.net/get/inotify-${EXT_INOTIFY_VERSION}.tgz"
    else
        EXT_INOTIFY_URL="https://pecl.php.net/get/inotify.tgz"
    fi
    EXT_INOTIFY_URL="${PHP_EXT_INOTIFY_URL:-$EXT_INOTIFY_URL}"

    local EXT_APCU_URL
    if [[ -n "$EXT_APCU_VERSION" ]]; then
        EXT_APCU_URL="https://pecl.php.net/get/apcu-${EXT_APCU_VERSION}.tgz"
    else
        EXT_APCU_URL="https://pecl.php.net/get/apcu.tgz"
    fi
    EXT_APCU_URL="${PHP_EXT_APCU_URL:-$EXT_APCU_URL}"

    local EXT_PSR_URL
    if [[ -n "$EXT_PSR_VERSION" ]]; then
        EXT_PSR_URL="https://pecl.php.net/get/psr-${EXT_PSR_VERSION}.tgz"
    else
        EXT_PSR_URL="https://pecl.php.net/get/psr.tgz"
    fi
    EXT_PSR_URL="${PHP_EXT_PSR_URL:-$EXT_PSR_URL}"

    local EXT_MEMCACHED_URL
    if [[ -n "$EXT_MEMCACHED_VERSION" ]]; then
        EXT_MEMCACHED_URL="https://pecl.php.net/get/memcached-${EXT_MEMCACHED_VERSION}.tgz"
    else
        EXT_MEMCACHED_URL="https://pecl.php.net/get/memcached.tgz"
    fi
    EXT_MEMCACHED_URL="${PHP_EXT_MEMCACHED_URL:-$EXT_MEMCACHED_URL}"

    local EXT_MEMCACHE_URL
    if [[ -n "$EXT_MEMCACHE_VERSION" ]]; then
        EXT_MEMCACHE_URL="https://pecl.php.net/get/memcache-${EXT_MEMCACHE_VERSION}.tgz"
    else
        EXT_MEMCACHE_URL="https://pecl.php.net/get/memcache.tgz"
    fi
    EXT_MEMCACHE_URL="${PHP_EXT_MEMCACHE_URL:-$EXT_MEMCACHE_URL}"

    local EXT_MONGODB_URL
    if [[ -n "$EXT_MONGODB_VERSION" ]]; then
        EXT_MONGODB_URL="https://pecl.php.net/get/mongodb-${EXT_MONGODB_VERSION}.tgz"
    else
        EXT_MONGODB_URL="https://pecl.php.net/get/mongodb.tgz"
    fi
    EXT_MONGODB_URL="${PHP_EXT_MONGODB_URL:-$EXT_MONGODB_URL}"

    local EXT_XDEBUG_URL
    if [[ -n "$EXT_XDEBUG_VERSION" ]]; then
        EXT_XDEBUG_URL="https://pecl.php.net/get/xdebug-${EXT_XDEBUG_VERSION}.tgz"
    else
        EXT_XDEBUG_URL="https://pecl.php.net/get/xdebug.tgz"
    fi
    EXT_XDEBUG_URL="${PHP_EXT_XDEBUG_URL:-$EXT_XDEBUG_URL}"

    local EXT_IMAGICK_URL
    if [[ -n "$EXT_IMAGICK_VERSION" ]]; then
        EXT_IMAGICK_URL="https://pecl.php.net/get/imagick-${EXT_IMAGICK_VERSION}.tgz"
    else
        EXT_IMAGICK_URL="https://pecl.php.net/get/imagick.tgz"
    fi
    EXT_IMAGICK_URL="${PHP_EXT_IMAGICK_URL:-$EXT_IMAGICK_URL}"

    # 如有需要可以继续扩展其它扩展（保持模块不缺失）
    local EXT_GMAGICK_URL="${PHP_EXT_GMAGICK_URL:-https://pecl.php.net/get/gmagick.tgz}"
    local EXT_SWOOLE_URL="${PHP_EXT_SWOOLE_URL:-https://pecl.php.net/get/swoole.tgz}"

    # ========= PECL 扩展安装（保持原有模块，不删减） =========
    install_php_ext_generic "redis"     "$EXT_REDIS_URL"
    install_php_ext_generic "inotify"   "$EXT_INOTIFY_URL"
    install_php_ext_generic "apcu"      "$EXT_APCU_URL"
    install_php_ext_generic "psr"       "$EXT_PSR_URL"
    install_php_ext_generic "memcached" "$EXT_MEMCACHED_URL"
    install_php_ext_generic "memcache"  "$EXT_MEMCACHE_URL"
    install_php_ext_generic "mongodb"   "$EXT_MONGODB_URL"
    install_php_ext_generic "xdebug"    "$EXT_XDEBUG_URL"
    install_php_ext_generic "imagick"   "$EXT_IMAGICK_URL"

    # 保持原脚本的模块完整性：如需 gmagick / swoole 也一起保持
    # install_php_ext_generic "gmagick"   "$EXT_GMAGICK_URL"
    # install_php_ext_generic "swoole"    "$EXT_SWOOLE_URL"

    # ====== Yaf / Phalcon：使用 Git 仓库安装（保持原逻辑） ======
    local yaf_flag="${ENABLE_YAF:-1}"
    local phalcon_flag="${ENABLE_PHALCON:-1}"

    if [[ "$yaf_flag" == "1" ]]; then
        install_php_ext_yaf_from_git
    else
        log_info "已跳过 Yaf 安装（ENABLE_YAF=${yaf_flag}）"
    fi

if [[ "$phalcon_flag" == "1" ]]; then
    if declare -F install_php_ext_phalcon_from_git >/dev/null 2>&1; then
        install_php_ext_phalcon_from_git
    else
        log_notice "函数 install_php_ext_phalcon_from_git 未定义，已跳过 Phalcon 安装"
        echo "phalcon (func_missing)" >> "$PHP_FAILED_EXT_LOG"
    fi
fi

    if [[ -s "$PHP_FAILED_EXT_LOG" ]]; then
        yellow "部分扩展下载或构建失败，已记录到：$PHP_FAILED_EXT_LOG"
        yellow "你可以查看该文件，按行补充对应的源码地址 / Git 仓库 / 本地 TAR 后重新执行模块 4。"
    else
        log_info "所有配置的扩展安装流程已执行完成"
    fi
}

# =========================================
# 闭源 Loader 安装：ionCube / SourceGuardian
# =========================================
install_closed_source_loaders() {
    local PHP_PREFIX_BIN="${PHP_INSTALL_DIR}/bin"
    local php_ini="${PHP_INSTALL_DIR}/etc/php.ini"
    local ext_dir
    local php_ver_short

    if [[ ! -x "${PHP_PREFIX_BIN}/php" ]]; then
        log_notice "未找到 ${PHP_PREFIX_BIN}/php，跳过闭源 Loader 安装"
        return
    fi

    ext_dir="$(${PHP_PREFIX_BIN}/php-config --extension-dir 2>/dev/null || true)"
    if [[ -z "$ext_dir" ]]; then
        log_notice "无法获取 extension_dir，跳过闭源 Loader 安装"
        return
    fi

    # 正确获取主次版本号，如 7.4 / 8.3
    php_ver_short="$(${PHP_PREFIX_BIN}/php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null)"
    # 如果上面因为某些原因失败，回退到脚本里已有的 PHP_MAJOR_MINOR
    if [[ -z "$php_ver_short" && -n "${PHP_MAJOR_MINOR}" ]]; then
        php_ver_short="${PHP_MAJOR_MINOR}"
    fi

    log_info "准备为 PHP ${php_ver_short} 安装 ionCube / SourceGuardian Loader"

    # ==== 1. 处理 ionCube Loader ====
    local IONCUBE_TAR="${IONCUBE_TAR:-/usr/local/src/php-ext/ioncube_loaders_lin_x86-64.tar.gz}"
    local IONCUBE_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
    local IONCUBE_DIR="/usr/local/src/php-ext/ioncube"

    mkdir -p /usr/local/src/php-ext

    if [[ ! -f "$IONCUBE_TAR" ]]; then
        log_info "下载 ionCube Loader：$IONCUBE_URL -> $IONCUBE_TAR"
        if ! curl -L -o "$IONCUBE_TAR" "$IONCUBE_URL"; then
            log_notice "下载 ionCube Loader 失败：$IONCUBE_URL"
            echo "ioncube (download_failed)" >> "$PHP_FAILED_EXT_LOG"
            IONCUBE_TAR=""
        fi
    fi

    if [[ -n "$IONCUBE_TAR" ]]; then
        rm -rf "$IONCUBE_DIR"
        mkdir -p "$IONCUBE_DIR"
        if tar -xzf "$IONCUBE_TAR" -C "$IONCUBE_DIR" --strip-components=1; then
            local ic_file="${IONCUBE_DIR}/ioncube_loader_lin_${php_ver_short}.so"
            if [[ -f "$ic_file" ]]; then
                cp "$ic_file" "${ext_dir}/ioncube_loader.so"
                log_info "已为 PHP ${php_ver_short} 安装 ionCube Loader -> ${ext_dir}/ioncube_loader.so"
            else
                log_notice "未找到对应版本的 ionCube so：$ic_file"
                echo "ioncube (so_not_found_${php_ver_short})" >> "$PHP_FAILED_EXT_LOG"
            fi
        else
            log_notice "解压 ionCube Loader 失败：$IONCUBE_TAR"
            echo "ioncube (extract_failed)" >> "$PHP_FAILED_EXT_LOG"
        fi
    fi

    # ==== 2. 处理 SourceGuardian Loader ====
    local SG_TAR="${SOURCEGUARDIAN_TAR:-/usr/local/src/php-ext/loaders.linux-x86_64.tar.gz}"
    local SG_URL="https://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz"
    local SG_DIR="/usr/local/src/php-ext/sourceguardian"

    if [[ ! -f "$SG_TAR" ]]; then
        log_info "下载 SourceGuardian Loader：$SG_URL -> $SG_TAR"
        if ! curl -L -o "$SG_TAR" "$SG_URL"; then
            log_notice "下载 SourceGuardian Loader 失败：$SG_URL"
            echo "sourceguardian (download_failed)" >> "$PHP_FAILED_EXT_LOG"
            SG_TAR=""
        fi
    fi

    if [[ -n "$SG_TAR" ]]; then
        rm -rf "$SG_DIR"
        mkdir -p "$SG_DIR"
        if tar -xzf "$SG_TAR" -C "$SG_DIR"; then
            local sg_file="${SG_DIR}/ixed.${php_ver_short}.lin"
            if [[ -f "$sg_file" ]]; then
                cp "$sg_file" "${ext_dir}/ixed.so"
                log_info "已为 PHP ${php_ver_short} 安装 SourceGuardian Loader -> ${ext_dir}/ixed.so"
            else
                log_notice "未找到对应版本的 SourceGuardian：$sg_file"
                echo "sourceguardian (so_not_found_${php_ver_short})" >> "$PHP_FAILED_EXT_LOG"
            fi
        else
            log_notice "解压 SourceGuardian Loader 失败：$SG_TAR"
            echo "sourceguardian (extract_failed)" >> "$PHP_FAILED_EXT_LOG"
        fi
    fi

    # ==== 3. 写入 php.ini，确保 ionCube 是第一个配置块 ====
    if [[ -f "$php_ini" ]]; then
        cp "$php_ini" "${php_ini}.bak_loader_$(date +%F_%H%M%S)"

        # 先删掉旧的 loader 相关行
        sed -i '/ionCube Loader/d;/ioncube_loader\.so/d;/SourceGuardian/d;/ixed\.so/d' "$php_ini"

        local tmpfile
        tmpfile=$(mktemp)

        {
            echo "[ionCube Loader]"
            echo "zend_extension=${ext_dir}/ioncube_loader.so"
            echo
            echo "[SourceGuardian]"
            echo "extension=${ext_dir}/ixed.so"
            echo
            cat "$php_ini"
        } >"$tmpfile"

        mv "$tmpfile" "$php_ini"

        log_info "已自动写入 ionCube / SourceGuardian 配置到 ${php_ini}（ionCube 为首行）"
    else
        log_notice "未找到 php.ini：$php_ini，无法自动写入 Loader 配置"
    fi
}

###############################################
# 启动模块 4（增强：已装PHP/扩展/loader 三态决策）
###############################################

# 扫描 /usr/local 下已存在的 php 安装目录（兼容 /usr/local/php7.4 这类）
detect_installed_php_dirs() {
    local d
    PHP_INSTALLED_DIRS=()
    for d in /usr/local/php* /usr/local/php; do
        [[ -d "$d" && -x "$d/bin/php" ]] && PHP_INSTALLED_DIRS+=("$d")
    done
}

has_any_php_installed() {
    [[ ${#PHP_INSTALLED_DIRS[@]} -gt 0 ]]
}

# ===== 新增：列出检测到的 PHP 目录 =====
list_installed_php_dirs() {
    local d
    for d in "${PHP_INSTALLED_DIRS[@]}"; do
        echo "  - ${d} (php: ${d}/bin/php)"
    done
}

# 判断“扩展是否基本齐全”：用 php -m 判断（不改你现有扩展列表逻辑，只做兜底判定）
php_extensions_seem_installed() {
    local phpbin="$1"
    [[ -x "$phpbin" ]] || return 1

    # 这里挑你脚本里常见/关键扩展做“是否装过扩展体系”的判定
    # 注意：不是要求全部存在，而是判定“扩展安装流程是否跑过”
    local need_any=(redis imagick mysqli pdo_mysql mbstring gd zip intl)
    local mods
    mods="$("$phpbin" -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    local hit=0 x
    for x in "${need_any[@]}"; do
        if echo "$mods" | grep -q "^${x}$"; then
            hit=1
            break
        fi
    done

    [[ $hit -eq 1 ]]
}

# 判断 loader 是否已写入 php.ini（兼容你 install_closed_source_loaders 的写法）
php_loader_seem_configured() {
    local phpini="$1"
    [[ -f "$phpini" ]] || return 1
    grep -Eqi 'ioncube_loader\.so|zend_extension\s*=.*ioncube|sourceguardian|ixed\.so' "$phpini"
}

# 用户选择：B/C 场景要提示后执行
php_action_menu_when_exists() {
    echo
    yellow "检测到目标版本 PHP 已存在：${PHP_INSTALL_DIR}"
    echo "请选择接下来要做什么："
    echo "  A) 仅安装/修复扩展 + Loader（不重装 PHP，推荐）"
    echo "  B) 安装“另一个版本”PHP + 扩展 + Loader（共存，需要重新选择版本）"
    echo "  C) 重装当前版本（危险：将删除 ${PHP_INSTALL_DIR}）"
    echo "  0) 退出模块 4"
    read -r -p "请输入 A/B/C/0（默认 A）: " PHP_ACT
    PHP_ACT="${PHP_ACT:-A}"
}

}

###############################################
# run_module4(): 模块 4 顶层执行段封装（修复：避免脚本加载时直接运行）
###############################################
run_module4() {
log_info "开始执行模块 4：PHP 安装与扩展框架"

# 先扫描现有 PHP（用于提示与决策）
detect_installed_php_dirs

# 模块4控制变量（必须初始化，避免沿用上一次残留值）
SKIP_MODULE_4=0
INSTALL_PHP=0
PHP_VERSION=""
PHP_MAJOR_MINOR=""
PHP_INSTALL_DIR=""

# ========= 新入口逻辑：先检查系统是否已有 PHP =========
if [[ ${#PHP_INSTALLED_DIRS[@]} -gt 0 ]]; then
    echo
    yellow "检测到系统已安装 PHP："
    for _d in "${PHP_INSTALLED_DIRS[@]}"; do
        echo "  - ${_d} (php: ${_d}/bin/php)"
    done

    echo
    echo "请选择接下来要做什么："
    echo "  1) 管理/修复现有 PHP（选择一个版本后进入 A/B/C/0 菜单）"
    echo "  2) 安装新版本 PHP（共存，选择一个不同版本安装）"
    echo "  3) 跳过模块 4（不安装/不处理 PHP）"
    read -r -p "请输入 1-3（默认 1）: " PHP_ENTRY_CH
    PHP_ENTRY_CH="${PHP_ENTRY_CH:-1}"

    case "$PHP_ENTRY_CH" in
        1)
            # 只选版本（不再问是否安装）
            select_php_version_only
            INSTALL_PHP=1
            ;;
        2)
            # 只选版本（不再问是否安装）
            select_php_version_only
            INSTALL_PHP=1
            ;;
        3)
            log_info "已选择跳过模块 4"
            SKIP_MODULE_4=1
            ;;
        *)
            log_notice "输入无效，默认按 1 处理（管理/修复现有 PHP）"
            select_php_version_only
            INSTALL_PHP=1
            ;;
    esac
else
    # 系统没有 PHP，才询问是否安装
    select_php_version
    if [[ "${INSTALL_PHP}" != "1" ]]; then
        log_info "已选择不安装 PHP，跳过模块 4"
        SKIP_MODULE_4=1
    fi
fi

# ========= 关键兜底：跳过就直接不执行后续模块4逻辑 =========
if [[ "${SKIP_MODULE_4}" == "1" ]]; then
    log_info "模块 4 执行完成"
else
    # 兜底：必须在任何 download/compile 之前检查版本号
    if [[ -z "${PHP_VERSION}" ]]; then
        log_error "PHP_VERSION 为空，可能是未完成版本选择或逻辑分支漏设变量。中止模块 4。"
        exit 1
    fi
# 目标版本是否已存在
if is_php_installed; then
    php_action_menu_when_exists
    local_act="$PHP_ACT"

    case "$local_act" in
        A|a)
            # A：PHP 已安装，但扩展/loader 可能没装 -> 只跑扩展与 loader
            log_info "执行 A：仅安装/修复扩展 + Loader"
            # 确保 php.ini 路径存在（你脚本 generate_php_ini 是生成逻辑；这里不强制重生成）
            # 如果你脚本里 PHP_INI_PATH 有变量就用它，没有就按默认位置推断
            php_ini_guess="${PHP_INSTALL_DIR}/etc/php.ini"
            [[ -f "$php_ini_guess" ]] || php_ini_guess="/usr/local/php/etc/php.ini"

            # 只要能跑 php，就允许继续装扩展/loader
            if [[ -x "${PHP_INSTALL_DIR}/bin/php" ]]; then
                # 扩展没装过：跑扩展
                if php_extensions_seem_installed "${PHP_INSTALL_DIR}/bin/php"; then
                    log_info "检测到扩展体系已存在（php -m 命中关键扩展），仍会执行一次扩展安装以补齐缺失。"
                else
                    log_notice "检测到 PHP 已安装但扩展体系不完整，将执行扩展安装流程。"
                fi
                install_php_extensions
                # loader 没配置：跑 loader
                if php_loader_seem_configured "$php_ini_guess"; then
                    log_info "检测到 Loader 已配置（php.ini 已包含 ionCube/SourceGuardian 相关项），仍会执行一次 loader 安装以补齐缺失文件。"
                else
                    log_notice "检测到 Loader 未配置，将执行 Loader 安装与写入流程。"
                fi
                install_closed_source_loaders
            else
                log_error "找不到 ${PHP_INSTALL_DIR}/bin/php，无法继续。请检查目录是否完整。"
                exit 1
            fi
            ;;
        B|b)
            # B：用户要装新版本（共存）-> 重新走版本选择并走全新安装
            log_info "执行 B：安装另一个版本（共存）"
            log_info "请重新选择一个“不同版本”，随后将执行全新安装 + 扩展 + Loader"

            # 重新选择版本（你已确认 select_php_version_only 已存在）
            select_php_version_only

            if is_php_installed; then
                log_notice "你选择的版本仍然已存在：${PHP_INSTALL_DIR}，将按 A 执行仅扩展+Loader。"
                install_php_extensions
                install_closed_source_loaders
            else
                download_php_source || { log_error "PHP 源码未准备好，退出模块 4"; exit 1; }
                if [[ -f "${PHP_SRC_BASE}/php-${PHP_VERSION}.tar.gz" ]]; then
                    compile_php
                    generate_php_ini
                    generate_php_fpm_conf
                    create_php_fpm_service
                    install_php_extensions
                    install_closed_source_loaders
                else
                    log_error "未找到 php-${PHP_VERSION}.tar.gz，退出模块 4"
                    exit 1
                fi
            fi
            ;;
        C|c)
            # C：重装当前版本（危险）
            echo
            red "危险操作：将删除 ${PHP_INSTALL_DIR} 并重装当前版本。"
            read -r -p "确认重装？输入 YES 继续： " _yes
            if [[ "$_yes" != "YES" ]]; then
                log_info "已取消重装，退出模块 4"
                log_info "模块 4 执行完成"
            else
                rm -rf "${PHP_INSTALL_DIR}"
                download_php_source || { log_error "PHP 源码未准备好，退出模块 4"; exit 1; }
                if [[ -f "${PHP_SRC_BASE}/php-${PHP_VERSION}.tar.gz" ]]; then
                    compile_php
                    generate_php_ini
                    generate_php_fpm_conf
                    create_php_fpm_service
                    install_php_extensions
                    install_closed_source_loaders
                else
                    log_error "未找到 php-${PHP_VERSION}.tar.gz，退出模块 4"
                    exit 1
                fi
            fi
            ;;
        0)
            log_info "用户选择退出模块 4"
            ;;
        *)
            log_notice "输入无效，默认按 A 执行：仅扩展+Loader"
            install_php_extensions
            install_closed_source_loaders
            ;;
    esac

else
    # 没装目标版本：走全新安装
    download_php_source || { log_error "PHP 源码未准备好，退出模块 4"; exit 1; }

    if [[ -f "${PHP_SRC_BASE}/php-${PHP_VERSION}.tar.gz" ]]; then
        compile_php
        generate_php_ini
        generate_php_fpm_conf
        create_php_fpm_service
        install_php_extensions
        install_closed_source_loaders
    else
        log_error "未找到 php-${PHP_VERSION}.tar.gz，退出模块 4"
        exit 1
    fi
fi

log_info "模块 4 执行完成"
fi

###########################################
# LNMP Installer — Module 5
# MySQL 5.7–8.2 / MariaDB 10.6–10.11
# 二选一源码安装 + my.cnf + systemd + 初始化
###########################################

DB_SRC_BASE="${BASE_DIR}/dbsrc"
DB_DATA_DIR="/data/mysql"
MYSQL_INSTALL_DIR="/usr/local/mysql"
MARIADB_INSTALL_DIR="/usr/local/mariadb"

###############################################
# 选择数据库类型与版本
###############################################
select_db_type() {
    echo
    yellow "================ 数据库安装选项 ================"
    echo "1) 安装 MySQL"
    echo "2) 安装 MariaDB"
    echo "3) 不安装数据库"
    echo "==============================================="
    read -rp "请选择数据库类型 [1-3]：" db_choice

    case "$db_choice" in
        1)
            INSTALL_DB=1
            DB_TYPE="mysql"
            echo
            yellow "请选择 MySQL 版本："
            echo "1) 5.7.44  (推荐，最后一个 5.7 GA)"
            echo "2) 8.0.39"
            echo "3) 8.1.0"
            echo "4) 8.2.0"
            echo "5) 自定义输入（5.7–8.2 范围）"
            read -rp "请输入 [1-5]：" mysql_choice

            case "$mysql_choice" in
                1) MYSQL_VERSION="5.7.44" ;;
                2) MYSQL_VERSION="8.0.39" ;;
                3) MYSQL_VERSION="8.1.0" ;;
                4) MYSQL_VERSION="8.2.0" ;;
                5)
                    read -rp "请输入 MySQL 版本号（例如 5.7.44）：" MYSQL_VERSION
                    ;;
                *)
                    red "输入无效，默认使用 5.7.44"
                    MYSQL_VERSION="5.7.44"
                    ;;
            esac

            # 简单校验一下格式，防止输错
            if [[ ! "$MYSQL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                red "检测到 MySQL 版本格式不正确，回退到默认 5.7.44"
                MYSQL_VERSION="5.7.44"
            fi
            log_info "将安装 MySQL ${MYSQL_VERSION}"
            ;;

        2)
            INSTALL_DB=1
            DB_TYPE="mariadb"
            echo
            yellow "请选择 MariaDB 版本："
            echo "1) 10.6.18 (LTS，推荐)"
            echo "2) 10.9.8"
            echo "3) 10.10.7"
            echo "4) 10.11.6 (LTS)"
            echo "5) 自定义输入（10.6–10.11 范围）"
            read -rp "请输入 [1-5]：" maria_choice

            case "$maria_choice" in
                1) MARIADB_VERSION="10.6.18" ;;
                2) MARIADB_VERSION="10.9.8" ;;
                3) MARIADB_VERSION="10.10.7" ;;
                4) MARIADB_VERSION="10.11.6" ;;
                5)
                    read -rp "请输入 MariaDB 版本号（例如 10.11.6）：" MARIADB_VERSION
                    ;;
                *)
                    red "输入无效，默认使用 10.6.18"
                    MARIADB_VERSION="10.6.18"
                    ;;
            esac

            if [[ ! "$MARIADB_VERSION" =~ ^10\.[0-9]+\.[0-9]+$ ]]; then
                red "检测到 MariaDB 版本格式不正确，回退到默认 10.6.18"
                MARIADB_VERSION="10.6.18"
            fi
            log_info "将安装 MariaDB ${MARIADB_VERSION}"
            ;;

        3)
            INSTALL_DB=0
            DB_TYPE=""
            log_info "选择不安装数据库，将跳过模块 5"
            ;;

        *)
            red "无效选择，默认不安装数据库。"
            INSTALL_DB=0
            DB_TYPE=""
            ;;
    esac
}


###############################################
# 下载 MySQL 源码
###############################################
download_mysql_source() {
    mkdir -p "$DB_SRC_BASE"
    cd "$DB_SRC_BASE"

    local TAR="mysql-${MYSQL_VERSION}.tar.gz"
    local URL="https://downloads.mysql.com/archives/get/p/23/file/${TAR}"

    if [[ -f "$TAR" ]]; then
        log_info "MySQL 源码已存在：$TAR"
        return
    fi

    log_info "尝试下载 MySQL 源码：$URL"
    if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
        log_error "MySQL 源码下载失败：$URL"
        echo "$URL" >> /tmp/lnmp_download_failed.txt
        log_error "请手动将 ${TAR} 下载至 ${DB_SRC_BASE} 后重新执行脚本"
        return 1
    fi
}

###############################################
# 编译安装 MySQL
###############################################
compile_mysql() {
    log_info "开始编译 MySQL 源码..."

    if [ -z "${MYSQL_VERSION}" ]; then
        log_error "MYSQL_VERSION 变量为空，无法继续编译。"
        return 1
    fi

    mkdir -p "${DB_SRC_BASE}"
    cd "${DB_SRC_BASE}" || {
        log_error "进入 ${DB_SRC_BASE} 失败。"
        return 1
    }

    # 保守一点：只删除同版本目录，不乱删别的源码
    rm -rf "mysql-${MYSQL_VERSION}"

    if [ ! -f "mysql-${MYSQL_VERSION}.tar.gz" ]; then
        log_error "未找到源码包 mysql-${MYSQL_VERSION}.tar.gz，请先执行下载步骤。"
        return 1
    fi

    if ! tar xf "mysql-${MYSQL_VERSION}.tar.gz"; then
        log_error "解压 mysql-${MYSQL_VERSION}.tar.gz 失败，终止 MySQL 编译。"
        return 1
    fi

    cd "mysql-${MYSQL_VERSION}" || {
        log_error "进入 mysql-${MYSQL_VERSION} 目录失败。"
        return 1
    }

    mkdir -p build
    cd build || {
        log_error "进入 mysql-${MYSQL_VERSION}/build 目录失败。"
        return 1
    }

    CPU_CORES=$(nproc 2>/dev/null || echo 1)
    log_info "使用 CPU 核心数：${CPU_CORES}"

    # 关键改动：增加 DOWNLOAD_BOOST，使用绝对路径 ${DB_SRC_BASE}/boost
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=${MYSQL_INSTALL_DIR} \
        -DMYSQL_DATADIR=${DB_DATA_DIR} \
        -DSYSCONFDIR=/etc \
        -DWITH_INNOBASE_STORAGE_ENGINE=1 \
        -DWITH_PARTITION_STORAGE_ENGINE=1 \
        -DWITH_FEDERATED_STORAGE_ENGINE=1 \
        -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
        -DWITH_ARCHIVE_STORAGE_ENGINE=1 \
        -DWITH_READLINE=1 \
        -DENABLED_LOCAL_INFILE=1 \
        -DMYSQL_UNIX_ADDR=/tmp/mysql.sock \
        -DMYSQL_TCP_PORT=3306 \
        -DWITH_SSL=system \
        -DWITH_ZLIB=system \
        -DDOWNLOAD_BOOST=1 \
        -DWITH_BOOST=${DB_SRC_BASE}/boost \
        -DWITH_EMBEDDED_SERVER=OFF \
        -DWITH_DEBUG=0

    if [ $? -ne 0 ]; then
        log_error "CMake 配置 MySQL 失败（Boost 或依赖有问题），终止 MySQL 安装。"
        return 1
    fi

    # 编译阶段增加失败判断
    if ! make -j"${CPU_CORES}"; then
        log_notice "MySQL 并行编译失败，尝试单线程编译..."
        if ! make; then
            log_error "MySQL 编译失败，请检查上面的错误信息。"
            return 1
        fi
    fi

    if ! make install; then
        log_error "MySQL make install 失败，请检查上面的错误信息。"
        return 1
    fi

    log_info "MySQL 安装完成：${MYSQL_INSTALL_DIR}"

    # 创建常用软链接
    ln -sf "${MYSQL_INSTALL_DIR}/bin/mysql" /usr/bin/mysql
    ln -sf "${MYSQL_INSTALL_DIR}/bin/mysqladmin" /usr/bin/mysqladmin
    ln -sf "${MYSQL_INSTALL_DIR}/bin/mysqldump" /usr/bin/mysqldump

    return 0
}

###############################################
# 下载 MariaDB 源码
###############################################
download_mariadb_source() {
    mkdir -p "$DB_SRC_BASE"
    cd "$DB_SRC_BASE"

    local TAR="mariadb-${MARIADB_VERSION}.tar.gz"
    local URL="https://archive.mariadb.org/mariadb-${MARIADB_VERSION}/source/${TAR}"

    if [[ -f "$TAR" ]]; then
        log_info "MariaDB 源码已存在：$TAR"
        return
    fi

    log_info "尝试下载 MariaDB 源码：$URL"
    if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
        log_error "MariaDB 源码下载失败：$URL"
        echo "$URL" >> /tmp/lnmp_download_failed.txt
        log_error "请手动将 ${TAR} 下载至 ${DB_SRC_BASE} 后重新执行脚本"
        return 1
    fi
}

###############################################
# 编译安装 MariaDB
###############################################
compile_mariadb() {
    cd "$DB_SRC_BASE"
    tar xf "mariadb-${MARIADB_VERSION}.tar.gz"
    cd "mariadb-${MARIADB_VERSION}"

    mkdir -p build
    cd build

    cmake .. \
        -DCMAKE_INSTALL_PREFIX=${MARIADB_INSTALL_DIR} \
        -DMYSQL_DATADIR=${DB_DATA_DIR} \
        -DSYSCONFDIR=/etc \
        -DWITH_INNOBASE_STORAGE_ENGINE=1 \
        -DWITH_PARTITION_STORAGE_ENGINE=1 \
        -DWITH_FEDERATEDX_STORAGE_ENGINE=1 \
        -DWITH_ARCHIVE_STORAGE_ENGINE=1 \
        -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
        -DWITH_ARIA_STORAGE_ENGINE=1 \
        -DENABLED_LOCAL_INFILE=1 \
        -DWITH_SSL=system \
        -DWITH_ZLIB=system \
        -DWITH_EMBEDDED_SERVER=OFF \
        -DWITH_DEBUG=0

    make -j"$(nproc)"
    make install

    log_info "MariaDB 安装完成：${MARIADB_INSTALL_DIR}"

    ln -sf ${MARIADB_INSTALL_DIR}/bin/mysql /usr/bin/mysql
    ln -sf ${MARIADB_INSTALL_DIR}/bin/mysqldump /usr/bin/mysqldump
}

###############################################
# 生成 my.cnf（通用配置）
###############################################
generate_my_cnf() {
    mkdir -p /etc

    cat >/etc/my.cnf <<EOF
[client]
port = 3306
socket = /tmp/mysql.sock

[mysql]
prompt="\\u@\\h [\\d]> "
default_character_set = utf8mb4

[mysqld]
user = mysql
port = 3306
basedir = ${1}
datadir = ${DB_DATA_DIR}
socket = /tmp/mysql.sock
pid-file = ${DB_DATA_DIR}/mysql.pid

character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
skip-name-resolve = 1

max_connections = 500
max_connect_errors = 1000000
open_files_limit = 65535
table_open_cache = 2048

innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
innodb_file_per_table = 1
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = 1

slow_query_log = 1
slow_query_log_file = ${DB_DATA_DIR}/mysql-slow.log
long_query_time = 1

log-error = ${DB_DATA_DIR}/mysql-error.log

[mysql.server]
basedir = ${1}
datadir = ${DB_DATA_DIR}
EOF

    log_info "my.cnf 生成完成：/etc/my.cnf"
}

###############################################
# 初始化数据目录与 root 密码
###############################################
init_mysql_data() {
    mkdir -p "${DB_DATA_DIR}"
    chown -R mysql:mysql "${DB_DATA_DIR}"

if [[ -n "$(ls -A "${DB_DATA_DIR}" 2>/dev/null)" ]]; then
    log_notice "检测到数据目录非空：${DB_DATA_DIR}"
    log_notice "MySQL --initialize 要求 datadir 必须为空，否则会直接失败。"
    log_notice "请确认 ${DB_DATA_DIR} 内没有重要数据（否则请先备份）。"
    echo
    echo "请选择处理方式："
    echo "  1) 清理数据目录并继续（危险：会删除 ${DB_DATA_DIR} 下所有文件）"
    echo "  2) 退出脚本，我手动处理（推荐）"
    read -r -p "请输入 1 或 2（默认 2）: " _choice
    _choice="${_choice:-2}"

    case "${_choice}" in
        1)
            log_notice "你选择了清理：rm -rf ${DB_DATA_DIR}/*"
            rm -rf "${DB_DATA_DIR:?}/"* || {
                log_error "清理失败，请检查权限或文件占用后重试。"
                exit 1
            }
            # 再次确认确实为空
            if [[ -n "$(ls -A "${DB_DATA_DIR}" 2>/dev/null)" ]]; then
                log_error "清理后数据目录仍非空：${DB_DATA_DIR}，请手动检查后再执行脚本。"
                exit 1
            fi
            log_info "数据目录已清理，继续执行初始化..."
            ;;
        2|*)
            log_notice "你选择了退出脚本，请手动处理数据目录后再重跑："
            log_notice "为避免误删，已建议你先备份：mv ${DB_DATA_DIR} ${bk} && mkdir -p ${DB_DATA_DIR}"
            log_notice "  - 备份后清空：rm -rf ${DB_DATA_DIR}/*"
            log_notice "  - 或更换 datadir 后再初始化"
            exit 1
            ;;
    esac
fi
    log_info "初始化 MySQL 数据目录..."

    # 用 tee 落盘，避免“看不到输出 / 空日志”
    : > /root/mysql_init.log
    (
        set -o pipefail
        ${MYSQL_INSTALL_DIR}/bin/mysqld \
            --defaults-file=/etc/my.cnf \
            --initialize \
            --user=mysql \
            --basedir="${MYSQL_INSTALL_DIR}" \
            --datadir="${DB_DATA_DIR}" 2>&1 | tee -a /root/mysql_init.log
    )
    local init_rc=$?

    if [[ $init_rc -ne 0 ]]; then
        log_error "mysqld --initialize 初始化失败（exit=$init_rc）"
        log_error "请优先查看："
        log_error "  1) /root/mysql_init.log"
        log_error "  2) ${DB_DATA_DIR}/mysql-error.log（若 my.cnf 配置了 log-error）"
        log_error "  3) ${DB_DATA_DIR}/*.err（MySQL 默认错误日志）"
        return 1
    fi

    # ====== 临时密码提取：多路径兜底 ======
    local candidates=()
    [[ -f /root/mysql_init.log ]] && candidates+=(/root/mysql_init.log)
    [[ -f "${DB_DATA_DIR}/mysql-error.log" ]] && candidates+=("${DB_DATA_DIR}/mysql-error.log")
    local errfiles
    errfiles=$(ls -1 "${DB_DATA_DIR}"/*.err 2>/dev/null | head -n 5 || true)
    if [[ -n "$errfiles" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && candidates+=("$f")
        done <<< "$errfiles"
    fi

    local TMPPASS=""
    if (( ${#candidates[@]} > 0 )); then
        TMPPASS=$(grep -hE "temporary password|A temporary password is generated for" "${candidates[@]}" 2>/dev/null \
            | tail -n 1 | awk '{print $NF}')
    fi

    if [[ -z "$TMPPASS" ]]; then
        log_error "初始化成功，但未能从日志中提取到临时 root 密码。"
        log_error "请在以下文件中搜索关键字：temporary password"
        for f in "${candidates[@]}"; do
            log_error "  - ${f}"
        done
        echo "" > /root/mysql_root_temp_password.txt
        return 1
    fi

    echo "$TMPPASS" > /root/mysql_root_temp_password.txt
    chmod 600 /root/mysql_root_temp_password.txt
    log_notice "修改初始密码为自定义密码，请根据提示操作！"
}

###############################################
# 创建 MySQL / MariaDB systemd 服务
###############################################
create_mysql_service() {
    cat >/etc/systemd/system/mysqld.service <<EOF
[Unit]
Description=MySQL Server
After=network.target
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=mysql
Group=mysql
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf --basedir=/usr/local/mysql --datadir=/data/mysql --user=mysql
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=3
TimeoutStartSec=300
TimeoutStopSec=300
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mysqld
    systemctl start mysqld

    log_info "MySQL systemd 服务已创建并启动：mysqld.service"
}

create_mariadb_service() {
    cat >/etc/systemd/system/mariadb.service <<EOF
[Unit]
Description=MariaDB Server
After=network.target

[Service]
Type=forking
ExecStart=${MARIADB_INSTALL_DIR}/bin/mysqld_safe --defaults-file=/etc/my.cnf
ExecStop=/bin/kill -TERM \$MAINPID
LimitNOFILE=65535
Restart=on-failure
RestartPreventExitStatus=1

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mariadb
    systemctl start mariadb

    log_info "MariaDB systemd 服务已创建并启动：mariadb.service"
}

###############################################
# 启动模块 5：MySQL / MariaDB 安装
###############################################
###############################################
# MySQL root 登录校验 + 自动救援重置（只保留这一套）
###############################################

# 统一 mysql 客户端：强制走 socket（避免 TCP/权限/解析差异）
mysql_cli() {
  local sock="${MYSQL_SOCKET:-/tmp/mysql.sock}"
  /usr/local/mysql/bin/mysql --protocol=socket -S "$sock" "$@"
}

# 仅等待 socket 文件出现（不做 SELECT 1，避免 expired 导致误判）
wait_mysql_socket_ready() {
  local sock="$1"
  local timeout="${2:-120}"
  local i
  for i in $(seq 1 "$timeout"); do
    [[ -S "$sock" ]] && return 0
    sleep 1
  done
  return 1
}

read_tmp_mysql_pass() {
  local f="/root/mysql_root_temp_password.txt"
  [[ -s "$f" ]] || { echo ""; return 1; }
  tr -d '\r\n' < "$f"
}

prompt_new_mysql_root_pass() {
  local p1 p2
  while true; do
    read -r -s -p "请输入要设置的 MySQL root 新密码: " p1; echo
    read -r -s -p "请再次输入确认: " p2; echo

    if [[ -z "$p1" || "$p1" != "$p2" ]]; then
      echo "[WARN] 两次输入不一致或为空，请重试。"
      continue
    fi
    if [[ "$p1" == *"'"* ]]; then
      echo "[WARN] 密码中包含单引号 ' ，会导致 SQL 解析失败。请换一个不含单引号的密码。"
      continue
    fi

    MYSQL_ROOT_NEW_PASS="$p1"
    return 0
  done
}

# 用临时密码直接改新密码（不再先 SELECT 1 判断，否则会被 expired 误判）
set_root_pass_with_tmp_pass() {
  local tmp_pass="$1"
  local new_pass="$2"

  MYSQL_SOCKET="/tmp/mysql.sock" \
    mysql_cli -uroot -p"$tmp_pass" --connect-expired-password \
      -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${new_pass}';
          ALTER USER 'root'@'localhost' PASSWORD EXPIRE NEVER;
          FLUSH PRIVILEGES;" >/dev/null 2>&1
}

# 救援：skip-grant-tables + 独立 rescue.sock（port=0，不占 3306）
rescue_reset_root_pass_skip_grants() {
  local new_pass="$1"
  local old_sock="${MYSQL_SOCKET:-/tmp/mysql.sock}"

  log_notice "临时密码无法登录（或为空），进入救援模式 skip-grant-tables 重置 root..."

  # 1) 尽量停干净，避免 ibdata1 lock (error:11)
  systemctl stop mysqld >/dev/null 2>&1 || true
  pkill -9 -u mysql mysqld mysqld_safe 2>/dev/null || true
  pkill -9 mysqld mysqld_safe 2>/dev/null || true
  sleep 1

  rm -f /tmp/mysql-rescue.pid /tmp/mysql-rescue.sock /tmp/mysql-rescue.err >/dev/null 2>&1 || true

  # 2) 直起救援实例
  /usr/local/mysql/bin/mysqld \
    --defaults-file=/etc/my.cnf \
    --user=mysql \
    --skip-grant-tables \
    --skip-networking \
    --datadir="${DB_DATA_DIR:-/data/mysql}" \
    --socket=/tmp/mysql-rescue.sock \
    --pid-file=/tmp/mysql-rescue.pid \
    --port=0 \
    --log-error=/tmp/mysql-rescue.err \
    --basedir=/usr/local/mysql >/dev/null 2>&1 &

  wait_mysql_socket_ready "/tmp/mysql-rescue.sock" 120 || {
    log_error "救援实例未能启动：/tmp/mysql-rescue.sock 不存在"
    tail -n 200 /tmp/mysql-rescue.err 2>/dev/null || true
    MYSQL_SOCKET="$old_sock"
    return 1
  }

  MYSQL_SOCKET="/tmp/mysql-rescue.sock"

  local ver
  ver="$(/usr/local/mysql/bin/mysqld --version 2>/dev/null | head -n1)"
  log_info "检测 mysqld 版本：$ver"

  # 3) 执行重置（注意：不要用不存在的 --skip-password）
  if echo "$ver" | grep -q "Ver 5\.7"; then
    mysql_cli -uroot -e "FLUSH PRIVILEGES;
      UPDATE mysql.user
        SET plugin='mysql_native_password',
            authentication_string=PASSWORD('${new_pass}'),
            password_expired='N'
      WHERE User='root' AND Host IN ('localhost','127.0.0.1','::1','%');
      FLUSH PRIVILEGES;" >/dev/null 2>&1 || {
        log_error "救援 SQL 执行失败（5.7），请查看 /tmp/mysql-rescue.err"
        tail -n 200 /tmp/mysql-rescue.err 2>/dev/null || true
        MYSQL_SOCKET="$old_sock"
        return 1
      }
  else
    mysql_cli -uroot -e "FLUSH PRIVILEGES;
      ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${new_pass}';
      ALTER USER 'root'@'localhost' PASSWORD EXPIRE NEVER;
      FLUSH PRIVILEGES;" >/dev/null 2>&1 || {
        log_error "救援 SQL 执行失败（非 5.7），请查看 /tmp/mysql-rescue.err"
        tail -n 200 /tmp/mysql-rescue.err 2>/dev/null || true
        MYSQL_SOCKET="$old_sock"
        return 1
      }
  fi

  # 4) 关闭救援实例，确保 pid 退出（杜绝 ibdata1 lock）
  mysql_cli -uroot -e "SHUTDOWN;" >/dev/null 2>&1 || true
  local rp=""
  rp="$(cat /tmp/mysql-rescue.pid 2>/dev/null || true)"
  local i
  for i in $(seq 1 40); do
    [[ -n "$rp" ]] && kill -0 "$rp" 2>/dev/null || break
    sleep 1
  done
  [[ -n "$rp" ]] && kill -9 "$rp" >/dev/null 2>&1 || true
  rm -f /tmp/mysql-rescue.pid /tmp/mysql-rescue.sock >/dev/null 2>&1 || true

  MYSQL_SOCKET="$old_sock"
  return 0
}

# 总入口：确保 root 最终可用（必须在模块6前完成）
ensure_mysql_root_access() {
  local tmp_pass new_pass

  tmp_pass="$(read_tmp_mysql_pass || true)"
  prompt_new_mysql_root_pass
  new_pass="$MYSQL_ROOT_NEW_PASS"

  # 确保 mysqld 正常实例 socket 存在（避免服务没起来就改密码）
  wait_mysql_socket_ready "/tmp/mysql.sock" 120 || {
    log_error "mysqld 未就绪：/tmp/mysql.sock 不存在"
    return 1
  }

  # 1) 有临时密码：直接尝试用临时密码改新密码（不做 SELECT 1 预判）
  if [[ -n "$tmp_pass" ]] && set_root_pass_with_tmp_pass "$tmp_pass" "$new_pass"; then
    :
  else
    # 2) 临时密码不可用：救援兜底
    rescue_reset_root_pass_skip_grants "$new_pass" || return 1

    # 救援后要把正常 mysqld 拉起来
    systemctl restart mysqld >/dev/null 2>&1 || systemctl start mysqld >/dev/null 2>&1 || true
    wait_mysql_socket_ready "/tmp/mysql.sock" 120 || {
      log_error "救援后 mysqld 未就绪：/tmp/mysql.sock 不存在"
      return 1
    }
  fi

  # 3) 最终校验：用新密码登录（允许 connect-expired-password）
  MYSQL_SOCKET="/tmp/mysql.sock" \
    mysql_cli -uroot -p"$new_pass" --connect-expired-password -e "SELECT 1;" >/dev/null 2>&1
}

log_info "==============================================="
}

###############################################
# run_module5(): 模块 5 顶层执行段封装（修复：避免脚本加载时直接运行）
###############################################
run_module5() {
# ===== 预检查：已安装数据库则默认跳过（不再先询问菜单）=====
if is_mysql_installed; then
    echo
    log_notice "检测到 MySQL 已安装（/usr/local/mysql），默认跳过模块 5。"
    /usr/local/mysql/bin/mysql --version 2>/dev/null || true
    if [[ "${FORCE_DB_MENU:-0}" != "1" ]]; then
        return 0
    fi
    log_warn "FORCE_DB_MENU=1 已开启，将进入数据库安装菜单（可能覆盖现有安装）。"
elif is_mariadb_installed; then
    echo
    log_notice "检测到 MariaDB 已安装（/usr/local/mariadb），默认跳过模块 5。"
    /usr/local/mariadb/bin/mysql --version 2>/dev/null || true
    if [[ "${FORCE_DB_MENU:-0}" != "1" ]]; then
        return 0
    fi
    log_warn "FORCE_DB_MENU=1 已开启，将进入数据库安装菜单（可能覆盖现有安装）。"
elif command -v mariadb >/dev/null 2>&1 || (command -v mysql >/dev/null 2>&1 && mysql --version 2>/dev/null | grep -qi "mariadb"); then
    echo
    log_notice "检测到系统包 MariaDB 已安装，默认跳过模块 5。"
    mariadb --version 2>/dev/null || mysql --version 2>/dev/null || true
    if [[ "${FORCE_DB_MENU:-0}" != "1" ]]; then
        return 0
    fi
    log_warn "FORCE_DB_MENU=1 已开启，将进入数据库安装菜单（可能覆盖现有安装）。"
fi


log_info "开始执行模块 5：数据库安装（MySQL / MariaDB）"
log_info "==============================================="

select_db_type

if [[ "$INSTALL_DB" == "3" ]]; then
    log_info "选择：不安装数据库，跳过模块 5。"
else
    if [[ "$DB_TYPE" == "mysql" ]]; then
        if is_mysql_installed; then
            log_notice "检测到 MySQL 已安装（/usr/local/mysql/bin/mysqld），本次跳过 MySQL 安装。"
            log_notice "如需重装，请备份或删除 /usr/local/mysql 后再单独重跑模块 5。"
        else
            log_info "选择安装 MySQL，开始下载与编译..."

            # 先尝试下载源码
            if ! download_mysql_source; then
                log_error "MySQL 源码下载失败，请根据上方错误检查网络、代理或下载地址。"
                log_error "本次跳过 MySQL 安装、初始化和 systemd 配置。"
            else
                # 下载成功再尝试编译
                if ! compile_mysql; then
                    log_error "MySQL 编译/安装失败，已跳过初始化和 systemd 配置。"
                    log_error "请根据上方 CMake/make 错误信息（如 Boost、libtirpc 等依赖）处理后，重新执行模块 5。"
                else
                    # 只有编译成功才继续生成配置和初始化
                     generate_my_cnf "${MYSQL_INSTALL_DIR}"
                if ! init_mysql_data; then
                     log_error "[FATAL] MySQL 初始化失败，终止脚本（避免后续模块在未初始化的数据库上继续运行）"
                     exit 1
                fi

                if ! create_mysql_service; then
                     log_error "[FATAL] MySQL systemd 服务创建/启动失败，终止脚本"
                     exit 1
                fi
                if ! ensure_mysql_root_access; then
                log_error "[FATAL] MySQL root 密码设置失败，终止脚本（避免模块6继续跑）"
                 exit 1
                fi
                log_info "MySQL 安装及初始化完成。"
                install -m 600 -o root -g root /dev/null /root/mysql_root_new_password.txt 2>/dev/null || true
                printf '%s\n' "${MYSQL_ROOT_NEW_PASS}" > /root/mysql_root_new_password.txt
                chmod 600 /root/mysql_root_new_password.txt
                log_info "MySQL root 新密码已保存：/root/mysql_root_new_password.txt（权限 600）"

                fi
            fi
        fi

    elif [[ "$DB_TYPE" == "mariadb" ]]; then
        if is_mariadb_installed; then
            log_notice "检测到 MariaDB 已安装（/usr/local/mariadb/bin/mysqld），本次跳过 MariaDB 安装。"
            log_notice "如需重装，请备份或删除 /usr/local/mariadb 后再单独重跑模块 5。"
        else
            log_info "选择安装 MariaDB，开始下载与编译..."

            if ! download_mariadb_source; then
                log_error "MariaDB 源码下载失败，请检查网络、代理或下载地址。"
                log_error "本次跳过 MariaDB 安装、初始化和 systemd 配置。"
            elif [[ ! -f \"${DB_SRC_BASE}/mariadb-${MARIADB_VERSION}.tar.gz\" ]]; then
                log_error "未找到 mariadb-${MARIADB_VERSION}.tar.gz，无法继续 MariaDB 安装。"
            else
                if ! compile_mariadb; then
                    log_error "MariaDB 编译/安装失败，已跳过初始化和 systemd 配置。"
                    log_error "请根据上方 CMake/make 错误信息处理后，重新执行模块 5。"
                else
                    generate_my_cnf \"${MARIADB_INSTALL_DIR}\"
                    if ! id mysql >/dev/null 2>&1; then
                        useradd -r -s /sbin/nologin mysql
                    fi
                    init_mariadb_data
                    create_mariadb_service
                    log_info "MariaDB 安装及初始化完成。"
                fi
            fi
        fi
    fi
fi

log_info "数据库安装执行完成"

###########################################
# LNMP Installer — Module 6
# Redis / Memcached / Pure-FTPD / Node.js / phpMyAdmin
###########################################

REDIS_SRC_BASE="${BASE_DIR}/redis"
REDIS_INSTALL_DIR="/usr/local/redis"

MEMCACHED_SRC_BASE="${BASE_DIR}/memcached"
MEMCACHED_INSTALL_DIR="/usr/local/memcached"

PUREFTPD_SRC_BASE="${BASE_DIR}/pureftpd"
PUREFTPD_INSTALL_DIR="/usr/local/pureftpd"

PHPMYADMIN_SRC_BASE="${BASE_DIR}/phpmyadmin"
PHPMYADMIN_WEBROOT="/data/wwwroot/default/phpmyadmin"

###############################################
# 选择可选组件
###############################################
select_optional_components() {
    echo
    yellow "可选组件安装选择："

    echo "是否安装 Redis？"
    echo "1) 安装"
    echo "2) 不安装"
    read -p "输入 1-2: " REDIS_CH
    [[ "$REDIS_CH" == "1" ]] && INSTALL_REDIS=1 || INSTALL_REDIS=0

    echo
    echo "是否安装 Memcached？"
    echo "1) 安装"
    echo "2) 不安装"
    read -p "输入 1-2: " MEMCACHED_CH
    [[ "$MEMCACHED_CH" == "1" ]] && INSTALL_MEMCACHED=1 || INSTALL_MEMCACHED=0

    echo
    echo "是否安装 Pure-FTPD？（源码编译）"
    echo "1) 安装"
    echo "2) 不安装"
    read -p "输入 1-2: " PFTPD_CH
    [[ "$PFTPD_CH" == "1" ]] && INSTALL_PUREFTPD=1 || INSTALL_PUREFTPD=0

    echo
    echo "是否安装 Node.js（APT）？"
    echo "1) 安装"
    echo "2) 不安装"
    read -p "输入 1-2: " NODE_CH
    [[ "$NODE_CH" == "1" ]] && INSTALL_NODEJS=1 || INSTALL_NODEJS=0

    echo
    echo "是否安装 phpMyAdmin？"
    echo "1) 安装"
    echo "2) 不安装"
    read -p "输入 1-2: " PHPMYADMIN_CH
    [[ "$PHPMYADMIN_CH" == "1" ]] && INSTALL_PHPMYADMIN=1 || INSTALL_PHPMYADMIN=0
}

###############################################
# 安装 Redis（源码）
###############################################
install_redis() {
    log_info "开始安装 Redis（源码）"

    mkdir -p "$REDIS_SRC_BASE"
    cd "$REDIS_SRC_BASE"

    # 默认选择一个较新的稳定版本，你可以按需修改
    local REDIS_VER="7.2.5"
    local TAR="redis-${REDIS_VER}.tar.gz"
    local URL="https://download.redis.io/releases/${TAR}"

    if [[ ! -f "$TAR" ]]; then
        log_info "下载 Redis：$URL"
        if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
            log_error "Redis 下载失败：$URL"
            echo "$URL" >> /tmp/lnmp_download_failed.txt
            return
        fi
    else
        log_info "Redis 源码包已存在：$TAR"
    fi

    rm -rf "redis-${REDIS_VER}"
    tar xf "$TAR"
    cd "redis-${REDIS_VER}"

    make -j"$(nproc)"
    make PREFIX="${REDIS_INSTALL_DIR}" install

    mkdir -p /etc/redis
    mkdir -p /data/redis
    cp redis.conf /etc/redis/redis.conf

    sed -i 's#^dir .*#dir /data/redis#' /etc/redis/redis.conf
    sed -i 's/^supervised .*/supervised systemd/' /etc/redis/redis.conf
    sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf

    cat >/etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
Type=simple
ExecStart=${REDIS_INSTALL_DIR}/bin/redis-server /etc/redis/redis.conf
ExecStop=${REDIS_INSTALL_DIR}/bin/redis-cli shutdown nosave
User=www
Group=www
Restart=on-failure
RestartSec=2
TimeoutStartSec=60
TimeoutStopSec=60
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redis
    systemctl restart redis

    log_info "Redis 安装完成，使用 systemd 管理：redis.service"
}

###############################################
# 安装 Memcached（源码）
###############################################
install_memcached() {
    log_info "开始安装 Memcached（源码）"

    mkdir -p "$MEMCACHED_SRC_BASE"
    cd "$MEMCACHED_SRC_BASE"

    local MEMCACHED_VER="1.6.27"
    local TAR="memcached-${MEMCACHED_VER}.tar.gz"
    local URL="https://memcached.org/files/${TAR}"

    if [[ ! -f "$TAR" ]]; then
        log_info "下载 Memcached：$URL"
        if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
            log_error "Memcached 下载失败：$URL"
            echo "$URL" >> /tmp/lnmp_download_failed.txt
            return
        fi
    else
        log_info "Memcached 源码包已存在：$TAR"
    fi

    rm -rf "memcached-${MEMCACHED_VER}"
    tar xf "$TAR"
    cd "memcached-${MEMCACHED_VER}"

    ./configure --prefix="${MEMCACHED_INSTALL_DIR}"
    make -j"$(nproc)"
    make install

    cat >/etc/systemd/system/memcached.service <<EOF
[Unit]
Description=Memcached
After=network.target

[Service]
ExecStart=${MEMCACHED_INSTALL_DIR}/bin/memcached -u www -m 128 -p 11211 -c 1024
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable memcached
    systemctl restart memcached

    log_info "Memcached 安装完成，使用 systemd 管理：memcached.service"
}

###############################################
# 安装 Pure-FTPD（源码）
###############################################
install_pureftpd() {
    log_info "开始安装 Pure-FTPD（源码）"

    mkdir -p "$PUREFTPD_SRC_BASE"
    cd "$PUREFTPD_SRC_BASE"

    local PFTPD_VER="1.0.51"
    local TAR="pure-ftpd-${PFTPD_VER}.tar.gz"
    local URL="https://download.pureftpd.org/pub/pure-ftpd/releases/${TAR}"

    if [[ ! -f "$TAR" ]]; then
        log_info "下载 Pure-FTPD：$URL"
        if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
            log_error "Pure-FTPD 下载失败：$URL"
            echo "$URL" >> /tmp/lnmp_download_failed.txt
            return
        fi
    else
        log_info "Pure-FTPD 源码包已存在：$TAR"
    fi

    rm -rf "pure-ftpd-${PFTPD_VER}"
    tar xf "$TAR"
    cd "pure-ftpd-${PFTPD_VER}"

    ./configure \
        --prefix="${PUREFTPD_INSTALL_DIR}" \
        --with-puredb \
        --with-tls

    make -j"$(nproc)"
    make install

    mkdir -p /etc/pure-ftpd
    cat >/etc/pure-ftpd/pure-ftpd.conf <<EOF
ChrootEveryone              yes
BrokenClientsCompatibility  no
MaxClientsNumber            50
Daemonize                   no
MaxClientsPerIP             5
VerboseLog                  no
DisplayDotFiles             yes
AnonymousOnly               no
NoAnonymous                 yes
SyslogFacility              ftp
DontResolve                 yes
EOF

    cat >/etc/systemd/system/pure-ftpd.service <<EOF
[Unit]
Description=Pure-FTPd FTP server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/pureftpd/sbin/pure-ftpd -c 50 -C 5 -l unix -E -j -R -P 127.0.0.1 -p 30000:31000
Restart=on-failure
RestartSec=2
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target

EOF

    systemctl daemon-reload
    systemctl enable pure-ftpd
    systemctl restart pure-ftpd

    log_info "Pure-FTPD 安装完成，使用 systemd 管理：pure-ftpd.service"
}

###############################################
# 安装 Node.js（APT）
###############################################
install_nodejs() {
    log_info "开始安装 Node.js（APT）"
    apt update
    apt install -y nodejs npm
    log_info "Node.js 安装完成：$(node --version 2>/dev/null)"
}

###############################################
# 安装 phpMyAdmin
###############################################
install_phpmyadmin() {
    log_info "开始安装 phpMyAdmin"

    mkdir -p "$PHPMYADMIN_SRC_BASE"
    cd "$PHPMYADMIN_SRC_BASE"

    # 默认使用一个较新的版本（可按需修改）
    local PMA_VER="5.2.1"
    local TAR="phpMyAdmin-${PMA_VER}-all-languages.tar.gz"
    local URL="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/${TAR}"

    if [[ ! -f "$TAR" ]]; then
        log_info "下载 phpMyAdmin：$URL"
        if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
            log_error "phpMyAdmin 下载失败：$URL"
            echo "$URL" >> /tmp/lnmp_download_failed.txt
            return
        fi
    else
        log_info "phpMyAdmin 源码包已存在：$TAR"
    fi

    rm -rf "$PHPMYADMIN_WEBROOT"
    mkdir -p "$PHPMYADMIN_WEBROOT"

    tar xf "$TAR" -C "$PHPMYADMIN_WEBROOT" --strip-components=1

    chown -R www:www "$PHPMYADMIN_WEBROOT"

    # 配置基础 config.inc.php（生成随机 blowfish secret）
    local BLOWFISH=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

    cat >"${PHPMYADMIN_WEBROOT}/config.inc.php" <<EOF
<?php
\$cfg['blowfish_secret'] = '${BLOWFISH}';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = '127.0.0.1';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
EOF

    # 询问是否使用 BasicAuth 保护
    echo
    yellow "是否为 phpMyAdmin 启用 BasicAuth 保护？"
    echo "1) 启用（推荐）"
    echo "2) 不启用"
    read -p "输入 1-2: " PMA_AUTH_CH

    if [[ "$PMA_AUTH_CH" == "1" ]]; then
        apt install -y apache2-utils

        local HTFILE="/usr/local/nginx/conf/htpasswd_pma"
        yellow "请设置 phpMyAdmin 基本认证账户："
        read -p "用户名: " PMA_USER

        htpasswd -c "$HTFILE" "$PMA_USER"

        # 创建单独的 vhost 配置，监听 /phpmyadmin
        cat >/usr/local/nginx/conf/vhost/phpmyadmin.conf <<EOF
server {
    listen 80;
    server_name _;

    root /data/wwwroot/default;
    index index.php index.html;

    location /phpmyadmin {
        alias ${PHPMYADMIN_WEBROOT};
        index index.php;

        auth_basic "Restricted phpMyAdmin";
        auth_basic_user_file ${HTFILE};

        location ~ \.php\$ {
            fastcgi_pass   unix:/run/php-fpm.sock;
            fastcgi_index  index.php;
            include        fastcgi.conf;
        }
    }
}
EOF

        log_info "phpMyAdmin BasicAuth 已启用，vhost 配置：/usr/local/nginx/conf/vhost/phpmyadmin.conf"
    else
        # 无 BasicAuth 简单配置（可手动加入到 default server）
        cat >/usr/local/nginx/conf/vhost/phpmyadmin.conf <<EOF
server {
    listen 80;
    server_name _;

    root /data/wwwroot/default;
    index index.php index.html;

    location /phpmyadmin {
        alias ${PHPMYADMIN_WEBROOT};
        index index.php;

        location ~ \.php\$ {
            fastcgi_pass   unix:/run/php-fpm.sock;
            fastcgi_index  index.php;
            include        fastcgi.conf;
        }
    }
}
EOF
        log_notice "phpMyAdmin 未启用 BasicAuth，建议在生产环境开启！"
    fi

    systemctl reload nginx || systemctl restart nginx

    log_info "phpMyAdmin 已安装到：${PHPMYADMIN_WEBROOT}"
    log_info "访问路径示例：http://服务器IP/phpmyadmin"
}

###############################################
# 启动模块 6
###############################################
}

###############################################
# run_module6(): 模块 6 顶层执行段封装（修复：避免脚本加载时直接运行）
###############################################

###############################################
# 可选组件选择（模块 6）：先检测再询问
###############################################
is_service_or_bin_exists() {
  local svc="$1" bin="$2" altbin="$3"
  if [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1; then return 0; fi
  if [[ -n "$altbin" ]] && [[ -x "$altbin" ]]; then return 0; fi
  if [[ -n "$svc" ]] && systemctl list-unit-files | awk '{print $1}' | grep -qx "$svc"; then return 0; fi
  return 1
}

select_optional_components() {
  # 默认全不装
  INSTALL_REDIS=0; FORCE_REDIS=0
  INSTALL_MEMCACHED=0; FORCE_MEMCACHED=0
  INSTALL_PUREFTPD=0; FORCE_PUREFTPD=0
  INSTALL_NODEJS=0; FORCE_NODEJS=0
  INSTALL_PHPMYADMIN=0; FORCE_PHPMYADMIN=0

  log_info ">>> 可选组件安装选择（先检测再询问）"

  # ---- Redis ----
  if is_service_or_bin_exists "redis.service" "redis-server" "/usr/local/redis/bin/redis-server"; then
    log_notice "检测到 Redis 已安装"
    read -p "Redis：1) 跳过  2) 重装/修复  请选择[1-2]（默认1）: " ans
    ans=${ans:-1}
    if [[ "$ans" == "2" ]]; then INSTALL_REDIS=1; FORCE_REDIS=1; fi
  else
    read -p "是否安装 Redis？1) 安装 2) 不安装（默认2）: " ans
    ans=${ans:-2}
    [[ "$ans" == "1" ]] && INSTALL_REDIS=1
  fi

  # ---- Memcached ----
  if is_service_or_bin_exists "memcached.service" "memcached" "/usr/local/memcached/bin/memcached"; then
    log_notice "检测到 Memcached 已安装"
    read -p "Memcached：1) 跳过  2) 重装/修复  请选择[1-2]（默认1）: " ans
    ans=${ans:-1}
    if [[ "$ans" == "2" ]]; then INSTALL_MEMCACHED=1; FORCE_MEMCACHED=1; fi
  else
    read -p "是否安装 Memcached？1) 安装 2) 不安装（默认2）: " ans
    ans=${ans:-2}
    [[ "$ans" == "1" ]] && INSTALL_MEMCACHED=1
  fi

  # ---- Pure-FTPD ----
  if is_service_or_bin_exists "pure-ftpd.service" "pure-ftpd" "/usr/local/pureftpd/sbin/pure-ftpd"; then
    log_notice "检测到 Pure-FTPd 已安装"
    read -p "Pure-FTPd：1) 跳过  2) 重装/修复  请选择[1-2]（默认1）: " ans
    ans=${ans:-1}
    if [[ "$ans" == "2" ]]; then INSTALL_PUREFTPD=1; FORCE_PUREFTPD=1; fi
  else
    read -p "是否安装 Pure-FTPd？1) 安装 2) 不安装（默认2）: " ans
    ans=${ans:-2}
    [[ "$ans" == "1" ]] && INSTALL_PUREFTPD=1
  fi

  # ---- Node.js ----
  if is_service_or_bin_exists "" "node" "" || is_service_or_bin_exists "" "npm" ""; then
    log_notice "检测到 Node.js/NPM 已安装：$(command -v node 2>/dev/null || true)"
    read -p "Node.js：1) 跳过  2) 重装/修复  请选择[1-2]（默认1）: " ans
    ans=${ans:-1}
    if [[ "$ans" == "2" ]]; then INSTALL_NODEJS=1; FORCE_NODEJS=1; fi
  else
    read -p "是否安装 Node.js？1) 安装 2) 不安装（默认2）: " ans
    ans=${ans:-2}
    [[ "$ans" == "1" ]] && INSTALL_NODEJS=1
  fi

  # ---- phpMyAdmin ----
  if [[ -d "/data/wwwroot/default/phpmyadmin" || -d "/data/wwwroot/phpmyadmin" || -d "/usr/share/phpmyadmin" ]]; then
    log_notice "检测到 phpMyAdmin 已存在"
    read -p "phpMyAdmin：1) 跳过  2) 重装/修复  请选择[1-2]（默认1）: " ans
    ans=${ans:-1}
    if [[ "$ans" == "2" ]]; then INSTALL_PHPMYADMIN=1; FORCE_PHPMYADMIN=1; fi
  else
    read -p "是否安装 phpMyAdmin？1) 安装 2) 不安装（默认2）: " ans
    ans=${ans:-2}
    [[ "$ans" == "1" ]] && INSTALL_PHPMYADMIN=1
  fi
}
run_module6() {
  select_optional_components
  # ---- 兜底：可选组件安装函数缺失时自动补齐（避免 command not found） ----
  if [[ "${INSTALL_NODEJS:-0}" == "1" ]] && ! declare -F install_nodejs >/dev/null 2>&1; then
    install_nodejs() {
      log_info "开始安装 Node.js（APT）"
      apt update
      apt install -y nodejs npm
      log_info "Node.js 安装完成：$(node -v 2>/dev/null || true)"
    }
  fi
  if [[ "${INSTALL_PHPMYADMIN:-0}" == "1" ]] && ! declare -F install_phpmyadmin >/dev/null 2>&1; then
    install_phpmyadmin() {
      log_info "开始安装 phpMyAdmin"
      local PMA_VER="${PHPMYADMIN_VERSION:-5.2.1}"
      local SRC_BASE="${PHPMYADMIN_SRC_BASE:-/usr/local/src/phpmyadmin}"
      local WEBROOT="${PHPMYADMIN_WEBROOT:-/data/wwwroot/default/phpmyadmin}"
      mkdir -p "$SRC_BASE"
      cd "$SRC_BASE" || return 1
      local TAR="phpMyAdmin-${PMA_VER}-all-languages.tar.gz"
      local URL="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/${TAR}"
      if [[ ! -f "$TAR" ]]; then
        log_info "下载 phpMyAdmin：$URL"
        if ! curl -L --connect-timeout 20 -o "$TAR" "$URL"; then
          log_error "phpMyAdmin 下载失败：$URL"
          echo "$URL" >> /tmp/lnmp_download_failed.txt
          return 1
        fi
      else
        log_info "phpMyAdmin 源码包已存在：$TAR"
      fi
      rm -rf "$WEBROOT" "${SRC_BASE}/phpMyAdmin-${PMA_VER}-all-languages"
      if ! tar -zxf "$TAR"; then
        log_error "解压 phpMyAdmin 失败：$TAR"
        return 1
      fi
      mv "${SRC_BASE}/phpMyAdmin-${PMA_VER}-all-languages" "$WEBROOT"
      # 生成一个简易入口（可选）
      if [[ -d "$WEBROOT" ]]; then
        log_info "phpMyAdmin 已部署到：$WEBROOT"
      fi
    }
  fi
if [[ "$INSTALL_REDIS" == "1" ]]; then
    if (command -v redis-server >/dev/null 2>&1 || [[ -x "/usr/local/redis/bin/redis-server" ]]) && [[ "${FORCE_REDIS:-0}" != "1" ]]; then
        log_notice "检测到 Redis 已安装，按选择跳过。"
    else
        install_redis
    fi
fi

if [[ "$INSTALL_MEMCACHED" == "1" ]]; then
    if (command -v memcached >/dev/null 2>&1 || [[ -x "/usr/local/memcached/bin/memcached" ]]) && [[ "${FORCE_MEMCACHED:-0}" != "1" ]]; then
        log_notice "检测到 Memcached 已安装，按选择跳过。"
    else
        install_memcached
    fi
fi

if [[ "$INSTALL_PUREFTPD" == "1" ]]; then
    if (command -v pure-ftpd >/dev/null 2>&1 || [[ -x "/usr/local/pureftpd/sbin/pure-ftpd" ]]) && [[ "${FORCE_PUREFTPD:-0}" != "1" ]]; then
        log_notice "检测到 Pure-FTPd 已安装，按选择跳过。"
    else
        install_pureftpd
    fi
fi



if [[ "$INSTALL_NODEJS" == "1" ]]; then
    if (command -v node >/dev/null 2>&1 || command -v npm >/dev/null 2>&1) && [[ "${FORCE_NODEJS:-0}" != "1" ]]; then
        log_notice "检测到 Node.js 已安装，按选择跳过。"
    else
        install_nodejs
    fi
fi

if [[ "$INSTALL_PHPMYADMIN" == "1" ]]; then
    if ([[ -d "/data/wwwroot/default/phpmyadmin" || -d "/data/wwwroot/phpmyadmin" || -d "/usr/share/phpmyadmin" ]]) && [[ "${FORCE_PHPMYADMIN:-0}" != "1" ]]; then
        log_notice "检测到 phpMyAdmin 已存在，按选择跳过。"
    else
        install_phpmyadmin
    fi
fi

###log_info "模块 6 执行完成"

###########################################
# LNMP Installer — Module 7
# 虚拟主机管理 / 默认站点 / SSH 密钥一键配置
###########################################

VHOST_DIR="/usr/local/nginx/conf/vhost"
NGINX_SSL_DIR="/usr/local/nginx/conf/ssl"
WEBROOT_BASE="/data/wwwroot"
WEBLOG_BASE="/data/wwwlogs"

###############################################
# 创建虚拟主机（PHP-FPM 模式）
###############################################
lnmp_create_vhost() {
    echo
    yellow "创建新的 Nginx 虚拟主机"

    read -p "请输入域名（如：example.com，不带 http/https）: " VHOST_DOMAIN
    if [[ -z "$VHOST_DOMAIN" ]]; then
        log_error "域名不能为空"
        return 1
    fi

    read -p "请输入站点根目录 [默认：${WEBROOT_BASE}/${VHOST_DOMAIN}]: " VHOST_ROOT
    VHOST_ROOT=${VHOST_ROOT:-${WEBROOT_BASE}/${VHOST_DOMAIN}}

    read -p "是否启用 HTTPS？(y/N): " ENABLE_HTTPS
    ENABLE_HTTPS=${ENABLE_HTTPS:-n}

    mkdir -p "${VHOST_ROOT}"
    mkdir -p "${WEBLOG_BASE}"

    local ACCESS_LOG="${WEBLOG_BASE}/${VHOST_DOMAIN}_access.log"
    local ERROR_LOG="${WEBLOG_BASE}/${VHOST_DOMAIN}_error.log"
    local CONF_FILE="${VHOST_DIR}/${VHOST_DOMAIN}.conf"

    if [[ "${ENABLE_HTTPS}" =~ ^[Yy]$ ]]; then
        mkdir -p "${NGINX_SSL_DIR}"
        echo
        yellow "请输入 SSL 证书路径，示例：${NGINX_SSL_DIR}/${VHOST_DOMAIN}.crt"
        read -p "证书文件 (ssl_certificate): " SSL_CERT
        read -p "私钥文件 (ssl_certificate_key): " SSL_KEY

        cat >"$CONF_FILE" <<EOF
server {
    listen 80;
    server_name ${VHOST_DOMAIN} www.${VHOST_DOMAIN};
    return 301 https://\$host\$request_uri;

}
server {
    listen 443 ssl http2;
    server_name ${VHOST_DOMAIN} www.${VHOST_DOMAIN};

    ssl_certificate      ${SSL_CERT};
    ssl_certificate_key  ${SSL_KEY};

    root   ${VHOST_ROOT};
    index  index.php index.html index.htm;

    access_log  ${ACCESS_LOG}  combined;
    error_log   ${ERROR_LOG}   error;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass   unix:/run/php-fpm.sock;
        fastcgi_index  index.php;
        include        fastcgi.conf;
    }

    location ~* \.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)\$ {
        expires 30d;
        access_log off;
    }

    location ~* \.(js|css)\$ {
        expires 7d;
        access_log off;
    }

    location ~ ^/(\.user.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
        deny all;
    }

    location /.well-known {
        allow all;
    }
}
EOF

    else
        cat >"$CONF_FILE" <<EOF
server {
    listen 80;
    server_name ${VHOST_DOMAIN} www.${VHOST_DOMAIN};

    root   ${VHOST_ROOT};
    index  index.php index.html index.htm;

    access_log  ${ACCESS_LOG}  combined;
    error_log   ${ERROR_LOG}   error;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass   unix:/run/php-fpm.sock;
        fastcgi_index  index.php;
        include        fastcgi.conf;
    }

    location ~* \.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)\$ {
        expires 30d;
        access_log off;
    }

    location ~* \.(js|css)\$ {
        expires 7d;
        access_log off;
    }

    location ~ ^/(\.user.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
        deny all;
    }

    location /.well-known {
        allow all;
    }
}
EOF
    fi

    chown -R www:www "${VHOST_ROOT}"

    log_info "虚拟主机配置已创建：${CONF_FILE}"
    log_info "站点目录：${VHOST_ROOT}"

    if ! nginx -t; then
        log_error "Nginx 配置测试失败，请先修复：nginx -t"
        return 1
    fi

    # 优先 reload；若服务未启动则 start；避免把“inactive cannot reload”误判成配置失败
    if systemctl is-active --quiet nginx; then
        if systemctl reload nginx; then
            green "Nginx 配置检查通过，已重载"
        else
            log_warn "Nginx reload 失败，尝试 restart..."
            systemctl restart nginx && green "Nginx 已重启"
        fi
    else
        log_warn "Nginx 当前未启动（inactive），尝试启动..."
        systemctl start nginx && green "Nginx 已启动"
    fi
}

###############################################
# 设置 / 初始化默认站点
###############################################
lnmp_setup_default_site() {
    local DEFAULT_ROOT="${WEBROOT_BASE}/default"
    mkdir -p "${DEFAULT_ROOT}"

    cat >"${DEFAULT_ROOT}/index.php" <<'EOF'
<?php
phpinfo();
EOF

    cat >"${DEFAULT_ROOT}/index.html" <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>LNMP 安装成功</title>
<style>
body { font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans","PingFang SC","Hiragino Sans GB",sans-serif; background:#f5f5f5; margin:0; padding:0; }
.container { max-width:800px; margin:60px auto; background:#fff; border-radius:8px; box-shadow:0 2px 8px rgba(0,0,0,0.08); padding:40px; }
h1 { margin-top:0; font-size:28px; color:#333; }
p { color:#666; line-height:1.8; }
code { background:#f0f0f0; padding:2px 4px; border-radius:4px; }
</style>
</head>
<body>
<div class="container">
  <h1>🎉 LNMP 环境安装成功</h1>
  <p>如果你能看到这个页面，说明 Nginx + PHP 已正常工作。</p>
  <p>默认站点目录：<code>/data/wwwroot/default</code></p>
  <p>你可以执行以下命令继续配置：</p>
  <ul>
    <li><code>bash lnmp.sh vhost</code> 创建新的虚拟主机</li>
    <li><code>bash lnmp.sh default</code> 重新生成默认站点页面</li>
    <li><code>bash lnmp.sh sshkey</code> 配置 SSH 密钥登录</li>
  </ul>
</div>
</body>
</html>
EOF

    chown -R www:www "${DEFAULT_ROOT}"

    log_info "默认站点已生成：${DEFAULT_ROOT}"
    log_info "你可以在浏览器访问服务器 IP 验证。"

    nginx -t && systemctl reload nginx && \
        green "Nginx 配置检查通过，已重载" || \
        log_error "Nginx 配置测试失败，请检查：nginx -t"
}

###############################################
# SSH 密钥登录一键配置
###############################################
lnmp_sshkey_setup() {
    yellow "SSH 密钥登录一键配置（仅影响当前服务器）"

    local SSH_DIR="/root/.ssh"
    local KEY_FILE="${SSH_DIR}/lnmp_ed25519"
    local PUB_FILE="${KEY_FILE}.pub"
    local AUTH_FILE="${SSH_DIR}/authorized_keys"
    local SSHD_CONFIG="/etc/ssh/sshd_config"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    if [[ -f "$KEY_FILE" ]]; then
        yellow "检测到已有密钥：${KEY_FILE}"
        read -p "是否覆盖重建？(y/N): " OVERWRITE
        OVERWRITE=${OVERWRITE:-n}
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            log_info "保留现有密钥，直接将公钥加入 authorized_keys"
        else
            rm -f "$KEY_FILE" "$PUB_FILE"
        fi
    fi

    if [[ ! -f "$KEY_FILE" ]]; then
        log_info "生成新的 ED25519 密钥对..."
        ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "lnmp_sshkey_$(hostname)"
    fi

    touch "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"

    if ! grep -q "$(cat "$PUB_FILE")" "$AUTH_FILE"; then
        cat "$PUB_FILE" >> "$AUTH_FILE"
    fi

    log_info "公钥已写入：${AUTH_FILE}"
    log_info "私钥路径：${KEY_FILE}"

    # 调整 sshd_config（关闭密码登录）
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%F_%H%M%S)"

    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#\?UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"

    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

    green "SSH 密钥登录配置完成"
    echo
    yellow "请使用以下私钥连接服务器（示例）："
    echo "  ssh -i ${KEY_FILE} root@服务器IP"
    yellow "原密码登录已关闭，如需恢复可编辑：${SSHD_CONFIG}，并重启 sshd 服务。"
}

###############################################
# 服务状态和重启（辅助命令）
###############################################
lnmp_status_all() {
    echo
    yellow "LNMP 服务状态检查："
    for svc in nginx php-fpm mysqld mariadb redis memcached pure-ftpd docker; do
        if systemctl list-unit-files | grep -q "^${svc}.service"; then
            local st
            st=$(systemctl is-active "$svc")
            printf "  %-10s : %s\n" "$svc" "$st"
        fi
    done
}

lnmp_restart_all() {
    echo
    yellow "尝试重启 LNMP 相关服务..."

    for svc in nginx php-fpm mysqld mariadb redis memcached pure-ftpd docker; do
        if systemctl list-unit-files | grep -q "^${svc}.service"; then
            systemctl restart "$svc"
            printf "  重启 %-10s : %s\n" "$svc" "$(systemctl is-active "$svc")"
        fi
    done
}

###############################################
# 卸载占位（提示手动操作）
###############################################
lnmp_remove_notice() {
    red "注意：完整卸载涉及删除 /usr/local 下的组件、/data 下的数据以及 systemd 服务。"
    echo "出于安全考虑，本脚本仅给出提示，不自动执行 rm -rf。"
    echo "你可以参考以下路径手动清理："
    echo "  - /usr/local/nginx"
    echo "  - /usr/local/phpX.Y"
    echo "  - /usr/local/mysql 或 /usr/local/mariadb"
    echo "  - /usr/local/redis"
    echo "  - /usr/local/memcached"
    echo "  - /usr/local/pureftpd"
    echo "  - /data/wwwroot"
    echo "  - /data/wwwlogs"
    echo "  - /data/mysql"
    echo
    echo "以及停用 & 删除以下 systemd 服务（按需）："
    echo "  systemctl disable --now nginx php-fpm mysqld mariadb redis memcached pure-ftpd"
}

###############################################
# 简单帮助函数（子命令用）
###############################################
lnmp_usage() {
    cat <<EOF
用法：bash lnmp.sh [子命令]

子命令：
  install      进行完整安装（在主入口中实现）
  vhost        创建新的虚拟主机
  default      生成/重置默认站点页面
  sshkey       配置 SSH 密钥登录
  status       查看 LNMP 相关服务状态
  restart      重启 LNMP 相关服务
  remove       显示卸载提示（不自动删除）

示例：
  bash lnmp.sh install
  bash lnmp.sh vhost
  bash lnmp.sh default
  bash lnmp.sh sshkey
  bash lnmp.sh status
EOF
}

###########################################
# LNMP Installer — Module 8
# 一键安装主流程 + 子命令入口 + 收尾清理
###########################################

###############################################
# 一键安装主流程
###############################################
}

###############################################
# run_module7(): 默认站点/管理工具入口（对应原脚本 Module 7）
###############################################
run_module7() {
    if declare -F lnmp_setup_default_site >/dev/null 2>&1; then
        log_info "开始执行模块 7：默认站点初始化"
        lnmp_setup_default_site
    else
        log_notice "跳过：未定义 lnmp_setup_default_site"
    fi
}


###############################################
# run_module8(): 收尾输出（对应原脚本 Module 8）
###############################################
run_module8() {
    log_info "===== LNMP 一键安装流程完成 ====="
    if declare -F lnmp_status_all >/dev/null 2>&1; then
        echo
        lnmp_status_all
    fi
    cat <<'EOF'

后续常用命令：
  bash lnmp.sh vhost      # 创建虚拟主机
  bash lnmp.sh default    # 重置默认站点页面
  bash lnmp.sh sshkey     # 配置 SSH 密钥登录
  bash lnmp.sh status     # 查看服务状态
  bash lnmp.sh restart    # 重启相关服务
EOF
}


lnmp_install_all() {
    log_info "===== LNMP 一键安装开始 ====="
    run_module1
    run_module2
    run_module3
    run_module4
    run_module5
    run_module6
    run_module7
    run_module8
}

###############################################
# 兜底：若某些辅助函数因脚本结构/裁剪导致未生效，则在此补齐
# 说明：避免出现 "command not found"（例如 status/restart 子命令）
###############################################
__ensure_helper_functions() {
  if ! declare -F lnmp_status_all >/dev/null 2>&1; then
    lnmp_status_all() {
      echo
      yellow "LNMP 服务状态检查："
      for svc in nginx php-fpm mysqld mariadb redis memcached pure-ftpd docker; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
          printf "  %-10s : %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
        fi
      done
    }
  fi

  if ! declare -F lnmp_restart_all >/dev/null 2>&1; then
    lnmp_restart_all() {
      echo
      yellow "尝试重启 LNMP 相关服务..."
      for svc in nginx php-fpm mysqld mariadb redis memcached pure-ftpd docker; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
          systemctl restart "$svc" 2>/dev/null || true
          printf "  重启 %-10s : %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
        fi
      done
    }
  fi
}

lnmp_main() {
    __ensure_helper_functions
    local CMD="$1"

    case "$CMD" in
        ""|"install")
            lnmp_install_all
            ;;
        vhost)
            lnmp_create_vhost
            ;;
        default)
            lnmp_setup_default_site
            ;;
        sshkey)
            lnmp_sshkey_setup
            ;;
        status)
            lnmp_status_all
            ;;
        restart)
            lnmp_restart_all
            ;;
        remove)
            lnmp_remove_notice
            ;;
        help|-h|--help)
            lnmp_usage
            ;;
        *)
            red "未知子命令：$CMD"
            lnmp_usage
            ;;
    esac
}

###############################################
# 调用入口
###############################################

# ===== Script entry point (single) =====
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  lnmp_main "$@"
  exit $?
fi
