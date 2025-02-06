#!/bin/bash

# 定义常量
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
LOG_FILE="/var/log/hysteria_install.log"
CLIENT_CONFIG="$HYSTERIA_DIR/client.json"
HY_ALIAS="/usr/local/bin/hy"

# 初始化日志
init_log() {
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "------------------- Hysteria2 安装日志 -------------------"
}

# 检测最佳 MTU 值
get_best_mtu() {
    echo -e "\033[34m检测最佳 MTU 值...\033[0m"
    local base_mtu=1500
    local target_ip="1.1.1.1"
    while ping -M do -c 1 -s $((base_mtu - 28)) "$target_ip" &>/dev/null; do
        ((base_mtu--))
    done
    echo "最佳 MTU: $((base_mtu + 1))"
    echo $((base_mtu + 1))
}

# 优化 UDP 缓冲区
optimize_udp_buffer() {
    echo -e "\033[34m优化 UDP 缓冲区设置...\033[0m"
    sysctl -w net.core.rmem_max=26214400
    sysctl -w net.core.wmem_max=26214400
    sysctl -w net.core.rmem_default=26214400
    sysctl -w net.core.wmem_default=26214400
    sysctl -p
}

# 生成随机端口或端口跳跃范围
generate_ports() {
    local base_port=$(shuf -i 10000-60000 -n 1)
    local step=$(shuf -i 1-10 -n 1)
    echo "$base_port"
    echo "$((base_port + step * 10))"
}

# 安装 Hysteria2
install_hysteria() {
    echo -e "\033[34m正在安装 Hysteria2...\033[0m"
    mkdir -p "$HYSTERIA_DIR" && chmod 755 "$HYSTERIA_DIR"
    check_error "创建 Hysteria 目录" true || return

    local mtu=$(get_best_mtu)
    optimize_udp_buffer

    read -p "是否启用端口跳跃？(y/n, 默认 n): " PORT_JUMP
    local port port_jump
    if [[ "$PORT_JUMP" =~ ^[yY] ]]; then
        port=$(generate_ports | head -n1)
        port_jump=$(generate_ports | tail -n1)
    else
        port=$(shuf -i 1000-65535 -n 1)
    fi

    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo -e "\033[34m正在创建配置文件...\033[0m"
    cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$port
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $password
  mtu: $mtu
$( [[ "$PORT_JUMP" =~ ^[yY] ]] && echo "  port_range: [$port, $port_jump]" )
EOF
    check_error "创建配置文件" true || return
}

# 设置快捷命令
setup_alias() {
    if [[ "$(lsb_release -si)" == "Debian" ]]; then
        echo -e "\033[34m设置 hy 命令快捷方式...\033[0m"
        echo "#!/bin/bash" > "$HY_ALIAS"
        echo "$0" >> "$HY_ALIAS"
        chmod +x "$HY_ALIAS"
    fi
}

# 主函数
main() {
    init_log
    detect_system
    setup_alias
    while true; do
        show_menu
        read -p "" option
        case $option in
            1) install_hysteria ;;
            9) exit 0 ;;
        esac
    done
}

# 运行主函数
if [ "$EUID" -eq 0 ]; then
    main
else
    echo -e "\033[31m请以 root 用户运行此脚本。\033[0m"
fi
