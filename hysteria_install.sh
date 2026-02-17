#!/bin/bash

# ====================================================
# Hysteria2 Professional Script v2.3
# Multi-language & True Port Hopping Support
# ====================================================

HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
SYSCTL_CONF="/etc/sysctl.d/99-hysteria.conf"
SELF_INSTALL_PATH="/usr/local/bin/hy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LANGUAGE="zh"

# ================= 自安装 hy 命令 =================
install_self() {
    SCRIPT_REAL_PATH="$(realpath "$0")"
    if [ "$SCRIPT_REAL_PATH" != "$SELF_INSTALL_PATH" ]; then
        install -m 755 "$SCRIPT_REAL_PATH" "$SELF_INSTALL_PATH"
        echo -e "${GREEN}已安装 hy 命令到 /usr/local/bin/hy${NC}"
    fi
}

# ================= 语言选择 =================
select_language() {
    clear
    echo "请选择语言 / Please select language:"
    echo "1. 中文 (默认)"
    echo "2. English"
    read -t 10 -p "选择 [1-2]: " lang_choice
    case $lang_choice in
        2) LANGUAGE="en" ;;
        *) LANGUAGE="zh" ;;
    esac
}

load_language() {
    declare -gA msg
    if [ "$LANGUAGE" == "zh" ]; then
        msg[welcome]="Hysteria2 专业管理脚本 v2.3"
        msg[install]="安装 / 更新"
        msg[restart]="重启服务"
        msg[stop]="停止服务"
        msg[status]="查看状态"
        msg[config]="显示连接信息"
        msg[log]="查看实时日志"
        msg[uninstall]="卸载 Hysteria2"
        msg[exit]="退出"
        msg[input_port]="请输入主监听端口(默认随机): "
        msg[input_pass]="请输入密码(默认随机): "
        msg[input_hop]="是否开启端口跳跃? (y/N): "
        msg[input_hop_range]="请输入跳跃端口范围 (示例 20000-50000): "
        msg[done]="操作完成"
        msg[root]="请用 root 运行"
    else
        msg[welcome]="Hysteria2 Professional Script v2.3"
        msg[install]="Install / Update"
        msg[restart]="Restart Service"
        msg[stop]="Stop Service"
        msg[status]="View Status"
        msg[config]="Show Config"
        msg[log]="View Logs"
        msg[uninstall]="Uninstall"
        msg[exit]="Exit"
        msg[input_port]="Enter main port (default random): "
        msg[input_pass]="Enter password (default random): "
        msg[input_hop]="Enable Port Hopping? (y/N): "
        msg[input_hop_range]="Enter hopping range (e.g. 20000-50000): "
        msg[done]="Completed"
        msg[root]="Run as root"
    fi
}

# ================= 初始化 =================
init_sys() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}${msg[root]}${NC}" && exit 1
    
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "Unsupported arch"; exit 1 ;;
    esac

    if [ -f /etc/debian_version ]; then
        apt update -y && apt install -y curl openssl qrencode jq ca-certificates iptables
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl openssl qrencode jq ca-certificates iptables
    fi
}

# ================= MTU 探测 =================
detect_mtu() {
    local mtu=1500
    for size in 1472 1462 1440 1420 1400 1380; do
        if ping -c1 -W1 -M do -s $size 8.8.8.8 &>/dev/null; then
            mtu=$((size + 28))
            break
        fi
    done
    echo $mtu
}

# ================= 网络优化 =================
optimize_network() {
    cat > "$SYSCTL_CONF" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_ecn=1
EOF
    sysctl --system >/dev/null 2>&1
}

# ================= 安装逻辑 =================
install_hy2() {
    mkdir -p "$HYSTERIA_DIR"

    read -p "${msg[input_port]}" port
    port=${port:-$(shuf -i 10000-60000 -n 1)}

    read -p "${msg[input_pass]}" password
    password=${password:-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)}

    read -p "${msg[input_hop]}" hop_choice
    if [[ "$hop_choice" =~ ^[Yy]$ ]]; then
        read -p "${msg[input_hop_range]}" hop_range
        HOP_ENABLE=true
    else
        HOP_ENABLE=false
    fi

    # 下载二进制
    echo -e "${BLUE}正在下载 Hysteria2 ($ARCH)...${NC}"
    curl -L -o "$HYSTERIA_BINARY" "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-$ARCH"
    chmod +x "$HYSTERIA_BINARY"

    # 生成自签证书
    SNI=$(shuf -n1 -e cloudflare.com microsoft.com apple.com bing.com)
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$HYSTERIA_DIR/server.key" -out "$HYSTERIA_DIR/server.crt" \
        -subj "/CN=$SNI" -days 3650 -batch

    # 写入配置
    cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$port
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $password
udp:
  hop: $HOP_ENABLE
