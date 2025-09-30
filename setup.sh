#!/bin/bash

# Docker Registry Proxy 初始化脚本
# 用于生成 htpasswd 认证文件

set -e

echo "=========================================="
echo "Docker Registry Proxy - 初始化脚本"
echo "=========================================="
echo ""

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "❌ 错误: Docker 未安装"
    echo "请先安装 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# 创建必要的目录
echo "📁 创建目录结构..."
mkdir -p auth config

# 检查 htpasswd 文件是否已存在
if [ -f "auth/htpasswd" ]; then
    echo ""
    echo "⚠️  警告: auth/htpasswd 文件已存在"
    read -p "是否要重新生成？这将删除所有现有用户 (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "✅ 保留现有 htpasswd 文件"
        exit 0
    fi
    rm -f auth/htpasswd
fi

# 提示用户输入用户名和密码
echo ""
echo "📝 创建 Registry 访问凭证"
echo "提示: 用户需要使用这些凭证通过 'docker login' 登录代理服务器"
echo ""

read -p "请输入用户名: " USERNAME
if [ -z "$USERNAME" ]; then
    echo "❌ 错误: 用户名不能为空"
    exit 1
fi

# 使用 stty 隐藏密码输入
echo -n "请输入密码: "
stty -echo
read PASSWORD
stty echo
echo ""

if [ -z "$PASSWORD" ]; then
    echo "❌ 错误: 密码不能为空"
    exit 1
fi

# 使用 Docker 容器生成 htpasswd 文件
echo ""
echo "🔐 生成 htpasswd 文件..."
docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$USERNAME" "$PASSWORD" > auth/htpasswd

if [ $? -eq 0 ]; then
    echo "✅ htpasswd 文件生成成功: auth/htpasswd"
    echo ""
    echo "📋 用户信息:"
    echo "   用户名: $USERNAME"
    echo "   密码: ********"
else
    echo "❌ 错误: htpasswd 文件生成失败"
    exit 1
fi

# 设置文件权限
chmod 600 auth/htpasswd

echo ""
echo "=========================================="
echo "✅ 初始化完成！"
echo "=========================================="
echo ""
echo "📌 下一步操作:"
echo ""
echo "1. 复制环境变量模板:"
echo "   cp .env.example .env"
echo ""
echo "2. 编辑 .env 文件，修改以下配置:"
echo "   - REGISTRY_DOMAIN: 您的域名"
echo "   - TRAEFIK_CERTRESOLVER: Traefik 证书解析器名称"
echo "   - TRAEFIK_ENTRYPOINT: Traefik HTTPS 入口名称"
echo ""
echo "3. 确保 Traefik 网络存在:"
echo "   docker network create traefik-net"
echo ""
echo "4. 启动服务:"
echo "   docker-compose up -d"
echo ""
echo "5. 测试登录:"
echo "   docker login docker-proxy.yourdomain.com"
echo "   用户名: $USERNAME"
echo "   密码: (您刚才设置的密码)"
echo ""
echo "6. 拉取镜像测试:"
echo "   docker pull docker-proxy.yourdomain.com/library/nginx:alpine"
echo ""
echo "=========================================="
echo ""

# 可选：添加更多用户
echo "💡 提示: 如需添加更多用户，运行:"
echo "   docker run --rm --entrypoint htpasswd httpd:2 -Bbn <username> <password> >> auth/htpasswd"
echo ""
