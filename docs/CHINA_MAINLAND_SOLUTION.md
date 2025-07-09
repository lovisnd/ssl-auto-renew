# 🇨🇳 中国大陆服务器未备案域名SSL证书解决方案

## 🚨 问题分析

您的域名 `zhangmingrui.top` 在中国大陆服务器上未备案，导致：
- HTTP访问被重定向到备案拦截页面
- Let's Encrypt的HTTP验证无法通过
- 无法使用webroot验证方式申请SSL证书

## 🛠️ 解决方案

### 方案1：使用DNS验证方式（推荐）

DNS验证不需要HTTP访问，完全绕过备案限制。

#### 1.1 手动DNS验证

```bash
# 使用DNS验证申请证书
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d zhangmingrui.top \
  -d www.zhangmingrui.top \
  --email lovisnd@zhangmingrui.top \
  --agree-tos \
  --no-eff-email
```

**操作步骤**：
1. 运行上述命令
2. Certbot会提示您添加DNS TXT记录
3. 登录您的DNS管理面板（DNSPod）
4. 添加指定的TXT记录
5. 等待DNS传播（通常1-5分钟）
6. 按回车继续验证

#### 1.2 自动化DNS验证脚本

让我创建一个支持DNS验证的SSL续订脚本：

```bash
# 创建DNS验证配置
sudo nano /opt/ssl-auto-renewal/config/dns-config.conf
```

**配置内容**：
```bash
# DNS验证配置
USE_DNS_VALIDATION=true
DNS_PROVIDER="manual"  # 手动模式
DOMAINS_DNS="zhangmingrui.top,www.zhangmingrui.top"
```

### 方案2：使用海外服务器中转

#### 2.1 设置反向代理

如果您有海外服务器，可以设置反向代理：

```nginx
# 海外服务器Nginx配置
server {
    listen 80;
    server_name zhangmingrui.top www.zhangmingrui.top;
    
    # Let's Encrypt验证路径
    location /.well-known/acme-challenge/ {
        proxy_pass http://your-china-server-ip/.well-known/acme-challenge/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}
```

#### 2.2 临时DNS切换

1. 申请证书时，将DNS A记录指向海外服务器
2. 完成证书申请后，切换回中国大陆服务器
3. 使用定时任务在续订时自动切换

### 方案3：使用Cloudflare代理

#### 3.1 启用Cloudflare代理

1. 将域名DNS托管到Cloudflare
2. 启用橙色云朵（代理模式）
3. 设置SSL/TLS模式为"完全"或"完全（严格）"

#### 3.2 Cloudflare Origin证书

```bash
# 使用Cloudflare Origin证书
# 在Cloudflare面板生成Origin证书
# 直接安装到Nginx，无需Let's Encrypt
```

### 方案4：使用ACME DNS API

如果DNS提供商支持API，可以使用自动化DNS验证：

#### 4.1 DNSPod API配置

```bash
# 安装acme.sh（支持DNSPod API）
curl https://get.acme.sh | sh
source ~/.bashrc

# 配置DNSPod API
export DP_Id="your-dnspod-id"
export DP_Key="your-dnspod-key"

# 申请证书
acme.sh --issue --dns dns_dp -d zhangmingrui.top -d www.zhangmingrui.top
```

## 🔧 实施步骤

### 立即可用的DNS验证方案

#### 步骤1：使用DNS验证脚本申请证书

```bash
# 为您的域名申请SSL证书（手动DNS验证）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain zhangmingrui.top --manual

# 测试模式（推荐先运行）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain zhangmingrui.top --manual --test
```

#### 步骤2：添加DNS TXT记录

当脚本运行时，会提示您添加DNS TXT记录：

1. **登录DNSPod控制台**：https://console.dnspod.cn/
2. **选择域名**：zhangmingrui.top
3. **添加TXT记录**：
   - 记录类型：TXT
   - 主机记录：_acme-challenge
   - 记录值：（脚本会显示具体值）
   - TTL：600秒

4. **验证记录生效**：
   ```bash
   dig +short TXT _acme-challenge.zhangmingrui.top
   ```

5. **确认后按回车继续**

#### 步骤3：配置Nginx使用新证书

证书申请成功后，配置Nginx：

```bash
# 创建SSL配置
sudo nano /etc/nginx/sites-available/zhangmingrui.top
```

