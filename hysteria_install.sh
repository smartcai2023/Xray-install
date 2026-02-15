#!/bin/bash

# ====================================================
# Hysteria 2 Professional Management Script v2.0
# Enhanced Edition
# ====================================================

HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
SYSCTL_CONF="/etc/sysctl.d/99-hysteria.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LANGUAGE="zh"

# ========== Language Selection ==========
select_language() {
    clear
    echo "Please select language / 请选择语言:"
    echo "1. 中文 (Default)"
    echo "2. English"
    read -t 10 -p "Choice [1-2]: " lang_choice
    case $lang_choice in
        2) LANGUAGE="en" ;;
        *) LANGUAGE="zh" ;;
    esac
}

load_language() {
    declare -gA msg
    if [ "$LANGUAGE" == "zh" ]; then
        msg[welcome]="Hysteria 2 专业管理脚本 v2.0"
        msg[input_port]="请输入端口 (默认随机): "
        msg[input_pass]="请输入密码 (默认随机): "
        msg[input_hop]="是否开启端口跳跃? (y/N): "
        msg[done]="操作完成！"
        msg[root_req]="请以 root 运行"
    else
        msg[welcome]="Hysteria 2 Professional Script v2.0"
        msg[input_port]="Enter port (default random): "
        msg[input_pass]="Enter password (default random): "
        msg[input_hop]="Enable UDP port hopping? (y/N): "
        msg[done]="Completed!"
        msg[root_req]="Run as root"
    fi
}

# ========== Init ==========
init_sys() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}${msg[root_req]}${NC}" && exit 1

    command -v systemctl >/dev/null 2>&1 || {
        echo -e "${RED}Systemd not found!${NC}"
        exit 1
    }

    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "Unsupported architecture"; exit 1 ;;
    esac

    if [ -f /etc/debian_version ]; then
        apt update -y
        apt install -y curl openssl qrencode jq ca-certificates
        ln -sf "$0" /usr/bin/hy
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl openssl qrencode jq ca-certificates
    fi
}

# ========== MTU Detect ==========
detect_mtu() {
    MTU=1500
    for size in 1472 1464 1452 1440 1420 1400; do
        if ping -c1 -M do -s $size 8.8.8.8 &>/dev/null; then
            MTU=$((size+28))
            break
        fi
    done
    echo $MTU
}

# ========== Optimize ==========
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

    BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    echo -e "${BLUE}BBR status: $BBR_STATUS${NC}"
}

# ========== Firewall ==========
open_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $1/udp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$1/udp
        firewall-cmd --reload
    fi
}

# ========== Install ==========
install_hy2() {

    mkdir -p "$HYSTERIA_DIR"

    read -p "${msg[input_port]}" port
    port=${port:-$(shuf -i 10000-60000 -n 1)}

    ss -lun | grep -q ":$port " && {
        echo -e "${RED}Port already in use!${NC}"
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
Description=Hysteria 2 Server
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
    open_firewall $port

    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria

    echo -e "${GREEN}${msg[done]}${NC}"
    show_client_config
}

# ========== Client Info ==========
show_client_config() {

    port=$(grep -oP 'listen: :\K\d+' "$HYSTERIA_CONFIG")
    password=$(grep -oP 'password: \K\S+' "$HYSTERIA_CONFIG")
    SNI=$(openssl x509 -in $HYSTERIA_DIR/server.crt -noout -subject | awk -F= '{print $NF}')

    IPV4=$(curl -s4 --max-time 5 api.ipify.org || curl -s4 --max-time 5 ifconfig.me)
    IPV6=$(curl -s6 --max-time 5 api64.ipify.org)

    URL4="hysteria2://$password@$IPV4:$port/?insecure=1&sni=$SNI#Hy2_IPv4"
    echo -e "\n${GREEN}IPv4 Link:${NC}\n$URL4"
    qrencode -t ANSIUTF8 "$URL4"

    if [ -n "$IPV6" ]; then
        URL6="hysteria2://$password@[$IPV6]:$port/?insecure=1&sni=$SNI#Hy2_IPv6"
        echo -e "\n${GREEN}IPv6 Link:${NC}\n$URL6"
        qrencode -t ANSIUTF8 "$URL6"
    fi

    echo -e "\nMTU detected: $(detect_mtu)"
}

# ========== Menu ==========
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================="
        echo -e "  ${msg[welcome]}"
        echo -e "==================================${NC}"
        echo "1. Install / Update"
        echo "2. Restart"
        echo "3. Stop"
        echo "4. Status"
        echo "5. Show Config"
        echo "6. Logs"
        echo "7. Uninstall"
        echo "8. Exit"
        read -p "Choice: " choice
        case $choice in
            1) install_hy2 ;;
            2) systemctl restart hysteria ;;
            3) systemctl stop hysteria ;;
            4) systemctl status hysteria ;;
            5) show_client_config ;;
            6) journalctl -u hysteria -f ;;
            7) rm -rf "$HYSTERIA_DIR" "$HYSTERIA_BINARY" "$HYSTERIA_SERVICE" "$SYSCTL_CONF"; systemctl daemon-reload ;;
            8) exit ;;
        esac
        read -p "Press Enter..."
    done
}

# ========== Run ==========
select_language
load_language
init_sys
main_menu
