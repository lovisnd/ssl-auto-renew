#!/bin/bash

# SSL证书域名问题快速修复脚本
# 专门针对DNSPod拦截和域名验证失败问题

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
SSL证书域名问题快速修复脚本

用法: $0 [选项]

选项:
    -d, --domain DOMAIN     指定要修复的域名
    -a, --auto             自动修复模式（推荐）
    -c, --check-only       仅检查问题，不执行修复
    -f, --force            强制执行所有修复步骤
    -h, --help             显示此帮助信息

示例:
    $0 --domain zhangmingrui.top --auto
    $0 --check-only
    $0 --force

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

# 检查必要的命令
check_dependencies() {
    local deps=("curl" "dig" "nginx" "certbot")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必要的命令: ${missing[*]}"
        log_info "请先安装缺少的软件包"
        exit 1
    fi
}

# 获取服务器公网IP
get_server_ip() {
    local ip
    ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    echo "$ip"
}

# 检查域名DNS解析
check_dns_resolution() {
    local domain="$1"
    local server_ip="$2"
    
    log_info "检查域名 $domain 的DNS解析..."
    
    # 获取域名解析的IP
    local resolved_ip
    resolved_ip=$(dig +short "$domain" 2>/dev/null | tail -n1)
    
    if [[ -z "$resolved_ip" ]]; then
        log_error "域名 $domain 无法解析"
        return 1
    fi
    
    log_info "域名解析IP: $resolved_ip"
    log_info "服务器IP: $server_ip"
    
    if [[ "$resolved_ip" == "$server_ip" ]]; then
        log_success "DNS解析正确"
        return 0
    else
        log_error "DNS解析错误：域名指向 $resolved_ip，但服务器IP是 $server_ip"
        return 1
    fi
}

# 检查HTTP访问
check_http_access() {
    local domain="$1"
    
    log_info "检查域名 $domain 的HTTP访问..."
    
    # 检查HTTP访问
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$domain/" 2>/dev/null || echo "000")
    
    log_info "HTTP状态码: $http_status"
    
    # 检查是否被重定向到拦截页面
    local response_url
    response_url=$(curl -s -L -w "%{url_effective}" -o /dev/null "http://$domain/" 2>/dev/null || echo "")
    
    if [[ "$response_url" == *"dnspod.qcloud.com"* ]] || [[ "$response_url" == *"webblock"* ]]; then
        log_error "域名被DNSPod拦截，重定向到: $response_url"
        return 1
    fi
    
    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "404" ]]; then
        log_success "HTTP访问正常"
        return 0
    else
        log_warning "HTTP访问异常，状态码: $http_status"
        return 1
    fi
}

# 检查Nginx配置
check_nginx_config() {
    local domain="$1"
    
    log_info "检查Nginx配置..."
    
    # 检查Nginx是否运行
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx服务未运行"
        return 1
    fi
    
    # 检查域名配置文件
    local config_files=(
        "/etc/nginx/sites-available/$domain"
        "/etc/nginx/sites-enabled/$domain"
        "/etc/nginx/conf.d/$domain.conf"
    )
    
    local found_config=false
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            log_success "找到配置文件: $config_file"
            found_config=true
            break
        fi
    done
    
    if [[ "$found_config" == false ]]; then
        log_warning "未找到域名 $domain 的Nginx配置文件"
        return 1
    fi
    
    # 测试Nginx配置
    if nginx -t &>/dev/null; then
        log_success "Nginx配置语法正确"
        return 0
    else
        log_error "Nginx配置语法错误"
        nginx -t
        return 1
    fi
}

# 检查webroot目录
check_webroot() {
    local webroot="$1"
    
    log_info "检查webroot目录: $webroot"
    
    if [[ ! -d "$webroot" ]]; then
        log_error "webroot目录不存在: $webroot"
        return 1
    fi
    
    # 检查权限
    if [[ ! -w "$webroot" ]]; then
        log_error "webroot目录不可写: $webroot"
        return 1
    fi
    
    # 检查.well-known目录
    local wellknown_dir="$webroot/.well-known/acme-challenge"
    if [[ ! -d "$wellknown_dir" ]]; then
        log_warning ".well-known目录不存在，将创建"
        mkdir -p "$wellknown_dir"
        chown -R www-data:www-data "$wellknown_dir"
        chmod -R 755 "$wellknown_dir"
    fi
    
    log_success "webroot目录检查通过"
    return 0
}

