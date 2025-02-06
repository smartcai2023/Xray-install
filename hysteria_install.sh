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
    if [ $? -ne 0 ]; then
        echo -e "\033[31m错误: $error_msg\033[0m"
        return 1
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
    check_error "安装依赖"
}

# 自动检测最佳 MTU
get_best_mtu() {
    local best_mtu=$(ping -c 4 -M do -s 1472 8.8.8.8 2>/dev/null | awk -F'=' '/bytes from/{print $NF}' | sort -n | tail -n1)
    if [[ -z "$best_mtu" ]]; then
        best_mtu=1400 # 默认 MTU
    fi
    echo "$best_mtu"
}

# 设置 UDP 缓冲区优化
optimize_udp_buffer() {
    echo "优化 UDP 缓冲区..."
    sysctl -w net.core.rmem_max=2500000
    sysctl -w net.core.wmem_max=2500000
}

# 生成端口跳跃配置
generate_port_hopping() {
    local start_port=$1
    local end_port=$2
    echo "port_hopping: { min: $start_port, max: $end_port }"
}

# 安装 Hysteria2
install_hysteria() {
    echo -e "\033[34m正在安装 Hysteria2...\033[0m"
    mkdir -p "$HYSTERIA_DIR" && chmod 755 "$HYSTERIA_DIR"
    check_error "创建 Hysteria 目录" || return

    local port password mtu
    read -p "请输入端口范围 (格式: 端口1-端口2, 默认 40000-50000): " port_range
    IFS='-' read -r start_port end_port <<< "${port_range:-40000-50000}"
    mtu=$(get_best_mtu)
    optimize_udp_buffer

    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

    echo -e "\033[34m正在创建配置文件...\033[0m"
    cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$start_port
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $password
mtu: $mtu
$(generate_port_hopping "$start_port" "$end_port")
EOF
    check_error "创建配置文件" || return

    systemctl daemon-reload
    systemctl enable hysteria
    systemctl start hysteria
    echo -e "\033[32mHysteria2 安装完成！\033[0m"
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
    read -p "请输入选项 (1-9): " option
    case $option in
        1) install_hysteria ;;
        2) systemctl stop hysteria ;;
        3) systemctl restart hysteria ;;
        4) systemctl status hysteria ;;
        5) update_hysteria ;;
        6) uninstall_hysteria ;;
        7) cat "$LOG_FILE" ;;
        8) generate_client_config ;;
        9) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

# 设置快捷方式 (仅 Debian/Ubuntu)
setup_hy_command() {
    if [[ "$(lsb_release -si)" =~ (Debian|Ubuntu) ]]; then
        echo "#!/bin/bash" > /usr/local/bin/hy
        echo "$(declare -f show_menu)" >> /usr/local/bin/hy
        echo "show_menu" >> /usr/local/bin/hy
        chmod +x /usr/local/bin/hy
    fi
}

# 运行主函数
if [ "$EUID" -eq 0 ]; then
    setup_hy_command
    show_menu
else
    echo -e "\033[31m请以 root 用户运行此脚本。\033[0m"
fi
