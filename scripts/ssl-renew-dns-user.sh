#!/bin/bash

# SSL证书自动续期脚本 - 用户模式版本
# 避免sudo警告，以普通用户身份运行

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 配置文件路径
CONFIG_DIR="$PROJECT_DIR/config"
DOMAINS_CONF="$CONFIG_DIR/domains.conf"
DNS_API_CONF="$CONFIG_DIR/dns-api.conf"
EMAIL_CONF="$CONFIG_DIR/email.conf"

# 日志文件
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/ssl-renewal-user.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR" "$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS" "$1"
}

# 显示帮助信息
show_help() {
    cat << EOF
SSL证书自动续期脚本 - 用户模式

用法: $0 [选项]

选项:
    --domain DOMAIN        指定单个域名进行证书申请/续期
    --provider PROVIDER    指定DNS服务商 (cloudflare, aliyun, tencent)
    --staging             使用Let's Encrypt测试环境
    --force               强制续期证书
    -h, --help            显示此帮助信息

示例:
    $0                                          # 续期所有配置的域名
    $0 --domain zhangmingrui.top --provider cloudflare
    $0 --domain zhangmingrui.top --staging     # 测试环境
    $0 --force                                 # 强制续期所有域名

EOF
}

# 检查用户权限
check_user_permissions() {
    if [[ $EUID -eq 0 ]]; then
        log_error "此脚本不应以root权限运行"
        log_info "请以普通用户身份运行此脚本"
        log_info "正确用法: $0"
        exit 1
    fi
    
    log_info "以用户 $(whoami) 身份运行"
}

# 检查acme.sh安装
check_acme_installation() {
    local acme_script="$HOME/.acme.sh/acme.sh"
    
    if [[ ! -f "$acme_script" ]]; then
        log_error "未找到acme.sh安装"
        log_info "请运行: /opt/ssl-auto-renewal/scripts/fix-acme-dns-hook.sh --reinstall"
        return 1
    fi
    
    log_info "acme.sh已安装"
    return 0
}

# 设置acme.sh使用Let's Encrypt
setup_letsencrypt_ca() {
    local acme_script="$HOME/.acme.sh/acme.sh"
    
    log_info "配置acme.sh使用Let's Encrypt CA..."
    
    # 设置默认CA为Let's Encrypt
    if $acme_script --set-default-ca --server letsencrypt; then
        log_success "已设置Let's Encrypt为默认CA"
    else
        log_warning "设置Let's Encrypt CA失败，将在命令中指定"
    fi
    
    # 注册Let's Encrypt账户（如果需要）
    local email="admin@$(hostname -d 2>/dev/null || echo "localhost")"
    if [[ -f "$DNS_API_CONF" ]]; then
        source "$DNS_API_CONF"
        if [[ -n "${CLOUDFLARE_EMAIL:-}" ]]; then
            email="$CLOUDFLARE_EMAIL"
        fi
    fi
    
    log_info "注册Let's Encrypt账户: $email"
    $acme_script --register-account -m "$email" --server letsencrypt || true
}

# 设置DNS API环境变量
setup_dns_api() {
    local provider="$1"
    
    log_info "设置DNS API环境变量..."
    
    # 加载DNS配置
    if [[ -f "$DNS_API_CONF" ]]; then
        source "$DNS_API_CONF"
    else
        log_error "DNS API配置文件不存在: $DNS_API_CONF"
        return 1
    fi
    
    case "$provider" in
        "cloudflare")
            export CF_Email="$CLOUDFLARE_EMAIL"
            export CF_Key="$CLOUDFLARE_API_KEY"
            log_success "Cloudflare API环境变量设置完成"
            ;;
        "aliyun")
            export Ali_Key="$ALIYUN_ACCESS_KEY_ID"
            export Ali_Secret="$ALIYUN_ACCESS_KEY_SECRET"
            log_success "阿里云DNS API环境变量设置完成"
            ;;
        "tencent")
            export Tencent_SecretId="$TENCENT_SECRET_ID"
            export Tencent_SecretKey="$TENCENT_SECRET_KEY"
            log_success "腾讯云DNS API环境变量设置完成"
            ;;
        *)
            log_error "不支持的DNS服务商: $provider"
            return 1
            ;;
    esac
    
    return 0
}

# 申请或续期单个域名证书
process_domain_certificate() {
    local domain="$1"
    local provider="$2"
    local staging="${3:-false}"
    local force="${4:-false}"
    
    local acme_script="$HOME/.acme.sh/acme.sh"
    local dns_hook="dns_${provider}"
    
    # 替换cloudflare为cf
    if [[ "$provider" == "cloudflare" ]]; then
        dns_hook="dns_cf"
    fi
    
    log_info "开始为域名 $domain 使用DNS API申请证书"
    log_info "DNS服务商: $provider"
    
    # 设置DNS API环境变量
    if ! setup_dns_api "$provider"; then
        return 1
    fi
    
    # 构建acme.sh命令
    local acme_cmd="$acme_script"
    local domains="-d $domain"
    
    # 添加www子域名（如果主域名不是www开头）
    if [[ ! "$domain" =~ ^www\. ]]; then
        domains="$domains -d www.$domain"
    fi
    
    # 检查证书是否已存在
    local cert_exists=false
    if $acme_script --list | grep -q "$domain"; then
        cert_exists=true
        log_info "发现已存在的证书"
    fi
    
    # 构建命令参数
    local cmd_args=""
    if [[ "$cert_exists" == "true" && "$force" == "false" ]]; then
        cmd_args="--renew $domains --dns $dns_hook"
        log_info "执行证书续期..."
    else
        cmd_args="--issue $domains --dns $dns_hook"
        if [[ "$force" == "true" ]]; then
            cmd_args="$cmd_args --force"
        fi
        log_info "执行证书申请..."
    fi
    
    # 添加CA服务器参数
    cmd_args="$cmd_args --server letsencrypt"
    
    # 添加staging参数
    if [[ "$staging" == "true" ]]; then
        cmd_args="$cmd_args --staging"
        log_info "使用Let's Encrypt测试环境"
    fi
    
    # 显示环境变量状态（不显示具体值）
    case "$provider" in
        "cloudflare")
            log_info "环境变量已设置: CF_Email=$CF_Email, CF_Key=[已设置]"
            ;;
        "aliyun")
            log_info "环境变量已设置: Ali_Key=[已设置], Ali_Secret=[已设置]"
            ;;
        "tencent")
            log_info "环境变量已设置: Tencent_SecretId=[已设置], Tencent_SecretKey=[已设置]"
            ;;
    esac
    
    # 执行命令
    log_info "执行命令: acme.sh $cmd_args"
    
    if eval "$acme_cmd $cmd_args"; then
        log_success "域名 $domain 的SSL证书处理成功"
        
        # 安装证书到系统目录
        install_certificate "$domain"
        
        return 0
    else
        log_error "域名 $domain 的SSL证书申请失败"
        return 1
    fi
}

