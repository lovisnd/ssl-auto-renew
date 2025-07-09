#!/bin/bash

# 自动创建DNS验证SSL的Nginx配置脚本
# 专门用于DNS验证获得的SSL证书

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
DNS验证SSL证书的Nginx配置生成脚本

用法: $0 [选项] DOMAIN [WEBROOT]

参数:
    DOMAIN              域名（如：zhangmingrui.top）
    WEBROOT             网站根目录（默认：/var/www/html）

选项:
    -c, --cloudflare    启用Cloudflare代理配置
    -w, --wildcard      通配符证书配置
    -p, --php           启用PHP支持
    -a, --api           创建API子域名配置
    -h, --help          显示此帮助信息

示例:
    $0 zhangmingrui.top
    $0 zhangmingrui.top /var/www/html
    $0 --cloudflare --php zhangmingrui.top
    $0 --wildcard zhangmingrui.top

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

# 检查Nginx是否安装
check_nginx() {
    if ! command -v nginx &> /dev/null; then
        log_error "Nginx未安装"
        log_info "请先安装Nginx: sudo apt install nginx"
        exit 1
    fi
}

# 检查SSL证书是否存在
check_ssl_certificate() {
    local domain="$1"
    
    # 检查acme.sh证书路径（优先）
    local acme_cert_dir=""
    local acme_cert_path=""
    local acme_key_path=""
    
    # 检查ECC证书
    if [[ -d "/home/ubuntu/.acme.sh/${domain}_ecc" ]]; then
        acme_cert_dir="/home/ubuntu/.acme.sh/${domain}_ecc"
        acme_cert_path="$acme_cert_dir/fullchain.cer"
        acme_key_path="$acme_cert_dir/$domain.key"
    # 检查RSA证书
    elif [[ -d "/home/ubuntu/.acme.sh/$domain" ]]; then
        acme_cert_dir="/home/ubuntu/.acme.sh/$domain"
        acme_cert_path="$acme_cert_dir/fullchain.cer"
        acme_key_path="$acme_cert_dir/$domain.key"
    fi
    
    # 检查Let's Encrypt标准路径
    local letsencrypt_cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    local letsencrypt_key_path="/etc/letsencrypt/live/$domain/privkey.pem"
    
    if [[ -f "$acme_cert_path" ]] && [[ -f "$acme_key_path" ]]; then
        log_success "找到acme.sh SSL证书: $acme_cert_dir"
        export CERT_PATH="$acme_cert_path"
        export KEY_PATH="$acme_key_path"
        export CERT_TYPE="acme.sh"
        return 0
    elif [[ -f "$letsencrypt_cert_path" ]] && [[ -f "$letsencrypt_key_path" ]]; then
        log_success "找到Let's Encrypt SSL证书: /etc/letsencrypt/live/$domain/"
        export CERT_PATH="$letsencrypt_cert_path"
        export KEY_PATH="$letsencrypt_key_path"
        export CERT_TYPE="letsencrypt"
        return 0
    else
        log_warning "SSL证书不存在: $domain"
        log_info "请先申请SSL证书:"
        log_info "/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain $domain --provider cloudflare"
        return 1
    fi
}

# 创建基础SSL配置
create_basic_ssl_config() {
    local domain="$1"
    local webroot="$2"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log_info "创建基础SSL配置: $domain"
    
    cat > "$config_file" << EOF
# HTTP重定向到HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    # 直接重定向到HTTPS
    return 301 https://\$server_name\$request_uri;
}

# HTTPS主配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain www.$domain;
    
    # SSL证书配置
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # 网站根目录
    root $webroot;
    index index.html index.htm index.php;
    
    # 基本location配置
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # 安全头配置
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 隐藏Nginx版本
    server_tokens off;
    
    # 日志配置
    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;
}
EOF
    
    log_success "基础SSL配置创建完成"
}

