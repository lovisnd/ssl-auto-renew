# 🚀 DNS API自动化SSL证书申请指南

## 🎯 完全自动化解决方案

既然您的DNS支持API自动配置，我们可以实现完全自动化的SSL证书申请和续订，无需任何手动操作！

## 🛠️ 支持的DNS服务商

- **DNSPod** (腾讯云DNS) - 推荐
- **阿里云DNS**
- **Cloudflare**
- **腾讯云DNS**
- **华为云DNS**

## 🚀 快速开始

### 步骤1：配置DNS API

根据您的DNS服务商选择对应的配置命令：

#### DNSPod (推荐，适合您的域名)
```bash
# 配置DNSPod API
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod
```

#### 其他服务商
```bash
# 阿里云DNS
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider aliyun

# Cloudflare
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider cloudflare

# 腾讯云DNS
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider tencent
```

### 步骤2：获取API密钥

#### DNSPod API密钥获取
1. 访问：https://console.dnspod.cn/account/token
2. 点击"创建密钥"
3. 记录下ID和Token

#### 其他服务商API密钥
- **阿里云**：https://ram.console.aliyun.com/manage/ak
- **Cloudflare**：https://dash.cloudflare.com/profile/api-tokens
- **腾讯云**：https://console.cloud.tencent.com/cam/capi

### 步骤3：测试配置

```bash
# 检查API配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --check-config

# 测试证书申请
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top --test
```

### 步骤4：申请证书

```bash
# 申请真实证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top
```

## 📋 详细配置步骤

### DNSPod配置示例

```bash
# 1. 运行配置向导
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod

# 向导会提示输入：
# - DNSPod ID: 您的API ID
# - DNSPod Key: 您的API Token
# - 默认邮箱: 用于Let's Encrypt通知

# 2. 检查配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --check-config

# 3. 测试申请
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top --test

# 4. 正式申请
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top
```

## 🔄 自动续订设置

### 更新定时任务

将原来的手动续订改为自动续订：

```bash
# 移除旧的定时任务
crontab -l | grep -v ssl-renew.sh | crontab -

# 添加新的自动续订任务
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh >> /opt/ssl-auto-renewal/logs/cron.log 2>&1") | crontab -

# 验证定时任务
crontab -l
```

### 批量域名配置

编辑域名配置文件：
```bash
sudo nano /opt/ssl-auto-renewal/config/domains.conf
```

添加您的域名：
```
zhangmingrui.top:lovisnd@zhangmingrui.top:/var/www/html
www.zhangmingrui.top:lovisnd@zhangmingrui.top:/var/www/html
```

然后运行批量续订：
```bash
# 测试所有域名
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --test

# 申请所有域名的证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh
```

## 🎯 完整的自动化流程

### 一次性设置
```bash
# 1. 配置DNS API
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod

# 2. 配置域名列表
sudo nano /opt/ssl-auto-renewal/config/domains.conf
# 添加: zhangmingrui.top:lovisnd@zhangmingrui.top:/var/www/html

# 3. 测试配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --test

# 4. 申请证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh

# 5. 设置自动续订
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh >> /opt/ssl-auto-renewal/logs/cron.log 2>&1") | crontab -
```

### 日常运维
- **完全自动化**：证书会自动续订，无需人工干预
- **邮件通知**：续订成功/失败会自动发送邮件
- **日志监控**：查看 `/opt/ssl-auto-renewal/logs/ssl-renew-dns-auto.log`

## 🔧 配置文件说明

DNS API配置文件位置：`/opt/ssl-auto-renewal/config/dns-api.conf`

```bash
# DNS服务商类型
DNS_PROVIDER="dnspod"

# DNSPod配置
DNSPOD_ID="your-id"
DNSPOD_KEY="your-key"

# 默认邮箱
DEFAULT_EMAIL="lovisnd@zhangmingrui.top"
```

## 🚨 安全注意事项

1. **API密钥安全**：
   ```bash
   # 设置配置文件权限
   sudo chmod 600 /opt/ssl-auto-renewal/config/dns-api.conf
   sudo chown root:root /opt/ssl-auto-renewal/config/dns-api.conf
   ```

2. **定期检查**：
   ```bash
   # 检查证书状态
   sudo /opt/ssl-auto-renewal/scripts/check-ssl.sh --all
   
   # 查看续订日志
   tail -f /opt/ssl-auto-renewal/logs/ssl-renew-dns-auto.log
   ```

## 📊 监控和维护

### 实时监控
```bash
# 查看续订日志
tail -f /opt/ssl-auto-renewal/logs/ssl-renew-dns-auto.log

# 检查定时任务
crontab -l

# 测试邮件通知
sudo /opt/ssl-auto-renewal/scripts/notify.sh --test
```

### 手动续订
```bash
# 强制续订所有证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --force

# 续订特定域名
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top
```

## 🎉 优势总结

✅ **完全自动化** - 无需手动操作  
✅ **支持多域名** - 批量管理  
✅ **安全可靠** - API方式验证  
✅ **实时通知** - 邮件提醒  
✅ **详细日志** - 便于排查  
✅ **定时续订** - 永不过期  

## 🆘 故障排除

### 常见问题

**API配置错误**
```bash
# 重新配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod

# 检查配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --check-config
```

**证书申请失败**
```bash
# 查看详细日志
tail -50 /opt/ssl-auto-renewal/logs/ssl-renew-dns-auto.log

# 测试模式排查
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top --test
```

**定时任务不执行**
```bash
# 检查cron服务
sudo systemctl status cron

# 手动测试脚本
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --test
```

---

**总结**：DNS API自动化是未备案域名在中国大陆服务器申请SSL证书的最佳解决方案，实现了完全自动化的证书管理！