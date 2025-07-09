#!/bin/bash

# 域名验证和故障排除脚本
# 用于检查域名配置和Let's Encrypt验证问题

set -e

# 配置路径
BASE_DIR="/opt/ssl-auto-renewal"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
DOMAINS_CONFIG="$CONFIG_DIR/domains.conf"

# 日志文件
LOG_FILE="$LOG_DIR/domain-check.log"

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

# 检查域名DNS解析
check_dns_resolution() {
    local domain="$1"
    
    log_info "检查域名DNS解析: $domain"
    
    # 检查A记录
    local ip_addresses=$(dig +short A "$domain" 2>/dev/null)
    if [[ -z "$ip_addresses" ]]; then
        log_error "域名 $domain 没有A记录"
        return 1
    fi
    
    log_success "域名 $domain 的IP地址:"
    echo "$ip_addresses" | while read -r ip; do
        echo "  - $ip"
    done
    
    # 检查是否指向本服务器
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "无法获取")
    log_info "本服务器IP: $server_ip"
    
    if echo "$ip_addresses" | grep -q "$server_ip"; then
        log_success "域名正确指向本服务器"
        return 0
    else
        log_warn "域名未指向本服务器，请检查DNS配置"
        return 1
    fi
}

# 检查HTTP访问
check_http_access() {
    local domain="$1"
    local webroot="$2"
    
    log_info "检查HTTP访问: $domain"
    
    # 创建测试文件
    local test_file="$webroot/.well-known/acme-challenge/test-$(date +%s)"
    local test_content="SSL证书验证测试文件 - $(date)"
    
    mkdir -p "$webroot/.well-known/acme-challenge"
    echo "$test_content" > "$test_file"
    
    # 测试HTTP访问
    local test_url="http://$domain/.well-known/acme-challenge/$(basename "$test_file")"
    log_info "测试URL: $test_url"
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/domain-test-response "$test_url" 2>/dev/null || echo "000")
    
    if [[ "$response" == "200" ]]; then
        local content=$(cat /tmp/domain-test-response 2>/dev/null)
        if [[ "$content" == "$test_content" ]]; then
            log_success "HTTP访问测试成功"
            rm -f "$test_file" /tmp/domain-test-response
            return 0
        else
            log_error "HTTP访问返回内容不正确"
            log_error "期望: $test_content"
            log_error "实际: $content"
        fi
    else
        log_error "HTTP访问失败，状态码: $response"
        
        # 显示详细错误信息
        if [[ -f /tmp/domain-test-response ]]; then
            log_error "响应内容:"
            head -10 /tmp/domain-test-response | while read -r line; do
                echo "  $line"
            done
        fi
    fi
    
    rm -f "$test_file" /tmp/domain-test-response
    return 1
}

# 检查Web服务器配置
check_web_server() {
    local domain="$1"
    local webroot="$2"
    
    log_info "检查Web服务器配置"
    
    # 检查webroot目录
    if [[ ! -d "$webroot" ]]; then
        log_error "Webroot目录不存在: $webroot"
        return 1
    fi
    
    if [[ ! -w "$webroot" ]]; then
        log_error "Webroot目录不可写: $webroot"
        return 1
    fi
    
    log_success "Webroot目录检查通过: $webroot"
    
    # 检查Nginx配置
    if systemctl is-active --quiet nginx; then
        log_info "Nginx服务正在运行"
        
        # 检查是否有对应的站点配置
        local nginx_config="/etc/nginx/sites-enabled/$domain"
        if [[ -f "$nginx_config" ]]; then
            log_success "找到Nginx配置文件: $nginx_config"
            
            # 检查配置中的webroot设置
            if grep -q "$webroot" "$nginx_config"; then
                log_success "Nginx配置中包含正确的webroot路径"
            else
                log_warn "Nginx配置中可能缺少正确的webroot路径"
            fi
        else
            log_warn "未找到域名对应的Nginx配置文件"
        fi
        
        # 测试Nginx配置
        if nginx -t >/dev/null 2>&1; then
            log_success "Nginx配置语法正确"
        else
            log_error "Nginx配置语法错误"
            nginx -t
            return 1
        fi
    elif systemctl is-active --quiet apache2; then
        log_info "Apache服务正在运行"
    else
        log_error "未检测到运行中的Web服务器"
        return 1
    fi
    
    return 0
}

