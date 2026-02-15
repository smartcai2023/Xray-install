#!/bin/bash
set -euo pipefail

# ========================== 全局变量 ==========================
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

# 语言变量（默认中文）
LANG_SELECT="zh"

# ========================== 语言包 ==========================
# 中文语言包
declare -A MSG_ZH=(
    ["init_log"]="------------------- Hysteria2 安装日志 -------------------"
    ["error_prefix"]="[错误]"
    ["info_prefix"]="[信息]"
    ["success_prefix"]="[成功]"
    ["warn_prefix"]="[警告]"
    ["cmd_not_found"]="命令 %s 未找到，请先安装"
    ["lang_select_title"]="===== 选择语言 / Select Language ====="
    ["lang_select_zh"]="1. 中文"
    ["lang_select_en"]="2. English"
    ["lang_select_prompt"]="请选择语言 (1/2，默认1): "
    ["lang_selected_zh"]="已选择中文界面"
    ["lang_selected_en"]="Selected English interface"
    ["lang_invalid"]="无效的选择，使用默认中文"
    ["detect_system_start"]="开始检测系统环境..."
    ["install_lsb_release"]="正在安装 lsb-release..."
    ["unsupported_os"]="无法检测系统类型，不支持的操作系统"
    ["detect_os"]="检测到 %s 系统，使用 %s 安装依赖..."
    ["install_deps_failed"]="安装依赖失败"
    ["sys_detect_complete"]="系统检测和依赖安装完成"
    ["download_file_attempt"]="正在下载文件 (尝试 %s/%s): %s"
    ["download_success"]="下载成功: %s"
    ["download_failed_retry"]="下载失败，等待 %s 秒后重试..."
    ["download_failed"]="下载失败: %s"
    ["gen_random_config"]="生成随机端口和密码"
    ["get_server_ip"]="正在检测服务器IP地址..."
    ["get_ip_failed"]="无法获取服务器公网IP地址"
    ["optimize_system"]="正在优化系统网络参数..."
    ["sysctl_apply_warn"]="部分系统参数无法立即生效，重启后生效"
    ["sys_optimize_complete"]="系统参数优化完成"
    ["install_hysteria_start"]="开始安装 Hysteria2..."
    ["create_dir_failed"]="创建 Hysteria 目录失败"
    ["custom_config_prompt"]="是否自定义端口和密码？(y/n, 默认 n): "
    ["custom_port_prompt"]="请输入自定义端口 (10000-65535): "
    ["custom_password_prompt"]="请输入自定义密码: "
    ["port_must_number"]="端口必须是数字"
    ["port_range_error"]="端口必须在 10000-65535 范围内"
    ["gen_cert"]="正在生成自签证书..."
    ["gen_cert_failed"]="生成自签证书失败"
    ["create_config"]="正在创建配置文件..."
    ["create_config_failed"]="创建配置文件失败"
    ["download_binary"]="正在下载 Hysteria 二进制文件..."
    ["set_perm_failed"]="设置可执行权限失败"
    ["create_service"]="正在创建 systemd 服务..."
    ["create_service_failed"]="创建服务文件失败"
    ["reload_systemd_failed"]="重载 systemd 配置失败"
    ["start_service_failed"]="启动 Hysteria 服务失败"
    ["install_success"]="Hysteria2 安装并启动成功！"
    ["config_info"]="配置信息："
    ["port"]="端口: "
    ["password"]="密码: "
    ["config_file"]="配置文件: "
    ["log_file"]="日志文件: "
    ["service_log"]="服务日志: "
    ["service_start_failed"]="Hysteria2 服务启动失败，请检查日志"
    ["stop_service_start"]="正在停止 Hysteria2..."
    ["stop_service_failed"]="停止 Hysteria 服务失败"
    ["service_stopped"]="Hysteria2 已停止"
    ["service_not_running"]="Hysteria2 服务未运行"
    ["restart_service_start"]="正在重启 Hysteria2..."
    ["restart_service_failed"]="重启 Hysteria 服务失败"
    ["service_restarted"]="Hysteria2 已重启"
    ["restart_not_running"]="Hysteria2 重启后未正常运行"
    ["service_not_installed"]="Hysteria2 服务未安装或未启用"
    ["view_status_start"]="查看 Hysteria2 状态..."
    ["service_status"]="服务状态："
    ["port_listening"]="端口监听："
    ["no_port_listen"]="未发现 Hysteria 端口监听"
    ["process_info"]="进程信息："
    ["no_process"]="未发现 Hysteria 进程"
    ["check_update_start"]="正在检查 Hysteria2 更新..."
    ["not_installed_cannot_update"]="Hysteria2 未安装，无法更新"
    ["get_version_failed"]="无法获取当前版本信息"
    ["get_latest_version_failed"]="无法获取最新版本信息"
    ["version_latest"]="当前已是最新版本：%s"
    ["new_version_found"]="发现新版本：%s，当前版本：%s，正在更新..."
    ["backup_failed"]="备份当前版本失败"
    ["update_verify_failed"]="新版本验证失败，已回滚到旧版本"
    ["update_success"]="Hysteria2 已更新到版本：%s"
    ["uninstall_confirm"]="确定要卸载 Hysteria2 吗？(y/n): "
    ["uninstall_cancelled"]="卸载操作已取消"
    ["uninstall_start"]="正在卸载 Hysteria2..."
    ["uninstall_complete"]="Hysteria2 已完全卸载"
    ["view_log_start"]="查看安装日志：%s"
    ["installation_log"]="=================== 安装日志 ==================="
    ["read_log_failed"]="无法读取日志文件"
    ["service_log_title"]="=================== 服务日志 ==================="
    ["gen_client_config_start"]="生成客户端配置信息..."
    ["config_file_not_found"]="未找到 Hysteria 配置文件，请先安装 Hysteria2"
    ["extract_config_failed"]="无法从配置文件中提取客户端设置"
    ["client_config_title"]="=================== 客户端配置 ==================="
    ["qr_code"]="二维码："
    ["qr_generate_failed"]="二维码生成失败，请检查qrencode是否安装正确"
    ["client_config_saved"]="客户端配置文件已保存到：%s"
    ["menu_title"]="          Hysteria2 管理脚本           "
    ["menu_1"]="1. 安装 Hysteria2"
    ["menu_2"]="2. 停止 Hysteria2"
    ["menu_3"]="3. 重启 Hysteria2"
    ["menu_4"]="4. 查看 Hysteria2 状态"
    ["menu_5"]="5. 更新 Hysteria2"
    ["menu_6"]="6. 卸载 Hysteria2"
    ["menu_7"]="7. 查看日志"
    ["menu_8"]="8. 生成客户端配置"
    ["menu_9"]="9. 退出脚本"
    ["menu_prompt"]="请输入选项 (1-9): "
    ["invalid_option"]="无效选项，请输入 1-9 之间的数字"
    ["press_enter"]="按回车键返回菜单..."
    ["non_root_user"]="检测到非 root 用户运行，尝试自动提权..."
    ["run_as_root"]="请以 root 用户运行此脚本（sudo %s）"
    ["script_exit"]="脚本正常退出"
)