# 创建基本的Nginx配置
create_nginx_config() {
    local domain="$1"
    local webroot="$2"
    
    log_info "为域名 $domain 创建Nginx配置..."
    
    local config_file="/etc/nginx/sites-available/$domain"
    
    cat > "$config_file" << EOF
server {
    listen 80;
    server_name $domain www.$domain;
    
    root $webroot;
    index index.html index.htm;
    
    # Let's Encrypt验证路径
    location /.well-known/acme-challenge/ {
        root $webroot;
        try_files \$uri =404;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    
    # 启用站点
    ln -sf "$config_file" "/etc/nginx/sites-enabled/$domain"
    
    # 测试配置
    if nginx -t; then
        systemctl reload nginx
        log_success "Nginx配置创建并重载成功"
        return 0
    else
        log_error "Nginx配置创建失败"
        return 1
    fi
}

# 创建测试页面
create_test_page() {
    local webroot="$1"
    local domain="$2"
    
    log_info "创建测试页面..."
    
    mkdir -p "$webroot"
    
    cat > "$webroot/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $domain</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>Welcome to $domain</h1>
    <p>This is a test page for SSL certificate verification.</p>
    <p>Server IP: $(get_server_ip)</p>
    <p>Time: $(date)</p>
</body>
</html>
EOF
    
    # 设置权限
    chown -R www-data:www-data "$webroot"
    chmod -R 755 "$webroot"
    
    log_success "测试页面创建成功"
}

# 测试Let's Encrypt验证路径
test_acme_challenge() {
    local domain="$1"
    local webroot="$2"
    
    log_info "测试Let's Encrypt验证路径..."
    
    local challenge_dir="$webroot/.well-known/acme-challenge"
    local test_file="$challenge_dir/test-$(date +%s)"
    local test_content="test-content-$(date +%s)"
    
    # 创建测试文件
    mkdir -p "$challenge_dir"
    echo "$test_content" > "$test_file"
    chown www-data:www-data "$test_file"
    chmod 644 "$test_file"
    
    # 测试访问
    local test_url="http://$domain/.well-known/acme-challenge/$(basename "$test_file")"
    local response
    response=$(curl -s "$test_url" 2>/dev/null || echo "")
    
    # 清理测试文件
    rm -f "$test_file"
    
    if [[ "$response" == "$test_content" ]]; then
        log_success "Let's Encrypt验证路径测试通过"
        return 0
    else
        log_error "Let's Encrypt验证路径测试失败"
        log_error "期望内容: $test_content"
        log_error "实际响应: $response"
        return 1
    fi
}

# 修复防火墙设置
fix_firewall() {
    log_info "检查和修复防火墙设置..."
    
    # 检查ufw
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        log_success "UFW防火墙规则已更新"
    fi
    
    # 检查iptables
    if command -v iptables &> /dev/null; then
        iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        log_success "iptables防火墙规则已更新"
    fi
}

# 主要的修复函数
fix_domain_issues() {
    local domain="$1"
    local auto_mode="$2"
    local check_only="$3"
    local force_mode="$4"
    
    log_info "开始修复域名 $domain 的问题..."
    
    # 获取服务器IP
    local server_ip
    server_ip=$(get_server_ip)
    log_info "服务器公网IP: $server_ip"
    
    # 从domains.conf获取webroot
    local webroot="/var/www/html"
    if [[ -f "/opt/ssl-auto-renewal/config/domains.conf" ]]; then
        local domain_config
        domain_config=$(grep "^$domain:" "/opt/ssl-auto-renewal/config/domains.conf" 2>/dev/null || echo "")
        if [[ -n "$domain_config" ]]; then
            webroot=$(echo "$domain_config" | cut -d':' -f2)
        fi
    fi
    
    log_info "使用webroot目录: $webroot"
    
    # 检查步骤
    local dns_ok=false
    local http_ok=false
    local nginx_ok=false
    local webroot_ok=false
    local acme_ok=false
    
    # DNS检查
    if check_dns_resolution "$domain" "$server_ip"; then
        dns_ok=true
    fi
    
    # HTTP访问检查
    if check_http_access "$domain"; then
        http_ok=true
    fi
    
    # Nginx配置检查
    if check_nginx_config "$domain"; then
        nginx_ok=true
    fi
    
    # webroot检查
    if check_webroot "$webroot"; then
        webroot_ok=true
    fi
    
    # ACME challenge测试
    if test_acme_challenge "$domain" "$webroot"; then
        acme_ok=true
    fi
    
    # 如果只是检查模式，显示结果并退出
    if [[ "$check_only" == true ]]; then
        echo
        log_info "检查结果摘要:"
        echo "DNS解析: $([ "$dns_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
        echo "HTTP访问: $([ "$http_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
        echo "Nginx配置: $([ "$nginx_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
        echo "Webroot目录: $([ "$webroot_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
        echo "ACME验证: $([ "$acme_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
        return 0
    fi
    
    # 修复步骤
    local need_fixes=false
    
    if [[ "$dns_ok" == false ]]; then
        log_error "DNS解析问题需要手动修复："
        log_info "1. 登录您的DNS服务商控制台"
        log_info "2. 将域名 $domain 的A记录指向 $server_ip"
        log_info "3. 如果域名被拦截，请联系DNS服务商解除拦截"
        need_fixes=true
    fi
    
    if [[ "$nginx_ok" == false ]] && ([[ "$auto_mode" == true ]] || [[ "$force_mode" == true ]]); then
        log_info "修复Nginx配置..."
        create_nginx_config "$domain" "$webroot"
        nginx_ok=true
    fi
    
    if [[ "$webroot_ok" == false ]] && ([[ "$auto_mode" == true ]] || [[ "$force_mode" == true ]]); then
        log_info "修复webroot目录..."
        check_webroot "$webroot"
        create_test_page "$webroot" "$domain"
        webroot_ok=true
    fi
    
    if [[ "$auto_mode" == true ]] || [[ "$force_mode" == true ]]; then
        fix_firewall
    fi
    
    # 重新测试ACME challenge
    if [[ "$nginx_ok" == true ]] && [[ "$webroot_ok" == true ]]; then
        if test_acme_challenge "$domain" "$webroot"; then
            acme_ok=true
        fi
    fi
    
    # 最终结果
    echo
    log_info "修复结果摘要:"
    echo "DNS解析: $([ "$dns_ok" == true ] && echo "✓ 正常" || echo "✗ 需要手动修复")"
    echo "HTTP访问: $([ "$http_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
    echo "Nginx配置: $([ "$nginx_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
    echo "Webroot目录: $([ "$webroot_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
    echo "ACME验证: $([ "$acme_ok" == true ] && echo "✓ 正常" || echo "✗ 异常")"
    
    if [[ "$dns_ok" == true ]] && [[ "$acme_ok" == true ]]; then
        log_success "域名 $domain 已准备好申请SSL证书！"
        log_info "现在可以运行: sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test"
        return 0
    else
        log_warning "仍有问题需要解决，请查看上面的详细信息"
        if [[ "$dns_ok" == false ]]; then
            log_info "DNS问题解决指南: /opt/ssl-auto-renewal/DOMAIN_TROUBLESHOOTING.md"
        fi
        return 1
    fi
}

# 主函数
main() {
    local domain=""
    local auto_mode=false
    local check_only=false
    local force_mode=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                domain="$2"
                shift 2
                ;;
            -a|--auto)
                auto_mode=true
                shift
                ;;
            -c|--check-only)
                check_only=true
                shift
                ;;
            -f|--force)
                force_mode=true
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
    check_dependencies
    
    # 如果没有指定域名，尝试从配置文件获取
    if [[ -z "$domain" ]]; then
        if [[ -f "/opt/ssl-auto-renewal/config/domains.conf" ]]; then
            log_info "未指定域名，从配置文件获取第一个域名..."
            domain=$(head -n1 "/opt/ssl-auto-renewal/config/domains.conf" | cut -d':' -f1)
            if [[ -n "$domain" ]]; then
                log_info "使用域名: $domain"
            else
                log_error "配置文件中没有找到域名"
                exit 1
            fi
        else
            log_error "请指定域名或确保配置文件存在"
            show_help
            exit 1
        fi
    fi
    
    # 执行修复
    fix_domain_issues "$domain" "$auto_mode" "$check_only" "$force_mode"
}

# 运行主函数
main "$@"