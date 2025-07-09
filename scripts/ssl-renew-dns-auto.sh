#!/bin/bash

# SSL证书DNS API自动验证续订脚本
# 支持多种DNS服务商的API自动验证
# 实现完全自动化的SSL证书申请和续订

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
LOG_FILE="$LOG_DIR/ssl-renew-dns-auto.log"
ERROR_LOG="$LOG_DIR/ssl-error.log"

# DNS API配置文件
DNS_CONFIG_FILE="$CONFIG_DIR/dns-api.conf"

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
SSL证书DNS API自动验证续订脚本

用法: $0 [选项]

选项:
    -d, --domain DOMAIN     指定单个域名进行DNS API验证
    -t, --test             测试模式（dry-run）
    -f, --force            强制续订所有证书
    -p, --provider PROVIDER DNS服务商 (dnspod, aliyun, cloudflare, tencent)
    -s, --setup            设置DNS API配置
    -c, --check-config     检查DNS API配置
    -h, --help             显示此帮助信息

支持的DNS服务商:
    - dnspod      DNSPod (腾讯云DNS)
    - aliyun      阿里云DNS
    - cloudflare  Cloudflare
    - tencent     腾讯云DNS
    - huawei      华为云DNS

示例:
    $0 --setup --provider dnspod
    $0 --domain zhangmingrui.top --provider dnspod
    $0 --test --domain zhangmingrui.top

EOF
}

# 检查运行权限
check_permissions() {
    # acme.sh建议不要使用sudo运行，但我们需要root权限来安装证书
    if [[ $EUID -eq 0 ]]; then
        log_warning "检测到以root权限运行"
        log_info "acme.sh建议以普通用户运行，但证书安装需要root权限"
        log_info "继续执行..."
    fi
}

# 检查acme.sh是否安装
check_acme_sh() {
    if ! command -v acme.sh &> /dev/null && [[ ! -f ~/.acme.sh/acme.sh ]]; then
        log_info "acme.sh未安装，正在安装..."
        install_acme_sh
    else
        log_info "acme.sh已安装"
        # 确保acme.sh可用
        if [[ -f ~/.acme.sh/acme.sh ]] && ! command -v acme.sh &> /dev/null; then
            ln -sf ~/.acme.sh/acme.sh /usr/local/bin/acme.sh
        fi
    fi
}

# 安装acme.sh
install_acme_sh() {
    log_info "下载并安装acme.sh..."
    
    # 下载安装脚本
    curl -s https://get.acme.sh | sh -s email=admin@$(hostname -d 2>/dev/null || echo "localhost")
    
    # 重新加载环境变量
    source ~/.bashrc 2>/dev/null || true
    
    # 创建软链接
    if [[ -f ~/.acme.sh/acme.sh ]]; then
        ln -sf ~/.acme.sh/acme.sh /usr/local/bin/acme.sh
        log_success "acme.sh安装成功"
    else
        log_error "acme.sh安装失败"
        exit 1
    fi
}

# 创建DNS API配置文件
create_dns_config() {
    if [[ ! -f "$DNS_CONFIG_FILE" ]]; then
        cat > "$DNS_CONFIG_FILE" << 'EOF'
# DNS API配置文件
# 请根据您的DNS服务商配置相应的API密钥

# DNS服务商类型 (dnspod, aliyun, cloudflare, tencent, huawei)
DNS_PROVIDER=""

# DNSPod配置 (腾讯云DNS)
DNSPOD_ID=""
DNSPOD_KEY=""

# 阿里云DNS配置
ALIYUN_ACCESS_KEY_ID=""
ALIYUN_ACCESS_KEY_SECRET=""

# Cloudflare配置
CLOUDFLARE_EMAIL=""
CLOUDFLARE_API_KEY=""

# 腾讯云DNS配置
TENCENT_SECRET_ID=""
TENCENT_SECRET_KEY=""

# 华为云DNS配置
HUAWEI_ACCESS_KEY_ID=""
HUAWEI_SECRET_ACCESS_KEY=""

# 默认邮箱
DEFAULT_EMAIL="admin@localhost"
EOF
        log_info "已创建DNS API配置文件: $DNS_CONFIG_FILE"
        log_info "请编辑此文件配置您的DNS API密钥"
    fi
}