# 英文语言包
declare -A MSG_EN=(
    ["init_log"]="------------------- Hysteria2 Installation Log -------------------"
    ["error_prefix"]="[Error]"
    ["info_prefix"]="[Info]"
    ["success_prefix"]="[Success]"
    ["warn_prefix"]="[Warning]"
    ["cmd_not_found"]="Command %s not found, please install it first"
    ["lang_select_title"]="===== 选择语言 / Select Language ====="
    ["lang_select_zh"]="1. 中文"
    ["lang_select_en"]="2. English"
    ["lang_select_prompt"]="Select language (1/2, default 1): "
    ["lang_selected_zh"]="Chinese interface selected"
    ["lang_selected_en"]="English interface selected"
    ["lang_invalid"]="Invalid selection, using default Chinese"
    ["detect_system_start"]="Starting system environment detection..."
    ["install_lsb_release"]="Installing lsb-release..."
    ["unsupported_os"]="Unable to detect system type, unsupported operating system"
    ["detect_os"]="Detected %s system, using %s to install dependencies..."
    ["install_deps_failed"]="Failed to install dependencies"
    ["sys_detect_complete"]="System detection and dependency installation completed"
    ["download_file_attempt"]="Downloading file (attempt %s/%s): %s"
    ["download_success"]="Download successful: %s"
    ["download_failed_retry"]="Download failed, retrying after %s seconds..."
    ["download_failed"]="Download failed: %s"
    ["gen_random_config"]="Generating random port and password"
    ["get_server_ip"]="Detecting server IP addresses..."
    ["get_ip_failed"]="Unable to get server public IP address"
    ["optimize_system"]="Optimizing system network parameters..."
    ["sysctl_apply_warn"]="Some system parameters cannot take effect immediately, will take effect after restart"
    ["sys_optimize_complete"]="System parameter optimization completed"
    ["install_hysteria_start"]="Starting Hysteria2 installation..."
    ["create_dir_failed"]="Failed to create Hysteria directory"
    ["custom_config_prompt"]="Customize port and password? (y/n, default n): "
    ["custom_port_prompt"]="Enter custom port (10000-65535): "
    ["custom_password_prompt"]="Enter custom password: "
    ["port_must_number"]="Port must be a number"
    ["port_range_error"]="Port must be in the range 10000-65535"
    ["gen_cert"]="Generating self-signed certificate..."
    ["gen_cert_failed"]="Failed to generate self-signed certificate"
    ["create_config"]="Creating configuration file..."
    ["create_config_failed"]="Failed to create configuration file"
    ["download_binary"]="Downloading Hysteria binary file..."
    ["set_perm_failed"]="Failed to set executable permission"
    ["create_service"]="Creating systemd service..."
    ["create_service_failed"]="Failed to create service file"
    ["reload_systemd_failed"]="Failed to reload systemd configuration"
    ["start_service_failed"]="Failed to start Hysteria service"
    ["install_success"]="Hysteria2 installed and started successfully!"
    ["config_info"]="Configuration Information:"
    ["port"]="Port: "
    ["password"]="Password: "
    ["config_file"]="Config File: "
    ["log_file"]="Log File: "
    ["service_log"]="Service Log: "
    ["service_start_failed"]="Hysteria2 service failed to start, please check logs"
    ["stop_service_start"]="Stopping Hysteria2..."
    ["stop_service_failed"]="Failed to stop Hysteria service"
    ["service_stopped"]="Hysteria2 has been stopped"
    ["service_not_running"]="Hysteria2 service is not running"
    ["restart_service_start"]="Restarting Hysteria2..."
    ["restart_service_failed"]="Failed to restart Hysteria service"
    ["service_restarted"]="Hysteria2 has been restarted"
    ["restart_not_running"]="Hysteria2 did not run normally after restart"
    ["service_not_installed"]="Hysteria2 service is not installed or enabled"
    ["view_status_start"]="Viewing Hysteria2 status..."
    ["service_status"]="Service Status:"
    ["port_listening"]="Port Listening:"
    ["no_port_listen"]="No Hysteria port listening found"
    ["process_info"]="Process Information:"
    ["no_process"]="No Hysteria process found"
    ["check_update_start"]="Checking for Hysteria2 updates..."
    ["not_installed_cannot_update"]="Hysteria2 is not installed, cannot update"
    ["get_version_failed"]="Unable to get current version information"
    ["get_latest_version_failed"]="Unable to get latest version information"
    ["version_latest"]="Already on the latest version: %s"
    ["new_version_found"]="New version found: %s, current version: %s, updating..."
    ["backup_failed"]="Failed to backup current version"
    ["update_verify_failed"]="New version verification failed, rolled back to old version"
    ["update_success"]="Hysteria2 has been updated to version: %s"
    ["uninstall_confirm"]="Are you sure to uninstall Hysteria2? (y/n): "
    ["uninstall_cancelled"]="Uninstallation cancelled"
    ["uninstall_start"]="Uninstalling Hysteria2..."
    ["uninstall_complete"]="Hysteria2 has been completely uninstalled"
    ["view_log_start"]="Viewing installation log: %s"
    ["installation_log"]="=================== Installation Log ==================="
    ["read_log_failed"]="Unable to read log file"
    ["service_log_title"]="=================== Service Log ==================="
    ["gen_client_config_start"]="Generating client configuration information..."
    ["config_file_not_found"]="Hysteria configuration file not found, please install Hysteria2 first"
    ["extract_config_failed"]="Unable to extract client settings from configuration file"
    ["client_config_title"]="=================== Client Configuration ==================="
    ["qr_code"]="QR Code:"
    ["qr_generate_failed"]="Failed to generate QR code, please check if qrencode is installed correctly"
    ["client_config_saved"]="Client configuration file saved to: %s"
    ["menu_title"]="          Hysteria2 Management Script           "
    ["menu_1"]="1. Install Hysteria2"
    ["menu_2"]="2. Stop Hysteria2"
    ["menu_3"]="3. Restart Hysteria2"
    ["menu_4"]="4. View Hysteria2 Status"
    ["menu_5"]="5. Update Hysteria2"
    ["menu_6"]="6. Uninstall Hysteria2"
    ["menu_7"]="7. View Logs"
    ["menu_8"]="8. Generate Client Configuration"
    ["menu_9"]="9. Exit Script"
    ["menu_prompt"]="Enter option (1-9): "
    ["invalid_option"]="Invalid option, please enter a number between 1-9"
    ["press_enter"]="Press Enter to return to menu..."
    ["non_root_user"]="Detected non-root user, attempting automatic privilege escalation..."
    ["run_as_root"]="Please run this script as root (sudo %s)"
    ["script_exit"]="Script exited normally"
)

