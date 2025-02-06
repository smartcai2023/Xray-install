#!/bin/bash

# 定义常量
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
LOG_FILE="/var/log/hysteria_install.log"
CLIENT_CONFIG="$HYSTERIA_DIR/client.json"

# 颜色定义
GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
RESET="\033[0m"

# 初始化日志
init_log() {
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "------------------- Hysteria2 安装日志 -------------------"
}

# 错误处理函数
check_error() {
    local error_msg=$1
    local exit_code=$2
    if [ $? -ne 0 ]; then
        echo -e "\033[31m错误: $error_msg\033[0m"
        if [ "$exit_code" = true ]; then
            return 1
        fi
    fi
}

# 系统检测和依赖安装
detect_system() {
    case $(lsb_release -si) in
        "Ubuntu" | "Debian")
            pkg_manager="apt"
            install_cmd="apt update && apt install -y"
            ;;
        "CentOS" | "Amazon")
            pkg_manager="yum"
            install_cmd="yum install -y"
            ;;
        *)
            echo "不支持的系统类型: $(lsb_release -si)"
            exit 1
            ;;
    esac

    echo "检测到 $(lsb_release -si) 系统，使用 $pkg_manager 安装依赖..."
    eval "$install_cmd curl openssl qrencode jq"
    check_error "安装依赖" true
}

# 下载文件（带重试机制）
download_file() {
    local url=$1
    local output=$2
    local retries=${3:-3}
    local delay=${4:-2}

    for ((i=1; i<=retries; i++)); do
        echo -e "\033[34m正在下载文件 (尝试 $i/$retries): $url\033[0m"
        if curl -fsSL -o "$output" "$url"; then
            echo -e "\033[32m下载成功: $output\033[0m"
            return 0
        else
            echo -e "\033[33m下载失败，等待 $delay 秒后重试...\033[0m"
            sleep $delay
        fi
    done
    echo -e "\033[31m下载失败: $url\033[0m"
    return 1
}

# 随机生成端口和密码
generate_config() {
    local port=$(shuf -i 1000-65535 -n 1)
    local password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo "$port"
    echo "$password"
}

# 获取服务器IP地址
get_server_ips() {
    local ipv4=$(curl -4 -s ifconfig.me)
    local ipv6=$(curl -6 -s ifconfig.me)
    echo "$ipv4"
    echo "$ipv6"
}

# Hysteria2 版本比较
version_compare() {
    local current=$1
    local latest=$2
    if [ "$(printf '%s\n' "$current" "$latest" | sort -V | head -n1)" = "$current" ]; then
        return 1
    else
        return 0
    fi
}

# 自动检测最佳 MTU
detect_mtu() {
    local target="8.8.8.8"  # Google DNS 服务器，可修改为自己的目标
    local mtu=1500
    while [[ $mtu -gt 1200 ]]; do
        if ping -M do -s $((mtu - 28)) -c 1 "$target" >/dev/null 2>&1; then
            echo -e "${GREEN}最佳 MTU 值检测成功: $mtu${RESET}"
            echo $mtu
            return
        fi
        mtu=$((mtu - 10))
    done
    echo -e "${RED}无法检测到最佳 MTU，默认使用 1400${RESET}"
    echo 1400
}

# 优化 UDP 缓冲区
optimize_udp_buffer() {
    echo -e "${BLUE}正在优化 UDP 缓冲区...${RESET}"
    sysctl -w net.core.rmem_max=26214400
    sysctl -w net.core.wmem_max=26214400
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}UDP 缓冲区优化完成！${RESET}"
}

# 启用 BBR 拥塞控制
enable_bbr() {
    echo -e "${BLUE}正在启用 BBR 拥塞控制...${RESET}"
    modprobe tcp_bbr 2>/dev/null
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}BBR 启用成功！${RESET}"
}

# Hysteria2 安装
install_hysteria() {
    echo -e "\033[34m正在安装 Hysteria2...\033[0m"

    # 创建目录
    mkdir -p "$HYSTERIA_DIR" && chmod 755 "$HYSTERIA_DIR"
    check_error "创建 Hysteria 目录" true || return

    # 用户自定义配置
    read -p "是否自定义端口和密码？(y/n, 默认 n): " CUSTOM_CONFIG
    local port password
    if [[ "$CUSTOM_CONFIG" =~ ^[yY] ]]; then
        read -p "请输入自定义端口 (默认随机生成): " CUSTOM_PORT
        read -p "请输入自定义密码 (默认随机生成): " CUSTOM_PASSWORD
        port=${CUSTOM_PORT:-$(generate_config | head -n1)}
        password=${CUSTOM_PASSWORD:-$(generate_config | tail -n1)}
    else
        port=$(generate_config | head -n1)
        password=$(generate_config | tail -n1)
    fi

    # 生成自签证书
    echo -e "\033[34m正在生成自签证书...\033[0m"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$HYSTERIA_DIR/server.key" -out "$HYSTERIA_DIR/server.crt" \
        -subj "/CN=example.com" -days 3650 -batch
    check_error "生成自签证书" true || return

    # 创建配置文件
    echo -e "\033[34m正在创建配置文件...\033[0m"
    cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$port
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $password
EOF
    check_error "创建配置文件" true || return

    # 下载并安装二进制文件
    echo -e "\033[34m正在下载 Hysteria 二进制文件...\033[0m"
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" \
        "$HYSTERIA_BINARY" 3 5
    check_error "下载 Hysteria 二进制文件" true || return
    chmod +x "$HYSTERIA_BINARY"
    check_error "设置 Hysteria 二进制文件可执行权限" true || return

    # 创建systemd服务
    echo -e "\033[34m正在创建 systemd 服务...\033[0m"
    cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Hysteria VPN Service
After=network.target

[Service]
ExecStart=$HYSTERIA_BINARY server --config $HYSTERIA_CONFIG
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    check_error "创建 systemd 服务文件" true || return

    # 启动服务
    systemctl daemon-reload
    check_error "重载 systemd 配置" true || return
    systemctl enable hysteria
    check_error "启用 Hysteria 服务" true || return
    systemctl start hysteria
    check_error "启动 Hysteria 服务" true || return

    echo -e "\033[32mHysteria2 安装完成！\033[0m"
    echo -e "端口: \033[33m$port\033[0m"
    echo -e "密码: \033[33m$password\033[0m"
    echo -e "配置文件: \033[33m$HYSTERIA_CONFIG\033[0m"
    echo -e "日志文件: \033[33m$LOG_FILE\033[0m"
}

# 主函数
main() {
    init_log
    detect_system

    # 优化网络设置
    mtu_value=$(detect_mtu)
    optimize_udp_buffer
    enable_bbr

    # 更新配置文件中的 MTU 值
    echo -e "\033[34m请在 Hysteria2 配置文件中修改以下 MTU 设置:\033[0m"
    echo -e "\033[32mudp:\n  mtu: $mtu_value\033[0m"
    read -p "按回车键继续..."

    # 选择操作
    install_hysteria
}

# 运行主函数
if [ "$EUID" -eq 0 ]; then
    main
else
    echo -e "\033[31m请以 root 用户运行此脚本。\033[0m"
fi
