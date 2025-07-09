# DNS API快速设置指南

## 概述

由于您的域名 `zhangmingrui.top` 在中国大陆未备案，无法使用HTTP验证方式申请SSL证书。本指南将帮助您快速配置DNS API验证方式。

## 第一步：选择DNS服务商

根据您域名的DNS解析服务商，选择对应的配置方式：

### 支持的DNS服务商

- **DNSPod** (腾讯云DNS) - 推荐
- **阿里云DNS**
- **Cloudflare** - 推荐
- **腾讯云DNS**
- **华为云DNS**

## 第二步：获取API密钥

### DNSPod (推荐)

1. 访问：https://console.dnspod.cn/account/token
2. 创建API Token
3. 记录 `ID` 和 `Token`

### Cloudflare (推荐)

1. 访问：https://dash.cloudflare.com/profile/api-tokens
2. 创建API Token 或使用Global API Key
3. 记录邮箱和API Key

### 阿里云DNS

1. 访问：https://ram.console.aliyun.com/manage/ak
2. 创建AccessKey
3. 记录 `AccessKey ID` 和 `AccessKey Secret`

## 第三步：配置DNS API

### 方法1：使用配置向导（推荐）

```bash
# DNSPod配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod

# Cloudflare配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider cloudflare

# 阿里云配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider aliyun
```

### 方法2：手动编辑配置文件

编辑配置文件：
```bash
sudo nano /opt/ssl-auto-renewal/config/dns-api.conf
```

#### DNSPod配置示例：
```bash
DNS_PROVIDER="dnspod"
DNSPOD_ID="你的DNSPod_ID"
DNSPOD_KEY="你的DNSPod_Token"
DEFAULT_EMAIL="your-email@example.com"
```

#### Cloudflare配置示例：
```bash
DNS_PROVIDER="cloudflare"
CLOUDFLARE_EMAIL="your-email@example.com"
CLOUDFLARE_API_KEY="你的Cloudflare_API_Key"
DEFAULT_EMAIL="your-email@example.com"
```

## 第四步：测试配置

```bash
# 1. 检查配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --check-config

# 2. 测试Cloudflare API连接（推荐先测试）
/opt/ssl-auto-renewal/scripts/test-cloudflare-api.sh zhangmingrui.top

# 3. 测试申请证书（推荐使用用户模式，避免sudo警告）
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --test

# 或使用原脚本（可能有sudo警告）
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top --test
```

## 第五步：申请正式证书

### 方法1：用户模式申请（推荐）

```bash
# 以普通用户身份申请证书（避免acme.sh的sudo警告）
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --provider cloudflare

# 然后以root权限安装证书（脚本会提示具体命令）
sudo ~/.acme.sh/acme.sh --install-cert -d zhangmingrui.top \
    --key-file /etc/letsencrypt/live/zhangmingrui.top/privkey.pem \
    --fullchain-file /etc/letsencrypt/live/zhangmingrui.top/fullchain.pem \
    --cert-file /etc/letsencrypt/live/zhangmingrui.top/cert.pem \
    --ca-file /etc/letsencrypt/live/zhangmingrui.top/chain.pem \
    --reloadcmd 'systemctl reload nginx'
```

### 方法2：一键申请（可能有警告）

```bash
# 一键申请和安装证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top
```

## 第六步：配置Nginx

```bash
# 自动生成Nginx配置
sudo /opt/ssl-auto-renewal/scripts/create-nginx-ssl-config.sh zhangmingrui.top

# 如果使用Cloudflare代理
sudo /opt/ssl-auto-renewal/scripts/create-nginx-ssl-config.sh --cloudflare zhangmingrui.top

# 如果需要PHP支持
sudo /opt/ssl-auto-renewal/scripts/create-nginx-ssl-config.sh --php zhangmingrui.top
```

## 常见问题

### 1. Cannot find DNS API hook错误

**问题**：运行时出现 `Cannot find DNS API hook for: dns_cf` 错误

**解决**：
```bash
# 1. 检查acme.sh DNS hook状态
/opt/ssl-auto-renewal/scripts/fix-acme-dns-hook.sh --check

# 2. 更新acme.sh到最新版本
/opt/ssl-auto-renewal/scripts/fix-acme-dns-hook.sh --update

# 3. 如果更新失败，重新安装acme.sh
/opt/ssl-auto-renewal/scripts/fix-acme-dns-hook.sh --reinstall

# 4. 测试DNS API功能
/opt/ssl-auto-renewal/scripts/fix-acme-dns-hook.sh --test zhangmingrui.top

# 5. 重新尝试申请证书
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --test
```

### 2. acme.sh sudo警告

**问题**：运行脚本时出现 `It seems that you are using sudo, please read this page first` 警告

**解决**：使用用户模式脚本
```bash
# 使用用户模式脚本（推荐）
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --test

# 申请正式证书
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --provider cloudflare
```

### 3. DNS_PROVIDER未定义错误

**问题**：运行脚本时出现 `DNS_PROVIDER: unbound variable` 错误

**解决**：
```bash
# 先配置DNS API
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod

# 或手动编辑配置文件
sudo nano /opt/ssl-auto-renewal/config/dns-api.conf
```

### 4. API认证失败

**问题**：DNS API认证失败

**解决**：
- 检查API密钥是否正确
- 确认API密钥有DNS记录管理权限
- 检查域名是否在对应DNS服务商管理

### 5. ZeroSSL账户问题

**问题**：出现以下错误信息
```
acme.sh is using ZeroSSL as default CA now.
Please update your account with an email address first.
acme.sh --register-account -m my@example.com
```

**解决**：使用修复后的用户模式脚本（已强制使用Let's Encrypt）
```bash
# 测试环境申请（推荐先测试）
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --provider cloudflare --staging

# 正式环境申请
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --provider cloudflare
```

**详细解决方案**：参考 [ZeroSSL修复指南](ZEROSSL_FIX_GUIDE.md)

### 6. 证书申请失败

**问题**：acme.sh申请证书失败

**解决**：
```bash
# 查看详细日志
sudo tail -f /opt/ssl-auto-renewal/logs/ssl-renew-dns-auto.log

# 使用用户模式手动测试
/opt/ssl-auto-renewal/scripts/ssl-renew-dns-user.sh --domain zhangmingrui.top --staging
```

## 完整流程示例

以DNSPod为例的完整配置流程：

```bash
# 1. 配置DNS API
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --setup --provider dnspod
# 按提示输入DNSPod ID和Token

# 2. 测试配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --check-config

# 3. 测试申请证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top --test

# 4. 申请正式证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --domain zhangmingrui.top

# 5. 配置Nginx
sudo /opt/ssl-auto-renewal/scripts/create-nginx-ssl-config.sh zhangmingrui.top

# 6. 测试网站
curl -I https://zhangmingrui.top/
```

## 自动续订设置

证书申请成功后，系统会自动设置定时任务进行续订。您也可以手动检查：

```bash
# 查看定时任务
sudo crontab -l

# 手动测试续订
sudo /opt/ssl-auto-renewal/scripts/ssl-renew-dns-auto.sh --test
```

## 技术支持

如果遇到问题，请查看：
- 日志文件：`/opt/ssl-auto-renewal/logs/`
- 配置文件：`/opt/ssl-auto-renewal/config/`
- 详细文档：`/opt/ssl-auto-renewal/DNS_API_SETUP.md`