#!/bin/bash

# DNS证书续订提醒脚本
# 用于检查DNS验证证书的过期时间并发送提醒

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
LOG_FILE="$LOG_DIR/dns-reminder.log"

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
}

# 显示帮助信息
show_help() {
    cat << EOF
DNS证书续订提醒脚本

用法: $0 [选项]

选项:
    -d, --domain DOMAIN     检查指定域名的证书
    -a, --all              检查所有配置的域名
    -w, --warning-days N   提前N天发送警告（默认30天）
    -c, --critical-days N  提前N天发送紧急警告（默认7天）
    -q, --quiet            静默模式，只在需要提醒时输出
    -h, --help             显示此帮助信息

示例:
    $0 --domain zhangmingrui.top
    $0 --all --warning-days 45
    $0 --quiet

EOF
}

# 检查单个域名的证书状态
check_domain_certificate() {
    local domain="$1"
    local warning_days="${2:-30}"
    local critical_days="${3:-7}"
    local quiet_mode="${4:-false}"
    
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [[ ! -f "$cert_path" ]]; then
        if [[ "$quiet_mode" != "true" ]]; then
            log_warning "域名 $domain 没有SSL证书文件"
        fi
        return 1
    fi
    
    # 获取证书过期时间
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    local expiry_timestamp
    expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp
    current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [[ "$quiet_mode" != "true" ]]; then
        log_info "域名 $domain 的证书还有 $days_until_expiry 天过期"
    fi
    
    # 检查是否需要发送提醒
    local need_reminder=false
    local reminder_type=""
    local reminder_message=""
    
    if [[ $days_until_expiry -lt $critical_days ]]; then
        need_reminder=true
        reminder_type="critical"
        reminder_message="🚨 紧急：域名 $domain 的SSL证书将在 $days_until_expiry 天后过期！请立即续订！"
    elif [[ $days_until_expiry -lt $warning_days ]]; then
        need_reminder=true
        reminder_type="warning"
        reminder_message="⚠️ 警告：域名 $domain 的SSL证书将在 $days_until_expiry 天后过期，请及时续订"
    fi
    
    if [[ "$need_reminder" == "true" ]]; then
        echo
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  SSL证书续订提醒${NC}"
        echo -e "${RED}========================================${NC}"
        echo
        echo -e "${YELLOW}$reminder_message${NC}"
        echo
        echo -e "${BLUE}证书信息：${NC}"
        echo "域名: $domain"
        echo "过期时间: $expiry_date"
        echo "剩余天数: $days_until_expiry 天"
        echo
        echo -e "${BLUE}续订命令：${NC}"
        echo "sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $domain --manual"
        echo
        echo -e "${BLUE}测试命令：${NC}"
        echo "sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $domain --manual --test"
        echo
        echo -e "${RED}========================================${NC}"
        echo
        
        # 发送邮件通知
        send_email_notification "$domain" "$reminder_type" "$reminder_message" "$days_until_expiry"
        
        # 记录提醒日志
        if [[ "$reminder_type" == "critical" ]]; then
            log_error "$reminder_message"
        else
            log_warning "$reminder_message"
        fi
        
        return 2  # 需要提醒
    fi
    
    return 0  # 正常
}

# 发送邮件通知
send_email_notification() {
    local domain="$1"
    local type="$2"
    local message="$3"
    local days="$4"
    
    local notify_script="$SCRIPT_DIR/notify.sh"
    
    if [[ -f "$notify_script" ]]; then
        local subject="SSL证书续订提醒 - $domain"
        local body="域名: $domain
过期天数: $days 天
提醒类型: $type
消息: $message

续订步骤:
1. 运行测试命令: sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $domain --manual --test
2. 如果测试通过，运行: sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $domain --manual
3. 按照提示添加DNS TXT记录
4. 等待DNS传播后按回车继续

注意: DNS验证需要手动操作，请及时处理！"
        
        if [[ "$type" == "critical" ]]; then
            "$notify_script" --error --domain "$domain" --subject "$subject" --message "$body"
        else
            "$notify_script" --warning --domain "$domain" --subject "$subject" --message "$body"
        fi
    fi
}

