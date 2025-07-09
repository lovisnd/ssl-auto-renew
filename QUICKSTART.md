# SSL Certificate Auto-Renewal System - Quick Start Guide

<div align="center">

[English](#english) | [中文](#chinese)

</div>

---

## English

This guide will help you quickly deploy the SSL certificate auto-renewal system in 5 minutes.

### Prerequisites

✅ Ubuntu 18.04+ system  
✅ Root or sudo privileges  
✅ Nginx or Apache installed  
✅ Domain resolved to server IP  
✅ Ports 80 and 443 open  

### One-Click Deployment

#### Step 1: Download and Install

```bash
# Download project files to server
cd /tmp
git clone https://github.com/lovisnd/ssl-auto-renew.git ssl-auto-renewal
cd ssl-auto-renewal

# Or download directly as archive
# wget <download-url> -O ssl-auto-renewal.tar.gz
# tar -xzf ssl-auto-renewal.tar.gz
# cd ssl-auto-renewal

# Run one-click installation script
sudo bash install.sh
```

The installation process takes about 2-3 minutes. The script will automatically:
- Install Certbot and related dependencies
- Create directory structure and configuration files
- Set up cron jobs
- Configure firewall rules

#### Step 2: Configure Domains

```bash
# Copy example configuration files
sudo cp /opt/ssl-auto-renewal/config/domains.conf.example /opt/ssl-auto-renewal/config/domains.conf
sudo cp /opt/ssl-auto-renewal/config/email.conf.example /opt/ssl-auto-renewal/config/email.conf

# Edit domain configuration file
sudo nano /opt/ssl-auto-renewal/config/domains.conf

# First set default email address (at the top of file)
DEFAULT_EMAIL="admin@yourdomain.com"

# Then add your domains using simplified format: domain:webroot_path
# For example:
example.com:/var/www/html
www.example.com:/var/www/html

# Or use complete format (if you need different email for specific domain):
# special.example.com:special@example.com:/var/www/special
```

#### Step 3: Test Configuration

```bash
# Test certificate application (won't actually apply for certificate)
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# If test succeeds, apply for real certificate (Certbot will automatically create certificate files and directories)
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh
```

**Important Note**: You don't need to manually create `/etc/letsencrypt/live/your-domain.com/` directory or certificate files. Certbot will automatically create all necessary files and directories when applying for certificates. For detailed SSL certificate configuration instructions, please refer to [SSL Certificate Setup Guide](docs/SSL_CERTIFICATE_SETUP.md).

#### Step 4: Verify Deployment

```bash
# Check certificate status
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all

# Check cron jobs
crontab -l | grep ssl-renew

# View logs
tail -f /opt/ssl-auto-renewal/logs/ssl-renew.log
```

### Common Commands

```bash
# Manual certificate renewal
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh

# Check certificate status
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all

# Force renew all certificates
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --force

# Generate status report
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --report /tmp/report.txt
```

### Email Notification Configuration (Optional)

#### Method 1: Using Configuration Wizard (Recommended)

If you're using Tencent Enterprise Email, you can use the configuration wizard:
```bash
sudo /opt/ssl-auto-renewal/scripts/test-smtp.sh --setup-tencent
```

#### Method 2: Manual Configuration

```bash
# Copy example email configuration
sudo cp /opt/ssl-auto-renewal/config/email.conf.example /opt/ssl-auto-renewal/config/email.conf

# Edit email configuration
sudo nano /opt/ssl-auto-renewal/config/email.conf

# Basic configuration
ENABLE_EMAIL_NOTIFICATION=true
NOTIFICATION_EMAIL="your-email@domain.com"

# External SMTP configuration (Tencent Enterprise Email example)
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.exmail.qq.com"
SMTP_PORT="465"
SMTP_USE_SSL=true
SMTP_USERNAME="your-email@yourcompany.com"
SMTP_PASSWORD="your-password"

# Test email functionality
sudo /opt/ssl-auto-renewal/scripts/notify.sh --test
```

### Web Server Configuration

#### Nginx Configuration Example

```nginx
# /etc/nginx/sites-available/your-domain
server {
    listen 80;
    server_name your-domain.com;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    root /var/www/html;
    index index.html;
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/your-domain /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Troubleshooting

#### Issue 1: Certificate Application Failed

```bash
# Check domain resolution
nslookup your-domain.com

# Check web server status
sudo systemctl status nginx  # or apache2

# Check port 80
sudo netstat -tlnp | grep :80

# Manual test
sudo certbot certonly --webroot -w /var/www/html -d your-domain.com --dry-run
```

#### Issue 2: Cron Jobs Not Working

```bash
# Check cron service
sudo systemctl status cron

# View cron jobs
crontab -l

# View cron logs
sudo tail -f /var/log/syslog | grep CRON
```

### Important File Locations

```
/opt/ssl-auto-renewal/
├── config/
│   ├── domains.conf      # Domain configuration
│   └── email.conf        # Email configuration
├── scripts/
│   ├── ssl-renew.sh      # Main renewal script
│   ├── check-ssl.sh      # Status check script
│   └── notify.sh         # Email notification script
└── logs/
    ├── ssl-renew.log     # Renewal logs
    ├── ssl-error.log     # Error logs
    └── cron.log          # Cron job logs
```

### Automation Schedule

- **Daily 2:00 AM**: Automatically check and renew expiring certificates
- **Daily 8:00 AM**: Generate certificate status reports
- **Monday 9:00 AM**: Send weekly report emails (if enabled)
- **1st of each month 3:00 AM**: Clean up logs older than 30 days

---

## Chinese

本指南将帮助你在5分钟内快速部署SSL证书自动续订系统。

### 前提条件

✅ Ubuntu 18.04+ 系统  
✅ Root或sudo权限  
✅ 已安装Nginx或Apache  
✅ 域名已解析到服务器IP  
✅ 80和443端口已开放  

### 一键部署

#### 步骤1: 下载并安装

```bash
# 下载项目文件到服务器
cd /tmp
git clone https://github.com/lovisnd/ssl-auto-renew.git ssl-auto-renewal
cd ssl-auto-renewal

# 或者直接下载压缩包
# wget <download-url> -O ssl-auto-renewal.tar.gz
# tar -xzf ssl-auto-renewal.tar.gz
# cd ssl-auto-renewal

# 运行一键安装脚本
sudo bash install.sh
```

安装过程大约需要2-3分钟，脚本会自动：
- 安装Certbot和相关依赖
- 创建目录结构和配置文件
- 设置定时任务
- 配置防火墙规则

#### 步骤2: 配置域名

```bash
# 复制示例配置文件
sudo cp /opt/ssl-auto-renewal/config/domains.conf.example /opt/ssl-auto-renewal/config/domains.conf
sudo cp /opt/ssl-auto-renewal/config/email.conf.example /opt/ssl-auto-renewal/config/email.conf

# 编辑域名配置文件
sudo nano /opt/ssl-auto-renewal/config/domains.conf

# 首先设置默认邮箱地址（在文件顶部）
DEFAULT_EMAIL="admin@yourdomain.com"

# 然后添加你的域名，使用简化格式：域名:网站根目录
# 例如：
example.com:/var/www/html
www.example.com:/var/www/html

# 或者使用完整格式（如需为特定域名指定不同邮箱）：
# special.example.com:special@example.com:/var/www/special
```

#### 步骤3: 测试配置

```bash
# 测试证书申请（不会实际申请证书）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 如果测试成功，申请真实证书（Certbot会自动创建证书文件和目录）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh
```

**重要说明**：您不需要手动创建`/etc/letsencrypt/live/your-domain.com/`目录或证书文件，Certbot会在申请证书时自动创建所有必要的文件和目录。详细的SSL证书配置说明请参考 [SSL证书配置指南](docs/SSL_CERTIFICATE_SETUP.md)。

#### 步骤4: 验证部署

```bash
# 检查证书状态
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all

# 检查定时任务
crontab -l | grep ssl-renew

# 查看日志
tail -f /opt/ssl-auto-renewal/logs/ssl-renew.log
```

### 常用命令

```bash
# 手动续订证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh

# 检查证书状态
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all

# 强制续订所有证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --force

# 生成状态报告
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --report /tmp/report.txt
```

### 邮件通知配置（可选）

#### 方法一：使用配置向导（推荐）

如果您使用腾讯企业邮箱，可以使用配置向导：
```bash
sudo /opt/ssl-auto-renewal/scripts/test-smtp.sh --setup-tencent
```

#### 方法二：手动配置

```bash
# 复制示例邮件配置
sudo cp /opt/ssl-auto-renewal/config/email.conf.example /opt/ssl-auto-renewal/config/email.conf

# 编辑邮件配置
sudo nano /opt/ssl-auto-renewal/config/email.conf

# 基本配置
ENABLE_EMAIL_NOTIFICATION=true
NOTIFICATION_EMAIL="your-email@domain.com"

# 外部SMTP配置（腾讯企业邮箱示例）
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.exmail.qq.com"
SMTP_PORT="465"
SMTP_USE_SSL=true
SMTP_USERNAME="your-email@yourcompany.com"
SMTP_PASSWORD="your-password"

# 测试邮件功能
sudo /opt/ssl-auto-renewal/scripts/notify.sh --test
```

### Web服务器配置

#### Nginx配置示例

```nginx
# /etc/nginx/sites-available/your-domain
server {
    listen 80;
    server_name your-domain.com;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    root /var/www/html;
    index index.html;
}
```

```bash
# 启用站点
sudo ln -s /etc/nginx/sites-available/your-domain /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 故障排除

#### 问题1: 证书申请失败

```bash
# 检查域名解析
nslookup your-domain.com

# 检查Web服务器状态
sudo systemctl status nginx  # 或 apache2

# 检查80端口
sudo netstat -tlnp | grep :80

# 手动测试
sudo certbot certonly --webroot -w /var/www/html -d your-domain.com --dry-run
```

#### 问题2: 定时任务不工作

```bash
# 检查cron服务
sudo systemctl status cron

# 查看定时任务
crontab -l

# 查看cron日志
sudo tail -f /var/log/syslog | grep CRON
```

### 重要文件位置

```
/opt/ssl-auto-renewal/
├── config/
│   ├── domains.conf      # 域名配置
│   └── email.conf        # 邮件配置
├── scripts/
│   ├── ssl-renew.sh      # 主续订脚本
│   ├── check-ssl.sh      # 状态检查脚本
│   └── notify.sh         # 邮件通知脚本
└── logs/
    ├── ssl-renew.log     # 续订日志
    ├── ssl-error.log     # 错误日志
    └── cron.log          # 定时任务日志
```

### 自动化时间表

- **每天凌晨2点**: 自动检查并续订即将过期的证书
- **每天上午8点**: 生成证书状态报告
- **每周一上午9点**: 发送周报邮件（如果启用）
- **每月1号凌晨3点**: 清理30天前的日志文件

---

⭐ If this project helps you, please give it a star!

🔒 **Make SSL certificate management simple and reliable!**