# SMTP邮件配置指南

本指南详细说明如何配置外部SMTP服务器，特别是腾讯企业邮箱的配置方法。

## 🚀 快速配置

### 腾讯企业邮箱一键配置

使用配置向导快速设置腾讯企业邮箱：

```bash
sudo /opt/ssl-auto-renewal/scripts/test-smtp.sh --setup-tencent
```

按照提示输入：
- 企业邮箱地址
- 邮箱密码
- 通知接收邮箱（可选，默认使用发件邮箱）

## 📧 支持的邮件服务商

### 腾讯企业邮箱

```bash
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.exmail.qq.com"
SMTP_PORT="465"
SMTP_USE_TLS=false
SMTP_USE_SSL=true
SMTP_USERNAME="your-email@yourcompany.com"
SMTP_PASSWORD="your-password"
SMTP_FROM_EMAIL="your-email@yourcompany.com"
SMTP_FROM_NAME="SSL证书自动续订系统"
```

### QQ邮箱

```bash
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.qq.com"
SMTP_PORT="587"
SMTP_USE_TLS=true
SMTP_USE_SSL=false
SMTP_USERNAME="your-email@qq.com"
SMTP_PASSWORD="your-authorization-code"  # 使用授权码，不是QQ密码
```

### Gmail

```bash
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USE_TLS=true
SMTP_USE_SSL=false
SMTP_USERNAME="your-email@gmail.com"
SMTP_PASSWORD="your-app-password"  # 使用应用专用密码
```

### 163邮箱

```bash
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.163.com"
SMTP_PORT="587"
SMTP_USE_TLS=true
SMTP_USE_SSL=false
SMTP_USERNAME="your-email@163.com"
SMTP_PASSWORD="your-authorization-code"  # 使用授权码
```

### 阿里云邮箱

```bash
USE_EXTERNAL_SMTP=true
SMTP_SERVER="smtp.mxhichina.com"
SMTP_PORT="587"
SMTP_USE_TLS=true
SMTP_USE_SSL=false
SMTP_USERNAME="your-email@yourdomain.com"
SMTP_PASSWORD="your-password"
```

## 🔧 手动配置步骤

### 1. 编辑配置文件

```bash
sudo nano /opt/ssl-auto-renewal/config/email.conf
```

### 2. 基本设置

```bash
# 启用邮件通知
ENABLE_EMAIL_NOTIFICATION=true

# 通知接收邮箱
NOTIFICATION_EMAIL="admin@yourcompany.com"

# 邮件主题前缀
EMAIL_SUBJECT_PREFIX="[SSL续订通知]"
```

### 3. SMTP服务器配置

```bash
# 启用外部SMTP
USE_EXTERNAL_SMTP=true

# SMTP服务器设置
SMTP_SERVER="smtp.exmail.qq.com"
SMTP_PORT="465"
SMTP_USERNAME="ssl-notify@yourcompany.com"
SMTP_PASSWORD="your-secure-password"

# 加密设置
SMTP_USE_TLS=false  # 对于465端口，通常使用SSL
SMTP_USE_SSL=true   # 腾讯企业邮箱推荐使用SSL

# 发件人信息
SMTP_FROM_EMAIL="ssl-notify@yourcompany.com"
SMTP_FROM_NAME="SSL证书自动续订系统"
```

### 4. 高级设置

```bash
# 邮件重试设置
ENABLE_EMAIL_RETRY=true
EMAIL_RETRY_COUNT=3
EMAIL_RETRY_INTERVAL=60

# 日志设置
ENABLE_EMAIL_LOGGING=true
EMAIL_LOG_FILE="/opt/ssl-auto-renewal/logs/email.log"

# 通知类型
NOTIFY_ON_SUCCESS=true
NOTIFY_ON_FAILURE=true
NOTIFY_ON_EXPIRING=true
EXPIRY_NOTIFICATION_DAYS=7
```

## 🧪 测试配置

### 使用测试工具

```bash
# 查看当前配置
sudo /opt/ssl-auto-renewal/scripts/test-smtp.sh --config

# 测试邮件发送
sudo /opt/ssl-auto-renewal/scripts/test-smtp.sh --test

# 测试发送到指定邮箱
sudo /opt/ssl-auto-renewal/scripts/test-smtp.sh --test admin@example.com
```

### 使用通知脚本