# 检查防火墙设置
check_firewall() {
    log_info "检查防火墙设置"
    
    # 检查80端口
    if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
        log_success "端口80正在监听"
    else
        log_error "端口80未监听"
        return 1
    fi
    
    # 检查UFW防火墙
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | head -1)
        log_info "UFW状态: $ufw_status"
        
        if ufw status | grep -q "80.*ALLOW"; then
            log_success "UFW允许端口80"
        else
            log_warn "UFW可能阻止端口80"
        fi
    fi
    
    return 0
}

# 生成修复建议
generate_fix_suggestions() {
    local domain="$1"
    local webroot="$2"
    
    echo ""
    echo "========================================"
    echo "修复建议"
    echo "========================================"
    
    echo ""
    echo "1. DNS配置问题："
    echo "   - 确保域名 $domain 的A记录指向您的服务器IP"
    echo "   - 等待DNS传播完成（可能需要几分钟到几小时）"
    echo "   - 使用在线工具检查DNS: https://dnschecker.org/"
    
    echo ""
    echo "2. Web服务器配置："
    echo "   - 确保Nginx/Apache正在运行且配置正确"
    echo "   - 检查站点配置文件中的webroot路径"
    echo "   - 确保 $webroot/.well-known/acme-challenge/ 目录可访问"
    
    echo ""
    echo "3. 防火墙设置："
    echo "   - 确保端口80和443已开放"
    echo "   - 检查云服务商的安全组设置"
    
    echo ""
    echo "4. 域名拦截问题："
    echo "   - 如果域名被DNS服务商拦截，请联系服务商解除拦截"
    echo "   - 检查域名是否在黑名单中"
    echo "   - 考虑更换DNS服务商"
    
    echo ""
    echo "5. 基本Nginx配置示例："
    echo "   创建文件: /etc/nginx/sites-available/$domain"
    echo ""
    cat << EOF
server {
    listen 80;
    server_name $domain;
    
    root $webroot;
    index index.html;
    
    location /.well-known/acme-challenge/ {
        root $webroot;
        try_files \$uri =404;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    echo ""
    echo "   然后执行："
    echo "   sudo ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/"
    echo "   sudo nginx -t"
    echo "   sudo systemctl reload nginx"
    
    echo ""
    echo "6. 测试命令："
    echo "   curl -I http://$domain/.well-known/acme-challenge/"
    echo "   $0 --domain $domain --webroot $webroot"
    
    echo "========================================"
}

# 显示帮助信息
show_help() {
    echo "域名验证和故障排除脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --domain DOMAIN       检查指定域名"
    echo "  --webroot PATH        指定webroot路径"
    echo "  --all                 检查所有配置的域名"
    echo "  --fix-suggestions     显示修复建议"
    echo "  --help, -h            显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --domain example.com --webroot /var/www/html"
    echo "  $0 --all"
    echo "  $0 --domain example.com --fix-suggestions"
    echo ""
}

# 检查单个域名
check_single_domain() {
    local domain="$1"
    local webroot="$2"
    
    echo "========================================"
    echo "检查域名: $domain"
    echo "Webroot: $webroot"
    echo "========================================"
    
    local dns_ok=false
    local http_ok=false
    local web_ok=false
    local fw_ok=false
    
    # DNS检查
    if check_dns_resolution "$domain"; then
        dns_ok=true
    fi
    
    echo ""
    
    # Web服务器检查
    if check_web_server "$domain" "$webroot"; then
        web_ok=true
    fi
    
    echo ""
    
    # HTTP访问检查
    if check_http_access "$domain" "$webroot"; then
        http_ok=true
    fi
    
    echo ""
    
    # 防火墙检查
    if check_firewall; then
        fw_ok=true
    fi
    
    echo ""
    echo "========================================"
    echo "检查结果汇总"
    echo "========================================"
    echo "DNS解析: $([ "$dns_ok" = true ] && echo "✓ 通过" || echo "✗ 失败")"
    echo "Web服务器: $([ "$web_ok" = true ] && echo "✓ 通过" || echo "✗ 失败")"
    echo "HTTP访问: $([ "$http_ok" = true ] && echo "✓ 通过" || echo "✗ 失败")"
    echo "防火墙: $([ "$fw_ok" = true ] && echo "✓ 通过" || echo "✗ 失败")"
    echo "========================================"
    
    if [[ "$dns_ok" = true && "$http_ok" = true && "$web_ok" = true && "$fw_ok" = true ]]; then
        log_success "所有检查通过，域名配置正确！"
        echo ""
        echo "现在可以尝试申请SSL证书："
        echo "sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test"
        return 0
    else
        log_error "检查发现问题，请根据上述结果进行修复"
        generate_fix_suggestions "$domain" "$webroot"
        return 1
    fi
}

# 检查所有域名
check_all_domains() {
    if [[ ! -f "$DOMAINS_CONFIG" ]]; then
        log_error "域名配置文件不存在: $DOMAINS_CONFIG"
        exit 1
    fi
    
    local total_domains=0
    local failed_domains=0
    
    while IFS=':' read -r domain param2 param3 || [[ -n "$domain" ]]; do
        # 跳过注释和空行
        [[ "$domain" =~ ^[[:space:]]*# ]] && continue
        [[ "$domain" =~ ^DEFAULT_EMAIL= ]] && continue
        [[ -z "$domain" ]] && continue
        
        domain=$(echo "$domain" | xargs)
        [[ -z "$domain" ]] && continue
        
        # 解析webroot路径
        local webroot
        if [[ -n "$param3" ]]; then
            # 完整格式: domain:email:webroot
            webroot="$param3"
        elif [[ -n "$param2" ]]; then
            # 简化格式: domain:webroot
            webroot="$param2"
        else
            log_warn "跳过域名 $domain (缺少webroot路径)"
            continue
        fi
        
        ((total_domains++))
        
        echo ""
        if ! check_single_domain "$domain" "$webroot"; then
            ((failed_domains++))
        fi
        
    done < <(grep -v '^#' "$DOMAINS_CONFIG" | grep -v '^$')
    
    echo ""
    echo "========================================"
    echo "总体检查结果"
    echo "========================================"
    echo "总域名数: $total_domains"
    echo "失败域名数: $failed_domains"
    echo "成功域名数: $((total_domains - failed_domains))"
    
    if [[ $failed_domains -eq 0 ]]; then
        log_success "所有域名检查通过！"
    else
        log_error "$failed_domains 个域名检查失败"
    fi
    
    return $failed_domains
}

# 主函数
main() {
    local domain=""
    local webroot=""
    local check_all=false
    local show_fix=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                domain="$2"
                shift 2
                ;;
            --webroot)
                webroot="$2"
                shift 2
                ;;
            --all)
                check_all=true
                shift
                ;;
            --fix-suggestions)
                show_fix=true
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
    
    echo "域名验证和故障排除脚本"
    echo "========================================"
    
    if [[ "$check_all" = true ]]; then
        check_all_domains
    elif [[ -n "$domain" ]]; then
        if [[ -z "$webroot" ]]; then
            log_error "请指定webroot路径"
            exit 1
        fi
        
        if [[ "$show_fix" = true ]]; then
            generate_fix_suggestions "$domain" "$webroot"
        else
            check_single_domain "$domain" "$webroot"
        fi
    else
        log_error "请指定要检查的域名或使用 --all 检查所有域名"
        show_help
        exit 1
    fi
}

# 执行主函数
main "$@"