# ========================== 语言工具函数 ==========================
# 获取语言消息
get_msg() {
    local key="$1"
    shift
    local msg=""
    
    if [ "$LANG_SELECT" = "en" ]; then
        msg=${MSG_EN[$key]}
    else
        msg=${MSG_ZH[$key]}
    fi
    
    # 格式化消息（支持参数）
    if [ $# -gt 0 ]; then
        printf "$msg" "$@"
    else
        echo -n "$msg"
    fi
}

# 选择语言
select_language() {
    clear
    echo -e "${BLUE}$(get_msg lang_select_title)${NC}"
    echo -e "$(get_msg lang_select_zh)"
    echo -e "$(get_msg lang_select_en)"
    echo -n "$(get_msg lang_select_prompt) "
    
    read -r lang_choice
    lang_choice=${lang_choice:-1}
    
    case "$lang_choice" in
        1)
            LANG_SELECT="zh"
            echo -e "\n${GREEN}$(get_msg lang_selected_zh)${NC}"
            ;;
        2)
            LANG_SELECT="en"
            echo -e "\n${GREEN}$(get_msg lang_selected_en)${NC}"
            ;;
        *)
            echo -e "\n${YELLOW}$(get_msg lang_invalid)${NC}"
            LANG_SELECT="zh"
            ;;
    esac
    
    # 延迟后清屏
    sleep 1
    clear
}

