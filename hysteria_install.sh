#!/bin/bash

# 定义常量
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
LOG_FILE="/var/log/hysteria_install.log"
CLIENT_CONFIG="$HYSTERIA_DIR/client.json"

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

# 安装Hysteria2
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

# 停止服务
stop_service() {
    echo -e "\033[34m正在停止 Hysteria2...\033[0m"
    systemctl stop hysteria
    check_error "停止 Hysteria 服务" true || return
    echo -e "\033[32mHysteria2 已停止。\033[0m"
}

# 重启服务
restart_service() {
    echo -e "\033[34m正在重启 Hysteria2...\033[0m"
    systemctl restart hysteria
    check_error "重启 Hysteria 服务" true || return
    echo -e "\033[32mHysteria2 已重启。\033[0m"
}

# 查看服务状态
view_status() {
    echo -e "\033[34m查看 Hysteria2 状态...\033[0m"
    systemctl status hysteria
    check_error "查看 Hysteria 服务状态" true || return
}

# 更新Hysteria2
update_hysteria() {
    echo -e "\033[34m正在检查 Hysteria2 更新...\033[0m"

    # 获取当前版本
    current_version=$(command -v "$HYSTERIA_BINARY" && "$HYSTERIA_BINARY" version | awk '{print $2}')
    if [ -z "$current_version" ]; then
        echo -e "\033[31mHysteria2 未安装，无法更新。\033[0m"
        return
    fi

    # 获取最新版本
    latest_version=$(curl -s "https://api.github.com/repos/HyNetwork/hysteria/releases/latest" | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        latest_version=$(curl -s "https://github.com/HyNetwork/hysteria/releases/latest" | grep -oP 'releases/tag/\Kv\d+\.\d+\.\d+')
    fi

    if [ -z "$latest_version" ]; then
        echo -e "\033[31m无法获取最新版本信息。\033[0m"
        return
    fi

    # 比较版本
    if version_compare "$current_version" "$latest_version"; then
        echo -e "\033[32m当前已是最新版本：$current_version\033[0m"
        return
    fi

    echo -e "\033[34m发现新版本：$latest_version，正在更新...\033[0m"
    stop_service

    # 下载并更新二进制文件
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" \
        "$HYSTERIA_BINARY" 3 5
    check_error "下载 Hysteria 二进制文件" true || return
    chmod +x "$HYSTERIA_BINARY"
    check_error "设置 Hysteria 二进制文件可执行权限" true || return

    # 启动服务
    systemctl start hysteria
    check_error "启动 Hysteria 服务" true || return

    echo -e "\033[32mHysteria2 已更新到最新版本：$latest_version\033[0m"
}

# 卸载Hysteria2
uninstall_hysteria() {
    echo -e "\033[34m正在卸载 Hysteria2...\033[0m"
    stop_service
    systemctl disable hysteria
    rm -f "$HYSTERIA_SERVICE"
    rm -f "$HYSTERIA_BINARY"
    rm -rf "$HYSTERIA_DIR"
    systemctl daemon-reload
    echo -e "\033[32mHysteria2 已卸载。\033[0m"
}

# 查看日志
view_log() {
    echo -e "\033[34m正在查看日志文件：$LOG_FILE\033[0m"
    echo "------------------- Hysteria2 安装日志 -------------------"
    cat "$LOG_FILE"
}

# 生成客户端配置
generate_client_config() {
    if [ ! -f "$HYSTERIA_CONFIG" ]; then
        echo -e "\033[31m未找到 Hysteria 配置文件，请先安装 Hysteria2。\033[0m"
        return
    fi

    local ipv4=$(curl -4 -s ifconfig.me)
    local ipv6=$(curl -6 -s ifconfig.me)
    local port=$(grep -oP 'listen:\s*:\K\d+' "$HYSTERIA_CONFIG")
    local password=$(grep -oP 'password:\s*\K\S+' "$HYSTERIA_CONFIG")

    if [ -z "$port" ] || [ -z "$password" ]; then
        echo -e "\033[31m无法从配置文件中提取客户端设置。\033[0m"
        return
    fi

    # 生成配置URL
    local urls=()
    if [ -n "$ipv4" ]; then
        urls+=("hysteria2://$password@$ipv4:$port/?insecure=1&sni=example.com#Hysteria2 (IPv4)")
    fi
    if [ -n "$ipv6" ]; then
        urls+=("hysteria2://$password@[$ipv6]:$port/?insecure=1&sni=example.com#Hysteria2 (IPv6)")
    fi

    echo -e "\033[34m生成客户端配置...\033[0m"
    for url in "${urls[@]}"; do
        echo -e "\033[32m$url\033[0m"
        qrencode -t ANSIUTF8 -o - <<< "$url"
    done
}

# 显示菜单
show_menu() {
    clear
    echo -e "======================================"
    echo -e " Hysteria2 管理脚本"
    echo -e "======================================"
    echo -e "1. 安装 Hysteria2"
    echo -e "2. 停止 Hysteria2"
    echo -e "3. 重启 Hysteria2"
    echo -e "4. 状态 Hysteria2"
    echo -e "5. 更新 Hysteria2"
    echo -e "6. 卸载 Hysteria2"
    echo -e "7. 查看日志"
    echo -e "8. 生成客户端配置"
    echo -e "9. 退出脚本"
    echo -e "======================================"
    echo -e "请输入选项 (1-9): "
}

# 主函数
main() {
    init_log
    detect_system

    while true; do
        show_menu
        read -p "" option
        case $option in
            1)
                install_hysteria
                ;;
            2)
                stop_service
                ;;
            3)
                restart_service
                ;;
            4)
                view_status
                ;;
            5)
                update_hysteria
                ;;
            6)
                uninstall_hysteria
                ;;
            7)
                view_log
                ;;
            8)
                generate_client_config
                ;;
            9)
                echo -e "\033[34m脚本退出。\033[0m"
                exit 0
                ;;
            *)
                echo -e "\033[31m无效选项，请重新输入。\033[0m"
                ;;
        esac
        read -p "按回车键继续..." </dev/tty
    done
}

# 运行主函数
if [ "$EUID" -eq 0 ]; then
    main
else
    echo -e "\033[31m请以 root 用户运行此脚本。\033[0m"
fi