# 设置DNS API配置
setup_dns_config() {
    local provider="$1"
    
    create_dns_config
    
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  DNS API配置向导${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    case "$provider" in
        "dnspod")
            setup_dnspod_config
            ;;
        "aliyun")
            setup_aliyun_config
            ;;
        "cloudflare")
            setup_cloudflare_config
            ;;
        "tencent")
            setup_tencent_config
            ;;
        "huawei")
            setup_huawei_config
            ;;
        *)
            log_error "不支持的DNS服务商: $provider"
            log_info "支持的服务商: dnspod, aliyun, cloudflare, tencent, huawei"
            exit 1
            ;;
    esac
    
    # 更新配置文件中的DNS_PROVIDER
    sed -i "s/^DNS_PROVIDER=.*/DNS_PROVIDER=\"$provider\"/" "$DNS_CONFIG_FILE"
    
    log_success "DNS API配置完成"
    echo
    echo -e "${YELLOW}下一步：${NC}"
    echo "测试配置: $0 --check-config"
    echo "申请证书: $0 --domain your-domain.com --test"
}

# 设置DNSPod配置
setup_dnspod_config() {
    echo -e "${YELLOW}DNSPod API配置${NC}"
    echo
    echo "请访问 https://console.dnspod.cn/account/token 获取API密钥"
    echo
    
    read -p "请输入DNSPod ID: " dnspod_id
    read -p "请输入DNSPod Key: " dnspod_key
    read -p "请输入默认邮箱: " default_email
    
    # 更新配置文件
    sed -i "s/^DNSPOD_ID=.*/DNSPOD_ID=\"$dnspod_id\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^DNSPOD_KEY=.*/DNSPOD_KEY=\"$dnspod_key\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^DEFAULT_EMAIL=.*/DEFAULT_EMAIL=\"$default_email\"/" "$DNS_CONFIG_FILE"
    
    log_success "DNSPod配置已保存"
}

# 设置阿里云配置
setup_aliyun_config() {
    echo -e "${YELLOW}阿里云DNS API配置${NC}"
    echo
    echo "请访问 https://ram.console.aliyun.com/manage/ak 获取API密钥"
    echo
    
    read -p "请输入Access Key ID: " access_key_id
    read -p "请输入Access Key Secret: " access_key_secret
    read -p "请输入默认邮箱: " default_email
    
    # 更新配置文件
    sed -i "s/^ALIYUN_ACCESS_KEY_ID=.*/ALIYUN_ACCESS_KEY_ID=\"$access_key_id\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^ALIYUN_ACCESS_KEY_SECRET=.*/ALIYUN_ACCESS_KEY_SECRET=\"$access_key_secret\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^DEFAULT_EMAIL=.*/DEFAULT_EMAIL=\"$default_email\"/" "$DNS_CONFIG_FILE"
    
    log_success "阿里云DNS配置已保存"
}

# 设置Cloudflare配置
setup_cloudflare_config() {
    echo -e "${YELLOW}Cloudflare API配置${NC}"
    echo
    echo "请访问 https://dash.cloudflare.com/profile/api-tokens 获取API密钥"
    echo
    
    read -p "请输入Cloudflare邮箱: " cf_email
    read -p "请输入Cloudflare API Key: " cf_api_key
    read -p "请输入默认邮箱: " default_email
    
    # 更新配置文件
    sed -i "s/^CLOUDFLARE_EMAIL=.*/CLOUDFLARE_EMAIL=\"$cf_email\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^CLOUDFLARE_API_KEY=.*/CLOUDFLARE_API_KEY=\"$cf_api_key\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^DEFAULT_EMAIL=.*/DEFAULT_EMAIL=\"$default_email\"/" "$DNS_CONFIG_FILE"
    
    log_success "Cloudflare配置已保存"
}

# 设置腾讯云配置
setup_tencent_config() {
    echo -e "${YELLOW}腾讯云DNS API配置${NC}"
    echo
    echo "请访问 https://console.cloud.tencent.com/cam/capi 获取API密钥"
    echo
    
    read -p "请输入SecretId: " secret_id
    read -p "请输入SecretKey: " secret_key
    read -p "请输入默认邮箱: " default_email
    
    # 更新配置文件
    sed -i "s/^TENCENT_SECRET_ID=.*/TENCENT_SECRET_ID=\"$secret_id\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^TENCENT_SECRET_KEY=.*/TENCENT_SECRET_KEY=\"$secret_key\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^DEFAULT_EMAIL=.*/DEFAULT_EMAIL=\"$default_email\"/" "$DNS_CONFIG_FILE"
    
    log_success "腾讯云DNS配置已保存"
}

