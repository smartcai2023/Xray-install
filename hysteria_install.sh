#!/bin/bash

# 定义变量
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
LOG_FILE="/var/log/hysteria_install.log"
CLIENT_CONFIG="$HYSTERIA_DIR/client.json"

# 权限检测
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户运行此脚本。"
    exit 1
fi

# 日志功能
exec > >(tee -a "$LOG_FILE") 2>&1

# 错误检查函数
check_error() {
    if [ $? -ne 0 ]; then
        echo "错误: $1 失败。请检查日志文件: $LOG_FILE"
        read -p "按回车键返回主菜单..."
        return 1
    fi
}

# 检测系统类型并安装依赖
install_dependencies() {
    if command -v apt &> /dev/null; then
        echo "检测到 Debian/Ubuntu 系统，使用 apt 安装依赖..."
        apt update
        apt install -y curl openssl qrencode jq
    elif command -v yum &> /dev/null; then
        echo "检测到 CentOS/Amazon Linux 2 系统，使用 yum 安装依赖..."
        yum install -y curl openssl qrencode jq
    else
        echo "不支持的系统类型。"
        exit 1
    fi
    check_error "安装依赖" || return
}

# 下载文件（带重试机制）
download_file() {
    local url=$1
    local output=$2
    local retries=3
    local delay=2

    for ((i=1; i<=retries; i++)); do
        echo "正在下载文件 (尝试 $i/$retries): $url"
        if curl -fsSL -o "$output" "$url"; then
            echo "下载成功: $output"
            return 0
        else
            echo "下载失败，等待 $delay 秒后重试..."
            sleep $delay
        fi
    done

    echo "下载失败: $url"
    return 1
}

# 生成随机端口和密码
generate_random_port() {
    shuf -i 1000-65535 -n 1
}

generate_random_password() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

# 获取服务器的 IPv4 和 IPv6 地址
get_server_ips() {
    IPV4=$(curl -4 -s ifconfig.me)
    IPV6=$(curl -6 -s ifconfig.me)
    if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
        echo "无法获取服务器的 IPv4 和 IPv6 地址。"
        return 1
    fi
}

# 获取当前安装的 Hysteria2 版本
get_hysteria_version() {
    if [ -f "$HYSTERIA_BINARY" ]; then
        "$HYSTERIA_BINARY" version | grep -oP 'version \K\S+'
    else
        echo "未安装"
    fi
}

# 安装Hysteria2
install_hysteria() {
    echo "正在安装Hysteria2..."

    # 创建Hysteria目录
    mkdir -p $HYSTERIA_DIR
    check_error "创建 Hysteria 目录" || return

    # 生成随机端口和密码
    PORT=$(generate_random_port)
    PASSWORD=$(generate_random_password)

    # 生成自签证书
    echo "正在生成自签证书..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout $HYSTERIA_DIR/server.key -out $HYSTERIA_DIR/server.crt -subj "/CN=example.com" -days 3650
    check_error "生成自签证书" || return

    # 创建配置文件
    echo "正在创建配置文件..."
    cat > $HYSTERIA_CONFIG <<EOF
listen: :$PORT
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $PASSWORD
EOF
    check_error "创建配置文件" || return

    # 下载并安装Hysteria二进制文件
    echo "正在下载Hysteria二进制文件..."
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" "$HYSTERIA_BINARY"
    check_error "下载 Hysteria 二进制文件" || return
    chmod +x $HYSTERIA_BINARY
    check_error "设置 Hysteria 二进制文件可执行权限" || return

    # 创建systemd服务
    echo "正在创建systemd服务..."
    cat > $HYSTERIA_SERVICE <<EOF
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
    check_error "创建 systemd 服务文件" || return

    # 重载systemd并启动服务
    echo "正在启动Hysteria2服务..."
    systemctl daemon-reload
    check_error "重载 systemd 配置" || return
    systemctl enable hysteria
    check_error "启用 Hysteria 服务" || return
    systemctl start hysteria
    check_error "启动 Hysteria 服务" || return

    echo "Hysteria2安装完成！"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "配置文件: $HYSTERIA_CONFIG"
    echo "日志文件: $LOG_FILE"
    read -p "按回车键返回主菜单..."
}

# 停止Hysteria2
stop_hysteria() {
    echo "正在停止Hysteria2..."
    systemctl stop hysteria
    check_error "停止 Hysteria 服务" || return
    echo "Hysteria2已停止。"
    read -p "按回车键返回主菜单..."
}

# 重启Hysteria2
restart_hysteria() {
    echo "正在重启Hysteria2..."
    systemctl restart hysteria
    check_error "重启 Hysteria 服务" || return
    echo "Hysteria2已重启。"
    read -p "按回车键返回主菜单..."
}

# 状态 Hysteria2
status_hysteria() {
    systemctl status hysteria
    check_error "查看 Hysteria 服务状态" || return
    read -p "按回车键返回主菜单..."
}

