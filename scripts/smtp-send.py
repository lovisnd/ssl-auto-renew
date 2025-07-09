#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SSL证书自动续订系统 - SMTP邮件发送脚本
支持各种SMTP服务器，包括腾讯企业邮箱、Gmail等
作者: SSL Auto Renewal System
版本: 1.0
"""

import smtplib
import sys
import os
import configparser
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header
import argparse
import logging
from datetime import datetime

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SMTPSender:
    def __init__(self, config_file):
        """初始化SMTP发送器"""
        self.config = {}
        self.load_config(config_file)
        
    def load_config(self, config_file):
        """加载邮件配置"""
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # 解析shell格式的配置文件
            for line in content.split('\n'):
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # 去除引号
                    value = value.strip('"\'')
                    self.config[key] = value
                    
            logger.info("邮件配置加载成功")
            
        except Exception as e:
            logger.error(f"加载配置文件失败: {e}")
            sys.exit(1)
    
    def get_config(self, key, default=''):
        """获取配置值"""
        return self.config.get(key, default)
    
    def create_message(self, to_email, subject, body, from_name=None):
        """创建邮件消息"""
        msg = MIMEMultipart()
        
        # 发件人
        from_email = self.get_config('SMTP_FROM_EMAIL') or self.get_config('SMTP_USERNAME')
        if not from_name:
            from_name = self.get_config('SMTP_FROM_NAME', 'SSL Auto Renewal System')
        
        # 确保from_email存在且格式正确
        if not from_email:
            logger.error("发件人邮箱地址未配置")
            raise ValueError("发件人邮箱地址未配置")
        
        # 设置From头部，确保符合RFC 5322规范
        if from_name and from_name.strip():
            # 对发件人名称进行编码，避免特殊字符问题
            encoded_name = Header(from_name, 'utf-8').encode()
            msg['From'] = f"{encoded_name} <{from_email}>"
        else:
            msg['From'] = from_email
        
        msg['To'] = to_email
        msg['Subject'] = Header(subject, 'utf-8')
        
        # 添加其他必要的头部
        msg['Date'] = datetime.now().strftime('%a, %d %b %Y %H:%M:%S %z')
        msg['Message-ID'] = f"<{datetime.now().strftime('%Y%m%d%H%M%S')}.{os.getpid()}@{from_email.split('@')[1]}>"
        
        # 邮件正文
        msg.attach(MIMEText(body, 'plain', 'utf-8'))
        
        return msg
    
    def send_email(self, to_email, subject, body):
        """发送邮件"""
        try:
            # 检查是否启用外部SMTP
            if self.get_config('USE_EXTERNAL_SMTP').lower() != 'true':
                logger.error("外部SMTP未启用，请在配置文件中设置 USE_EXTERNAL_SMTP=true")
                return False
            
            # 获取SMTP配置
            smtp_server = self.get_config('SMTP_SERVER')
            smtp_port = int(self.get_config('SMTP_PORT', '587'))
            smtp_username = self.get_config('SMTP_USERNAME')
            smtp_password = self.get_config('SMTP_PASSWORD')
            use_tls = self.get_config('SMTP_USE_TLS', 'true').lower() == 'true'
            use_ssl = self.get_config('SMTP_USE_SSL', 'false').lower() == 'true'
            
            if not all([smtp_server, smtp_username, smtp_password]):
                logger.error("SMTP配置不完整，请检查服务器地址、用户名和密码")
                return False
            
            # 创建邮件消息
            msg = self.create_message(to_email, subject, body)
            
            # 连接SMTP服务器
            if use_ssl:
                # 使用SSL连接（通常是465端口）
                server = smtplib.SMTP_SSL(smtp_server, smtp_port)
                logger.info(f"使用SSL连接到 {smtp_server}:{smtp_port}")
            else:
                # 使用普通连接
                server = smtplib.SMTP(smtp_server, smtp_port)
                logger.info(f"连接到 {smtp_server}:{smtp_port}")
                
                if use_tls:
                    # 启用TLS加密
                    server.starttls()
                    logger.info("启用TLS加密")
            
            # 登录
            server.login(smtp_username, smtp_password)
            logger.info(f"登录成功: {smtp_username}")
            
            # 发送邮件 - 使用正确的发件人地址
            from_email = self.get_config('SMTP_FROM_EMAIL') or smtp_username
            text = msg.as_string()
            server.sendmail(from_email, to_email, text)
            server.quit()
            
            logger.info(f"邮件发送成功: {to_email}")
            return True
            
        except smtplib.SMTPAuthenticationError as e:
            logger.error(f"SMTP认证失败: {e}")
            logger.error("请检查用户名和密码是否正确")
            return False
        except smtplib.SMTPConnectError as e:
            logger.error(f"SMTP连接失败: {e}")
            logger.error("请检查服务器地址和端口是否正确")
            return False
        except smtplib.SMTPException as e:
            logger.error(f"SMTP错误: {e}")
            return False
        except Exception as e:
            logger.error(f"发送邮件时发生未知错误: {e}")
            return False
    
    def test_connection(self):
        """测试SMTP连接"""
        try:
            smtp_server = self.get_config('SMTP_SERVER')
            smtp_port = int(self.get_config('SMTP_PORT', '587'))
            smtp_username = self.get_config('SMTP_USERNAME')
            smtp_password = self.get_config('SMTP_PASSWORD')
            use_tls = self.get_config('SMTP_USE_TLS', 'true').lower() == 'true'
            use_ssl = self.get_config('SMTP_USE_SSL', 'false').lower() == 'true'
            
            logger.info("开始测试SMTP连接...")
            logger.info(f"服务器: {smtp_server}:{smtp_port}")
            logger.info(f"用户名: {smtp_username}")
            logger.info(f"使用SSL: {use_ssl}")
            logger.info(f"使用TLS: {use_tls}")
            
            if use_ssl:
                server = smtplib.SMTP_SSL(smtp_server, smtp_port)
            else:
                server = smtplib.SMTP(smtp_server, smtp_port)
                if use_tls:
                    server.starttls()
            
            server.login(smtp_username, smtp_password)
            server.quit()
            
            logger.info("SMTP连接测试成功！")
            return True
            
        except Exception as e:
            logger.error(f"SMTP连接测试失败: {e}")
            return False

def main():
    parser = argparse.ArgumentParser(description='SSL证书系统SMTP邮件发送工具')
    parser.add_argument('--config', required=True, help='邮件配置文件路径')
    parser.add_argument('--to', required=True, help='收件人邮箱地址')
    parser.add_argument('--subject', required=True, help='邮件主题')
    parser.add_argument('--body', help='邮件正文')
    parser.add_argument('--body-file', help='邮件正文文件路径')
    parser.add_argument('--test', action='store_true', help='测试SMTP连接')
    
    args = parser.parse_args()
    
    # 创建SMTP发送器
    sender = SMTPSender(args.config)
    
    # 测试连接
    if args.test:
        success = sender.test_connection()
        sys.exit(0 if success else 1)
    
    # 获取邮件正文
    if args.body_file:
        try:
            with open(args.body_file, 'r', encoding='utf-8') as f:
                body = f.read()
        except Exception as e:
            logger.error(f"读取邮件正文文件失败: {e}")
            sys.exit(1)
    elif args.body:
        body = args.body
    else:
        # 从标准输入读取
        body = sys.stdin.read()
    
    # 发送邮件
    success = sender.send_email(args.to, args.subject, body)
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()