# 设置华为云配置
setup_huawei_config() {
    echo -e "${YELLOW}华为云DNS API配置${NC}"
    echo
    echo "请访问华为云控制台获取API密钥"
    echo
    
    read -p "请输入Access Key ID: " access_key_id
    read -p "请输入Secret Access Key: " secret_key
    read -p "请输入默认邮箱: " default_email
    
    # 更新配置文件
    sed -i "s/^HUAWEI_ACCESS_KEY_ID=.*/HUAWEI_ACCESS_KEY_ID=\"$access_key_id\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^HUAWEI_SECRET_ACCESS_KEY=.*/HUAWEI_SECRET_ACCESS_KEY=\"$secret_key\"/" "$DNS_CONFIG_FILE"
    sed -i "s/^DEFAULT_EMAIL=.*/DEFAULT_EMAIL=\"$default_email\"/" "$DNS_CONFIG_FILE"
    
    log_success "华为云DNS配置已保存"
}

# 加载DNS API配置
load_dns_config() {
    if [[ ! -f "$DNS_CONFIG_FILE" ]]; then
        log_error "DNS API配置文件不存在: $DNS_CONFIG_FILE"
        log_info "请先运行: $0 --setup --provider your-provider"
        exit 1
    fi
    
    source "$DNS_CONFIG_FILE"
    
    if [[ -z "$DNS_PROVIDER" ]]; then
        log_error "DNS_PROVIDER未配置"
        log_info "请先运行: $0 --setup --provider your-provider"
        exit 1
    fi
}

# 检查DNS API配置
check_dns_config() {
    load_dns_config
    
    log_info "检查DNS API配置..."
    log_info "DNS服务商: $DNS_PROVIDER"
    
    case "$DNS_PROVIDER" in
        "dnspod")
            if [[ -z "$DNSPOD_ID" ]] || [[ -z "$DNSPOD_KEY" ]]; then
                log_error "DNSPod API配置不完整"
                return 1
            fi
            export DP_Id="$DNSPOD_ID"
            export DP_Key="$DNSPOD_KEY"
            log_success "DNSPod API配置检查通过"
            ;;
        "aliyun")
            if [[ -z "$ALIYUN_ACCESS_KEY_ID" ]] || [[ -z "$ALIYUN_ACCESS_KEY_SECRET" ]]; then
                log_error "阿里云DNS API配置不完整"
                return 1
            fi
            export Ali_Key="$ALIYUN_ACCESS_KEY_ID"
            export Ali_Secret="$ALIYUN_ACCESS_KEY_SECRET"
            log_success "阿里云DNS API配置检查通过"
            ;;
        "cloudflare")
            if [[ -z "$CLOUDFLARE_EMAIL" ]] || [[ -z "$CLOUDFLARE_API_KEY" ]]; then
                log_error "Cloudflare API配置不完整"
                return 1
            fi
            export CF_Email="$CLOUDFLARE_EMAIL"
            export CF_Key="$CLOUDFLARE_API_KEY"
            log_success "Cloudflare API配置检查通过"
            ;;
        "tencent")
            if [[ -z "$TENCENT_SECRET_ID" ]] || [[ -z "$TENCENT_SECRET_KEY" ]]; then
                log_error "腾讯云DNS API配置不完整"
                return 1
            fi
            export Tencent_SecretId="$TENCENT_SECRET_ID"
            export Tencent_SecretKey="$TENCENT_SECRET_KEY"
            log_success "腾讯云DNS API配置检查通过"
            ;;
        *)
            log_error "不支持的DNS服务商: $DNS_PROVIDER"
            return 1
            ;;
    esac
    
    return 0
}

# 获取DNS API参数
get_dns_api_params() {
    local provider="$1"
    
    case "$provider" in
        "dnspod")
            echo "dns_dp"
            ;;
        "aliyun")
            echo "dns_ali"
            ;;
        "cloudflare")
            echo "dns_cf"
            ;;
        "tencent")
            echo "dns_tencent"
            ;;
        *)
            log_error "不支持的DNS服务商: $provider"
            exit 1
            ;;
    esac
}

