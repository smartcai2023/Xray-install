#!/bin/bash
set -euo pipefail

# ========================== 常量定义 ==========================
# 基础路径配置
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria.service"
HYSTERIA_BINARY="/usr/local/bin/hysteria"
LOG_FILE="/var/log/hysteria_install.log"
CLIENT_CONFIG="$HYSTERIA_DIR/client.json"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m' # No Color

# ========================== 工具函数 ==========================
# 初始化日志系统
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ------------------- Hysteria2 安装日志 -------------------"
}

# 错误处理函数
error_exit() {
    local error_msg="$1"
    local exit_code="${2:-1}"
    echo -e "\n${RED}[错误] $(date '+%Y-%m-%d %H:%M:%S'): $error_msg${NC}" >&2
    exit "$exit_code"
}

# 信息提示函数
info_msg() {
    echo -e "\n${BLUE}[信息] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}"
}

# 成功提示函数
success_msg() {
    echo -e "\n${GREEN}[成功] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}"
}

# 警告提示函数
warn_msg() {
    echo -e "\n${YELLOW}[警告] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "命令 $1 未找到，请先安装"
    fi
}

# ========================== 核心功能函数 ==========================
# 系统检测和依赖安装
detect_system() {
    info_msg "开始检测系统环境..."
    
    # 检查 lsb_release 命令
    if ! command -v lsb_release &> /dev/null; then
        info_msg "正在安装 lsb-release..."
        if [ -f /etc/debian_version ]; then
            apt update && apt install -y lsb-release
        elif [ -f /etc/redhat-release ]; then
            yum install -y redhat-lsb-core
        else
            error_exit "无法检测系统类型，不支持的操作系统"
        fi
    fi

    # 检测系统发行版
    local os_name=$(lsb_release -si)
    case "$os_name" in
        "Ubuntu" | "Debian")
            pkg_manager="apt"
            install_cmd="apt update -y && apt install -y"
            ;;
        "CentOS" | "Amazon" | "Rocky" | "AlmaLinux")
            pkg_manager="yum"
            install_cmd="yum install -y"
            ;;
        *)
            error_exit "不支持的系统类型: $os_name，仅支持 Ubuntu/Debian/CentOS/Amazon/Rocky/AlmaLinux"
            ;;
    esac

    info_msg "检测到 $os_name 系统，使用 $pkg_manager 安装依赖..."
    eval "$install_cmd curl openssl qrencode jq net-tools" || error_exit "安装依赖失败"
    
    # 检查必要命令
    check_command "curl"
    check_command "openssl"
    check_command "jq"
    check_command "qrencode"
    
    success_msg "系统检测和依赖安装完成"
}

# 下载文件（带重试机制和进度条）
download_file() {
    local url="$1"
    local output="$2"
    local retries="${3:-3}"
    local delay="${4:-2}"

    for ((i=1; i<=retries; i++)); do
        info_msg "正在下载文件 (尝试 $i/$retries): $url"
        if curl -fsSL --progress-bar -o "$output" "$url"; then
            success_msg "下载成功: $output"
            return 0
        else
            warn_msg "下载失败，等待 $delay 秒后重试..."
            sleep "$delay"
        fi
    done
    error_exit "下载失败: $url"
}

# 随机生成端口和密码（增强随机性）
generate_random_config() {
    # 排除知名端口，使用更安全的随机范围
    local port=$(shuf -i 10000-65535 -n 1)
    # 使用更强的随机密码生成方式
    local password=$(openssl rand -base64 16 | tr -d /=+ | cut -c -16)
    
    echo "$port"
    echo "$password"
}

# 获取服务器IP地址（多源检测）
get_server_ips() {
    info_msg "正在检测服务器IP地址..."
    
    # 多源获取IP，提高成功率
    local ipv4=$(curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || echo "")
    local ipv6=$(curl -6 -s --max-time 5 ifconfig.me || curl -6 -s --max-time 5 icanhazip.com || echo "")
    
    if [ -z "$ipv4" ] && [ -z "$ipv6" ]; then
        warn_msg "无法获取服务器公网IP地址"
    fi
    
    echo "$ipv4"
    echo "$ipv6"
}

