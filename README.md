# SSL Certificate Auto-Renewal System

<div align="center">

[English](#english) | [中文](#chinese)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-18.04%2B-orange.svg)](https://ubuntu.com/)
[![Let's Encrypt](https://img.shields.io/badge/Let's%20Encrypt-Supported-green.svg)](https://letsencrypt.org/)

</div>

---

## English

🔒 A complete and easy-to-deploy SSL certificate auto-renewal solution based on Let's Encrypt and Certbot, designed for Ubuntu systems.

### ✨ Features

- 🚀 **One-Click Deployment**: Fully automated installation and configuration
- 🔄 **Auto Renewal**: Automatically renew SSL certificates every three months
- 📧 **Email Notifications**: Email alerts for renewal success/failure
- 🌐 **Multi-Domain Support**: Support for unlimited number of domains
- 🔧 **Web Server Integration**: Automatic Nginx/Apache service restart
- 📊 **Status Monitoring**: Real-time certificate status checking and reporting
- 📝 **Detailed Logging**: Complete operation log recording
- 🛠️ **Maintenance Tools**: System health check and maintenance scripts
- ⚡ **High Reliability**: Multiple check mechanisms ensure certificate validity

### 📁 Project Structure

```
ssl-auto-renewal/
├── 📄 README.md                 # Project documentation
├── 📄 QUICKSTART.md             # Quick start guide
├── 📄 DEPLOYMENT.md             # Detailed deployment documentation
├── 🛡️ SECURITY.md               # Security deployment guide
├── 🚀 install.sh                # One-click installation script
├── 📄 LICENSE                   # Open source license
├── 🔒 .gitignore                # Git ignore file
├── 📁 config/                   # Configuration files directory
│   ├── 🌐 domains.conf.example  # Domain configuration example
│   ├── 📧 email.conf.example    # Email configuration example
│   └── 🔑 dns-api.conf.example  # DNS API configuration example
├── 📁 scripts/                  # Core scripts directory
│   ├── 🔄 ssl-renew.sh          # SSL renewal main script (HTTP validation)
│   ├── 🔄 ssl-renew-dns-user.sh # SSL renewal script (DNS validation)
│   ├── 🔍 check-ssl.sh          # SSL certificate check script
│   ├── 📧 notify.sh             # Email notification script
│   ├── 🛠️ maintenance.sh        # System maintenance script
│   └── 🔧 fix-domain-issue.sh   # Domain validation troubleshooting tool
├── 📁 docs/                     # Documentation directory
│   ├── 📚 SMTP_SETUP.md         # SMTP email configuration guide
│   ├── 🔐 SSL_CERTIFICATE_SETUP.md # SSL certificate configuration guide
│   ├── 🌐 DNS_API_SETUP.md      # DNS API configuration guide
│   ├── 🇨🇳 CHINA_MAINLAND_SOLUTION.md # China mainland solution
│   └── 🚨 DOMAIN_TROUBLESHOOTING.md # Domain troubleshooting guide
└── 📁 cron/                     # Cron job configuration
    └── ⏰ ssl-cron              # Cron task configuration file
```

### 🚀 Quick Start

#### Prerequisites

- ✅ Ubuntu 18.04+ system
- ✅ Root or sudo privileges
- ✅ Nginx or Apache installed
- ✅ Domain resolved to server IP
- ✅ Ports 80 and 443 open

#### One-Click Deployment

```bash
# 1. Download project
git clone <your-repo-url> ssl-auto-renewal
cd ssl-auto-renewal

# 2. Run installation script
sudo bash install.sh

# 3. Configuration setup
# Copy example configuration files and fill in actual information
sudo cp /opt/ssl-auto-renewal/config/domains.conf.example /opt/ssl-auto-renewal/config/domains.conf
sudo cp /opt/ssl-auto-renewal/config/email.conf.example /opt/ssl-auto-renewal/config/email.conf
sudo cp /opt/ssl-auto-renewal/config/dns-api.conf.example /opt/ssl-auto-renewal/config/dns-api.conf

# 4. Edit configuration files
sudo nano /opt/ssl-auto-renewal/config/domains.conf
# Add: your-domain.com:/var/www/html

sudo nano /opt/ssl-auto-renewal/config/email.conf
# Set: NOTIFICATION_EMAIL="your-email@domain.com"

# 5. Test configuration
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 6. Apply for certificate
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh
```

### 📖 Documentation

#### Core Documentation
- 📋 [Quick Start Guide](QUICKSTART.md) - 5-minute quick deployment
- 📚 [Detailed Deployment Documentation](DEPLOYMENT.md) - Complete deployment and configuration guide
- 🛡️ [Security Deployment Guide](SECURITY.md) - Security configuration and best practices

#### Specialized Guides
- 🔐 [SSL Certificate Configuration Guide](docs/SSL_CERTIFICATE_SETUP.md) - Certificate application and Nginx configuration
- 📧 [SMTP Email Configuration Guide](docs/SMTP_SETUP.md) - External email server configuration
- 🚀 [DNS API Automation Setup Guide](docs/DNS_API_SETUP.md) - Fully automated SSL certificate management
- 🇨🇳 [China Mainland Unregistered Domain Solution](docs/CHINA_MAINLAND_SOLUTION.md) - DNS validation SSL certificate application

#### Troubleshooting
- 🚨 [Domain Validation Troubleshooting](docs/DOMAIN_TROUBLESHOOTING.md) - Domain validation failure issues
- ⚡ [Quick Fix Guide](docs/QUICK_FIX_GUIDE.md) - Quick solutions for domain validation issues
- 🔧 [Quick DNS Setup Guide](docs/QUICK_DNS_SETUP.md) - Quick DNS validation configuration

### 🛡️ Security Features

- 🔐 **Permission Control**: Strict file permission settings
- 🔒 **Secure Communication**: All network communication uses HTTPS
- 📝 **Audit Logs**: Complete operation records
- 🚫 **Minimum Privileges**: Only use necessary system permissions
- 🔄 **Auto Updates**: Regular Certbot version updates

#### ⚠️ Security Configuration Notes

**Important: Configuration files contain sensitive information, please protect them!**

1. **Configuration File Security**
   ```bash
   # Set appropriate file permissions
   sudo chmod 600 /opt/ssl-auto-renewal/config/dns-api.conf
   sudo chmod 600 /opt/ssl-auto-renewal/config/email.conf
   ```

2. **Git Version Control**
   - ✅ Project includes `.gitignore` file, automatically excludes sensitive configurations
   - ✅ Provides `.example` sample files for safe configuration template sharing
   - ❌ Never commit configuration files containing real API keys to version control

### 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### 🙏 Acknowledgments

- [Let's Encrypt](https://letsencrypt.org/) - Free SSL certificate service
- [Certbot](https://certbot.eff.org/) - Automated certificate management tool
- [Ubuntu](https://ubuntu.com/) - Excellent Linux distribution

---

## Chinese

🔒 一个功能完整、易于部署的SSL证书自动续订解决方案，基于Let's Encrypt和Certbot，专为Ubuntu系统设计。

### ✨ 功能特性

- 🚀 **一键部署**: 全自动安装和配置
- 🔄 **自动续订**: 每三个月自动续订SSL证书
- 📧 **邮件通知**: 续订成功/失败邮件提醒
- 🌐 **多域名支持**: 支持无限数量域名管理
- 🔧 **Web服务器集成**: 自动重启Nginx/Apache服务
- 📊 **状态监控**: 实时证书状态检查和报告
- 📝 **详细日志**: 完整的操作日志记录
- 🛠️ **维护工具**: 系统健康检查和维护脚本
- ⚡ **高可靠性**: 多重检查机制确保证书有效性

### 📁 项目结构

```
ssl-auto-renewal/
├── 📄 README.md                 # 项目说明文档
├── 📄 QUICKSTART.md             # 快速开始指南
├── 📄 DEPLOYMENT.md             # 详细部署文档
├── 🛡️ SECURITY.md               # 安全部署指南
├── 🚀 install.sh                # 一键安装脚本
├── 📄 LICENSE                   # 开源许可证
├── 🔒 .gitignore                # Git忽略文件
├── 📁 config/                   # 配置文件目录
│   ├── 🌐 domains.conf.example  # 域名配置示例
│   ├── 📧 email.conf.example    # 邮件配置示例
│   └── 🔑 dns-api.conf.example  # DNS API配置示例
├── 📁 scripts/                  # 核心脚本目录
│   ├── 🔄 ssl-renew.sh          # SSL续订主脚本（HTTP验证）
│   ├── 🔄 ssl-renew-dns-user.sh # SSL续订脚本（DNS验证）
│   ├── 🔍 check-ssl.sh          # SSL证书检查脚本
│   ├── 📧 notify.sh             # 邮件通知脚本
│   ├── 🛠️ maintenance.sh        # 系统维护脚本
│   └── 🔧 fix-domain-issue.sh   # 域名验证故障排除工具
├── 📁 docs/                     # 文档目录
│   ├── 📚 SMTP_SETUP.md         # SMTP邮件配置指南
│   ├── 🔐 SSL_CERTIFICATE_SETUP.md # SSL证书配置指南
│   ├── 🌐 DNS_API_SETUP.md      # DNS API配置指南
│   ├── 🇨🇳 CHINA_MAINLAND_SOLUTION.md # 中国大陆解决方案
│   └── 🚨 DOMAIN_TROUBLESHOOTING.md # 域名故障排除指南
└── 📁 cron/                     # 定时任务配置
    └── ⏰ ssl-cron              # Cron任务配置文件
```

### 🚀 快速开始

#### 前提条件

- ✅ Ubuntu 18.04+ 系统
- ✅ Root或sudo权限
- ✅ 已安装Nginx或Apache
- ✅ 域名已解析到服务器IP
- ✅ 80和443端口已开放

#### 一键部署

```bash
# 1. 下载项目
git clone <your-repo-url> ssl-auto-renewal
cd ssl-auto-renewal

# 2. 运行安装脚本
sudo bash install.sh

# 3. 配置文件设置
# 复制示例配置文件并填入实际信息
sudo cp /opt/ssl-auto-renewal/config/domains.conf.example /opt/ssl-auto-renewal/config/domains.conf
sudo cp /opt/ssl-auto-renewal/config/email.conf.example /opt/ssl-auto-renewal/config/email.conf
sudo cp /opt/ssl-auto-renewal/config/dns-api.conf.example /opt/ssl-auto-renewal/config/dns-api.conf

# 4. 编辑配置文件
sudo nano /opt/ssl-auto-renewal/config/domains.conf
# 添加: your-domain.com:/var/www/html

sudo nano /opt/ssl-auto-renewal/config/email.conf
# 设置: NOTIFICATION_EMAIL="your-email@domain.com"

# 5. 测试配置
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh --test

# 6. 申请证书
sudo /opt/ssl-auto-renewal/scripts/ssl-renew.sh
```

### 📖 文档

#### 核心文档
- 📋 [快速开始指南](QUICKSTART.md) - 5分钟快速部署
- 📚 [详细部署文档](DEPLOYMENT.md) - 完整的部署和配置指南
- 🛡️ [安全部署指南](SECURITY.md) - 安全配置和最佳实践

#### 专项指南
- 🔐 [SSL证书配置指南](docs/SSL_CERTIFICATE_SETUP.md) - 证书申请和Nginx配置详解
- 📧 [SMTP邮件配置指南](docs/SMTP_SETUP.md) - 外部邮件服务器配置详解
- 🚀 [DNS API自动化设置指南](docs/DNS_API_SETUP.md) - 完全自动化SSL证书管理
- 🇨🇳 [中国大陆未备案域名解决方案](docs/CHINA_MAINLAND_SOLUTION.md) - DNS验证方式申请SSL证书

#### 故障排除
- 🚨 [域名验证故障排除](docs/DOMAIN_TROUBLESHOOTING.md) - 域名验证失败问题详解
- ⚡ [快速修复指南](docs/QUICK_FIX_GUIDE.md) - 域名验证问题快速解决方案
- 🔧 [快速DNS设置指南](docs/QUICK_DNS_SETUP.md) - DNS验证快速配置

### 🛡️ 安全特性

- 🔐 **权限控制**: 严格的文件权限设置
- 🔒 **安全通信**: 所有网络通信使用HTTPS
- 📝 **审计日志**: 完整的操作记录
- 🚫 **最小权限**: 仅使用必要的系统权限
- 🔄 **自动更新**: 定期更新Certbot版本

#### ⚠️ 安全配置注意事项

**重要：配置文件包含敏感信息，请注意保护！**

1. **配置文件安全**
   ```bash
   # 设置适当的文件权限
   sudo chmod 600 /opt/ssl-auto-renewal/config/dns-api.conf
   sudo chmod 600 /opt/ssl-auto-renewal/config/email.conf
   ```

2. **Git版本控制**
   - ✅ 项目已包含 `.gitignore` 文件，自动排除敏感配置
   - ✅ 提供 `.example` 示例文件，安全分享配置模板
   - ❌ 切勿将包含真实API密钥的配置文件提交到版本控制

### 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

### 🙏 致谢

- [Let's Encrypt](https://letsencrypt.org/) - 免费SSL证书服务
- [Certbot](https://certbot.eff.org/) - 自动化证书管理工具
- [Ubuntu](https://ubuntu.com/) - 优秀的Linux发行版

---

⭐ If this project helps you, please give it a star!

🔒 **Make SSL certificate management simple and reliable!**