#!/bin/bash

# SSL证书自动续订系统 - 维护脚本
# 功能：系统维护、日志清理、健康检查
# 作者: SSL Auto Renewal System
# 版本: 1.0

set -e

# 配置路径
BASE_DIR="/opt/ssl-auto-renewal"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
SCRIPTS_DIR="$BASE_DIR/scripts"

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

# 系统健康检查
health_check() {
    log_info "执行系统健康检查..."
    
    local issues=0
    
    # 检查必要的命令
    local required_commands=("certbot" "openssl" "crontab" "systemctl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "缺少必要命令: $cmd"
            ((issues++))
        fi
    done
    
    # 检查目录结构
    local required_dirs=("$CONFIG_DIR" "$LOG_DIR" "$SCRIPTS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "缺少必要目录: $dir"
            ((issues++))
        fi
    done
    
    # 检查配置文件
    if [[ ! -f "$CONFIG_DIR/domains.conf" ]]; then
        log_error "域名配置文件不存在"
        ((issues++))
    elif ! grep -v '^#' "$CONFIG_DIR/domains.conf" | grep -v '^$' >/dev/null 2>&1; then
        log_warn "域名配置文件为空"
    fi
    
    # 检查脚本权限
    local scripts=("ssl-renew.sh" "check-ssl.sh" "notify.sh")
    for script in "${scripts[@]}"; do
        if [[ ! -x "$SCRIPTS_DIR/$script" ]]; then
            log_error "脚本缺少执行权限: $script"
            ((issues++))
        fi
    done
    
    # 检查Web服务器
    if ! systemctl is-active --quiet nginx && ! systemctl is-active --quiet apache2; then
        log_warn "未检测到运行中的Web服务器"
    fi
    
    # 检查定时任务
    if ! crontab -l 2>/dev/null | grep -q "ssl-renew.sh"; then
        log_error "SSL续订定时任务未配置"
        ((issues++))
    fi
    
    # 检查磁盘空间
    local disk_usage=$(df /etc/letsencrypt 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" ]] && [[ $disk_usage -gt 90 ]]; then
        log_error "磁盘空间不足: ${disk_usage}%"
        ((issues++))
    fi
    
    # 检查证书过期情况
    local expired_count=0
    local expiring_count=0
    
    while IFS=':' read -r domain param2 param3 || [[ -n "$domain" ]]; do
        [[ "$domain" =~ ^[[:space:]]*# ]] && continue
        [[ "$domain" =~ ^DEFAULT_EMAIL= ]] && continue
        [[ -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        
        local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
        if [[ -f "$cert_path" ]]; then
            local not_after=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
            local expiry_timestamp=$(date -d "$not_after" +%s)
            local current_timestamp=$(date +%s)
            local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            if [[ $days_until_expiry -le 0 ]]; then
                ((expired_count++))
            elif [[ $days_until_expiry -le 7 ]]; then
                ((expiring_count++))
            fi
        fi
    done < <(grep -v '^#' "$CONFIG_DIR/domains.conf" | grep -v '^$')
    
    if [[ $expired_count -gt 0 ]]; then
        log_error "发现 $expired_count 个已过期证书"
        ((issues++))
    fi
    
    if [[ $expiring_count -gt 0 ]]; then
        log_warn "发现 $expiring_count 个即将过期证书"
    fi
    
    # 总结
    if [[ $issues -eq 0 ]]; then
        log_success "系统健康检查通过，未发现严重问题"
        return 0
    else
        log_error "系统健康检查发现 $issues 个问题需要处理"
        return 1
    fi
}

# 清理日志文件
cleanup_logs() {
    log_info "清理旧日志文件..."
    
    local days_to_keep="${1:-30}"
    local cleaned_count=0
    
    # 清理系统日志
    if [[ -d "$LOG_DIR" ]]; then
        local old_logs=$(find "$LOG_DIR" -name "*.log" -mtime +$days_to_keep)
        if [[ -n "$old_logs" ]]; then
            echo "$old_logs" | while read -r log_file; do
                rm -f "$log_file"
                ((cleaned_count++))
            done
        fi
    fi
    
    # 清理Let's Encrypt日志
    if [[ -d "/var/log/letsencrypt" ]]; then
        find /var/log/letsencrypt -name "*.log*" -mtime +60 -delete
    fi
    
    # 压缩大日志文件
    find "$LOG_DIR" -name "*.log" -size +10M -exec gzip {} \;
    
    log_success "日志清理完成，保留最近 $days_to_keep 天的日志"
}

# 更新系统组件
update_system() {
    log_info "更新系统组件..."
    
    # 更新Certbot
    if command -v snap >/dev/null 2>&1; then
        log_info "更新Certbot..."
        snap refresh certbot
    fi
    
    # 更新系统包
    log_info "更新系统包..."
    apt update
    apt list --upgradable | grep -E "(certbot|nginx|apache2|openssl)" || true
    
    log_success "系统组件更新完成"
}

# 备份配置和证书
backup_system() {
    local backup_dir="${1:-/backup/ssl-auto-renewal}"
    local date_stamp=$(date +%Y%m%d_%H%M%S)
    
    log_info "备份系统配置和证书到: $backup_dir"
    
    mkdir -p "$backup_dir"
    
    # 备份配置文件
    tar -czf "$backup_dir/ssl-config_$date_stamp.tar.gz" -C / opt/ssl-auto-renewal/config/
    
    # 备份Let's Encrypt证书
    if [[ -d "/etc/letsencrypt" ]]; then
        tar -czf "$backup_dir/letsencrypt_$date_stamp.tar.gz" -C / etc/letsencrypt/
    fi
    
    # 备份Web服务器配置
    if [[ -d "/etc/nginx" ]]; then
        tar -czf "$backup_dir/nginx_$date_stamp.tar.gz" -C / etc/nginx/
    fi
    
    if [[ -d "/etc/apache2" ]]; then
        tar -czf "$backup_dir/apache2_$date_stamp.tar.gz" -C / etc/apache2/
    fi
    
    # 清理30天前的备份
    find "$backup_dir" -name "*.tar.gz" -mtime +30 -delete
    
    log_success "备份完成: $backup_dir"
}

# 生成维护报告
generate_report() {
    local report_file="${1:-/tmp/ssl-maintenance-report.txt}"
    
    log_info "生成维护报告: $report_file"
    
    {
        echo "SSL证书自动续订系统 - 维护报告"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "服务器: $(hostname)"
        echo ""
        
        echo "系统信息:"
        echo "========"
        echo "操作系统: $(lsb_release -d | cut -f2)"
        echo "内核版本: $(uname -r)"
        echo "Certbot版本: $(certbot --version 2>&1 | head -1)"
        echo "磁盘使用率: $(df -h /etc/letsencrypt | tail -1 | awk '{print $5}')"
        echo "内存使用率: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
        echo ""
        
        echo "证书状态:"
        echo "========"
        "$SCRIPTS_DIR/check-ssl.sh" --all 2>/dev/null | grep -E "(域名|证书|天)" || echo "无证书信息"
        echo ""
        
        echo "服务状态:"
        echo "========"
        echo "Nginx: $(systemctl is-active nginx 2>/dev/null || echo '未安装')"
        echo "Apache: $(systemctl is-active apache2 2>/dev/null || echo '未安装')"
        echo "Cron: $(systemctl is-active cron 2>/dev/null || echo '异常')"
        echo ""
        
        echo "最近日志:"
        echo "========"
        if [[ -f "$LOG_DIR/ssl-renew.log" ]]; then
            echo "最后续订检查:"
            tail -5 "$LOG_DIR/ssl-renew.log" | grep -E "\[INFO\]|\[SUCCESS\]|\[ERROR\]" || echo "无相关日志"
        fi
        echo ""
        
        echo "定时任务:"
        echo "========"
        crontab -l | grep ssl || echo "无SSL相关定时任务"
        echo ""
        
        echo "建议操作:"
        echo "========"
        
        # 检查是否需要更新
        if snap list certbot 2>/dev/null | grep -q "certbot"; then
            local current_version=$(snap list certbot | tail -1 | awk '{print $2}')
            echo "- Certbot当前版本: $current_version"
        fi
        
        # 检查证书过期情况
        local expiring_certs=$("$SCRIPTS_DIR/check-ssl.sh" --all 2>/dev/null | grep -c "即将过期\|已过期" || echo "0")
        if [[ $expiring_certs -gt 0 ]]; then
            echo "- 关注 $expiring_certs 个即将过期或已过期的证书"
        else
            echo "- 所有证书状态正常"
        fi
        
        # 检查日志大小
        local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
        echo "- 日志目录大小: $log_size"
        
        echo ""
        echo "---"
        echo "此报告由SSL证书自动续订系统维护脚本生成"
        
    } > "$report_file"
    
    log_success "维护报告已生成: $report_file"
}

# 修复常见问题
fix_common_issues() {
    log_info "修复常见问题..."
    
    # 修复脚本权限
    chmod +x "$SCRIPTS_DIR"/*.sh
    
    # 修复目录权限
    chown -R root:root "$BASE_DIR"
    chmod 755 "$BASE_DIR" "$CONFIG_DIR" "$LOG_DIR" "$SCRIPTS_DIR"
    chmod 644 "$CONFIG_DIR"/*.conf
    
    # 重启cron服务
    systemctl restart cron
    
    # 检查并修复Web服务器配置
    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t 2>/dev/null; then
            log_warn "Nginx配置有问题，请手动检查"
        fi
    fi
    
    if command -v apache2ctl >/dev/null 2>&1; then
        if ! apache2ctl configtest 2>/dev/null; then
            log_warn "Apache配置有问题，请手动检查"
        fi
    fi
    
    log_success "常见问题修复完成"
}

# 显示帮助信息
show_help() {
    echo "SSL证书自动续订系统 - 维护脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --health-check, -h      执行系统健康检查"
    echo "  --cleanup [DAYS]        清理日志文件（默认保留30天）"
    echo "  --update                更新系统组件"
    echo "  --backup [DIR]          备份配置和证书"
    echo "  --report [FILE]         生成维护报告"
    echo "  --fix                   修复常见问题"
    echo "  --all                   执行所有维护操作"
    echo "  --help                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --health-check               # 健康检查"
    echo "  $0 --cleanup 15                 # 清理15天前的日志"
    echo "  $0 --backup /backup/ssl         # 备份到指定目录"
    echo "  $0 --report /tmp/report.txt     # 生成报告"
    echo "  $0 --all                        # 执行完整维护"
    echo ""
}

# 主函数
main() {
    local action=""
    local param=""
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --health-check|-h)
                action="health_check"
                shift
                ;;
            --cleanup)
                action="cleanup"
                param="$2"
                [[ "$2" =~ ^[0-9]+$ ]] && shift
                shift
                ;;
            --update)
                action="update"
                shift
                ;;
            --backup)
                action="backup"
                param="$2"
                [[ "$2" =~ ^[^-] ]] && shift
                shift
                ;;
            --report)
                action="report"
                param="$2"
                [[ "$2" =~ ^[^-] ]] && shift
                shift
                ;;
            --fix)
                action="fix"
                shift
                ;;
            --all)
                action="all"
                shift
                ;;
            --help)
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
    
    log_info "SSL证书自动续订系统维护脚本开始运行..."
    
    case "$action" in
        "health_check")
            health_check
            ;;
        "cleanup")
            cleanup_logs "$param"
            ;;
        "update")
            update_system
            ;;
        "backup")
            backup_system "$param"
            ;;
        "report")
            generate_report "$param"
            ;;
        "fix")
            fix_common_issues
            ;;
        "all")
            log_info "执行完整维护流程..."
            health_check
            cleanup_logs
            fix_common_issues
            backup_system
            generate_report
            log_success "完整维护流程执行完成"
            ;;
        *)
            log_error "未知操作: $action"
            exit 1
            ;;
    esac
    
    log_info "维护脚本执行完成"
}

# 执行主函数
main "$@"