# ========================== 工具函数 ==========================
# 初始化日志系统
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    # 仅将标准输出重定向到日志+终端，避免影响二维码等直接终端输出
    exec > >(tee -a "$LOG_FILE")
    # 错误输出仍保留到终端（不写入日志，避免二维码乱码）
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $(get_msg init_log)"
}

# 错误处理函数
error_exit() {
    local error_msg=$(get_msg "$1")
    shift
    local exit_code="${1:-1}"
    
    # 格式化错误消息
    if [ $# -gt 1 ]; then
        error_msg=$(printf "$error_msg" "${@:1:$#-1}")
    fi
    
    echo -e "\n${RED}$(get_msg error_prefix) $(date '+%Y-%m-%d %H:%M:%S'): $error_msg${NC}" >&2
    exit "$exit_code"
}

# 信息提示函数
info_msg() {
    local msg=$(get_msg "$1")
    shift
    
    # 格式化消息
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    
    echo -e "\n${BLUE}$(get_msg info_prefix) $(date '+%Y-%m-%d %H:%M:%S'): $msg${NC}"
}

# 成功提示函数
success_msg() {
    local msg=$(get_msg "$1")
    shift
    
    # 格式化消息
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    
    echo -e "\n${GREEN}$(get_msg success_prefix) $(date '+%Y-%m-%d %H:%M:%S'): $msg${NC}"
}

# 警告提示函数
warn_msg() {
    local msg=$(get_msg "$1")
    shift
    
    # 格式化消息
    if [ $# -gt 0 ]; then
        msg=$(printf "$msg" "$@")
    fi
    
    echo -e "\n${YELLOW}$(get_msg warn_prefix) $(date '+%Y-%m-%d %H:%M:%S'): $msg${NC}"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "cmd_not_found" "$1"
    fi
}

# ========================== 核心功能函数 ==========================
# 系统检测和依赖安装
detect_system() {
    info_msg "detect_system_start"
    
    # 检查 lsb_release 命令
    if ! command -v lsb_release &> /dev/null; then
        info_msg "install_lsb_release"
        if [ -f /etc/debian_version ]; then
            apt update && apt install -y lsb-release
        elif [ -f /etc/redhat-release ]; then
            yum install -y redhat-lsb-core
        else
            error_exit "unsupported_os"
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
            error_exit "unsupported_os"
            ;;
    esac

    info_msg "detect_os" "$os_name" "$pkg_manager"
    eval "$install_cmd curl openssl qrencode jq net-tools" || error_exit "install_deps_failed"
    
    # 检查必要命令
    check_command "curl"
    check_command "openssl"
    check_command "jq"
    check_command "qrencode"
    
    success_msg "sys_detect_complete"
}

# 下载文件（带重试机制和进度条）
download_file() {
    local url="$1"
    local output="$2"
    local retries="${3:-3}"
    local delay="${4:-2}"

    for ((i=1; i<=retries; i++)); do
        info_msg "download_file_attempt" "$i" "$retries" "$url"
        if curl -fsSL --progress-bar -o "$output" "$url"; then
            success_msg "download_success" "$output"
            return 0
        else
            warn_msg "download_failed_retry" "$delay"
            sleep "$delay"
        fi
    done
    error_exit "download_failed" "$url"
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
    info_msg "get_server_ip"
    
    # 多源获取IP，提高成功率
    local ipv4=$(curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || echo "")
    local ipv6=$(curl -6 -s --max-time 5 ifconfig.me || curl -6 -s --max-time 5 icanhazip.com || echo "")
    
    if [ -z "$ipv4" ] && [ -z "$ipv6" ]; then
        warn_msg "get_ip_failed"
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
    info_msg "optimize_system"
    
    # 检查并追加配置，避免重复
    local sysctl_conf="/etc/sysctl.conf"
    local temp_conf=$(mktemp)
    
    # 保留原有配置，过滤掉重复的参数
    grep -vE '^(net.core.default_qdisc|net.ipv4.tcp_congestion_control|net.ipv4.tcp_fastopen|net.ipv4.tcp_max_syn_backlog|net.ipv4.tcp_max_tw_buckets|net.ipv4.tcp_tw_reuse|net.ipv4.tcp_tw_recycle|net.ipv4.tcp_fin_timeout|net.ipv4.tcp_keepalive_time|net.ipv4.tcp_keepalive_intvl|net.ipv4.tcp_keepalive_probes)=' "$sysctl_conf" > "$temp_conf"
    
    # 添加优化参数
    cat >> "$temp_conf" <<EOF
# Hysteria2 network optimization parameters
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
    sysctl -p || warn_msg "sysctl_apply_warn"
    
    success_msg "sys_optimize_complete"
}

# 安装Hysteria2
install_hysteria() {
    info_msg "install_hysteria_start"

    # 创建目录
    mkdir -p "$HYSTERIA_DIR" && chmod 755 "$HYSTERIA_DIR" || error_exit "create_dir_failed"

    # 用户自定义配置
    read -p "$(get_msg custom_config_prompt) " -r CUSTOM_CONFIG
    CUSTOM_CONFIG=${CUSTOM_CONFIG:-n}
    
    local port password
    if [[ "$CUSTOM_CONFIG" =~ ^[yY]$ ]]; then
        read -p "$(get_msg custom_port_prompt) " -r CUSTOM_PORT
        read -p "$(get_msg custom_password_prompt) " -r CUSTOM_PASSWORD
        
        # 验证端口合法性
        if [[ -n "$CUSTOM_PORT" && ! "$CUSTOM_PORT" =~ ^[0-9]+$ ]]; then
            error_exit "port_must_number"
        fi
        if [[ -n "$CUSTOM_PORT" && ( "$CUSTOM_PORT" -lt 10000 || "$CUSTOM_PORT" -gt 65535 ) ]]; then
            error_exit "port_range_error"
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
    info_msg "gen_cert"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$HYSTERIA_DIR/server.key" -out "$HYSTERIA_DIR/server.crt" \
        -subj "/CN=hysteria2-server" -days 3650 -batch || error_exit "gen_cert_failed"
    
    chmod 600 "$HYSTERIA_DIR/server.key"  # 证书密钥更安全的权限
    chmod 644 "$HYSTERIA_DIR/server.crt"

    # 创建优化后的配置文件
    info_msg "create_config"
    cat > "$HYSTERIA_CONFIG" <<EOF
# Hysteria2 server configuration
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
    chmod 600 "$HYSTERIA_CONFIG" || error_exit "create_config_failed"

    # 下载并安装二进制文件
    info_msg "download_binary"
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" \
        "$HYSTERIA_BINARY" 3 5
    
    chmod +x "$HYSTERIA_BINARY" || error_exit "set_perm_failed"

    # 创建systemd服务（增强稳定性）
    info_msg "create_service"
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
    chmod 644 "$HYSTERIA_SERVICE" || error_exit "create_service_failed"

    # 启动服务
    systemctl daemon-reload || error_exit "reload_systemd_failed"
    systemctl enable --now hysteria || error_exit "start_service_failed"
    
    # 验证服务状态
    if systemctl is-active --quiet hysteria; then
        success_msg "install_success"
        echo -e "\n${YELLOW}$(get_msg config_info)${NC}"
        echo -e "$(get_msg port) ${GREEN}$port${NC}"
        echo -e "$(get_msg password) ${GREEN}$password${NC}"
        echo -e "$(get_msg config_file) ${GREEN}$HYSTERIA_CONFIG${NC}"
        echo -e "$(get_msg log_file) ${GREEN}$LOG_FILE${NC}"
        echo -e "$(get_msg service_log) ${GREEN}/var/log/hysteria_server.log${NC}"
    else
        error_exit "service_start_failed"
    fi
}

# 停止服务
stop_service() {
    info_msg "stop_service_start"
    
    if systemctl is-active --quiet hysteria; then
        systemctl stop hysteria || error_exit "stop_service_failed"
        success_msg "service_stopped"
    else
        warn_msg "service_not_running"
    fi
}

# 重启服务
restart_service() {
    info_msg "restart_service_start"
    
    if systemctl is-enabled --quiet hysteria; then
        systemctl restart hysteria || error_exit "restart_service_failed"
        
        # 验证重启结果
        if systemctl is-active --quiet hysteria; then
            success_msg "service_restarted"
        else
            error_exit "restart_not_running"
        fi
    else
        error_exit "service_not_installed"
    fi
}

# 查看服务状态
view_status() {
    info_msg "view_status_start"
    
    echo -e "\n${YELLOW}$(get_msg service_status)${NC}"
    systemctl status hysteria --no-pager
    
    echo -e "\n${YELLOW}$(get_msg port_listening)${NC}"
    ss -tulpn | grep hysteria || echo "$(get_msg no_port_listen)"
    
    echo -e "\n${YELLOW}$(get_msg process_info)${NC}"
    ps aux | grep hysteria | grep -v grep || echo "$(get_msg no_process)"
}

# 更新Hysteria2
update_hysteria() {
    info_msg "check_update_start"

    # 检查是否已安装
    if [ ! -f "$HYSTERIA_BINARY" ]; then
        error_exit "not_installed_cannot_update"
    fi

    # 获取当前版本
    local current_version=$("$HYSTERIA_BINARY" version 2>/dev/null | awk '{print $2}')
    if [ -z "$current_version" ]; then
        error_exit "get_version_failed"
    fi

    # 获取最新版本
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/HyNetwork/hysteria/releases/latest" | jq -r '.tag_name')
    
    # 备用获取方式
    if [ "$latest_version" = "null" ] || [ -z "$latest_version" ]; then
        latest_version=$(curl -s "https://github.com/HyNetwork/hysteria/releases/latest" | grep -oP 'releases/tag/\Kv\d+\.\d+\.\d+' | head -n1)
    fi

    if [ -z "$latest_version" ]; then
        error_exit "get_latest_version_failed"
    fi

    # 比较版本
    if ! version_compare "$current_version" "$latest_version"; then
        success_msg "version_latest" "$current_version"
        return
    fi

    info_msg "new_version_found" "$latest_version" "$current_version"
    
    # 备份当前二进制文件
    cp "$HYSTERIA_BINARY" "${HYSTERIA_BINARY}.old" || warn_msg "backup_failed"
    
    # 停止服务并更新
    stop_service
    
    # 下载新版本
    download_file "https://github.com/HyNetwork/hysteria/releases/latest/download/hysteria-linux-amd64" \
        "$HYSTERIA_BINARY" 3 5
    
    chmod +x "$HYSTERIA_BINARY" || error_exit "set_perm_failed"
    
    # 验证新版本
    local new_version=$("$HYSTERIA_BINARY" version 2>/dev/null | awk '{print $2}')
    if [ -z "$new_version" ]; then
        # 回滚
        mv "${HYSTERIA_BINARY}.old" "$HYSTERIA_BINARY"
        error_exit "update_verify_failed"
    fi

    # 启动服务
    systemctl start hysteria || error_exit "start_service_failed"
    
    success_msg "update_success" "$new_version"
}

# 卸载Hysteria2
uninstall_hysteria() {
    read -p "$(get_msg uninstall_confirm) " -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        info_msg "uninstall_cancelled"
        return
    fi

    info_msg "uninstall_start"
    
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
    
    success_msg "uninstall_complete"
}

# 查看日志
view_log() {
    info_msg "view_log_start" "$LOG_FILE"
    echo -e "${YELLOW}$(get_msg installation_log)${NC}"
    tail -n 50 "$LOG_FILE" || error_exit "read_log_failed"
    
    # 同时显示服务运行日志
    if [ -f "/var/log/hysteria_server.log" ]; then
        echo -e "\n${YELLOW}$(get_msg service_log_title)${NC}"
        tail -n 20 "/var/log/hysteria_server.log"
    fi
}

# 生成客户端配置（保留最初的二维码显示代码）
generate_client_config() {
    if [ ! -f "$HYSTERIA_CONFIG" ]; then
        error_exit "config_file_not_found"
    fi

    # 提取配置信息
    local ipv4=$(get_server_ips | head -n1)
    local ipv6=$(get_server_ips | tail -n1)
    local port=$(grep -oP 'listen:\s*:\K\d+' "$HYSTERIA_CONFIG")
    local password=$(grep -oP 'password:\s*\K\S+' "$HYSTERIA_CONFIG")

    if [ -z "$port" ] || [ -z "$password" ]; then
        error_exit "extract_config_failed"
    fi

    info_msg "gen_client_config_start"
    echo -e "\n${YELLOW}$(get_msg client_config_title)${NC}"
    
    # 生成配置URL
    local urls=()
    if [ -n "$ipv4" ]; then
        urls+=("hysteria2://$password@$ipv4:$port/?insecure=1&sni=hysteria2-server#Hysteria2 (IPv4)")
    fi
    if [ -n "$ipv6" ]; then
        urls+=("hysteria2://$password@[$ipv6]:$port/?insecure=1&sni=hysteria2-server#Hysteria2 (IPv6)")
    fi

    # 显示配置URL和二维码（保留最初的原生代码）
    for url in "${urls[@]}"; do
        echo -e "${GREEN}$url${NC}"
        echo -e "${YELLOW}$(get_msg qr_code) ${NC}"
        # 最初的二维码生成代码 - 直接调用qrencode，输出到标准输出
        if ! qrencode -t ANSIUTF8 -o - <<< "$url"; then
            error_exit "qr_generate_failed"
        fi
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
    success_msg "client_config_saved" "$CLIENT_CONFIG"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}$(get_msg menu_title)${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "$(get_msg menu_1)"
    echo -e "$(get_msg menu_2)"
    echo -e "$(get_msg menu_3)"
    echo -e "$(get_msg menu_4)"
    echo -e "$(get_msg menu_5)"
    echo -e "$(get_msg menu_6)"
    echo -e "$(get_msg menu_7)"
    echo -e "$(get_msg menu_8)"
    echo -e "$(get_msg menu_9)"
    echo -e "${BLUE}======================================${NC}"
    echo -n "$(get_msg menu_prompt) "
}

# ========================== 主函数 ==========================
main() {
    # 第一步：选择语言
    select_language
    
    # 检查是否为root用户，增加自动提权逻辑
    if [ "$EUID" -ne 0 ]; then
        info_msg "non_root_user"
        # 自动通过 sudo 重新执行脚本
        if sudo -v; then
            exec sudo bash "$0" "$@"
        else
            error_exit "run_as_root" "$0"
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
                success_msg "script_exit"
                exit 0
                ;;
            *)
                warn_msg "invalid_option"
                ;;
        esac
        
        echo -e "\n${BLUE}$(get_msg press_enter)${NC}"
        read -r </dev/tty
    done
}

# 启动主函数
main