# 添加Cloudflare配置
add_cloudflare_config() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log_info "添加Cloudflare代理配置"
    
    # 在HTTPS server块中添加Cloudflare IP配置
    sed -i '/server_name.*www\./a\
    \
    # Cloudflare真实IP配置\
    set_real_ip_from 103.21.244.0/22;\
    set_real_ip_from 103.22.200.0/22;\
    set_real_ip_from 103.31.4.0/22;\
    set_real_ip_from 104.16.0.0/13;\
    set_real_ip_from 104.24.0.0/14;\
    set_real_ip_from 108.162.192.0/18;\
    set_real_ip_from 131.0.72.0/22;\
    set_real_ip_from 141.101.64.0/18;\
    set_real_ip_from 162.158.0.0/15;\
    set_real_ip_from 172.64.0.0/13;\
    set_real_ip_from 173.245.48.0/20;\
    set_real_ip_from 188.114.96.0/20;\
    set_real_ip_from 190.93.240.0/20;\
    set_real_ip_from 197.234.240.0/22;\
    set_real_ip_from 198.41.128.0/17;\
    real_ip_header CF-Connecting-IP;' "$config_file"
    
    log_success "Cloudflare配置添加完成"
}

# 添加PHP支持
add_php_support() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log_info "添加PHP支持配置"
    
    # 检查PHP-FPM是否安装
    local php_version=""
    for version in 8.3 8.2 8.1 8.0 7.4; do
        if [[ -S "/var/run/php/php$version-fpm.sock" ]]; then
            php_version="$version"
            break
        fi
    done
    
    if [[ -z "$php_version" ]]; then
        log_warning "未找到PHP-FPM，请先安装PHP"
        return 1
    fi
    
    # 在location /之前添加PHP配置
    sed -i '/location \/ {/i\
    # PHP支持\
    location ~ \.php$ {\
        include snippets/fastcgi-php.conf;\
        fastcgi_pass unix:/var/run/php/php'$php_version'-fpm.sock;\
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\
        include fastcgi_params;\
    }\
    \
    # 阻止访问隐藏文件\
    location ~ /\. {\
        deny all;\
    }\
    ' "$config_file"
    
    log_success "PHP支持配置添加完成 (PHP $php_version)"
}

# 创建通配符证书配置
create_wildcard_config() {
    local domain="$1"
    local webroot="$2"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log_info "创建通配符证书配置: *.$domain"
    
    cat > "$config_file" << EOF
# HTTP重定向到HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain *.$domain;
    return 301 https://\$server_name\$request_uri;
}

# 主域名HTTPS配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # SSL证书配置（通配符证书）
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    
    root $webroot;
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;
}

# www子域名重定向到主域名
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name www.$domain;
    
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    
    return 301 https://$domain\$request_uri;
}
EOF
    
    log_success "通配符证书配置创建完成"
}

# 创建API子域名配置
create_api_config() {
    local domain="$1"
    local api_config_file="/etc/nginx/sites-available/api.$domain"
    
    log_info "创建API子域名配置: api.$domain"
    
    cat > "$api_config_file" << EOF
# API子域名HTTPS配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.$domain;
    
    # SSL证书配置
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # API根目录
    root /var/www/api;
    index index.php index.html;
    
    # API路由配置
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP API支持
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # CORS配置（如果需要）
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization" always;
    
    # 安全头
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    
    access_log /var/log/nginx/api.$domain.access.log;
    error_log /var/log/nginx/api.$domain.error.log;
}

# API HTTP重定向
server {
    listen 80;
    server_name api.$domain;
    return 301 https://\$server_name\$request_uri;
}
EOF
    
    # 创建API目录
    mkdir -p /var/www/api
    chown -R www-data:www-data /var/www/api
    
    # 启用API配置
    ln -sf "$api_config_file" "/etc/nginx/sites-enabled/"
    
    log_success "API子域名配置创建完成"
}

# 启用站点配置
enable_site() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    local enabled_file="/etc/nginx/sites-enabled/$domain"
    
    log_info "启用站点配置: $domain"
    
    # 创建软链接
    ln -sf "$config_file" "$enabled_file"
    
    # 测试Nginx配置
    if nginx -t; then
        systemctl reload nginx
        log_success "Nginx配置启用成功: $domain"
        return 0
    else
        log_error "Nginx配置测试失败"
        rm -f "$enabled_file"
        return 1
    fi
}

