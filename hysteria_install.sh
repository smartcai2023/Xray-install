#!/bin/bash

# ====================================================
# Hysteria2 Professional Script v2.2
# Fixed HY Command Installation
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

    # 如果当前不是从 /usr/local/bin/hy 运行，则安装自身
    if [ "$SCRIPT_REAL_PATH" != "$SELF_INSTALL_PATH" ]; then
        install -m 755 "$SCRIPT_REAL_PATH" "$SELF_INSTALL_PATH"
        echo -e "${GREEN}已安装 hy 命令到 /usr/local/bin/hy${NC}"
        echo -e "${YELLOW}请使用 hy 重新运行脚本${NC}"
        exit 0
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
        msg[welcome]="Hysteria2 专业管理脚本 v2.2"
        msg[install]="安装 / 更新"
        msg[restart]="重启服务"
        msg[stop]="停止服务"
        msg[status]="查看状态"
        msg[config]="显示连接信息"
        msg[log]="查看实时日志"
        msg[uninstall]="卸载 Hysteria2"
        msg[exit]="退出"
        msg[input_port]="请输入端口(默认随机): "
        msg[input_pass]="请输入密码(默认随机): "
        msg[input_hop]="开启端口跳跃? (y/N): "
        msg[done]="操作完成"
        msg[root]="请用 root 运行"
    else
        msg[welcome]="Hysteria2 Professional Script v2.2"
        msg[install]="Install / Update"
        msg[restart]="Restart Service"
        msg[stop]="Stop Service"
        msg[status]="View Status"
        msg[config]="Show Config"
        msg[log]="View Logs"
        msg[uninstall]="Uninstall"
        msg[exit]="Exit"
        msg[input_port]="Enter port (default random): "
        msg[input_pass]="Enter password (default random): "
        msg[input_hop]="Enable UDP hop? (y/N): "
        msg[done]="Completed"
        msg[root]="Run as root"
    fi
}

# ================= 初始化 =================
init_sys() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}${msg[root]}${NC}" && exit 1

    command -v systemctl >/dev/null 2>&1 || {
        echo "Systemd required"
        exit 1
    }

    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "Unsupported arch"; exit 1 ;;
    esac

    if [ -f /etc/debian_version ]; then
        apt update -y
        apt install -y curl openssl qrencode jq ca-certificates
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl openssl qrencode jq ca-certificates
    fi
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
EOF
sysctl --system >/dev/null 2>&1
}

# ================= 防火墙 =================
open_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $1/udp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$1/udp
        firewall-cmd --reload
    fi
}

remove_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow $1/udp 2>/dev/null
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --remove-port=$1/udp
        firewall-cmd --reload
    fi
}

# ================= 安装 =================
install_hy2() {

    mkdir -p "$HYSTERIA_DIR"

    read -p "${msg[input_port]}" port
    port=${port:-$(shuf -i 10000-60000 -n 1)}

    ss -lun | grep -q ":$port " && {
        echo "端口已占用"
        return
    }

    read -p "${msg[input_pass]}" password
    password=${password:-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)}

    read -p "${msg[input_hop]}" hop
    [[ "$hop" =~ ^[Yy]$ ]] && HOP="true" || HOP="false"

    curl -L -o "$HYSTERIA_BINARY" \
    "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-$ARCH"
    chmod +x "$HYSTERIA_BINARY"

    SNI=$(shuf -n1 -e cloudflare.com microsoft.com apple.com)

    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$HYSTERIA_DIR/server.key" \
        -out "$HYSTERIA_DIR/server.crt" \
        -subj "/CN=$SNI" -days 3650 -batch

cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$port
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $password
udp:
  hop: $HOP
ignoreClientBandwidth: true
EOF

cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target
[Service]
ExecStart=$HYSTERIA_BINARY server --config $HYSTERIA_CONFIG
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    optimize_network
    open_firewall $port

    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria

    echo -e "${GREEN}${msg[done]}${NC}"
}

# ================= 显示配置 =================
show_config() {
    port=$(grep -oP 'listen: :\K\d+' "$HYSTERIA_CONFIG")
    password=$(grep -oP 'password: \K\S+' "$HYSTERIA_CONFIG")
    SNI=$(openssl x509 -in $HYSTERIA_DIR/server.crt -noout -subject | awk -F= '{print $NF}')
    IP=$(curl -s4 api.ipify.org || hostname -I | awk '{print $1}')

    URL="hysteria2://$password@$IP:$port/?insecure=1&sni=$SNI#Hy2"
    echo -e "\n$URL"
    qrencode -t ANSIUTF8 "$URL"
}

# ================= 卸载 =================
uninstall_hy2() {

    port=$(grep -oP 'listen: :\K\d+' "$HYSTERIA_CONFIG" 2>/dev/null)

    systemctl stop hysteria 2>/dev/null
    systemctl disable hysteria 2>/dev/null

    remove_firewall $port

    rm -rf "$HYSTERIA_DIR"
    rm -f "$HYSTERIA_BINARY"
    rm -f "$HYSTERIA_SERVICE"
    rm -f "$SYSCTL_CONF"
    rm -f "$SELF_INSTALL_PATH"

    systemctl daemon-reload

    echo "已完全卸载"
    exit 0
}

# ================= 菜单 =================
main_menu() {
while true; do
clear
echo -e "${BLUE}=============================="
echo -e " ${msg[welcome]}"
echo -e "==============================${NC}"
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
2) systemctl restart hysteria ;;
3) systemctl stop hysteria ;;
4) systemctl status hysteria ;;
5) show_config ;;
6) journalctl -u hysteria -f ;;
7) uninstall_hy2 ;;
8) exit ;;
esac
read -p "回车继续..."
done
}

# ================= 启动流程 =================
install_self
select_language
load_language
init_sys
main_menu
