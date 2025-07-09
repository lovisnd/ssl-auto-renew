#!/bin/bash

# SSL证书自动续订方案 - 一键安装脚本
# 适用于Ubuntu系统
# 作者: SSL Auto Renewal System
# 版本: 1.0

set -e

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行，请使用 sudo bash install.sh"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_step "检查系统版本..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测系统版本"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "此脚本仅支持Ubuntu系统"
        exit 1
    fi
    
    log_info "检测到系统: $PRETTY_NAME"
}

# 更新系统包
update_system() {
    log_step "更新系统包..."
    apt update -y
    apt upgrade -y
}

# 安装必要的软件包
install_packages() {
    log_step "安装必要的软件包..."
    
    # 安装基础工具
    apt install -y curl wget git cron mailutils
    
    # 安装snapd（用于安装certbot）
    apt install -y snapd
    systemctl enable snapd
    systemctl start snapd
    
    # 等待snapd完全启动
    sleep 10
    
    # 安装certbot
    log_info "安装Certbot..."
    snap install core; snap refresh core
    snap install --classic certbot
    
    # 创建certbot软链接
    ln -sf /snap/bin/certbot /usr/bin/certbot
    
    log_info "软件包安装完成"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."
    
    local base_dir="/opt/ssl-auto-renewal"
    
    # 创建主目录
    mkdir -p "$base_dir"
    mkdir -p "$base_dir/scripts"
    mkdir -p "$base_dir/config"
    mkdir -p "$base_dir/logs"
    mkdir -p "$base_dir/cron"
    
    # 复制文件到目标目录
    cp -r scripts/* "$base_dir/scripts/" 2>/dev/null || true
    cp -r config/* "$base_dir/config/" 2>/dev/null || true
    cp -r cron/* "$base_dir/cron/" 2>/dev/null || true
    
    # 设置权限
    chmod +x "$base_dir/scripts/"*.sh
    chmod +x "$base_dir/scripts/"*.py
    
    log_info "目录结构创建完成: $base_dir"
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    if command -v ufw >/dev/null 2>&1; then
        # 允许HTTP和HTTPS流量
        ufw allow 80/tcp
        ufw allow 443/tcp
        log_info "防火墙规则已配置"
    else
        log_warn "未检测到ufw防火墙，请手动确保80和443端口开放"
    fi
}

# 检测Web服务器
detect_webserver() {
    log_step "检测Web服务器..."
    
    if systemctl is-active --quiet nginx; then
        echo "nginx" > /opt/ssl-auto-renewal/config/webserver.conf
        log_info "检测到Nginx服务器"
    elif systemctl is-active --quiet apache2; then
        echo "apache2" > /opt/ssl-auto-renewal/config/webserver.conf
        log_info "检测到Apache服务器"
    else
        log_warn "未检测到运行中的Web服务器，请手动配置"
        echo "none" > /opt/ssl-auto-renewal/config/webserver.conf
    fi
}

# 设置定时任务
setup_cron() {
    log_step "设置定时任务..."
    
    # 添加SSL续订定时任务（每天凌晨2点检查）
    local cron_job="0 2 * * * /opt/ssl-auto-renewal/scripts/ssl-renew.sh >> /opt/ssl-auto-renewal/logs/cron.log 2>&1"
    
    # 检查是否已存在相同的定时任务
    if ! crontab -l 2>/dev/null | grep -q "/opt/ssl-auto-renewal/scripts/ssl-renew.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log_info "定时任务已添加"
    else
        log_info "定时任务已存在，跳过添加"
    fi
    
    # 启动cron服务
    systemctl enable cron
    systemctl start cron
}

# 创建示例配置文件
create_sample_configs() {
    log_step "创建示例配置文件..."
    
    # 如果配置文件不存在，则创建示例配置
    if [[ ! -f /opt/ssl-auto-renewal/config/domains.conf ]]; then
        cat > /opt/ssl-auto-renewal/config/domains.conf << 'EOF'
# 域名配置文件
# 格式: domain_name:email:webroot_path
# 示例:
# example.com:admin@example.com:/var/www/html
# www.example.com:admin@example.com:/var/www/html
# api.example.com:admin@example.com:/var/www/api

# 请在下面添加你的域名配置
# your-domain.com:your-email@domain.com:/var/www/html
EOF
        log_info "已创建域名配置示例文件: /opt/ssl-auto-renewal/config/domains.conf"
    fi
    
    if [[ ! -f /opt/ssl-auto-renewal/config/email.conf ]]; then
        cat > /opt/ssl-auto-renewal/config/email.conf << 'EOF'
# 邮件通知配置文件
# 设置邮件通知相关参数

# 是否启用邮件通知 (true/false)
ENABLE_EMAIL_NOTIFICATION=false

# 通知邮箱地址
NOTIFICATION_EMAIL=""

# 邮件主题前缀
EMAIL_SUBJECT_PREFIX="[SSL续订通知]"

# SMTP配置（如果需要使用外部SMTP服务器）
SMTP_SERVER=""
SMTP_PORT=""
SMTP_USERNAME=""
SMTP_PASSWORD=""
EOF
        log_info "已创建邮件配置示例文件: /opt/ssl-auto-renewal/config/email.conf"
    fi
}

# 显示安装完成信息
show_completion_info() {
    log_step "安装完成！"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  SSL证书自动续订系统安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}下一步操作：${NC}"
    echo "1. 编辑域名配置文件："
    echo "   nano /opt/ssl-auto-renewal/config/domains.conf"
    echo ""
    echo "2. 配置邮件通知（可选）："
    echo "   nano /opt/ssl-auto-renewal/config/email.conf"
    echo ""
    echo "3. 域名验证故障排除（如遇到验证失败）："
    echo "   /opt/ssl-auto-renewal/scripts/fix-domain-issue.sh --domain your-domain.com --auto"
    echo ""
    echo "4. 中国大陆未备案域名（使用DNS验证）："
    echo "   /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain your-domain.com --manual --test"
    echo ""
    echo "5. 测试SSL证书申请："
    echo "   /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test"
    echo ""
    echo "6. 手动运行SSL续订："
    echo "   /opt/ssl-auto-renewal/scripts/ssl-renew.sh"
    echo ""
    echo -e "${YELLOW}重要文件位置：${NC}"
    echo "- 配置文件: /opt/ssl-auto-renewal/config/"
    echo "- 脚本文件: /opt/ssl-auto-renewal/scripts/"
    echo "- 日志文件: /opt/ssl-auto-renewal/logs/"
    echo ""
    echo -e "${YELLOW}定时任务：${NC}"
    echo "- 每天凌晨2点自动检查和续订SSL证书"
    echo "- 查看定时任务: crontab -l"
    echo ""
}

# 主函数
main() {
    log_info "开始安装SSL证书自动续订系统..."
    
    check_root
    check_system
    update_system
    install_packages
    create_directories
    configure_firewall
    detect_webserver
    create_sample_configs
    setup_cron
    show_completion_info
    
    log_info "安装脚本执行完成！"
}

# 执行主函数
main "$@"