# 版本比较函数（修复逻辑）
version_compare() {
    local current="$1"
    local latest="$2"
    
    # 移除版本号前缀的v
    current=${current#v}
    latest=${latest#v}
    
    # 使用 sort -V 进行版本比较
    if [ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -n1)" = "$latest" ] && [ "$current" != "$latest" ]; then
        return 0  # 有更新
    else
        return 1  # 无更新
    fi
}

# 优化系统参数（安全追加，不覆盖原有配置）
optimize_system() {
    info_msg "正在优化系统网络参数..."
    
    # 检查并追加配置，避免重复
    local sysctl_conf="/etc/sysctl.conf"
    local temp_conf=$(mktemp)
    
    # 保留原有配置，过滤掉重复的参数
    grep -vE '^(net.core.default_qdisc|net.ipv4.tcp_congestion_control|net.ipv4.tcp_fastopen|net.ipv4.tcp_max_syn_backlog|net.ipv4.tcp_max_tw_buckets|net.ipv4.tcp_tw_reuse|net.ipv4.tcp_tw_recycle|net.ipv4.tcp_fin_timeout|net.ipv4.tcp_keepalive_time|net.ipv4.tcp_keepalive_intvl|net.ipv4.tcp_keepalive_probes)=' "$sysctl_conf" > "$temp_conf"
    
    # 添加优化参数
    cat >> "$temp_conf" <<EOF
# Hysteria2 网络优化参数
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_max_tw_buckets=5000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_tw_recycle=0
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=30
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=3
EOF
    
    # 替换配置文件
    mv "$temp_conf" "$sysctl_conf"
    chmod 644 "$sysctl_conf"
    
    # 应用配置
    sysctl -p || warn_msg "部分系统参数无法立即生效，重启后生效"
    
    success_msg "系统参数优化完成"
}

# 安装Hysteria2
install_hysteria() {
    info_msg "开始安装 Hysteria2..."

    # 创建目录
    mkdir -p "$HYSTERIA_DIR" && chmod 755 "$HYSTERIA_DIR" || error_exit "创建 Hysteria 目录失败"

    # 用户自定义配置
    read -p "是否自定义端口和密码？(y/n, 默认 n): " -r CUSTOM_CONFIG
    CUSTOM_CONFIG=${CUSTOM_CONFIG:-n}
    
    local port password
    if [[ "$CUSTOM_CONFIG" =~ ^[yY]$ ]]; then
        read -p "请输入自定义端口 (10000-65535): " -r CUSTOM_PORT
        read -p "请输入自定义密码: " -r CUSTOM_PASSWORD
        
        # 验证端口合法性
        if [[ -n "$CUSTOM_PORT" && ! "$CUSTOM_PORT" =~ ^[0-9]+$ ]]; then
            error_exit "端口必须是数字"
        fi
        if [[ -n "$CUSTOM_PORT" && ( "$CUSTOM_PORT" -lt 10000 || "$CUSTOM_PORT" -gt 65535 ) ]]; then
            error_exit "端口必须在 10000-65535 范围内"
        fi
        
        port=${CUSTOM_PORT:-$(generate_random_config | head -n1)}
        password=${CUSTOM_PASSWORD:-$(generate_random_config | tail -n1)}
    else
        port=$(generate_random_config | head -n1)
        password=$(generate_random_config | tail -n1)
    fi

    # 优化系统参数
    optimize_system

    # 生成自签证书（更安全的参数）
    info_msg "正在生成自签证书..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$HYSTERIA_DIR/server.key" -out "$HYSTERIA_DIR/server.crt" \
        -subj "/CN=hysteria2-server" -days 3650 -batch || error_exit "生成自签证书失败"
    
    chmod 600 "$HYSTERIA_DIR/server.key"  # 证书密钥更安全的权限
    chmod 644 "$HYSTERIA_DIR/server.crt"

    # 创建优化后的配置文件
    info_msg "正在创建配置文件..."
    cat > "$HYSTERIA_CONFIG" <<EOF
# Hysteria2 服务器配置
listen: :$port
tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
auth:
  type: password
  password: $password
udp: true
multiplex: true
conn:
  send_window: 1024
  recv_window: 1024
  max_packet_size: 1500
logging:
  level: info
  output: /var/log/hysteria_server.log
EOF
    chmod 600 "$HYSTERIA_CONFIG" || error_exit "创建配置文件失败"

    # 下载并安装二进制文件
    info_msg "正在下载 Hysteria 二进制文件..."
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" \
        "$HYSTERIA_BINARY" 3 5
    
    chmod +x "$HYSTERIA_BINARY" || error_exit "设置可执行权限失败"

    # 创建systemd服务（增强稳定性）
    info_msg "正在创建 systemd 服务..."
    cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Hysteria VPN Service
After=network.target network-online.target
Wants=network-online.target

[Service]
ExecStart=$HYSTERIA_BINARY server --config $HYSTERIA_CONFIG
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
User=root
LimitNOFILE=65535
CPUWeight=100
IOWeight=100
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$HYSTERIA_SERVICE" || error_exit "创建服务文件失败"

    # 启动服务
    systemctl daemon-reload || error_exit "重载 systemd 配置失败"
    systemctl enable --now hysteria || error_exit "启动 Hysteria 服务失败"
    
    # 验证服务状态
    if systemctl is-active --quiet hysteria; then
        success_msg "Hysteria2 安装并启动成功！"
        echo -e "\n${YELLOW}配置信息：${NC}"
        echo -e "端口: ${GREEN}$port${NC}"
        echo -e "密码: ${GREEN}$password${NC}"
        echo -e "配置文件: ${GREEN}$HYSTERIA_CONFIG${NC}"
        echo -e "日志文件: ${GREEN}$LOG_FILE${NC}"
        echo -e "服务日志: ${GREEN}/var/log/hysteria_server.log${NC}"
    else
        error_exit "Hysteria2 服务启动失败，请检查日志"
    fi
}

# 停止服务
stop_service() {
    info_msg "正在停止 Hysteria2..."
    
    if systemctl is-active --quiet hysteria; then
        systemctl stop hysteria || error_exit "停止 Hysteria 服务失败"
        success_msg "Hysteria2 已停止"
    else
        warn_msg "Hysteria2 服务未运行"
    fi
}

# 重启服务
restart_service() {
    info_msg "正在重启 Hysteria2..."
    
    if systemctl is-enabled --quiet hysteria; then
        systemctl restart hysteria || error_exit "重启 Hysteria 服务失败"
        
        # 验证重启结果
        if systemctl is-active --quiet hysteria; then
            success_msg "Hysteria2 已重启"
        else
            error_exit "Hysteria2 重启后未正常运行"
        fi
    else
        error_exit "Hysteria2 服务未安装或未启用"
    fi
}

# 查看服务状态
view_status() {
    info_msg "查看 Hysteria2 状态..."
    
    echo -e "\n${YELLOW}服务状态：${NC}"
    systemctl status hysteria --no-pager
    
    echo -e "\n${YELLOW}端口监听：${NC}"
    ss -tulpn | grep hysteria || echo "未发现 Hysteria 端口监听"
    
    echo -e "\n${YELLOW}进程信息：${NC}"
    ps aux | grep hysteria | grep -v grep || echo "未发现 Hysteria 进程"
}

# 更新Hysteria2
update_hysteria() {
    info_msg "正在检查 Hysteria2 更新..."

    # 检查是否已安装
    if [ ! -f "$HYSTERIA_BINARY" ]; then
        error_exit "Hysteria2 未安装，无法更新"
    fi

    # 获取当前版本
    local current_version=$("$HYSTERIA_BINARY" version 2>/dev/null | awk '{print $2}')
    if [ -z "$current_version" ]; then
        error_exit "无法获取当前版本信息"
    fi

    # 获取最新版本
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/HyNetwork/hysteria/releases/latest" | jq -r '.tag_name')
    
    # 备用获取方式
    if [ "$latest_version" = "null" ] || [ -z "$latest_version" ]; then
        latest_version=$(curl -s "https://github.com/HyNetwork/hysteria/releases/latest" | grep -oP 'releases/tag/\Kv\d+\.\d+\.\d+' | head -n1)
    fi

    if [ -z "$latest_version" ]; then
        error_exit "无法获取最新版本信息"
    fi

    # 比较版本
    if ! version_compare "$current_version" "$latest_version"; then
        success_msg "当前已是最新版本：$current_version"
        return
    fi

    info_msg "发现新版本：$latest_version，当前版本：$current_version，正在更新..."
    
    # 备份当前二进制文件
    cp "$HYSTERIA_BINARY" "${HYSTERIA_BINARY}.old" || warn_msg "备份当前版本失败"
    
    # 停止服务并更新
    stop_service
    
    # 下载新版本
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" \
        "$HYSTERIA_BINARY" 3 5
    
    chmod +x "$HYSTERIA_BINARY" || error_exit "设置可执行权限失败"
    
    # 验证新版本
    local new_version=$("$HYSTERIA_BINARY" version 2>/dev/null | awk '{print $2}')
    if [ -z "$new_version" ]; then
        # 回滚
        mv "${HYSTERIA_BINARY}.old" "$HYSTERIA_BINARY"
        error_exit "新版本验证失败，已回滚到旧版本"
    fi

    # 启动服务
    systemctl start hysteria || error_exit "启动新版本失败"
    
    success_msg "Hysteria2 已更新到版本：$new_version"
}

# 卸载Hysteria2
uninstall_hysteria() {
    read -p "确定要卸载 Hysteria2 吗？(y/n): " -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        info_msg "卸载操作已取消"
        return
    fi

    info_msg "正在卸载 Hysteria2..."
    
    # 停止并禁用服务
    if systemctl is-active --quiet hysteria; then
        systemctl stop hysteria
    fi
    
    if systemctl is-enabled --quiet hysteria; then
        systemctl disable hysteria
    fi
    
    # 删除文件
    rm -f "$HYSTERIA_SERVICE"
    rm -f "$HYSTERIA_BINARY"
    rm -f "${HYSTERIA_BINARY}.old"
    rm -rf "$HYSTERIA_DIR"
    rm -f "/var/log/hysteria_server.log"
    
    systemctl daemon-reload
    
    success_msg "Hysteria2 已完全卸载"
}

# 查看日志
view_log() {
    info_msg "查看安装日志：$LOG_FILE"
    echo -e "${YELLOW}=================== 安装日志 ===================${NC}"
    tail -n 50 "$LOG_FILE" || error_exit "无法读取日志文件"
    
    # 同时显示服务运行日志
    if [ -f "/var/log/hysteria_server.log" ]; then
        echo -e "\n${YELLOW}=================== 服务日志 ===================${NC}"
        tail -n 20 "/var/log/hysteria_server.log"
    fi
}

# 生成客户端配置
generate_client_config() {
    if [ ! -f "$HYSTERIA_CONFIG" ]; then
        error_exit "未找到 Hysteria 配置文件，请先安装 Hysteria2"
    fi

    # 提取配置信息
    local ipv4=$(get_server_ips | head -n1)
    local ipv6=$(get_server_ips | tail -n1)
    local port=$(grep -oP 'listen:\s*:\K\d+' "$HYSTERIA_CONFIG")
    local password=$(grep -oP 'password:\s*\K\S+' "$HYSTERIA_CONFIG")

    if [ -z "$port" ] || [ -z "$password" ]; then
        error_exit "无法从配置文件中提取客户端设置"
    fi

    info_msg "生成客户端配置信息..."
    echo -e "\n${YELLOW}=================== 客户端配置 ===================${NC}"
    
    # 生成配置URL
    local urls=()
    if [ -n "$ipv4" ]; then
        urls+=("hysteria2://$password@$ipv4:$port/?insecure=1&sni=hysteria2-server#Hysteria2 (IPv4)")
    fi
    if [ -n "$ipv6" ]; then
        urls+=("hysteria2://$password@[$ipv6]:$port/?insecure=1&sni=hysteria2-server#Hysteria2 (IPv6)")
    fi

    # 显示配置URL和二维码
    for url in "${urls[@]}"; do
        echo -e "${GREEN}$url${NC}"
        echo -e "${YELLOW}二维码：${NC}"
        qrencode -t ANSIUTF8 -o - <<< "$url"
        echo ""
    done

    # 生成JSON配置文件
    cat > "$CLIENT_CONFIG" <<EOF
{
  "server": "$ipv4:$port",
  "auth": "$password",
  "tls": {
    "insecure": true,
    "sni": "hysteria2-server"
  },
  "udp": true,
  "multiplex": true,
  "conn": {
    "send_window": 1024,
    "recv_window": 1024
  }
}
EOF
    success_msg "客户端配置文件已保存到：$CLIENT_CONFIG"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}          Hysteria2 管理脚本           ${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "1. 安装 Hysteria2"
    echo -e "2. 停止 Hysteria2"
    echo -e "3. 重启 Hysteria2"
    echo -e "4. 查看 Hysteria2 状态"
    echo -e "5. 更新 Hysteria2"
    echo -e "6. 卸载 Hysteria2"
    echo -e "7. 查看日志"
    echo -e "8. 生成客户端配置"
    echo -e "9. 退出脚本"
    echo -e "${BLUE}======================================${NC}"
    echo -n "请输入选项 (1-9): "
}

# ========================== 主函数 ==========================
main() {
    # 检查是否为root用户，增加自动提权逻辑
    if [ "$EUID" -ne 0 ]; then
        info_msg "检测到非 root 用户运行，尝试自动提权..."
        # 自动通过 sudo 重新执行脚本
        if sudo -v; then
            exec sudo bash "$0" "$@"
        else
            error_exit "请以 root 用户运行此脚本（sudo $0）"
        fi
    fi

    # 初始化日志
    init_log
    
    # 系统检测
    detect_system

    # 主菜单循环
    while true; do
        show_menu
        read -r option
        echo ""
        
        case "$option" in
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
                success_msg "脚本正常退出"
                exit 0
                ;;
            *)
                warn_msg "无效选项，请输入 1-9 之间的数字"
                ;;
        esac
        
        echo -e "\n${BLUE}按回车键返回菜单...${NC}"
        read -r </dev/tty
    done
}

# 启动主函数
main