# 创建测试页面
create_test_page() {
    local domain="$1"
    local webroot="$2"
    
    log_info "创建测试页面"
    
    # 确保目录存在
    mkdir -p "$webroot"
    
    # 创建测试页面
    cat > "$webroot/index.html" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $domain</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; }
        .ssl-info { background: #e8f5e8; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .status { color: #28a745; font-weight: bold; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .info-box { background: #f8f9fa; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎉 Welcome to $domain</h1>
            <p class="status">✅ HTTPS SSL Certificate Active</p>
        </div>
        
        <div class="ssl-info">
            <h3>🔒 SSL Certificate Information</h3>
            <p><strong>Domain:</strong> $domain</p>
            <p><strong>Certificate Type:</strong> Let's Encrypt (DNS Validation)</p>
            <p><strong>Encryption:</strong> TLS 1.2/1.3</p>
            <p><strong>Status:</strong> <span class="status">Active & Secure</span></p>
        </div>
        
        <div class="info-grid">
            <div class="info-box">
                <h4>🚀 Features</h4>
                <ul>
                    <li>DNS Validation SSL</li>
                    <li>Auto-renewal enabled</li>
                    <li>HTTP to HTTPS redirect</li>
                    <li>Security headers</li>
                    <li>OCSP Stapling</li>
                </ul>
            </div>
            <div class="info-box">
                <h4>📊 Server Info</h4>
                <p><strong>Server:</strong> Nginx</p>
                <p><strong>Time:</strong> <span id="time"></span></p>
                <p><strong>Protocol:</strong> <span id="protocol"></span></p>
            </div>
        </div>
        
        <div style="text-align: center; margin-top: 30px; color: #666;">
            <p>Your website is now secured with SSL certificate!</p>
            <p><small>Generated by SSL Auto-Renewal System</small></p>
        </div>
    </div>
    
    <script>
        document.getElementById('time').textContent = new Date().toLocaleString();
        document.getElementById('protocol').textContent = location.protocol.toUpperCase();
    </script>
</body>
</html>
EOF
    
    # 设置权限
    chown -R www-data:www-data "$webroot"
    chmod -R 755 "$webroot"
    
    log_success "测试页面创建完成: $webroot/index.html"
}

# 显示配置完成信息
show_completion_info() {
    local domain="$1"
    
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Nginx SSL配置完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${YELLOW}域名：${NC} $domain"
    echo -e "${YELLOW}配置文件：${NC} /etc/nginx/sites-available/$domain"
    echo -e "${YELLOW}SSL证书：${NC} $(dirname "$CERT_PATH")"
    echo -e "${YELLOW}证书类型：${NC} $CERT_TYPE"
    echo
    echo -e "${YELLOW}测试访问：${NC}"
    echo "HTTP:  http://$domain/ (自动跳转HTTPS)"
    echo "HTTPS: https://$domain/"
    echo "HTTPS: https://www.$domain/"
    echo
    echo -e "${YELLOW}SSL测试：${NC}"
    echo "curl -I https://$domain/"
    echo "openssl s_client -connect $domain:443 -servername $domain"
    echo
    echo -e "${YELLOW}在线SSL评级：${NC}"
    echo "https://www.ssllabs.com/ssltest/analyze.html?d=$domain"
    echo
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    local domain=""
    local webroot="/var/www/html"
    local cloudflare=false
    local wildcard=false
    local php=false
    local api=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cloudflare)
                cloudflare=true
                shift
                ;;
            -w|--wildcard)
                wildcard=true
                shift
                ;;
            -p|--php)
                php=true
                shift
                ;;
            -a|--api)
                api=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                else
                    webroot="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 检查必需参数
    if [[ -z "$domain" ]]; then
        log_error "请指定域名"
        show_help
        exit 1
    fi
    
    # 检查权限和依赖
    check_root
    check_nginx
    
    # 检查SSL证书
    if ! check_ssl_certificate "$domain"; then
        log_error "请先申请SSL证书后再运行此脚本"
        exit 1
    fi
    
    log_info "开始创建Nginx SSL配置..."
    log_info "域名: $domain"
    log_info "网站根目录: $webroot"
    
    # 创建网站目录
    mkdir -p "$webroot"
    
    # 根据选项创建配置
    if [[ "$wildcard" == "true" ]]; then
        create_wildcard_config "$domain" "$webroot"
    else
        create_basic_ssl_config "$domain" "$webroot"
    fi
    
    # 添加可选配置
    if [[ "$cloudflare" == "true" ]]; then
        add_cloudflare_config "$domain"
    fi
    
    if [[ "$php" == "true" ]]; then
        add_php_support "$domain"
    fi
    
    if [[ "$api" == "true" ]]; then
        create_api_config "$domain"
    fi
    
    # 启用站点
    if enable_site "$domain"; then
        # 创建测试页面
        create_test_page "$domain" "$webroot"
        
        # 显示完成信息
        show_completion_info "$domain"
    else
        log_error "配置启用失败"
        exit 1
    fi
}

# 运行主函数
main "$@"