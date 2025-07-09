#!/bin/bash

# SSL证书自动续订脚本
# 功能：检查和续订Let's Encrypt SSL证书
# 作者: SSL Auto Renewal System
# 版本: 1.0

set -e

# 配置路径
BASE_DIR="/opt/ssl-auto-renewal"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
DOMAINS_CONFIG="$CONFIG_DIR/domains.conf"
EMAIL_CONFIG="$CONFIG_DIR/email.conf"
WEBSERVER_CONFIG="$CONFIG_DIR/webserver.conf"

# 日志文件
LOG_FILE="$LOG_DIR/ssl-renew.log"
ERROR_LOG="$LOG_DIR/ssl-error.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log_with_timestamp "[INFO] $1"
}

log_warn() {
    log_with_timestamp "[WARN] $1"
}

log_error() {
    log_with_timestamp "[ERROR] $1" | tee -a "$ERROR_LOG"
}

log_success() {
    log_with_timestamp "[SUCCESS] $1"
}

# 检查必要文件是否存在
check_prerequisites() {
    log_info "检查系统环境..."
    
    # 检查certbot是否安装
    if ! command -v certbot >/dev/null 2>&1; then
        log_error "Certbot未安装，请先运行install.sh"
        exit 1
    fi
    
    # 检查配置文件
    if [[ ! -f "$DOMAINS_CONFIG" ]]; then
        log_error "域名配置文件不存在: $DOMAINS_CONFIG"
        exit 1
    fi
    
    # 检查域名配置是否为空
    if ! grep -v '^#' "$DOMAINS_CONFIG" | grep -v '^$' >/dev/null 2>&1; then
        log_error "域名配置文件为空，请先配置域名"
        exit 1
    fi
    
    log_info "系统环境检查完成"
}

# 加载邮件配置
load_email_config() {
    if [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
    else
        ENABLE_EMAIL_NOTIFICATION=false
    fi
}

# 获取默认邮箱地址
get_default_email() {
    local default_email=""
    
    # 从配置文件中读取默认邮箱
    if [[ -f "$DOMAINS_CONFIG" ]]; then
        default_email=$(grep "^DEFAULT_EMAIL=" "$DOMAINS_CONFIG" | cut -d'=' -f2 | tr -d '"' | xargs)
    fi
    
    # 如果没有配置默认邮箱，尝试从邮件配置文件获取
    if [[ -z "$default_email" ]] && [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
        default_email="$NOTIFICATION_EMAIL"
    fi
    
    # 如果还是没有，使用系统默认
    if [[ -z "$default_email" ]]; then
        default_email="admin@$(hostname -d 2>/dev/null || echo 'localhost')"
    fi
    
    echo "$default_email"
}

# 获取Web服务器类型
get_webserver_type() {
    if [[ -f "$WEBSERVER_CONFIG" ]]; then
        cat "$WEBSERVER_CONFIG"
    else
        echo "nginx"  # 默认使用nginx
    fi
}

# 重启Web服务器
restart_webserver() {
    local webserver=$(get_webserver_type)
    
    log_info "重启Web服务器: $webserver"
    
    case "$webserver" in
        "nginx")
            if systemctl is-active --quiet nginx; then
                systemctl reload nginx
                log_info "Nginx已重新加载"
            else
                log_warn "Nginx服务未运行"
            fi
            ;;
        "apache2")
            if systemctl is-active --quiet apache2; then
                systemctl reload apache2
                log_info "Apache已重新加载"
            else
                log_warn "Apache服务未运行"
            fi
            ;;
        *)
            log_warn "未知的Web服务器类型: $webserver"
            ;;
    esac
}

# 发送邮件通知
send_notification() {
    local subject="$1"
    local message="$2"
    local is_error="${3:-false}"
    
    if [[ "$ENABLE_EMAIL_NOTIFICATION" != "true" ]] || [[ -z "$NOTIFICATION_EMAIL" ]]; then
        return 0
    fi
    
    local full_subject="${EMAIL_SUBJECT_PREFIX:-[SSL续订通知]} $subject"
    
    # 构建邮件内容
    local email_body="SSL证书自动续订系统通知

时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)

$message

---
此邮件由SSL证书自动续订系统自动发送。
"
    
    # 发送邮件
    if command -v mail >/dev/null 2>&1; then
        echo "$email_body" | mail -s "$full_subject" "$NOTIFICATION_EMAIL"
        log_info "邮件通知已发送到: $NOTIFICATION_EMAIL"
    else
        log_warn "mail命令不可用，无法发送邮件通知"
    fi
}

# 检查证书是否需要续订
check_certificate_expiry() {
    local domain="$1"
    local days_threshold=30  # 30天内过期则续订
    
    # 获取证书过期时间
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [[ ! -f "$cert_path" ]]; then
        log_info "域名 $domain 的证书不存在，需要申请新证书"
        return 0  # 需要申请
    fi
    
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    local expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    log_info "域名 $domain 的证书还有 $days_until_expiry 天过期"
    
    if [[ $days_until_expiry -le $days_threshold ]]; then
        log_info "域名 $domain 的证书需要续订"
        return 0  # 需要续订
    else
        log_info "域名 $domain 的证书暂不需要续订"
        return 1  # 不需要续订
    fi
}

