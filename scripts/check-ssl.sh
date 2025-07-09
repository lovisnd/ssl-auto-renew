#!/bin/bash

# SSL证书状态检查脚本
# 功能：检查SSL证书的有效性和过期时间
# 作者: SSL Auto Renewal System
# 版本: 1.0

set -e

# 配置路径
BASE_DIR="/opt/ssl-auto-renewal"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
DOMAINS_CONFIG="$CONFIG_DIR/domains.conf"

# 日志文件
LOG_FILE="$LOG_DIR/ssl-check.log"

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

# 检查单个域名的SSL证书
check_domain_ssl() {
    local domain="$1"
    local check_online="${2:-true}"
    
    echo ""
    echo "========================================="
    echo "检查域名: $domain"
    echo "========================================="
    
    # 检查本地证书文件
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [[ -f "$cert_path" ]]; then
        log_info "找到本地证书文件: $cert_path"
        
        # 获取证书信息
        local cert_info=$(openssl x509 -in "$cert_path" -text -noout)
        local subject=$(echo "$cert_info" | grep "Subject:" | sed 's/.*Subject: //')
        local issuer=$(echo "$cert_info" | grep "Issuer:" | sed 's/.*Issuer: //')
        local not_before=$(openssl x509 -startdate -noout -in "$cert_path" | cut -d= -f2)
        local not_after=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
        
        # 计算剩余天数
        local expiry_timestamp=$(date -d "$not_after" +%s)
        local current_timestamp=$(date +%s)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
        
        echo "证书主体: $subject"
        echo "证书颁发者: $issuer"
        echo "生效时间: $not_before"
        echo "过期时间: $not_after"
        
        if [[ $days_until_expiry -gt 0 ]]; then
            if [[ $days_until_expiry -le 30 ]]; then
                log_warn "证书将在 $days_until_expiry 天后过期 (需要续订)"
            else
                log_success "证书还有 $days_until_expiry 天过期 (状态正常)"
            fi
        else
            log_error "证书已过期 $((days_until_expiry * -1)) 天"
        fi
        
        # 检查证书中的域名
        local san_domains=$(openssl x509 -in "$cert_path" -text -noout | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g' | sed 's/, /\n/g' | sort)
        if [[ -n "$san_domains" ]]; then
            echo "证书包含的域名:"
            echo "$san_domains" | sed 's/^/  - /'
        fi
        
    else
        log_warn "未找到本地证书文件，域名可能未申请SSL证书"
    fi
    
    # 在线检查SSL证书（如果启用）
    if [[ "$check_online" == "true" ]]; then
        echo ""
        log_info "检查在线SSL证书状态..."
        
        # 检查443端口是否开放
        if timeout 5 bash -c "</dev/tcp/$domain/443" 2>/dev/null; then
            # 获取在线证书信息
            local online_cert_info=$(echo | timeout 10 openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
            
            if [[ -n "$online_cert_info" ]]; then
                local online_not_after=$(echo "$online_cert_info" | grep "notAfter" | cut -d= -f2)
                local online_expiry_timestamp=$(date -d "$online_not_after" +%s)
                local online_days_until_expiry=$(( (online_expiry_timestamp - current_timestamp) / 86400 ))
                
                echo "在线证书过期时间: $online_not_after"
                
                if [[ $online_days_until_expiry -gt 0 ]]; then
                    if [[ $online_days_until_expiry -le 30 ]]; then
                        log_warn "在线证书将在 $online_days_until_expiry 天后过期"
                    else
                        log_success "在线证书还有 $online_days_until_expiry 天过期"
                    fi
                else
                    log_error "在线证书已过期 $((online_days_until_expiry * -1)) 天"
                fi
                
                # 比较本地和在线证书
                if [[ -f "$cert_path" ]] && [[ "$not_after" == "$online_not_after" ]]; then
                    log_success "本地证书与在线证书一致"
                elif [[ -f "$cert_path" ]]; then
                    log_warn "本地证书与在线证书不一致，可能需要重新加载Web服务器配置"
                fi
            else
                log_error "无法获取在线证书信息"
            fi
        else
            log_warn "无法连接到域名的443端口，可能域名未正确解析或防火墙阻止"
        fi
    fi
}

# 检查Web服务器配置
check_webserver_config() {
    echo ""
    echo "========================================="
    echo "检查Web服务器配置"
    echo "========================================="
    
    # 检查Nginx
    if command -v nginx >/dev/null 2>&1; then
        log_info "检查Nginx配置..."
        
        if nginx -t 2>/dev/null; then
            log_success "Nginx配置语法正确"
        else
            log_error "Nginx配置语法错误"
        fi
        
        if systemctl is-active --quiet nginx; then
            log_success "Nginx服务正在运行"
        else
            log_warn "Nginx服务未运行"
        fi
    fi
    
    # 检查Apache
    if command -v apache2 >/dev/null 2>&1; then
        log_info "检查Apache配置..."
        
        if apache2ctl configtest 2>/dev/null; then
            log_success "Apache配置语法正确"
        else
            log_error "Apache配置语法错误"
        fi
        
        if systemctl is-active --quiet apache2; then
            log_success "Apache服务正在运行"
        else
            log_warn "Apache服务未运行"
        fi
    fi
}

# 检查系统状态
check_system_status() {
    echo ""
    echo "========================================="
    echo "检查系统状态"
    echo "========================================="
    
    # 检查磁盘空间
    local disk_usage=$(df /etc/letsencrypt 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" ]] && [[ $disk_usage -gt 90 ]]; then
        log_warn "磁盘空间使用率较高: ${disk_usage}%"
    else
        log_success "磁盘空间充足: ${disk_usage}%"
    fi
    
    # 检查Certbot版本
    if command -v certbot >/dev/null 2>&1; then
        local certbot_version=$(certbot --version 2>&1 | head -1)
        log_info "Certbot版本: $certbot_version"
    else
        log_error "Certbot未安装"
    fi
    
    # 检查定时任务
    if crontab -l 2>/dev/null | grep -q "ssl-renew.sh"; then
        log_success "SSL续订定时任务已配置"
    else
        log_warn "SSL续订定时任务未配置"
    fi
    
    # 检查最近的续订日志
    if [[ -f "$BASE_DIR/logs/ssl-renew.log" ]]; then
        local last_run=$(tail -1 "$BASE_DIR/logs/ssl-renew.log" 2>/dev/null | grep -o '^\[.*\]' | sed 's/\[//;s/\]//')
        if [[ -n "$last_run" ]]; then
            log_info "最后一次续订检查: $last_run"
        fi
    fi
}

# 生成状态报告
generate_report() {
    local output_file="$1"
    local domains=()
    
    # 读取域名列表
    while IFS=':' read -r domain param2 param3 || [[ -n "$domain" ]]; do
        [[ "$domain" =~ ^[[:space:]]*# ]] && continue
        [[ "$domain" =~ ^DEFAULT_EMAIL= ]] && continue
        [[ -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        [[ -n "$domain" ]] && domains+=("$domain")
    done < <(grep -v '^#' "$DOMAINS_CONFIG" | grep -v '^$')
    
    # 生成报告
    {
        echo "SSL证书状态报告"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "服务器: $(hostname)"
        echo ""
        echo "域名证书状态:"
        echo "=============="
        
        for domain in "${domains[@]}"; do
            local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
            if [[ -f "$cert_path" ]]; then
                local not_after=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
                local expiry_timestamp=$(date -d "$not_after" +%s)
                local current_timestamp=$(date +%s)
                local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                
                printf "%-30s %s (%d天)\n" "$domain" "$not_after" "$days_until_expiry"
            else
                printf "%-30s %s\n" "$domain" "证书不存在"
            fi
        done
        
        echo ""
        echo "系统信息:"
        echo "========"
        echo "Certbot版本: $(certbot --version 2>&1 | head -1)"
        echo "磁盘使用率: $(df /etc/letsencrypt 2>/dev/null | tail -1 | awk '{print $5}')"
        
    } > "$output_file"
    
    log_success "状态报告已生成: $output_file"
}

# 显示帮助信息
show_help() {
    echo "SSL证书状态检查脚本"
    echo ""
    echo "用法: $0 [选项] [域名]"
    echo ""
    echo "选项:"
    echo "  --all, -a           检查所有配置的域名"
    echo "  --offline, -o       仅检查本地证书，不进行在线检查"
    echo "  --report FILE, -r   生成状态报告到指定文件"
    echo "  --system, -s        检查系统状态"
    echo "  --help, -h          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                          # 检查所有域名"
    echo "  $0 example.com              # 检查指定域名"
    echo "  $0 --all --offline          # 离线检查所有域名"
    echo "  $0 --report /tmp/ssl.txt    # 生成状态报告"
    echo "  $0 --system                 # 检查系统状态"
    echo ""
}

# 主函数
main() {
    local check_all=false
    local check_online=true
    local check_system=false
    local report_file=""
    local target_domain=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)
                check_all=true
                shift
                ;;
            --offline|-o)
                check_online=false
                shift
                ;;
            --system|-s)
                check_system=true
                shift
                ;;
            --report|-r)
                report_file="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
            *)
                target_domain="$1"
                shift
                ;;
        esac
    done
    
    log_info "SSL证书状态检查开始..."
    
    # 检查配置文件
    if [[ ! -f "$DOMAINS_CONFIG" ]]; then
        log_error "域名配置文件不存在: $DOMAINS_CONFIG"
        exit 1
    fi
    
    # 检查系统状态
    if [[ "$check_system" == "true" ]]; then
        check_system_status
        check_webserver_config
    fi
    
    # 生成报告
    if [[ -n "$report_file" ]]; then
        generate_report "$report_file"
        return 0
    fi
    
    # 检查指定域名
    if [[ -n "$target_domain" ]]; then
        check_domain_ssl "$target_domain" "$check_online"
        return 0
    fi
    
    # 检查所有域名
    local domains=()
    while IFS=':' read -r domain param2 param3 || [[ -n "$domain" ]]; do
        [[ "$domain" =~ ^[[:space:]]*# ]] && continue
        [[ "$domain" =~ ^DEFAULT_EMAIL= ]] && continue
        [[ -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        [[ -n "$domain" ]] && domains+=("$domain")
    done < <(grep -v '^#' "$DOMAINS_CONFIG" | grep -v '^$')
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        log_warn "未找到配置的域名"
        exit 1
    fi
    
    for domain in "${domains[@]}"; do
        check_domain_ssl "$domain" "$check_online"
    done
    
    echo ""
    log_info "SSL证书状态检查完成"
}

# 执行主函数
main "$@"