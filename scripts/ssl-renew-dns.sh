#!/bin/bash

# SSL证书DNS验证续订脚本
# 专门用于中国大陆未备案域名的SSL证书申请和续订
# 使用DNS验证方式绕过HTTP验证限制

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"

# 日志文件
LOG_FILE="$LOG_DIR/ssl-renew-dns.log"
ERROR_LOG="$LOG_DIR/ssl-error.log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 日志函数
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" >> "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $message" >> "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$ERROR_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" >> "$LOG_FILE"
}

# 显示帮助信息
show_help() {
    cat << EOF
SSL证书DNS验证续订脚本

用法: $0 [选项]

选项:
    -d, --domain DOMAIN     指定单个域名进行DNS验证
    -t, --test             测试模式（dry-run）
    -f, --force            强制续订所有证书
    -m, --manual           手动DNS验证模式
    -a, --auto             自动DNS验证模式（需要API配置）
    -h, --help             显示此帮助信息

示例:
    $0 --domain zhangmingrui.top --manual
    $0 --test --domain zhangmingrui.top
    $0 --force --auto

注意:
    - DNS验证适用于中国大陆未备案域名
    - 手动模式需要您手动添加DNS TXT记录
    - 自动模式需要配置DNS API密钥

EOF
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查certbot是否安装
check_certbot() {
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot未安装"
        log_info "请先运行安装脚本: sudo bash install.sh"
        exit 1
    fi
}

# 手动DNS验证单个域名
manual_dns_validation() {
    local domain="$1"
    local test_mode="$2"
    local email="${3:-admin@$domain}"
    
    log_info "开始为域名 $domain 进行手动DNS验证"
    
    # 构建certbot命令
    local certbot_cmd="certbot certonly --manual --preferred-challenges dns"
    
    if [[ "$test_mode" == "true" ]]; then
        certbot_cmd="$certbot_cmd --dry-run"
        log_info "运行测试模式（dry-run）"
    fi
    
    # 添加域名和子域名
    certbot_cmd="$certbot_cmd -d $domain -d www.$domain"
    certbot_cmd="$certbot_cmd --email $email --agree-tos --no-eff-email"
    
    log_info "执行命令: $certbot_cmd"
    
    echo
    echo -e "${YELLOW}重要提示：${NC}"
    echo "1. 接下来Certbot会要求您添加DNS TXT记录"
    echo "2. 请登录您的DNS管理面板（如DNSPod）"
    echo "3. 添加指定的TXT记录到 _acme-challenge.$domain"
    echo "4. 等待DNS传播（通常1-5分钟）"
    echo "5. 确认记录生效后按回车继续"
    echo
    
    # 执行certbot命令
    if eval "$certbot_cmd"; then
        if [[ "$test_mode" != "true" ]]; then
            log_success "域名 $domain 的SSL证书申请成功"
            
            # 重启Web服务器
            restart_webserver
            
            # 发送通知
            send_notification "success" "$domain" "DNS验证SSL证书申请成功"
        else
            log_success "域名 $domain 的DNS验证测试通过"
        fi
        return 0
    else
        log_error "域名 $domain 的SSL证书申请失败"
        send_notification "error" "$domain" "DNS验证SSL证书申请失败"
        return 1
    fi
}

# 检查DNS TXT记录
check_dns_txt_record() {
    local domain="$1"
    local txt_name="_acme-challenge.$domain"
    local expected_value="$2"
    
    log_info "检查DNS TXT记录: $txt_name"
    
    # 使用dig检查TXT记录
    local actual_value
    actual_value=$(dig +short TXT "$txt_name" | tr -d '"' | head -n1)
    
    if [[ -n "$actual_value" ]]; then
        log_info "找到TXT记录: $actual_value"
        if [[ "$actual_value" == "$expected_value" ]]; then
            log_success "DNS TXT记录验证通过"
            return 0
        else
            log_warning "DNS TXT记录值不匹配"
            log_warning "期望值: $expected_value"
            log_warning "实际值: $actual_value"
            return 1
        fi
    else
        log_warning "未找到DNS TXT记录: $txt_name"
        return 1
    fi
}

# 重启Web服务器
restart_webserver() {
    log_info "重启Web服务器..."
    
    # 检查并重启Nginx
    if systemctl is-active --quiet nginx; then
        if nginx -t; then
            systemctl reload nginx
            log_success "Nginx配置重载成功"
        else
            log_error "Nginx配置测试失败"
            return 1
        fi
    elif systemctl is-active --quiet apache2; then
        if apache2ctl configtest; then
            systemctl reload apache2
            log_success "Apache配置重载成功"
        else
            log_error "Apache配置测试失败"
            return 1
        fi
    else
        log_warning "未检测到运行中的Web服务器"
    fi
}

# 发送通知
send_notification() {
    local status="$1"
    local domain="$2"
    local message="$3"
    
    # 检查通知脚本是否存在
    local notify_script="$SCRIPT_DIR/notify.sh"
    if [[ -f "$notify_script" ]]; then
        if [[ "$status" == "success" ]]; then
            "$notify_script" --success --domain "$domain" --message "$message"
        else
            "$notify_script" --error --domain "$domain" --message "$message"
        fi
    fi
}

# 批量处理域名配置文件
process_domains_config() {
    local test_mode="$1"
    local force_mode="$2"
    
    local domains_config="$CONFIG_DIR/domains.conf"
    
    if [[ ! -f "$domains_config" ]]; then
        log_error "域名配置文件不存在: $domains_config"
        return 1
    fi
    
    log_info "处理域名配置文件: $domains_config"
    
    local success_count=0
    local error_count=0
    
    # 读取配置文件
    while IFS=':' read -r domain email webroot || [[ -n "$domain" ]]; do
        # 跳过注释和空行
        if [[ "$domain" =~ ^[[:space:]]*# ]] || [[ -z "$domain" ]]; then
            continue
        fi
        
        # 清理空格
        domain=$(echo "$domain" | xargs)
        email=$(echo "$email" | xargs)
        
        if [[ -n "$domain" ]]; then
            log_info "处理域名: $domain"
            
            # 检查是否需要续订
            if [[ "$force_mode" == "true" ]] || needs_renewal "$domain"; then
                if manual_dns_validation "$domain" "$test_mode" "$email"; then
                    ((success_count++))
                else
                    ((error_count++))
                fi
            else
                log_info "域名 $domain 的证书尚未到期，跳过续订"
            fi
        fi
    done < "$domains_config"
    
    log_info "处理完成: 成功 $success_count 个，失败 $error_count 个"
    
    if [[ $error_count -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# 检查证书是否需要续订
needs_renewal() {
    local domain="$1"
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [[ ! -f "$cert_path" ]]; then
        log_info "域名 $domain 没有现有证书，需要申请"
        return 0
    fi
    
    # 检查证书过期时间
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    local expiry_timestamp
    expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp
    current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    log_info "域名 $domain 的证书还有 $days_until_expiry 天过期"
    
    # 如果少于30天则需要续订
    if [[ $days_until_expiry -lt 30 ]]; then
        return 0
    else
        return 1
    fi
}

# 创建DNS验证指南
create_dns_guide() {
    local domain="$1"
    local txt_name="_acme-challenge.$domain"
    local txt_value="$2"
    
    cat << EOF

========================================
DNS验证操作指南
========================================

域名: $domain
记录类型: TXT
记录名称: $txt_name
记录值: $txt_value

DNSPod操作步骤:
1. 登录 https://console.dnspod.cn/
2. 选择域名 $domain
3. 点击"添加记录"
4. 记录类型选择 "TXT"
5. 主机记录填写 "_acme-challenge"
6. 记录值填写 "$txt_value"
7. 点击确认添加

验证方法:
dig +short TXT $txt_name

等待DNS传播后按回车继续...

========================================

EOF
}

# 主函数
main() {
    local domain=""
    local test_mode=false
    local force_mode=false
    local manual_mode=false
    local auto_mode=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                domain="$2"
                shift 2
                ;;
            -t|--test)
                test_mode=true
                shift
                ;;
            -f|--force)
                force_mode=true
                shift
                ;;
            -m|--manual)
                manual_mode=true
                shift
                ;;
            -a|--auto)
                auto_mode=true
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
    
    # 检查权限和依赖
    check_root
    check_certbot
    
    log_info "开始DNS验证SSL证书续订..."
    
    if [[ -n "$domain" ]]; then
        # 处理单个域名
        manual_dns_validation "$domain" "$test_mode"
    else
        # 处理配置文件中的所有域名
        if [[ "$manual_mode" == "true" ]]; then
            log_warning "批量处理时建议使用单个域名模式"
            log_info "使用: $0 --domain your-domain.com --manual"
        fi
        
        process_domains_config "$test_mode" "$force_mode"
    fi
    
    log_info "DNS验证SSL证书续订完成"
}

# 运行主函数
main "$@"