# 申请或续订SSL证书
renew_certificate() {
    local domain="$1"
    local email="$2"
    local webroot="$3"
    local test_mode="${4:-false}"
    
    log_info "开始处理域名: $domain"
    
    # 构建certbot命令
    local certbot_cmd="certbot certonly --webroot -w $webroot -d $domain --email $email --agree-tos --non-interactive"
    
    # 测试模式
    if [[ "$test_mode" == "true" ]]; then
        certbot_cmd="$certbot_cmd --dry-run"
        log_info "运行测试模式（dry-run）"
    fi
    
    # 执行certbot命令
    if $certbot_cmd; then
        if [[ "$test_mode" == "true" ]]; then
            log_success "域名 $domain 的证书测试申请成功"
        else
            log_success "域名 $domain 的证书申请/续订成功"
            
            # 发送成功通知
            send_notification "证书续订成功" "域名 $domain 的SSL证书已成功续订。"
        fi
        return 0
    else
        log_error "域名 $domain 的证书申请/续订失败"
        
        # 发送失败通知
        send_notification "证书续订失败" "域名 $domain 的SSL证书续订失败，请检查日志文件。" true
        return 1
    fi
}

# 处理所有域名
process_all_domains() {
    local test_mode="${1:-false}"
    local success_count=0
    local total_count=0
    local renewed_domains=()
    local default_email=$(get_default_email)
    
    log_info "开始处理所有域名..."
    log_info "默认邮箱地址: $default_email"
    
    # 读取域名配置文件
    while IFS=':' read -r domain param2 param3 || [[ -n "$domain" ]]; do
        # 跳过注释和空行
        [[ "$domain" =~ ^[[:space:]]*# ]] && continue
        [[ "$domain" =~ ^DEFAULT_EMAIL= ]] && continue
        [[ -z "$domain" ]] && continue
        
        # 去除空格
        domain=$(echo "$domain" | xargs)
        param2=$(echo "$param2" | xargs)
        param3=$(echo "$param3" | xargs)
        
        local email=""
        local webroot=""
        
        # 判断配置格式
        if [[ -n "$param3" ]]; then
            # 完整格式: domain:email:webroot
            email="$param2"
            webroot="$param3"
        elif [[ -n "$param2" ]]; then
            # 简化格式: domain:webroot
            email="$default_email"
            webroot="$param2"
        else
            log_warn "跳过无效配置行: $domain (缺少webroot路径)"
            continue
        fi
        
        # 验证配置
        if [[ -z "$domain" ]] || [[ -z "$email" ]] || [[ -z "$webroot" ]]; then
            log_warn "跳过无效配置行: $domain:$email:$webroot"
            continue
        fi
        
        total_count=$((total_count + 1))
        
        # 检查是否需要续订（测试模式下跳过检查）
        if [[ "$test_mode" == "true" ]] || check_certificate_expiry "$domain"; then
            if renew_certificate "$domain" "$email" "$webroot" "$test_mode"; then
                success_count=$((success_count + 1))
                if [[ "$test_mode" != "true" ]]; then
                    renewed_domains+=("$domain")
                fi
            fi
        fi
        
    done < <(grep -v '^#' "$DOMAINS_CONFIG" | grep -v '^$')
    
    log_info "域名处理完成: 成功 $success_count/$total_count"
    
    # 如果有证书被续订，重启Web服务器
    if [[ ${#renewed_domains[@]} -gt 0 ]] && [[ "$test_mode" != "true" ]]; then
        log_info "有证书被续订，准备重启Web服务器"
        restart_webserver
        
        # 发送汇总通知
        local renewed_list=$(printf '%s\n' "${renewed_domains[@]}")
        send_notification "批量证书续订完成" "以下域名的SSL证书已成功续订：

$renewed_list

Web服务器已重新加载配置。"
    fi
}

# 显示帮助信息
show_help() {
    echo "SSL证书自动续订脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --test, -t     测试模式（dry-run），不实际申请证书"
    echo "  --force, -f    强制续订所有证书，忽略过期时间检查"
    echo "  --help, -h     显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0              # 正常运行，检查并续订即将过期的证书"
    echo "  $0 --test       # 测试模式运行"
    echo "  $0 --force      # 强制续订所有证书"
    echo ""
}

# 主函数
main() {
    local test_mode=false
    local force_mode=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test|-t)
                test_mode=true
                shift
                ;;
            --force|-f)
                force_mode=true
                shift
                ;;
            --help|-h)
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
    
    log_info "SSL证书自动续订脚本开始运行..."
    
    if [[ "$test_mode" == "true" ]]; then
        log_info "运行模式: 测试模式"
    elif [[ "$force_mode" == "true" ]]; then
        log_info "运行模式: 强制续订模式"
    else
        log_info "运行模式: 正常模式"
    fi
    
    # 检查系统环境
    check_prerequisites
    
    # 加载邮件配置
    load_email_config
    
    # 处理所有域名
    if [[ "$force_mode" == "true" ]]; then
        # 强制模式：临时修改检查函数
        check_certificate_expiry() { return 0; }
    fi
    
    process_all_domains "$test_mode"
    
    log_info "SSL证书自动续订脚本运行完成"
}

# 执行主函数
main "$@"