# SSL证书自动续订系统 - 部署指南

本文档详细介绍如何在Ubuntu系统上部署和配置SSL证书自动续订系统。

## 系统要求

### 操作系统
- Ubuntu 18.04 LTS 或更高版本
- CentOS 7/8 (需要适当修改安装脚本)

### 硬件要求
- 最小内存：512MB
- 最小磁盘空间：2GB
- 网络：需要能够访问互联网

### 软件依赖
- Root权限或sudo权限
- 已安装并配置Web服务器（Nginx或Apache）
- 域名已正确解析到服务器IP地址

## 快速部署

### 1. 下载项目文件

```bash
# 方法1：使用git克隆（推荐）
git clone <repository-url> /opt/ssl-auto-renewal-source
cd /opt/ssl-auto-renewal-source

# 方法2：直接下载并解压
wget <download-url> -O ssl-auto-renewal.tar.gz
tar -xzf ssl-auto-renewal.tar.gz
cd ssl-auto-renewal
```

### 2. 运行安装脚本

```bash
# 给安装脚本执行权限
chmod +x install.sh

# 运行安装脚本
sudo bash install.sh
```

安装脚本将自动完成以下操作：
- 检查系统环境
- 更新系统包
- 安装必要软件（snapd、certbot、mailutils等）
- 创建目录结构
- 配置防火墙规则
- 检测Web服务器类型
- 设置定时任务
- 创建示例配置文件

### 3. 配置域名

编辑域名配置文件：

```bash
sudo nano /opt/ssl-auto-renewal/config/domains.conf
```

添加你的域名配置，格式如下：

```
# 格式: domain_name:email:webroot_path
example.com:admin@example.com:/var/www/html
www.example.com:admin@example.com:/var/www/html
api.example.com:admin@example.com:/var/www/api
```

### 4. 配置邮件通知（可选）

编辑邮件配置文件：

```bash
sudo nano /opt/ssl-auto-renewal/config/email.conf
```

启用邮件通知：

```bash
# 启用邮件通知
ENABLE_EMAIL_NOTIFICATION=true

# 设置通知邮箱
NOTIFICATION_EMAIL="admin@yourdomain.com"
```

### 5. 测试配置

```bash
# 测试SSL证书申请（dry-run模式，不会实际申请证书）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 检查证书状态
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all

# 测试邮件通知
sudo /opt/ssl-auto-renewal/scripts/notify.sh --test
```

## 详细配置

### Web服务器配置

#### Nginx配置示例

为每个域名创建虚拟主机配置：

```nginx
# /etc/nginx/sites-available/example.com
server {
    listen 80;
    server_name example.com www.example.com;
    
    # Let's Encrypt验证目录
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # 重定向到HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;
    
    # SSL证书配置
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 网站根目录
    root /var/www/html;
    index index.html index.php;
    
    location / {
        try_files $uri $uri/ =404;
    }
}
```

启用站点：

```bash
sudo ln -s /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### Apache配置示例

```apache
# /etc/apache2/sites-available/example.com.conf
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/html
    
    # Let's Encrypt验证目录
    Alias /.well-known/acme-challenge/ /var/www/html/.well-known/acme-challenge/
    <Directory "/var/www/html/.well-known/acme-challenge/">
        Options None
        AllowOverride None
        Require all granted
    </Directory>
    
    # 重定向到HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

<VirtualHost *:443>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/html
    
    # SSL配置
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/example.com/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/example.com/chain.pem
    
    # SSL安全配置
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
    SSLHonorCipherOrder off
    SSLSessionTickets off
</VirtualHost>
```

启用站点和SSL模块：

```bash
sudo a2enmod ssl rewrite
sudo a2ensite example.com.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### 邮件系统配置

#### 安装和配置Postfix

```bash
# 安装Postfix
sudo apt update
sudo apt install postfix mailutils

# 配置Postfix（选择"Internet Site"）
sudo dpkg-reconfigure postfix
```

#### 配置外部SMTP（可选）

如果使用外部SMTP服务器，编辑邮件配置：

