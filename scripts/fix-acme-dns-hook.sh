#!/bin/bash

# 修复acme.sh DNS API hook问题的脚本

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
修复acme.sh DNS API hook问题

用法: $0 [选项]

选项:
    --reinstall         重新安装acme.sh
    --update           更新acme.sh到最新版本
    --check            检查DNS hook状态
    --test DOMAIN      测试DNS API功能
    -h, --help         显示此帮助信息

示例:
    $0 --check
    $0 --update
    $0 --test zhangmingrui.top

EOF
}

# 检查用户权限
check_user_permissions() {
    if [[ $EUID -eq 0 ]]; then
        log_error "此脚本不应以root权限运行"
        log_info "请以普通用户身份运行此脚本"
        log_info "正确用法: /opt/ssl-auto-renewal/scripts/fix-acme-dns-hook.sh --check"
        exit 1
    fi
    
    log_info "以用户 $(whoami) 身份运行"
}

# 检查acme.sh安装状态
check_acme_installation() {
    log_info "检查acme.sh安装状态..."
    
    local acme_dir="$HOME/.acme.sh"
    local acme_script="$acme_dir/acme.sh"
    
    if [[ -f "$acme_script" ]]; then
        log_success "找到acme.sh: $acme_script"
        
        # 检查版本
        local version=$($acme_script --version 2>/dev/null || echo "未知")
        log_info "acme.sh版本: $version"
        
        # 检查DNS hook文件
        log_info "检查DNS hook文件..."
        local dns_cf_file="$acme_dir/dnsapi/dns_cf.sh"
        
        if [[ -f "$dns_cf_file" ]]; then
            log_success "找到Cloudflare DNS hook: $dns_cf_file"
            return 0
        else
            log_error "未找到Cloudflare DNS hook文件"
            return 1
        fi
    else
        log_error "未找到acme.sh安装"
        return 1
    fi
}

# 重新安装acme.sh
reinstall_acme() {
    log_info "重新安装acme.sh..."
    
    # 备份现有配置
    if [[ -d "$HOME/.acme.sh" ]]; then
        log_info "备份现有配置..."
        mv "$HOME/.acme.sh" "$HOME/.acme.sh.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 下载并安装最新版本
    log_info "下载最新版本的acme.sh..."
    curl -s https://get.acme.sh | sh -s email=admin@$(hostname -d 2>/dev/null || echo "localhost")
    
    # 重新加载环境
    source "$HOME/.bashrc" 2>/dev/null || true
    
    if [[ -f "$HOME/.acme.sh/acme.sh" ]]; then
        log_success "acme.sh重新安装成功"
        return 0
    else
        log_error "acme.sh重新安装失败"
        return 1
    fi
}

# 更新acme.sh
update_acme() {
    log_info "更新acme.sh..."
    
    local acme_script="$HOME/.acme.sh/acme.sh"
    
    if [[ -f "$acme_script" ]]; then
        if $acme_script --upgrade; then
            log_success "acme.sh更新成功"
            return 0
        else
            log_error "acme.sh更新失败"
            return 1
        fi
    else
        log_error "未找到acme.sh，请先安装"
        return 1
    fi
}

# 手动下载DNS hook文件
download_dns_hooks() {
    log_info "手动下载DNS hook文件..."
    
    local acme_dir="$HOME/.acme.sh"
    local dnsapi_dir="$acme_dir/dnsapi"
    
    # 确保目录存在
    mkdir -p "$dnsapi_dir"
    
    # 下载Cloudflare DNS hook
    log_info "下载Cloudflare DNS hook..."
    if curl -s -o "$dnsapi_dir/dns_cf.sh" "https://raw.githubusercontent.com/acmesh-official/acme.sh/master/dnsapi/dns_cf.sh"; then
        chmod +x "$dnsapi_dir/dns_cf.sh"
        log_success "Cloudflare DNS hook下载成功"
    else
        log_error "Cloudflare DNS hook下载失败"
        return 1
    fi
    
    # 下载其他常用DNS hook
    local dns_providers=("dns_dp.sh" "dns_ali.sh" "dns_tencent.sh")
    
    for provider in "${dns_providers[@]}"; do
        log_info "下载 $provider..."
        if curl -s -o "$dnsapi_dir/$provider" "https://raw.githubusercontent.com/acmesh-official/acme.sh/master/dnsapi/$provider"; then
            chmod +x "$dnsapi_dir/$provider"
            log_success "$provider 下载成功"
        else
            log_warning "$provider 下载失败"
        fi
    done
    
    return 0
}

