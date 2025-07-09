# SSL证书申请和配置指南

## 🔐 SSL证书文件路径说明

### Certbot自动创建的目录结构

当您使用Certbot申请SSL证书时，它会自动创建以下目录结构：

```
/etc/letsencrypt/
├── live/
│   └── example.com/           # 您的域名目录（自动创建）
│       ├── cert.pem           # 证书文件
│       ├── chain.pem          # 证书链文件
│       ├── fullchain.pem      # 完整证书链（cert.pem + chain.pem）
│       └── privkey.pem        # 私钥文件
├── archive/                   # 证书历史版本
├── renewal/                   # 续订配置
└── accounts/                  # Let's Encrypt账户信息
```

**重要**：您不需要手动创建这些文件夹，Certbot会自动处理！

## 🚀 正确的SSL证书申请流程

### 步骤1: 配置域名

首先在我们的系统中配置域名：

```bash
# 编辑域名配置文件
sudo nano /opt/ssl-auto-renewal/config/domains.conf

# 添加您的域名（替换example.com为您的实际域名）
example.com:/var/www/html
```

### 步骤2: 配置Nginx（申请证书前）

在申请证书之前，先配置基本的HTTP站点：

```bash
# 创建Nginx配置文件
sudo nano /etc/nginx/sites-available/example.com
```

**初始配置**（仅HTTP，用于证书验证）：
```nginx
server {
    listen 80;
    server_name example.com www.example.com;
    
    # Let's Encrypt验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    # 其他请求暂时返回简单页面
    location / {
        root /var/www/html;
        index index.html;
    }
}
```

```bash
# 启用站点
sudo ln -s /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 步骤3: 申请SSL证书

使用我们的自动化脚本申请证书：

```bash
# 测试模式（不会实际申请证书，用于验证配置）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 实际申请证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh
```

**或者手动使用Certbot**：
```bash
sudo certbot certonly \
  --webroot \
  -w /var/www/html \
  -d example.com \
  -d www.example.com \
  --email your-email@example.com \
  --agree-tos \
  --non-interactive
```

### 步骤4: 更新Nginx配置（添加HTTPS）

证书申请成功后，更新Nginx配置：

```bash
sudo nano /etc/nginx/sites-available/example.com
```

**完整配置**（HTTP + HTTPS）：
```nginx
# HTTP服务器 - 重定向到HTTPS
server {
    listen 80;
    server_name example.com www.example.com;
    
    # Let's Encrypt验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    # 其他请求重定向到HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS服务器
server {
    listen 443 ssl http2;
    server_name example.com www.example.com;
    
    # SSL证书配置（Certbot自动创建的文件）
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 网站根目录
    root /var/www/html;
    index index.html index.php;
    
    # 网站内容配置
    location / {
        try_files $uri $uri/ =404;
    }
    
    # PHP支持（如果需要）
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
}
```

```bash
# 测试配置并重新加载
sudo nginx -t
sudo systemctl reload nginx
```

## 🔍 验证SSL证书

### 检查证书文件

```bash
# 检查证书是否存在
ls -la /etc/letsencrypt/live/example.com/

# 查看证书详细信息
sudo openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -text -noout

# 检查证书有效期
sudo openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -noout -dates
```

### 使用我们的检查工具

```bash
# 检查特定域名证书
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh example.com

# 检查所有证书
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all
```

### 在线测试

访问以下网站测试SSL配置：
- https://www.ssllabs.com/ssltest/
- https://example.com（您的网站）

## ⚠️ 常见问题和解决方案

### 1. 域名解析问题

**问题**: 证书申请失败，提示域名无法访问

**解决方案**:
```bash
# 检查域名解析
nslookup example.com
dig example.com

# 确保域名指向您的服务器IP
ping example.com
```

### 2. 防火墙问题

**问题**: Let's Encrypt无法访问验证文件

**解决方案**:
```bash
# 确保80和443端口开放
sudo ufw allow 80
sudo ufw allow 443

# 或使用iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

### 3. Webroot权限问题

**问题**: 无法写入验证文件

**解决方案**:
```bash
# 确保webroot目录存在且权限正确
sudo mkdir -p /var/www/html/.well-known/acme-challenge
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```

### 4. 证书文件不存在

**问题**: Nginx启动失败，提示证书文件不存在

**解决方案**:
1. 先注释掉SSL配置，只保留HTTP
2. 申请证书成功后再启用SSL配置
3. 或者使用自签名证书作为临时方案

## 🔄 自动续订配置

我们的系统已经配置了自动续订：

```bash
# 查看cron任务
sudo crontab -l

# 手动测试续订
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 查看续订日志
sudo tail -f /opt/ssl-auto-renewal/logs/ssl-renew.log
```

## 📋 完整配置检查清单

- [ ] 域名已解析到服务器IP
- [ ] 防火墙已开放80和443端口
- [ ] Nginx基本HTTP配置已完成
- [ ] 域名已添加到domains.conf
- [ ] 证书申请成功
- [ ] Nginx HTTPS配置已更新
- [ ] SSL证书测试通过
- [ ] 自动续订功能正常

## 🎯 总结

**重点**：您不需要手动创建`/etc/letsencrypt/live/example.com/`目录，Certbot会在申请证书时自动创建所有必要的文件和目录。

**正确流程**：
1. 配置域名解析
2. 配置基本HTTP站点
3. 使用我们的脚本申请证书
4. 更新Nginx配置添加HTTPS
5. 测试和验证

这样可以确保SSL证书申请和配置过程顺利完成！