```bash
# 编辑邮件配置文件
sudo nano /opt/ssl-auto-renewal/config/email.conf

# 启用外部SMTP
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USERNAME="your-email@gmail.com"
SMTP_PASSWORD="your-app-password"
SMTP_USE_TLS=true
```

### 防火墙配置

```bash
# 使用ufw配置防火墙
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable

# 或使用iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```

## 运维管理

### 日常操作命令

```bash
# 手动续订证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh

# 强制续订所有证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --force

# 检查证书状态
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all

# 检查特定域名
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh example.com

# 生成状态报告
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --report /tmp/ssl-report.txt

# 发送测试邮件
sudo /opt/ssl-auto-renewal/scripts/notify.sh --test

# 发送状态报告邮件
sudo /opt/ssl-auto-renewal/scripts/notify.sh --status
```

### 日志文件位置

```bash
# 主要日志文件
/opt/ssl-auto-renewal/logs/ssl-renew.log      # 续订日志
/opt/ssl-auto-renewal/logs/ssl-error.log      # 错误日志
/opt/ssl-auto-renewal/logs/ssl-check.log      # 检查日志
/opt/ssl-auto-renewal/logs/notify.log         # 通知日志
/opt/ssl-auto-renewal/logs/cron.log           # 定时任务日志

# Let's Encrypt日志
/var/log/letsencrypt/letsencrypt.log

# 系统cron日志
/var/log/syslog | grep CRON
```

### 监控和告警

#### 设置监控脚本

```bash
# 创建监控脚本
sudo nano /opt/ssl-auto-renewal/scripts/monitor.sh
```

```bash
#!/bin/bash
# SSL证书监控脚本

# 检查即将过期的证书
EXPIRING_CERTS=$(/opt/ssl-auto-renewal/scripts/check-ssl.sh --all | grep -c "即将过期\|已过期")

if [ $EXPIRING_CERTS -gt 0 ]; then
    /opt/ssl-auto-renewal/scripts/notify.sh --emergency "发现 $EXPIRING_CERTS 个证书需要关注"
fi

# 检查续订失败
if grep -q "ERROR" /opt/ssl-auto-renewal/logs/ssl-renew.log; then
    /opt/ssl-auto-renewal/scripts/notify.sh --emergency "SSL证书续订过程中发现错误"
fi
```

#### 添加到定时任务

```bash
# 每小时检查一次
echo "0 * * * * /opt/ssl-auto-renewal/scripts/monitor.sh" | sudo crontab -
```

### 备份和恢复

#### 备份SSL证书

```bash
# 创建备份脚本
sudo nano /opt/ssl-auto-renewal/scripts/backup.sh
```

```bash
#!/bin/bash
# SSL证书备份脚本

BACKUP_DIR="/backup/ssl-certificates"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# 备份Let's Encrypt证书
tar -czf "$BACKUP_DIR/letsencrypt_$DATE.tar.gz" /etc/letsencrypt/

# 备份配置文件
tar -czf "$BACKUP_DIR/ssl-config_$DATE.tar.gz" /opt/ssl-auto-renewal/config/

# 清理30天前的备份
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete

echo "备份完成: $BACKUP_DIR"
```

#### 恢复SSL证书

```bash
# 停止Web服务器
sudo systemctl stop nginx  # 或 apache2

# 恢复证书文件
sudo tar -xzf /backup/ssl-certificates/letsencrypt_YYYYMMDD_HHMMSS.tar.gz -C /

# 恢复配置文件
sudo tar -xzf /backup/ssl-certificates/ssl-config_YYYYMMDD_HHMMSS.tar.gz -C /

# 重启Web服务器
sudo systemctl start nginx  # 或 apache2
```

## 故障排除

### 常见问题

#### 1. 证书申请失败

**问题**: Certbot申请证书时失败

**解决方案**:
```bash
# 检查域名解析
nslookup your-domain.com

# 检查80端口是否开放
sudo netstat -tlnp | grep :80

# 检查Web服务器配置
sudo nginx -t  # 或 sudo apache2ctl configtest

# 手动测试证书申请
sudo certbot certonly --webroot -w /var/www/html -d your-domain.com --dry-run
```