# 测试DNS API功能
test_dns_api() {
    local domain="$1"
    
    log_info "测试DNS API功能..."
    
    # 加载DNS配置
    local config_file="/opt/ssl-auto-renewal/config/dns-api.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        log_error "DNS配置文件不存在: $config_file"
        return 1
    fi
    
    # 设置Cloudflare环境变量
    export CF_Email="$CLOUDFLARE_EMAIL"
    export CF_Key="$CLOUDFLARE_API_KEY"
    
    local acme_script="$HOME/.acme.sh/acme.sh"
    
    if [[ -f "$acme_script" ]]; then
        log_info "执行DNS API测试..."
        log_info "命令: $acme_script --issue --dns dns_cf -d $domain --staging"
        
        if $acme_script --issue --dns dns_cf -d "$domain" --staging; then
            log_success "DNS API测试成功"
            return 0
        else
            log_error "DNS API测试失败"
            return 1
        fi
    else
        log_error "未找到acme.sh"
        return 1
    fi
}

# 显示诊断信息
show_diagnostic_info() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  acme.sh 诊断信息${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # 检查acme.sh路径
    log_info "acme.sh路径检查:"
    echo "  - HOME/.acme.sh/acme.sh: $([ -f "$HOME/.acme.sh/acme.sh" ] && echo "存在" || echo "不存在")"
    echo "  - 系统PATH中的acme.sh: $(command -v acme.sh 2>/dev/null || echo "未找到")"
    
    # 检查DNS hook文件
    log_info "DNS hook文件检查:"
    local dnsapi_dir="$HOME/.acme.sh/dnsapi"
    if [[ -d "$dnsapi_dir" ]]; then
        echo "  - dns_cf.sh: $([ -f "$dnsapi_dir/dns_cf.sh" ] && echo "存在" || echo "不存在")"
        echo "  - dns_dp.sh: $([ -f "$dnsapi_dir/dns_dp.sh" ] && echo "存在" || echo "不存在")"
        echo "  - dns_ali.sh: $([ -f "$dnsapi_dir/dns_ali.sh" ] && echo "存在" || echo "不存在")"
    else
        echo "  - dnsapi目录: 不存在"
    fi
    
    # 检查环境变量
    log_info "环境变量检查:"
    echo "  - CF_Email: $([ -n "${CF_Email:-}" ] && echo "已设置" || echo "未设置")"
    echo "  - CF_Key: $([ -n "${CF_Key:-}" ] && echo "已设置" || echo "未设置")"
    
    echo
}

# 主函数
main() {
    local action=""
    local domain=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reinstall)
                action="reinstall"
                shift
                ;;
            --update)
                action="update"
                shift
                ;;
            --check)
                action="check"
                shift
                ;;
            --test)
                action="test"
                domain="$2"
                shift 2
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
    
    if [[ -z "$action" ]]; then
        action="check"
    fi
    
    # 检查用户权限
    check_user_permissions
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  acme.sh DNS Hook 修复工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    case "$action" in
        "check")
            show_diagnostic_info
            if check_acme_installation; then
                log_success "acme.sh安装正常"
            else
                log_warning "acme.sh安装有问题，建议运行: $0 --reinstall"
            fi
            ;;
        "reinstall")
            if reinstall_acme; then
                download_dns_hooks
                log_success "重新安装完成"
            fi
            ;;
        "update")
            if update_acme; then
                download_dns_hooks
                log_success "更新完成"
            fi
            ;;
        "test")
            if [[ -z "$domain" ]]; then
                log_error "请指定测试域名"
                exit 1
            fi
            test_dns_api "$domain"
            ;;
        *)
            log_error "未知操作: $action"
            exit 1
            ;;
    esac
    
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  操作完成${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# 运行主函数
main "$@"