#!/bin/bash

# SSL证书邮件通知脚本
# 功能：发送SSL证书相关的邮件通知
# 作者: SSL Auto Renewal System
# 版本: 1.0

set -e

# 配置路径
BASE_DIR="/opt/ssl-auto-renewal"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
EMAIL_CONFIG="$CONFIG_DIR/email.conf"
DOMAINS_CONFIG="$CONFIG_DIR/domains.conf"

# 日志文件
LOG_FILE="$LOG_DIR/notify.log"

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
    echo -e "${BLUE}[INFO]${NC} $1"
    log_with_timestamp "[INFO] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log_with_timestamp "[WARN] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_with_timestamp "[ERROR] $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_with_timestamp "[SUCCESS] $1"
}

# 加载邮件配置
load_email_config() {
    if [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
        
        # 检查必要的配置
        if [[ "$ENABLE_EMAIL_NOTIFICATION" != "true" ]]; then
            log_warn "邮件通知未启用"
            return 1
        fi
        
        if [[ -z "$NOTIFICATION_EMAIL" ]]; then
            log_error "未配置通知邮箱地址"
            return 1
        fi
        
        return 0
    else
        log_error "邮件配置文件不存在: $EMAIL_CONFIG"
        return 1
    fi
}

# 检查SMTP配置
check_smtp_config() {
    if [[ "$USE_EXTERNAL_SMTP" == "true" ]]; then
        log_info "检查SMTP配置..."
        
        # 检查必要的SMTP配置
        if [[ -z "$SMTP_SERVER" ]]; then
            log_error "SMTP服务器地址未配置"
            return 1
        fi
        
        if [[ -z "$SMTP_USERNAME" ]]; then
            log_error "SMTP用户名未配置"
            return 1
        fi
        
        if [[ -z "$SMTP_PASSWORD" ]]; then
            log_error "SMTP密码未配置"
            return 1
        fi
        
        # 检查Python和smtp-send.py脚本
        if ! command -v python3 >/dev/null 2>&1; then
            log_error "Python3未安装，SMTP功能需要Python3支持"
            return 1
        fi
        
        local smtp_script="$BASE_DIR/scripts/smtp-send.py"
        if [[ ! -f "$smtp_script" ]]; then
            log_error "SMTP发送脚本不存在: $smtp_script"
            return 1
        fi
        
        log_success "SMTP配置检查通过"
        return 0
    fi
    
    return 1
}

# 使用SMTP发送邮件
send_email_smtp() {
    local recipient="$1"
    local subject="$2"
    local message="$3"
    
    log_info "使用SMTP发送邮件到: $recipient"
    
    local smtp_script="$BASE_DIR/scripts/smtp-send.py"
    
    # 发送邮件，使用标准输入传递邮件正文
    if echo "$message" | python3 "$smtp_script" \
        --config "$EMAIL_CONFIG" \
        --to "$recipient" \
        --subject "$subject"; then
        log_success "SMTP邮件发送成功"
        return 0
    else
        log_error "SMTP邮件发送失败"
        return 1
    fi
}

# 使用系统mail命令发送邮件
send_email_system() {
    local recipient="$1"
    local subject="$2"
    local message="$3"
    
    log_info "使用系统mail命令发送邮件到: $recipient"
    
    if echo "$message" | mail -s "$subject" "$recipient"; then
        log_success "系统邮件发送成功"
        return 0
    else
        log_error "系统邮件发送失败"
        return 1
    fi
}

# 通用邮件发送函数
send_email() {
    local recipient="$1"
    local subject="$2"
    local message="$3"
    local retry_count="${EMAIL_RETRY_COUNT:-3}"
    local retry_interval="${EMAIL_RETRY_INTERVAL:-60}"
    
    # 记录邮件发送日志
    if [[ "$ENABLE_EMAIL_LOGGING" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 尝试发送邮件到: $recipient, 主题: $subject" >> "${EMAIL_LOG_FILE:-$LOG_DIR/email.log}"
    fi
    
    local attempt=1
    while [[ $attempt -le $retry_count ]]; do
        log_info "邮件发送尝试 $attempt/$retry_count"
        
        local success=false
        
        # 优先使用SMTP，如果配置了的话
        if check_smtp_config; then
            if send_email_smtp "$recipient" "$subject" "$message"; then
                success=true
            fi
        else
            # 使用系统mail命令
            if send_email_system "$recipient" "$subject" "$message"; then
                success=true
            fi
        fi
        
        if [[ "$success" == "true" ]]; then
            # 记录成功日志
            if [[ "$ENABLE_EMAIL_LOGGING" == "true" ]]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 邮件发送成功到: $recipient" >> "${EMAIL_LOG_FILE:-$LOG_DIR/email.log}"
            fi
            return 0
        fi
        
        # 如果不是最后一次尝试，等待后重试
        if [[ $attempt -lt $retry_count ]] && [[ "$ENABLE_EMAIL_RETRY" == "true" ]]; then
            log_warn "邮件发送失败，${retry_interval}秒后重试..."
            sleep "$retry_interval"
        fi
        
        ((attempt++))
    done
    
    # 记录失败日志
    if [[ "$ENABLE_EMAIL_LOGGING" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 邮件发送失败到: $recipient, 已重试 $retry_count 次" >> "${EMAIL_LOG_FILE:-$LOG_DIR/email.log}"
    fi
    
    log_error "邮件发送失败，已重试 $retry_count 次"
    return 1
}

# 检查邮件系统
check_mail_system() {
    log_info "检查邮件系统..."
    
    # 优先检查SMTP配置
    if check_smtp_config; then
        log_success "SMTP邮件系统配置正确"
        return 0
    fi
    
    # 检查系统mail命令
    if ! command -v mail >/dev/null 2>&1; then
        log_error "mail命令不可用，请安装mailutils包"
        return 1
    fi
    
    # 检查postfix或其他MTA
    if systemctl is-active --quiet postfix; then
        log_success "Postfix邮件服务正在运行"
    elif systemctl is-active --quiet sendmail; then
        log_success "Sendmail邮件服务正在运行"
    else
        log_warn "未检测到运行中的邮件传输代理(MTA)"
        log_info "建议配置外部SMTP服务器以确保邮件发送功能正常"
    fi
    
    return 0
}

# 获取证书状态信息
get_certificate_status() {
    local domains=()
    local cert_info=()
    
    # 读取域名配置
    while IFS=':' read -r domain param2 param3 || [[ -n "$domain" ]]; do
        [[ "$domain" =~ ^[[:space:]]*# ]] && continue
        [[ "$domain" =~ ^DEFAULT_EMAIL= ]] && continue
        [[ -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        [[ -n "$domain" ]] && domains+=("$domain")
    done < <(grep -v '^#' "$DOMAINS_CONFIG" | grep -v '^$')
    
    # 获取每个域名的证书信息
    for domain in "${domains[@]}"; do
        local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
        
        if [[ -f "$cert_path" ]]; then
            local not_after=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
            local expiry_timestamp=$(date -d "$not_after" +%s)
            local current_timestamp=$(date +%s)
            local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            local status="正常"
            if [[ $days_until_expiry -le 0 ]]; then
                status="已过期"
            elif [[ $days_until_expiry -le 7 ]]; then
                status="即将过期"
            elif [[ $days_until_expiry -le 30 ]]; then
                status="需要关注"
            fi
            
            cert_info+=("$domain|$not_after|$days_until_expiry|$status")
        else
            cert_info+=("$domain|未找到证书|N/A|无证书")
        fi
    done
    
    printf '%s\n' "${cert_info[@]}"
}

# 发送测试邮件
send_test_email() {
    local recipient="${1:-$NOTIFICATION_EMAIL}"
    
    log_info "发送测试邮件到: $recipient"
    
    local subject="${EMAIL_SUBJECT_PREFIX:-[SSL续订通知]} 测试邮件"
    local message="这是一封来自SSL证书自动续订系统的测试邮件。

发送时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)
系统: $(uname -a)

如果您收到此邮件，说明邮件通知功能配置正确。

${EMAIL_SIGNATURE:-
---
SSL证书自动续订系统}"
    
    send_email "$recipient" "$subject" "$message"
}

# 发送证书状态报告
send_status_report() {
    local recipient="${1:-$NOTIFICATION_EMAIL}"
    local report_type="${2:-weekly}"  # daily, weekly, monthly
    
    log_info "发送证书状态报告到: $recipient"
    
    local subject="${EMAIL_SUBJECT_PREFIX:-[SSL续订通知]} SSL证书状态报告"
    
    # 获取证书状态
    local cert_status=$(get_certificate_status)
    
    # 统计信息
    local total_certs=$(echo "$cert_status" | wc -l)
    local expired_certs=$(echo "$cert_status" | grep -c "已过期" || true)
    local expiring_soon=$(echo "$cert_status" | grep -c "即将过期\|需要关注" || true)
    local normal_certs=$(echo "$cert_status" | grep -c "正常" || true)
    
    # 构建邮件内容
    local message="SSL证书状态报告

报告时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)
报告类型: $report_type

证书统计:
========
总证书数量: $total_certs
正常证书: $normal_certs
需要关注: $expiring_soon
已过期证书: $expired_certs

详细信息:
========"

    # 添加详细的证书信息
    echo "$cert_status" | while IFS='|' read -r domain expiry_date days_left status; do
        message="$message
$(printf "%-25s %-20s %10s天 %s" "$domain" "$expiry_date" "$days_left" "$status")"
    done
    
    message="$message

系统信息:
========
Certbot版本: $(certbot --version 2>&1 | head -1 || echo '未安装')
磁盘使用率: $(df /etc/letsencrypt 2>/dev/null | tail -1 | awk '{print $5}' || echo '未知')
最后续订检查: $(tail -1 "$BASE_DIR/logs/ssl-renew.log" 2>/dev/null | grep -o '^\[.*\]' | sed 's/\[//;s/\]//' || echo '无记录')

建议操作:
========"

    # 根据状态添加建议
    if [[ $expired_certs -gt 0 ]]; then
        message="$message
- 立即处理已过期的证书
- 检查域名解析和Web服务器配置"
    fi
    
    if [[ $expiring_soon -gt 0 ]]; then
        message="$message
- 关注即将过期的证书
- 确认自动续订功能正常工作"
    fi
    
    if [[ $expired_certs -eq 0 ]] && [[ $expiring_soon -eq 0 ]]; then
        message="$message
- 所有证书状态正常
- 继续保持定期监控"
    fi
    
    message="$message

---
此邮件由SSL证书自动续订系统自动发送。
如需停止接收此类邮件，请联系系统管理员。"
    
    send_email "$recipient" "$subject" "$message"
}

# 发送紧急通知
send_emergency_notification() {
    local message="$1"
    local recipient="${2:-$NOTIFICATION_EMAIL}"
    
    log_info "发送紧急通知到: $recipient"
    
    local subject="${EMAIL_SUBJECT_PREFIX:-[SSL续订通知]} 紧急通知 - SSL证书问题"
    
    local full_message="SSL证书系统紧急通知

时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)
紧急程度: 高

问题描述:
========
$message

建议操作:
========
1. 立即检查SSL证书状态
2. 查看系统日志文件
3. 手动运行证书续订脚本
4. 联系系统管理员

相关命令:
========
检查证书状态: /opt/ssl-auto-renewal/scripts/check-ssl.sh --all
手动续订证书: /opt/ssl-auto-renewal/scripts/ssl-renew.sh
查看日志: tail -f /opt/ssl-auto-renewal/logs/ssl-renew.log

---
此为自动生成的紧急通知邮件。
请立即采取相应措施。"
    
    send_email "$recipient" "$subject" "$full_message"
}

# 发送续订成功通知
send_renewal_success() {
    local domains="$1"
    local recipient="${2:-$NOTIFICATION_EMAIL}"
    
    log_info "发送续订成功通知到: $recipient"
    
    local subject="${EMAIL_SUBJECT_PREFIX:-[SSL续订通知]} SSL证书续订成功"
    
    local message="SSL证书续订成功通知

时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)

已成功续订的域名:
===============
$domains

操作结果:
========
- 证书已成功续订
- Web服务器配置已重新加载
- 新证书已生效

下次检查时间:
===========
系统将在每天凌晨2点自动检查证书状态。

---
SSL证书自动续订系统"
    
    send_email "$recipient" "$subject" "$message"
}

# 显示帮助信息
show_help() {
    echo "SSL证书邮件通知脚本"
    echo ""
    echo "用法: $0 [选项] [参数]"
    echo ""
    echo "选项:"
    echo "  --test [EMAIL]              发送测试邮件"
    echo "  --status [EMAIL]            发送状态报告"
    echo "  --emergency MESSAGE [EMAIL] 发送紧急通知"
    echo "  --success DOMAINS [EMAIL]   发送续订成功通知"
    echo "  --check                     检查邮件系统配置"
    echo "  --help, -h                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --test                           # 发送测试邮件"
    echo "  $0 --test admin@example.com         # 发送测试邮件到指定地址"
    echo "  $0 --status                         # 发送状态报告"
    echo "  $0 --emergency \"证书过期\"           # 发送紧急通知"
    echo "  $0 --success \"example.com\"         # 发送续订成功通知"
    echo "  $0 --check                          # 检查邮件系统"
    echo ""
}

# 主函数
main() {
    local action=""
    local message=""
    local domains=""
    local recipient=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test)
                action="test"
                recipient="$2"
                [[ "$2" =~ ^[^-] ]] && shift
                shift
                ;;
            --status)
                action="status"
                recipient="$2"
                [[ "$2" =~ ^[^-] ]] && shift
                shift
                ;;
            --emergency)
                action="emergency"
                message="$2"
                recipient="$3"
                shift 2
                [[ "$1" =~ ^[^-] ]] && { recipient="$1"; shift; }
                ;;
            --success)
                action="success"
                domains="$2"
                recipient="$3"
                shift 2
                [[ "$1" =~ ^[^-] ]] && { recipient="$1"; shift; }
                ;;
            --check)
                action="check"
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
    
    if [[ -z "$action" ]]; then
        log_error "请指定操作"
        show_help
        exit 1
    fi
    
    log_info "邮件通知脚本开始运行..."
    
    # 检查邮件系统
    if [[ "$action" == "check" ]]; then
        check_mail_system
        if load_email_config; then
            log_success "邮件配置检查通过"
        fi
        exit 0
    fi
    
    # 加载邮件配置
    if ! load_email_config; then
        exit 1
    fi
    
    # 检查邮件系统
    if ! check_mail_system; then
        log_warn "邮件系统检查失败，但继续尝试发送"
    fi
    
    # 执行相应操作
    case "$action" in
        "test")
            send_test_email "$recipient"
            ;;
        "status")
            send_status_report "$recipient"
            ;;
        "emergency")
            if [[ -z "$message" ]]; then
                log_error "紧急通知需要提供消息内容"
                exit 1
            fi
            send_emergency_notification "$message" "$recipient"
            ;;
        "success")
            if [[ -z "$domains" ]]; then
                log_error "续订成功通知需要提供域名列表"
                exit 1
            fi
            send_renewal_success "$domains" "$recipient"
            ;;
        *)
            log_error "未知操作: $action"
            exit 1
            ;;
    esac
    
    log_info "邮件通知脚本运行完成"
}

# 执行主函数
main "$@"