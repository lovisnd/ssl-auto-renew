#!/bin/bash

# SMTP配置测试脚本
# 用于测试腾讯企业邮箱等外部SMTP服务器配置

set -e

# 配置路径
BASE_DIR="/opt/ssl-auto-renewal"
CONFIG_DIR="$BASE_DIR/config"
EMAIL_CONFIG="$CONFIG_DIR/email.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo "SMTP配置测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --config              显示当前SMTP配置"
    echo "  --test [EMAIL]        测试SMTP发送功能"
    echo "  --setup-tencent       设置腾讯企业邮箱配置向导"
    echo "  --help, -h            显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --config                    # 显示当前配置"
    echo "  $0 --test admin@example.com    # 测试发送邮件"
    echo "  $0 --setup-tencent             # 腾讯企业邮箱配置向导"
    echo ""
}

# 显示当前SMTP配置
show_config() {
    log_info "当前SMTP配置:"
    echo "================================"
    
    if [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
        
        echo "邮件通知启用: ${ENABLE_EMAIL_NOTIFICATION:-未设置}"
        echo "通知邮箱: ${NOTIFICATION_EMAIL:-未设置}"
        echo "使用外部SMTP: ${USE_EXTERNAL_SMTP:-未设置}"
        
        if [[ "$USE_EXTERNAL_SMTP" == "true" ]]; then
            echo "SMTP服务器: ${SMTP_SERVER:-未设置}"
            echo "SMTP端口: ${SMTP_PORT:-未设置}"
            echo "SMTP用户名: ${SMTP_USERNAME:-未设置}"
            echo "SMTP密码: ${SMTP_PASSWORD:+已设置}"
            echo "使用TLS: ${SMTP_USE_TLS:-未设置}"
            echo "使用SSL: ${SMTP_USE_SSL:-未设置}"
            echo "发件人邮箱: ${SMTP_FROM_EMAIL:-未设置}"
            echo "发件人名称: ${SMTP_FROM_NAME:-未设置}"
        fi
    else
        log_error "配置文件不存在: $EMAIL_CONFIG"
        return 1
    fi
    
    echo "================================"
}

# 腾讯企业邮箱配置向导
setup_tencent() {
    log_info "腾讯企业邮箱配置向导"
    echo "================================"
    
    # 读取用户输入
    read -p "请输入您的企业邮箱地址: " email
    read -p "请输入您的邮箱密码: " -s password
    echo
    read -p "请输入通知接收邮箱 (默认使用发件邮箱): " notification_email
    
    if [[ -z "$notification_email" ]]; then
        notification_email="$email"
    fi
    
    # 备份原配置
    if [[ -f "$EMAIL_CONFIG" ]]; then
        cp "$EMAIL_CONFIG" "$EMAIL_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "已备份原配置文件"
    fi
    
    # 更新配置文件
    log_info "更新配置文件..."
    
    # 使用sed更新配置
    sed -i "s/^ENABLE_EMAIL_NOTIFICATION=.*/ENABLE_EMAIL_NOTIFICATION=true/" "$EMAIL_CONFIG"
    sed -i "s/^NOTIFICATION_EMAIL=.*/NOTIFICATION_EMAIL=\"$notification_email\"/" "$EMAIL_CONFIG"
    sed -i "s/^USE_EXTERNAL_SMTP=.*/USE_EXTERNAL_SMTP=true/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_SERVER=.*/SMTP_SERVER=\"smtp.exmail.qq.com\"/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_PORT=.*/SMTP_PORT=\"465\"/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_USERNAME=.*/SMTP_USERNAME=\"$email\"/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_PASSWORD=.*/SMTP_PASSWORD=\"$password\"/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_USE_TLS=.*/SMTP_USE_TLS=false/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_USE_SSL=.*/SMTP_USE_SSL=true/" "$EMAIL_CONFIG"
    sed -i "s/^SMTP_FROM_EMAIL=.*/SMTP_FROM_EMAIL=\"$email\"/" "$EMAIL_CONFIG"
    
    log_success "腾讯企业邮箱配置完成!"
    echo ""
    log_info "现在可以使用以下命令测试邮件发送:"
    echo "  $0 --test"
    echo "  $BASE_DIR/scripts/notify.sh --test"
}

# 测试SMTP发送
test_smtp() {
    local test_email="$1"
    
    log_info "测试SMTP邮件发送功能..."
    
    if [[ -z "$test_email" ]]; then
        if [[ -f "$EMAIL_CONFIG" ]]; then
            source "$EMAIL_CONFIG"
            test_email="$NOTIFICATION_EMAIL"
        fi
        
        if [[ -z "$test_email" ]]; then
            log_error "请指定测试邮箱地址"
            return 1
        fi
    fi
    
    log_info "发送测试邮件到: $test_email"
    
    # 首先测试SMTP连接
    log_info "测试SMTP连接..."
    if python3 "$BASE_DIR/scripts/smtp-send.py" --config "$EMAIL_CONFIG" --test --to "$test_email" --subject "连接测试"; then
        log_success "SMTP连接测试成功"
    else
        log_error "SMTP连接测试失败"
        return 1
    fi
    
    # 调用notify.sh脚本进行完整测试
    log_info "发送完整测试邮件..."
    if "$BASE_DIR/scripts/notify.sh" --test "$test_email"; then
        log_success "SMTP测试成功!"
    else
        log_error "SMTP测试失败，请检查配置"
        return 1
    fi
}

# 主函数
main() {
    local action=""
    local test_email=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                action="config"
                shift
                ;;
            --test)
                action="test"
                test_email="$2"
                [[ "$2" =~ ^[^-] ]] && shift
                shift
                ;;
            --setup-tencent)
                action="setup-tencent"
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
    
    # 检查配置文件
    if [[ ! -f "$EMAIL_CONFIG" ]] && [[ "$action" != "setup-tencent" ]]; then
        log_error "配置文件不存在: $EMAIL_CONFIG"
        log_info "请先运行安装脚本或使用 --setup-tencent 配置邮箱"
        exit 1
    fi
    
    # 执行相应操作
    case "$action" in
        "config")
            show_config
            ;;
        "test")
            test_smtp "$test_email"
            ;;
        "setup-tencent")
            setup_tencent
            ;;
        *)
            log_error "未知操作: $action"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"