ignoreClientBandwidth: true
EOF

    # 注入端口跳跃规则
    if [ "$HOP_ENABLE" = true ] && [ -n "$hop_range" ]; then
        cat >> "$HYSTERIA_CONFIG" <<EOF
preActions:
  - cmd: "iptables -t nat -A PREROUTING -p udp --dport $hop_range -j REDIRECT --to-ports $port"
  - cmd: "ip6tables -t nat -A PREROUTING -p udp --dport $hop_range -j REDIRECT --to-ports $port"
postActions:
  - cmd: "iptables -t nat -D PREROUTING -p udp --dport $hop_range -j REDIRECT --to-ports $port"
  - cmd: "ip6tables -t nat -D PREROUTING -p udp --dport $hop_range -j REDIRECT --to-ports $port"
EOF
    fi

    # 创建 Service
    cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target
[Service]
Type=simple
ExecStart=$HYSTERIA_BINARY server --config $HYSTERIA_CONFIG
Restart=always
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
[Install]
WantedBy=multi-user.target
EOF

    optimize_network
    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria
    echo -e "${GREEN}${msg[done]}${NC}"
}

# ================= 显示配置 =================
show_config() {
    if [ ! -f "$HYSTERIA_CONFIG" ]; then
        echo -e "${RED}未找到配置文件${NC}"
        return
    fi

    local port=$(grep -oP 'listen: :\K\d+' "$HYSTERIA_CONFIG")
    local password=$(grep -oP 'password: \K\S+' "$HYSTERIA_CONFIG")
    local SNI=$(openssl x509 -in $HYSTERIA_DIR/server.crt -noout -subject | awk -F= '{print $NF}' | xargs)
    local IP=$(curl -s4 --max-time 5 api.ipify.org || curl -s4 --max-time 5 ifconfig.me)
    local hop_range=$(grep -oP 'dport \K[0-9:-]+' "$HYSTERIA_CONFIG" | head -n1)

    local URL="hysteria2://$password@$IP:$port/?insecure=1&sni=$SNI"
    [ -n "$hop_range" ] && URL="${URL}&mport=${hop_range}"
    URL="${URL}#Hy2_$IP"

    echo -e "\n${BLUE}========== Hysteria 2 链接 ==========${NC}"
    echo -e "${GREEN}$URL${NC}"
    echo -e "${BLUE}=====================================${NC}"
    qrencode -t ANSIUTF8 "$URL"
    
    echo -e "\n服务器建议 MTU: ${YELLOW}$(detect_mtu)${NC} (若连接不稳定请在客户端设置此值)"
}

# ================= 卸载 =================
uninstall_hy2() {
    systemctl stop hysteria 2>/dev/null
    systemctl disable hysteria 2>/dev/null
    rm -rf "$HYSTERIA_DIR" "$HYSTERIA_BINARY" "$HYSTERIA_SERVICE" "$SYSCTL_CONF" "$SELF_INSTALL_PATH"
    systemctl daemon-reload
    echo -e "${GREEN}已彻底卸载。${NC}"
    exit 0
}

# ================= 菜单 =================
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================="
        echo -e "  ${msg[welcome]}"
        echo -e "==================================${NC}"
        echo "1. ${msg[install]}"
        echo "2. ${msg[restart]}"
        echo "3. ${msg[stop]}"
        echo "4. ${msg[status]}"
        echo "5. ${msg[config]}"
        echo "6. ${msg[log]}"
        echo "7. ${msg[uninstall]}"
        echo "8. ${msg[exit]}"
        read -p "选择: " num
        case $num in
            1) install_hy2 ;;
            2) systemctl restart hysteria && echo "已重启" ;;
            3) systemctl stop hysteria && echo "已停止" ;;
            4) systemctl status hysteria ;;
            5) show_config ;;
            6) journalctl -u hysteria -f ;;
            7) uninstall_hy2 ;;
            8) exit ;;
            *) echo "无效输入" ;;
        esac
        read -p "按回车继续..."
    done
}

# ================= 启动流程 =================
install_self
select_language
load_language
init_sys
main_menu