```bash
# 发送测试邮件
sudo /opt/ssl-auto-renewal/scripts/notify.sh --test

# 检查邮件系统
sudo /opt/ssl-auto-renewal/scripts/notify.sh --check

# 发送状态报告
sudo /opt/ssl-auto-renewal/scripts/notify.sh --status
```

## 🔍 故障排除

### 常见问题

#### 1. 认证失败

**问题**: `Authentication failed` 或 `535 Error`

**解决方案**:
- 检查用户名和密码是否正确
- 对于QQ邮箱、Gmail等，需要使用授权码而不是登录密码
- 确认邮箱已开启SMTP服务

#### 2. 连接超时

**问题**: `Connection timed out` 或 `Network unreachable`

**解决方案**:
- 检查服务器防火墙是否开放SMTP端口
- 确认SMTP服务器地址和端口正确
- 检查网络连接

#### 3. 邮件被拒绝（From头部问题）

**问题**: `Messages missing a valid address in From: header` 或 `550 5.7.1`

**解决方案**:
- 确保`SMTP_FROM_EMAIL`与`SMTP_USERNAME`一致
- 使用英文发件人名称，避免特殊字符
- 检查邮件头部格式是否符合RFC 5322规范

**正确配置示例**:
```bash
SMTP_USERNAME="ssl-notify@yourcompany.com"
SMTP_FROM_EMAIL="ssl-notify@yourcompany.com"  # 必须与SMTP_USERNAME相同
SMTP_FROM_NAME="SSL Auto Renewal System"      # 使用英文名称
```

#### 4. SSL/TLS错误

**问题**: `SSL handshake failed` 或 `Certificate verify failed`

**解决方案**:
- 检查SSL/TLS设置是否正确
- 腾讯企业邮箱465端口使用SSL，不使用TLS
- Gmail、QQ邮箱587端口使用TLS，不使用SSL

#### 4. Python依赖问题

**问题**: `ModuleNotFoundError` 或 `ImportError`

**解决方案**:
```bash
# 安装Python3和pip
sudo apt update
sudo apt install python3 python3-pip

# 安装邮件发送依赖
pip3 install smtplib email
```

### 调试模式

启用详细日志查看问题：

```bash
# 查看邮件发送日志
sudo tail -f /opt/ssl-auto-renewal/logs/email.log

# 查看系统日志
sudo tail -f /opt/ssl-auto-renewal/logs/notify.log

# 手动测试Python SMTP脚本
sudo python3 /opt/ssl-auto-renewal/scripts/smtp-send.py \
  --server smtp.exmail.qq.com \
  --port 465 \
  --username your-email@company.com \
  --password your-password \
  --use-ssl \
  --from-email your-email@company.com \
  --to admin@company.com \
  --subject "测试邮件" \
  --debug
```

## 📋 配置检查清单

- [ ] 邮件通知已启用 (`ENABLE_EMAIL_NOTIFICATION=true`)
- [ ] 通知邮箱已配置 (`NOTIFICATION_EMAIL`)
- [ ] 外部SMTP已启用 (`USE_EXTERNAL_SMTP=true`)
- [ ] SMTP服务器信息正确 (`SMTP_SERVER`, `SMTP_PORT`)
- [ ] 认证信息正确 (`SMTP_USERNAME`, `SMTP_PASSWORD`)
- [ ] 加密设置正确 (`SMTP_USE_TLS`, `SMTP_USE_SSL`)
- [ ] 发件人信息已设置 (`SMTP_FROM_EMAIL`)
- [ ] 测试邮件发送成功
- [ ] 日志记录正常

## 🔐 安全建议

1. **使用专用邮箱**: 为SSL证书通知创建专用的邮箱账户
2. **强密码**: 使用复杂的密码或授权码
3. **权限控制**: 限制配置文件的访问权限
4. **定期更新**: 定期更换邮箱密码
5. **监控日志**: 定期检查邮件发送日志

```bash
# 设置配置文件权限
sudo chmod 600 /opt/ssl-auto-renewal/config/email.conf
sudo chown root:root /opt/ssl-auto-renewal/config/email.conf
```

## 📞 技术支持

如果遇到配置问题，请：

1. 查看日志文件获取详细错误信息
2. 使用测试工具验证配置
3. 参考邮件服务商的SMTP配置文档
4. 检查服务器网络和防火墙设置

---

*本文档持续更新，如有问题请及时反馈。*