# 使用DNS API申请证书
issue_certificate_with_dns_api() {
    local domain="$1"
    local test_mode="$2"
    local provider="$3"
    
    # 如果没有指定provider，从配置文件加载
    if [[ -z "$provider" ]]; then
        load_dns_config
        provider="$DNS_PROVIDER"
    fi
    
    log_info "开始为域名 $domain 使用DNS API申请证书"
    log_info "DNS服务商: $provider"
    
    # 检查配置
    if ! check_dns_config; then
        return 1
    fi
    
    # 获取DNS API参数
    local dns_api
    dns_api=$(get_dns_api_params "$provider")
    
    # 构建acme.sh命令
    local acme_cmd="acme.sh --issue --dns $dns_api -d $domain -d www.$domain"
    
    if [[ "$test_mode" == "true" ]]; then
        acme_cmd="$acme_cmd --staging"
        log_info "运行测试模式（staging）"
    fi
    
    log_info "执行命令: $acme_cmd"
    
    # 执行acme.sh命令
    # 注意：忽略sudo警告，直接执行
    if eval "$acme_cmd"; then
        if [[ "$test_mode" != "true" ]]; then
            log_success "域名 $domain 的SSL证书申请成功"
            
            # 安装证书到系统
            install_certificate_to_system "$domain"
            
            # 重启Web服务器
            restart_webserver
            
            # 发送通知
            send_notification "success" "$domain" "DNS API SSL证书申请成功"
        else
            log_success "域名 $domain 的DNS API验证测试通过"
        fi
        return 0
    else
        log_error "域名 $domain 的SSL证书申请失败"
        send_notification "error" "$domain" "DNS API SSL证书申请失败"
        return 1
    fi
}

# 安装证书到系统
install_certificate_to_system() {
    local domain="$1"
    
    log_info "安装证书到系统目录..."
    
    # 创建证书目录
    local cert_dir="/etc/letsencrypt/live/$domain"
    mkdir -p "$cert_dir"
    
    # 安装证书
    acme.sh --install-cert -d "$domain" \
        --key-file "$cert_dir/privkey.pem" \
        --fullchain-file "$cert_dir/fullchain.pem" \
        --cert-file "$cert_dir/cert.pem" \
        --ca-file "$cert_dir/chain.pem"
    
    # 设置权限
    chmod 600 "$cert_dir"/*.pem
    chown root:root "$cert_dir"/*.pem
    
    log_success "证书安装完成"
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
            "$notify_script" --success "$domain"
        else
            "$notify_script" --emergency "$message"
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
        
        if [[ -n "$domain" ]]; then
            log_info "处理域名: $domain"
            
            # 检查是否需要续订
            if [[ "$force_mode" == "true" ]] || needs_renewal "$domain"; then
                if issue_certificate_with_dns_api "$domain" "$test_mode"; then
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

# 主函数
main() {
    local domain=""
    local test_mode=false
    local force_mode=false
    local provider=""
    local setup_mode=false
    local check_config_mode=false
    
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
            -p|--provider)
                provider="$2"
                shift 2
                ;;
            -s|--setup)
                setup_mode=true
                shift
                ;;
            -c|--check-config)
                check_config_mode=true
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
    check_permissions
    check_acme_sh
    
    # 处理不同模式
    if [[ "$setup_mode" == "true" ]]; then
        if [[ -z "$provider" ]]; then
            log_error "请指定DNS服务商"
            log_info "使用: $0 --setup --provider dnspod"
            exit 1
        fi
        setup_dns_config "$provider"
        exit 0
    fi
    
    if [[ "$check_config_mode" == "true" ]]; then
        check_dns_config
        exit 0
    fi
    
    log_info "开始DNS API自动验证SSL证书续订..."
    
    if [[ -n "$domain" ]]; then
        # 处理单个域名
        issue_certificate_with_dns_api "$domain" "$test_mode" "$provider"
    else
        # 处理配置文件中的所有域名
        process_domains_config "$test_mode" "$force_mode"
    fi
    
    log_info "DNS API自动验证SSL证书续订完成"
}

# 运行主函数
main "$@"