# 更新Hysteria2
update_hysteria() {
    echo "正在检查 Hysteria2 更新..."

    # 确保安装了 jq
    if ! command -v jq &> /dev/null; then
        echo "未安装 jq，正在安装..."
        install_dependencies
    fi

    # 获取当前版本
    CURRENT_VERSION=$(get_hysteria_version)
    if [ "$CURRENT_VERSION" == "未安装" ]; then
        echo "Hysteria2 未安装，请先安装。"
        read -p "按回车键返回主菜单..."
        return
    fi

    # 获取最新版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/HyNetwork/hysteria/releases/latest | jq -r .tag_name)
    if [ -z "$LATEST_VERSION" ]; then
        echo "无法获取最新版本信息。"
        read -p "按回车键返回主菜单..."
        return
    fi

    # 比较版本
    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo "当前已是最新版本，无需更新。"
    else
        echo "发现新版本: $LATEST_VERSION，正在更新..."

        # 停止服务
        systemctl stop hysteria
        check_error "停止 Hysteria 服务" || return

        # 下载并更新二进制文件
        echo "正在下载Hysteria二进制文件..."
        download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" "$HYSTERIA_BINARY"
        check_error "下载 Hysteria 二进制文件" || return
        chmod +x $HYSTERIA_BINARY
        check_error "设置 Hysteria 二进制文件可执行权限" || return

        # 启动服务
        systemctl start hysteria
        check_error "启动 Hysteria 服务" || return

        echo "Hysteria2 已更新到最新版本: $LATEST_VERSION"
    fi

    echo "当前 Hysteria2 版本: $(get_hysteria_version)"
    read -p "按回车键返回主菜单..."
}

# 卸载Hysteria2
uninstall_hysteria() {
    echo "正在卸载Hysteria2..."
    systemctl stop hysteria
    systemctl disable hysteria
    rm -f $HYSTERIA_SERVICE
    rm -f $HYSTERIA_BINARY
    rm -rf $HYSTERIA_DIR
    systemctl daemon-reload
    echo "Hysteria2已卸载。"
    read -p "按回车键返回主菜单..."
}

# 日志 Hysteria2
view_log() {
    echo "正在查看日志文件: $LOG_FILE"
    echo "----------------------------------------"
    cat $LOG_FILE
    echo "----------------------------------------"
    read -p "按回车键返回主菜单..."
}

# 生成二维码
generate_qr_code() {
    if ! command -v qrencode &> /dev/null; then
        echo "未安装 qrencode，正在安装..."
        install_dependencies
    fi

    echo "正在生成二维码..."
    qrencode -t ANSIUTF8 -o - <<< "$1"
}

# 客户端参数
view_client_config() {
    if [ ! -f "$HYSTERIA_CONFIG" ]; then
        echo "未找到 Hysteria 配置文件，请先安装 Hysteria2。"
        read -p "按回车键返回主菜单..."
        return
    fi

    # 获取服务器的 IPv4 和 IPv6 地址
    get_server_ips
    if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
        echo "无法获取服务器的 IP 地址。"
        read -p "按回车键返回主菜单..."
        return
    fi

    # 从配置文件中提取端口和密码
    PORT=$(grep -oP 'listen:\s*:\K\d+' $HYSTERIA_CONFIG)
    PASSWORD=$(grep -oP 'password:\s*\K\S+' $HYSTERIA_CONFIG)

    if [ -z "$PORT" ] || [ -z "$PASSWORD" ]; then
        echo "无法从配置文件中提取客户端设置。"
        read -p "按回车键返回主菜单..."
        return
    fi

    # 生成 Shadowrocket 支持的配置 URL
    if [ -n "$IPV4" ]; then
        SHADOWROCKET_URL_IPV4="hysteria2://$PASSWORD@$IPV4:$PORT/?insecure=1&sni=example.com#Hysteria2 (IPv4)"
        echo "----------------------------------------"
        echo "Shadowrocket 配置 URL (IPv4):"
        echo "$SHADOWROCKET_URL_IPV4"
        echo "----------------------------------------"
        echo "将以下内容复制到 Shadowrocket 客户端 (IPv4):"
        echo "$SHADOWROCKET_URL_IPV4"
        echo "----------------------------------------"
        generate_qr_code "$SHADOWROCKET_URL_IPV4"
    fi

    if [ -n "$IPV6" ]; then
        SHADOWROCKET_URL_IPV6="hysteria2://$PASSWORD@[$IPV6]:$PORT/?insecure=1&sni=example.com#Hysteria2 (IPv6)"
        echo "----------------------------------------"
        echo "Shadowrocket 配置 URL (IPv6):"
        echo "$SHADOWROCKET_URL_IPV6"
        echo "----------------------------------------"
        echo "将以下内容复制到 Shadowrocket 客户端 (IPv6):"
        echo "$SHADOWROCKET_URL_IPV6"
        echo "----------------------------------------"
        generate_qr_code "$SHADOWROCKET_URL_IPV6"
    fi

    read -p "按回车键返回主菜单..."
}

# 显示菜单
show_menu() {
    echo "======================================"
    echo " Hysteria2 管理脚本"
    echo "======================================"
    echo "1. 安装 Hysteria2"
    echo "2. 停止 Hysteria2"
    echo "3. 重启 Hysteria2"
    echo "4. 状态 Hysteria2"
    echo "5. 更新 Hysteria2"
    echo "6. 卸载 Hysteria2"
    echo "7. 日志 Hysteria2"
    echo "8. 客户端参数"
    echo "9. 退出脚本"
    echo "======================================"
}

# 主循环
while true; do
    show_menu
    read -p "请输入选项 (1-9): " OPTION
    case $OPTION in
        1) install_hysteria ;;
        2) stop_hysteria ;;
        3) restart_hysteria ;;
        4) status_hysteria ;;
        5) update_hysteria ;;
        6) uninstall_hysteria ;;
        7) view_log ;;
        8) view_client_config ;;
        9) break ;;
        *) echo "无效选项，请重新输入。" ;;
    esac
done

echo "脚本已退出。"