**Nginx配置内容**：
```nginx
server {
    listen 80;
    server_name zhangmingrui.top www.zhangmingrui.top;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name zhangmingrui.top www.zhangmingrui.top;
    
    # SSL证书配置
    ssl_certificate /etc/letsencrypt/live/zhangmingrui.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/zhangmingrui.top/privkey.pem;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 网站根目录
    root /var/www/html;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
```

```bash
# 启用配置并重启Nginx
sudo ln -s /etc/nginx/sites-available/zhangmingrui.top /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### 步骤4：设置自动续订

由于DNS验证需要手动操作，建议设置提醒：

```bash
# 创建续订提醒脚本
sudo nano /opt/ssl-auto-renewal/scripts/dns-renewal-reminder.sh
```

**提醒脚本内容**：
```bash
#!/bin/bash
# DNS证书续订提醒脚本

DOMAIN="zhangmingrui.top"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/cert.pem"

if [[ -f "$CERT_PATH" ]]; then
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
    EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_TIMESTAMP=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / 86400 ))
    
    if [[ $DAYS_UNTIL_EXPIRY -lt 30 ]]; then
        echo "警告：域名 $DOMAIN 的SSL证书将在 $DAYS_UNTIL_EXPIRY 天后过期"
        echo "请运行以下命令续订证书："
        echo "sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain $DOMAIN --manual"
        
        # 发送邮件提醒（如果配置了邮件）
        if [[ -f "/opt/ssl-auto-renewal/scripts/notify.sh" ]]; then
            /opt/ssl-auto-renewal/scripts/notify.sh --warning --domain "$DOMAIN" --message "SSL证书将在${DAYS_UNTIL_EXPIRY}天后过期，请手动续订"
        fi
    fi
fi
```

```bash
# 设置权限
sudo chmod +x /opt/ssl-auto-renewal/scripts/dns-renewal-reminder.sh

# 添加到定时任务（每周检查一次）
(crontab -l 2>/dev/null; echo "0 9 * * 1 /opt/ssl-auto-renewal/scripts/dns-renewal-reminder.sh") | crontab -
```

## 🚀 快速操作指南

### 立即执行（推荐）

```bash
# 1. 测试DNS验证
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain zhangmingrui.top --manual --test

# 2. 如果测试通过，申请真实证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns.sh --domain zhangmingrui.top --manual

# 3. 配置Nginx（使用上面的配置）
sudo nano /etc/nginx/sites-available/zhangmingrui.top

# 4. 启用配置
sudo ln -s /etc/nginx/sites-available/zhangmingrui.top /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 5. 测试HTTPS访问
curl -I https://zhangmingrui.top/
```

## 🔄 替代方案

### 方案A：使用acme.sh + DNSPod API

如果您有DNSPod API密钥，可以实现全自动化：

```bash
# 安装acme.sh
curl https://get.acme.sh | sh
source ~/.bashrc

# 配置DNSPod API
export DP_Id="your-dnspod-id"
export DP_Key="your-dnspod-key"

# 申请证书
acme.sh --issue --dns dns_dp -d zhangmingrui.top -d www.zhangmingrui.top

# 安装证书到Nginx
acme.sh --install-cert -d zhangmingrui.top \
  --key-file /etc/nginx/ssl/zhangmingrui.top.key \
  --fullchain-file /etc/nginx/ssl/zhangmingrui.top.crt \
  --reloadcmd "systemctl reload nginx"
```

### 方案B：使用Cloudflare代理

1. **将域名DNS托管到Cloudflare**
2. **启用代理模式**（橙色云朵）
3. **设置SSL模式为"完全"**
4. **使用Cloudflare Origin证书**

### 方案C：临时海外服务器

如果您有海外VPS，可以：
1. 在海外服务器申请证书
2. 下载证书文件
3. 上传到中国大陆服务器
4. 配置Nginx使用证书

## ⚠️ 注意事项

1. **DNS验证需要手动操作**，无法完全自动化（除非使用API）
2. **证书续订提醒很重要**，建议设置多重提醒
3. **备份证书文件**，以防意外丢失
4. **监控证书过期时间**，提前30天开始续订流程

## 📞 获取DNSPod API密钥

1. 登录DNSPod控制台：https://console.dnspod.cn/
2. 进入"API密钥管理"
3. 创建新的API密钥
4. 记录ID和Key用于自动化脚本

---

**总结**：DNS验证是未备案域名在中国大陆服务器申请SSL证书的最佳解决方案，虽然需要手动操作，但可以完全绕过备案限制。