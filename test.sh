#!/bin/bash

# Docker Registry Proxy - 测试脚本

set -e

# TODO: 修改为您的实际域名
REGISTRY_DOMAIN="${REGISTRY_DOMAIN:-docker-proxy.yourdomain.com}"

echo "=========================================="
echo "Docker Registry Proxy - 测试脚本"
echo "=========================================="
echo ""
echo "测试域名: $REGISTRY_DOMAIN"
echo ""

# 检查服务是否运行
echo "1️⃣  检查服务状态..."
if ! docker-compose ps | grep -q "Up"; then
    echo "❌ 错误: 服务未运行"
    echo "请先启动服务: docker-compose up -d"
    exit 1
fi
echo "✅ 服务正在运行"
echo ""

# 测试 Nginx 健康检查
echo "2️⃣  测试 Nginx 健康检查..."
if docker exec docker-registry-nginx wget -q -O- http://localhost/health > /dev/null 2>&1; then
    echo "✅ Nginx 健康检查通过"
else
    echo "❌ Nginx 健康检查失败"
    exit 1
fi
echo ""

# 测试 Registry 健康检查
echo "3️⃣  测试 Registry 健康检查..."
if docker exec docker-registry-proxy wget -q -O- http://localhost:5000/v2/ > /dev/null 2>&1; then
    echo "✅ Registry 健康检查通过"
else
    echo "❌ Registry 健康检查失败"
    exit 1
fi
echo ""

# 测试 Registry API（需要认证）
echo "4️⃣  测试 Registry API 认证..."
response=$(docker exec docker-registry-nginx wget -q -O- http://localhost/v2/ 2>&1 || true)
if echo "$response" | grep -q "401\|unauthorized"; then
    echo "✅ 认证保护正常（未授权访问被拒绝）"
else
    echo "⚠️  警告: 认证可能未生效"
fi
echo ""

# 测试上游连接
echo "5️⃣  测试到 Docker Hub 的连接..."
if docker exec docker-registry-proxy wget -q --spider https://registry-1.docker.io/v2/ 2>&1; then
    echo "✅ Docker Hub 连接正常"
else
    echo "❌ 无法连接到 Docker Hub"
    echo "请检查网络连接"
    exit 1
fi
echo ""

# 显示日志摘要
echo "6️⃣  最近的日志（最后 10 行）:"
echo "----------------------------------------"
docker-compose logs --tail=10 nginx
echo "----------------------------------------"
echo ""

echo "=========================================="
echo "✅ 基础测试完成！"
echo "=========================================="
echo ""
echo "📋 下一步测试:"
echo ""
echo "1. 测试登录（需要在客户端机器上执行）:"
echo "   docker login $REGISTRY_DOMAIN"
echo ""
echo "2. 测试拉取镜像:"
echo "   docker pull $REGISTRY_DOMAIN/library/alpine:latest"
echo ""
echo "3. 查看实时日志:"
echo "   docker-compose logs -f"
echo ""
echo "=========================================="