# 检查所有配置的域名
check_all_domains() {
    local warning_days="${1:-30}"
    local critical_days="${2:-7}"
    local quiet_mode="${3:-false}"
    
    local domains_config="$CONFIG_DIR/domains.conf"
    
    if [[ ! -f "$domains_config" ]]; then
        log_error "域名配置文件不存在: $domains_config"
        return 1
    fi
    
    if [[ "$quiet_mode" != "true" ]]; then
        log_info "检查所有配置的域名证书状态..."
    fi
    
    local total_domains=0
    local warning_domains=0
    local critical_domains=0
    local normal_domains=0
    
    # 读取配置文件
    while IFS=':' read -r domain email webroot || [[ -n "$domain" ]]; do
        # 跳过注释和空行
        if [[ "$domain" =~ ^[[:space:]]*# ]] || [[ -z "$domain" ]]; then
            continue
        fi
        
        # 清理空格
        domain=$(echo "$domain" | xargs)
        
        if [[ -n "$domain" ]]; then
            ((total_domains++))
            
            local result
            check_domain_certificate "$domain" "$warning_days" "$critical_days" "$quiet_mode"
            result=$?
            
            case $result in
                0)
                    ((normal_domains++))
                    ;;
                2)
                    if [[ $days_until_expiry -lt $critical_days ]]; then
                        ((critical_domains++))
                    else
                        ((warning_domains++))
                    fi
                    ;;
                *)
                    # 证书不存在或其他错误
                    ;;
            esac
        fi
    done < "$domains_config"
    
    # 显示汇总信息
    if [[ "$quiet_mode" != "true" ]] || [[ $warning_domains -gt 0 ]] || [[ $critical_domains -gt 0 ]]; then
        echo
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}  证书状态汇总${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo "总域名数: $total_domains"
        echo "正常域名: $normal_domains"
        echo "警告域名: $warning_domains"
        echo "紧急域名: $critical_domains"
        echo -e "${BLUE}========================================${NC}"
        echo
    fi
    
    # 返回状态码
    if [[ $critical_domains -gt 0 ]]; then
        return 2  # 有紧急情况
    elif [[ $warning_domains -gt 0 ]]; then
        return 1  # 有警告
    else
        return 0  # 全部正常
    fi
}

# 生成续订计划
generate_renewal_plan() {
    local domains_config="$CONFIG_DIR/domains.conf"
    
    if [[ ! -f "$domains_config" ]]; then
        log_error "域名配置文件不存在: $domains_config"
        return 1
    fi
    
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  SSL证书续订计划${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # 读取配置文件
    while IFS=':' read -r domain email webroot || [[ -n "$domain" ]]; do
        # 跳过注释和空行
        if [[ "$domain" =~ ^[[:space:]]*# ]] || [[ -z "$domain" ]]; then
            continue
        fi
        
        # 清理空格
        domain=$(echo "$domain" | xargs)
        
        if [[ -n "$domain" ]]; then
            local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
            
            if [[ -f "$cert_path" ]]; then
                local expiry_date
                expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
                local expiry_timestamp
                expiry_timestamp=$(date -d "$expiry_date" +%s)
                local current_timestamp
                current_timestamp=$(date +%s)
                local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                
                echo "域名: $domain"
                echo "过期时间: $expiry_date"
                echo "剩余天数: $days_until_expiry 天"
                
                if [[ $days_until_expiry -lt 30 ]]; then
                    echo -e "${RED}状态: 需要续订${NC}"
                    echo "续订命令: sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $domain --manual"
                else
                    echo -e "${GREEN}状态: 正常${NC}"
                fi
                
                echo "---"
            else
                echo "域名: $domain"
                echo -e "${YELLOW}状态: 无证书，需要申请${NC}"
                echo "申请命令: sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $domain --manual"
                echo "---"
            fi
        fi
    done < "$domains_config"
    
    echo -e "${BLUE}========================================${NC}"
    echo
}

# 主函数
main() {
    local domain=""
    local check_all=false
    local warning_days=30
    local critical_days=7
    local quiet_mode=false
    local show_plan=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                domain="$2"
                shift 2
                ;;
            -a|--all)
                check_all=true
                shift
                ;;
            -w|--warning-days)
                warning_days="$2"
                shift 2
                ;;
            -c|--critical-days)
                critical_days="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            -p|--plan)
                show_plan=true
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
    
    if [[ "$show_plan" == "true" ]]; then
        generate_renewal_plan
        exit 0
    fi
    
    if [[ -n "$domain" ]]; then
        # 检查单个域名
        check_domain_certificate "$domain" "$warning_days" "$critical_days" "$quiet_mode"
    elif [[ "$check_all" == "true" ]]; then
        # 检查所有域名
        check_all_domains "$warning_days" "$critical_days" "$quiet_mode"
    else
        # 默认检查所有域名
        check_all_domains "$warning_days" "$critical_days" "$quiet_mode"
    fi
}

# 运行主函数
main "$@"