#### 2. 邮件通知不工作

**问题**: 收不到邮件通知

**解决方案**:
```bash
# 检查邮件系统
sudo /opt/ssl-auto-renewal/scripts/notify.sh --check

# 测试系统邮件
echo "测试邮件" | mail -s "测试" your-email@domain.com

# 检查邮件日志
sudo tail -f /var/log/mail.log
```

#### 3. 定时任务不执行

**问题**: Cron任务没有按时执行

**解决方案**:
```bash
# 检查cron服务状态
sudo systemctl status cron

# 查看cron日志
sudo tail -f /var/log/syslog | grep CRON

# 检查crontab配置
sudo crontab -l

# 手动测试脚本
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh
```

#### 4. 权限问题

**问题**: 脚本执行时权限不足

**解决方案**:
```bash
# 检查文件权限
ls -la /opt/ssl-auto-renewal/scripts/

# 修复权限
sudo chmod +x /opt/ssl-auto-renewal/scripts/*.sh
sudo chown -R root:root /opt/ssl-auto-renewal/
```

### 日志分析

#### 查看详细错误信息

```bash
# 查看最近的错误
sudo tail -50 /opt/ssl-auto-renewal/logs/ssl-error.log

# 查看Let's Encrypt详细日志
sudo tail -100 /var/log/letsencrypt/letsencrypt.log

# 实时监控日志
sudo tail -f /opt/ssl-auto-renewal/logs/ssl-renew.log
```

#### 常见错误代码

- **Rate limit exceeded**: Let's Encrypt速率限制，等待一周后重试
- **DNS resolution failed**: 域名解析失败，检查DNS配置
- **Connection refused**: 无法连接到域名，检查防火墙和Web服务器
- **Validation failed**: 域名验证失败，检查webroot路径和权限

## 安全建议

### 1. 文件权限

```bash
# 设置适当的文件权限
sudo chmod 700 /opt/ssl-auto-renewal/scripts/
sudo chmod 600 /opt/ssl-auto-renewal/config/*.conf
sudo chmod 644 /opt/ssl-auto-renewal/logs/*.log
```

### 2. 定期更新

```bash
# 定期更新Certbot
sudo snap refresh certbot

# 更新系统包
sudo apt update && sudo apt upgrade
```

### 3. 监控访问

```bash
# 监控SSL证书目录访问
sudo auditctl -w /etc/letsencrypt/ -p rwxa -k ssl_access
```

### 4. 备份策略

- 每日备份SSL证书和配置文件
- 定期测试备份恢复流程
- 将备份存储在安全的异地位置

## 性能优化

### 1. 减少不必要的检查

```bash
# 修改检查频率，避免过于频繁的检查
# 编辑cron配置，将每日检查改为每周检查（对于稳定环境）
```

### 2. 并行处理

对于大量域名，可以修改脚本支持并行处理：

```bash
# 在ssl-renew.sh中添加并行处理逻辑
# 使用xargs -P 参数或GNU parallel
```

### 3. 缓存DNS查询

```bash
# 安装本地DNS缓存
sudo apt install dnsmasq
```

## 扩展功能

### 1. 支持通配符证书

```bash
# 修改domains.conf格式支持通配符
*.example.com:admin@example.com:dns-cloudflare
```

### 2. 多服务器同步

```bash
# 创建证书同步脚本
# 使用rsync或scp同步证书到其他服务器
```

### 3. 集成监控系统

```bash
# 集成Prometheus监控
# 创建metrics端点输出证书状态
```

## 总结

本部署指南涵盖了SSL证书自动续订系统的完整部署流程。按照本指南操作，你应该能够：

1. 成功部署SSL自动续订系统
2. 配置域名和邮件通知
3. 监控和维护证书状态
4. 处理常见问题和故障

如果在部署过程中遇到问题，请参考故障排除章节或查看相关日志文件。

定期检查系统状态，确保SSL证书能够正常续订，保障网站的安全性。