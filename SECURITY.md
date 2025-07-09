# 🛡️ 安全部署指南

本文档提供SSL证书自动续订系统的安全配置和最佳实践指南。

## 📋 安全检查清单

### ✅ 部署前检查

- [ ] 已复制 `.example` 配置文件为实际配置文件
- [ ] 已填入真实的API密钥和邮箱信息
- [ ] 已设置适当的文件权限 (600)
- [ ] 已确认 `.gitignore` 包含敏感配置文件
- [ ] 已测试邮件通知功能
- [ ] 已验证DNS API配置正确

### ✅ 运行时检查

- [ ] 定期轮换API密钥
- [ ] 监控日志文件，确保无敏感信息泄露
- [ ] 定期检查文件权限
- [ ] 备份配置文件到安全位置

## 🔐 敏感信息保护

### 配置文件权限设置

```bash
# 设置配置文件权限（仅所有者可读写）
sudo chmod 600 /opt/ssl-auto-renewal/config/dns-api.conf
sudo chmod 600 /opt/ssl-auto-renewal/config/email.conf
sudo chmod 644 /opt/ssl-auto-renewal/config/domains.conf

# 设置目录权限
sudo chmod 755 /opt/ssl-auto-renewal/config/
sudo chown -R root:root /opt/ssl-auto-renewal/config/
```

### Git版本控制安全

项目已配置 `.gitignore` 文件，自动排除以下敏感文件：

```gitignore
# 敏感配置文件
config/dns-api.conf
config/email.conf

# 日志文件
logs/
*.log

# 证书文件
*.pem
*.crt
*.key

# acme.sh相关文件
.acme.sh/
```

## 🔑 API密钥管理

### DNS服务商API密钥

不同DNS服务商的API密钥权限说明：

| 服务商 | 权限范围 | 安全建议 |
|--------|----------|----------|
| Cloudflare | 域名DNS记录管理 | 使用API Token而非Global API Key |
| 阿里云DNS | 域名解析管理 | 创建子账号，仅授予DNS权限 |
| 腾讯云DNS | 域名解析管理 | 使用子账号，最小权限原则 |
| DNSPod | 域名记录管理 | 定期轮换密钥 |

### API密钥轮换

建议每3-6个月轮换一次API密钥：

```bash
# 1. 在DNS服务商控制台生成新密钥
# 2. 更新配置文件
sudo nano /opt/ssl-auto-renewal/config/dns-api.conf

# 3. 测试新配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain test.com --test

# 4. 删除旧密钥
```

## 📧 邮件安全配置

### SMTP认证

使用外部SMTP服务器时的安全建议：

```bash
# 腾讯企业邮箱安全配置
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.exmail.qq.com"
SMTP_PORT="465"
SMTP_USE_SSL=true  # 使用SSL加密
SMTP_USERNAME="ssl-notify@yourcompany.com"  # 专用邮箱
SMTP_PASSWORD="app-specific-password"  # 应用专用密码
```

### 邮件内容安全

- ✅ 不在邮件中包含完整的错误信息
- ✅ 不在邮件中显示API密钥或敏感路径
- ✅ 使用专用的通知邮箱账号
- ✅ 启用邮件加密传输

## 🚨 安全事件响应

### 密钥泄露处理

如果怀疑API密钥泄露：

1. **立即行动**
   ```bash
   # 停止相关服务
   sudo systemctl stop cron
   
   # 禁用定时任务
   sudo crontab -r
   ```

2. **更换密钥**
   - 在DNS服务商控制台立即删除泄露的密钥
   - 生成新的API密钥
   - 更新配置文件

3. **检查影响**
   ```bash
   # 检查最近的DNS记录变更
   # 检查证书申请日志
   tail -100 /opt/ssl-auto-renewal/logs/ssl-renew.log
   ```

4. **恢复服务**
   ```bash
   # 测试新配置
   sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --test
   
   # 重新启用定时任务
   sudo crontab -e
   ```

### 日志监控

定期检查以下日志文件：

```bash
# SSL续订日志
sudo tail -f /opt/ssl-auto-renewal/logs/ssl-renew.log

# 错误日志
sudo tail -f /opt/ssl-auto-renewal/logs/ssl-error.log

# 邮件发送日志
sudo tail -f /opt/ssl-auto-renewal/logs/email.log

# 系统日志
sudo journalctl -u cron -f
```

## 🔒 网络安全

### 防火墙配置

确保只开放必要的端口：

```bash
# 检查当前防火墙状态
sudo ufw status

# 只允许必要端口
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP (证书验证需要)
sudo ufw allow 443/tcp  # HTTPS
```

### SSL/TLS配置

确保Web服务器使用安全的SSL配置：

```nginx
# Nginx安全配置示例
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
add_header Strict-Transport-Security "max-age=63072000" always;
```

## 📝 安全审计

### 定期安全检查

建议每月执行以下安全检查：

```bash
# 1. 检查文件权限
find /opt/ssl-auto-renewal -type f -exec ls -la {} \;

# 2. 检查配置文件内容（确保无明文密码）
sudo grep -r "password\|key\|secret" /opt/ssl-auto-renewal/config/

# 3. 检查日志文件大小
du -sh /opt/ssl-auto-renewal/logs/*

# 4. 验证证书有效性
sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all
```

### 备份策略

```bash
# 创建配置备份（加密存储）
sudo tar -czf ssl-config-backup-$(date +%Y%m%d).tar.gz \
  /opt/ssl-auto-renewal/config/

# 使用GPG加密备份
gpg --symmetric --cipher-algo AES256 ssl-config-backup-*.tar.gz
```

## 📞 安全支持

如果发现安全问题或需要安全相关支持：

1. 🔍 首先查看本安全指南
2. 📖 检查项目文档和日志
3. 🐛 通过GitHub Issues报告安全问题
4. 📧 对于严重安全问题，请私下联系维护者

---

⚠️ **重要提醒**: 安全是一个持续的过程，请定期审查和更新您的安全配置。