# 安装证书到系统目录
install_certificate() {
    local domain="$1"
    local acme_script="$HOME/.acme.sh/acme.sh"
    
    log_info "安装证书到系统目录: $domain"
    
    # 证书安装目录
    local cert_dir="/etc/ssl/certs/$domain"
    
    # 使用sudo安装证书
    if sudo mkdir -p "$cert_dir" && \
       sudo $acme_script --install-cert -d "$domain" \
           --key-file "$cert_dir/private.key" \
           --fullchain-file "$cert_dir/fullchain.pem" \
           --reloadcmd "systemctl reload nginx"; then
        
        log_success "证书安装成功: $domain"
        return 0
    else
        log_error "证书安装失败: $domain"
        return 1
    fi
}

# 发送通知邮件
send_notification() {
    local status="$1"
    local message="$2"
    
    if [[ -f "$EMAIL_CONF" ]]; then
        source "$EMAIL_CONF"
        
        if [[ "$SMTP_ENABLED" == "true" ]]; then
            log_info "发送邮件通知..."
            
            local subject="SSL证书续期 - $status"
            local notify_script="$SCRIPT_DIR/notify.sh"
            
            if [[ -f "$notify_script" ]]; then
                if [[ "$status" == "SUCCESS" ]]; then
                    "$notify_script" --success "$message"
                else
                    "$notify_script" --error "$message"
                fi
            fi
        fi
    fi
}

# 批量处理域名
batch_process_domains() {
    local staging="$1"
    local force="$2"
    
    log_info "开始批量SSL证书处理任务"
    
    # 加载域名配置
    if [[ ! -f "$DOMAINS_CONF" ]]; then
        log_error "域名配置文件不存在: $DOMAINS_CONF"
        return 1
    fi
    
    source "$DOMAINS_CONF"
    
    local success_count=0
    local error_count=0
    local results=""
    
    # 读取域名列表
    if [[ -n "${DOMAINS:-}" ]]; then
        IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
        
        for domain in "${DOMAIN_ARRAY[@]}"; do
            # 去除空格
            domain=$(echo "$domain" | xargs)
            
            if [[ -n "$domain" ]]; then
                if process_domain_certificate "$domain" "cloudflare" "$staging" "$force"; then
                    ((success_count++))
                    results+="\n✓ $domain - 处理成功"
                else
                    ((error_count++))
                    results+="\n✗ $domain - 处理失败"
                fi
            fi
        done
    else
        log_error "未找到域名配置"
        return 1
    fi
    
    # 生成总结报告
    local total_domains=$((success_count + error_count))
    local summary="SSL证书处理完成\n"
    summary+="总域名数: $total_domains\n"
    summary+="成功: $success_count\n"
    summary+="失败: $error_count\n"
    summary+="\n详细结果:$results"
    
    log_info "处理任务完成"
    echo -e "$summary"
    
    # 发送通知
    if [[ $error_count -eq 0 ]]; then
        send_notification "SUCCESS" "$summary"
        return 0
    else
        send_notification "ERROR" "$summary"
        return 1
    fi
}

# 主函数
main() {
    local domain=""
    local provider="cloudflare"
    local staging=false
    local force=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                domain="$2"
                shift 2
                ;;
            --provider)
                provider="$2"
                shift 2
                ;;
            --staging)
                staging=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  SSL证书自动续期 - 用户模式${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # 检查用户权限
    check_user_permissions
    
    # 检查acme.sh安装
    if ! check_acme_installation; then
        log_error "acme.sh检查失败"
        exit 1
    fi
    
    # 设置Let's Encrypt CA
    setup_letsencrypt_ca
    
    # 根据参数执行不同操作
    if [[ -n "$domain" ]]; then
        # 单个域名处理
        log_info "开始DNS API证书申请..."
        if process_domain_certificate "$domain" "$provider" "$staging" "$force"; then
            log_success "域名 $domain SSL证书处理成功完成"
            exit 0
        else
            log_error "域名 $domain SSL证书处理失败"
            exit 1
        fi
    else
        # 批量处理
        if batch_process_domains "$staging" "$force"; then
            log_success "SSL证书批量处理任务成功完成"
            exit 0
        else
            log_error "SSL证书批量处理任务失败"
            exit 1
        fi
    fi
}

# 运行主函数
main "$@"