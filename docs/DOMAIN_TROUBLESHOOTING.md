# 域名验证失败故障排除指南

## 🚨 您遇到的问题分析

根据错误日志，域名 `zhangmingrui.top` 的SSL证书申请失败，具体问题：

```
Domain: zhangmingrui.top
Type: unauthorized
Detail: 43.152.2.144: Invalid response from https://dnspod.qcloud.com/static/webblock.html?d=zhangmingrui.top
```

**问题原因**：Let's Encrypt尝试访问您的域名进行验证时，被重定向到了DNSPod的拦截页面，这表明：

1. **域名被DNS服务商拦截** - DNSPod可能认为域名存在安全风险
2. **DNS解析配置问题** - 域名可能没有正确指向您的服务器
3. **Web服务器配置问题** - Nginx配置可能有误

## 🔍 立即诊断

使用我们的域名检查工具进行详细诊断：

```bash
# 检查您的域名配置
sudo /opt/ssl-auto-renewal/scripts/domain-check.sh --domain zhangmingrui.top --webroot /var/www/html

# 或检查所有配置的域名
sudo /opt/ssl-auto-renewal/scripts/domain-check.sh --all
```

## 🛠️ 解决方案

### 1. 检查DNS解析

```bash
# 检查域名解析
dig zhangmingrui.top
nslookup zhangmingrui.top

# 检查您的服务器IP
curl ifconfig.me
```

**确保**：
- 域名的A记录指向您的服务器IP (43.152.2.144)
- DNS传播已完成（可能需要几分钟到几小时）

### 2. 联系DNS服务商

由于错误显示访问被重定向到DNSPod拦截页面，您需要：

1. **登录DNSPod控制台**
2. **检查域名状态** - 查看是否有安全拦截提示
3. **联系DNSPod客服** - 申请解除域名拦截
4. **提供证明材料** - 证明域名用于合法用途

### 3. 临时解决方案 - 更换DNS服务商

如果DNSPod拦截无法快速解除，可以临时更换DNS服务商：

**推荐的DNS服务商**：
- 阿里云DNS
- 腾讯云DNS
- Cloudflare
- 华为云DNS

### 4. 检查Web服务器配置

确保Nginx配置正确：

```bash
# 创建基本的Nginx配置
sudo nano /etc/nginx/sites-available/zhangmingrui.top
```

**基本配置内容**：
```nginx
server {
    listen 80;
    server_name zhangmingrui.top www.zhangmingrui.top;
    
    root /var/www/html;
    index index.html;
    
    # Let's Encrypt验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    location / {
        try_files $uri $uri/ =404;
    }
}
```

```bash
# 启用站点配置
sudo ln -s /etc/nginx/sites-available/zhangmingrui.top /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 5. 创建测试页面

```bash
# 创建基本的网站内容
sudo mkdir -p /var/www/html
echo "<h1>Welcome to zhangmingrui.top</h1>" | sudo tee /var/www/html/index.html

# 设置正确的权限
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```

### 6. 测试HTTP访问

```bash
# 本地测试
curl -I http://zhangmingrui.top/

# 测试Let's Encrypt验证路径
mkdir -p /var/www/html/.well-known/acme-challenge/
echo "test" | sudo tee /var/www/html/.well-known/acme-challenge/test
curl http://zhangmingrui.top/.well-known/acme-challenge/test
```

## 🔄 重新申请证书

完成上述修复后，重新申请证书：

```bash
# 1. 先测试配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 2. 如果测试通过，申请真实证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh

# 3. 检查证书状态
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh zhangmingrui.top
```

## 🆘 紧急备选方案

如果DNS拦截问题无法快速解决，可以考虑：

### 1. 使用子域名

```bash
# 在domains.conf中添加子域名
ssl.zhangmingrui.top:/var/www/html
www.zhangmingrui.top:/var/www/html
```

### 2. 使用其他域名

如果您有其他域名，可以先用其他域名测试SSL证书申请流程。

### 3. 使用DNS验证方式

修改ssl-renew.sh脚本，使用DNS验证而不是HTTP验证：

```bash
# 手动使用DNS验证
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d zhangmingrui.top \
  --email lovisnd@zhangmingrui.top \
  --agree-tos
```

## 📞 获取帮助

### DNSPod客服联系方式
- 官网：https://www.dnspod.cn/
- 客服电话：查看官网客服页面
- 工单系统：登录控制台提交工单

### 常见拦截原因
1. **新域名** - 刚注册的域名可能被临时拦截
2. **内容检测** - 域名内容被误判为违规
3. **安全策略** - DNS服务商的安全策略触发
4. **域名历史** - 域名之前可能被滥用过

## 📋 检查清单

完成以下检查后再次尝试申请证书：

- [ ] 域名DNS解析正确指向服务器IP
- [ ] DNS服务商没有拦截域名
- [ ] Nginx配置正确且服务运行正常
- [ ] HTTP访问测试通过
- [ ] 防火墙开放80和443端口
- [ ] webroot目录权限正确
- [ ] Let's Encrypt验证路径可访问

## 🎯 预期结果

修复完成后，您应该看到类似这样的成功输出：

```
[INFO] 开始处理域名: zhangmingrui.top
[INFO] 运行测试模式（dry-run）
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Account registered.
Simulating a certificate request for zhangmingrui.top
The dry run was successful.
[SUCCESS] 域名 zhangmingrui.top 的证书申请/续订成功
```

---

**重要提醒**：DNS拦截问题通常需要联系DNS服务商解决，这可能需要1-3个工作日。建议同时准备备选方案以确保项目进度。