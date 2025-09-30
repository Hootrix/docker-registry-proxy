# Docker Registry Proxy

基于 Traefik + Nginx + Docker Registry 2.0 的 Docker Hub 镜像代理服务。

## 特性

- ✅ **Traefik**: 自动化申请HTTPS证书
- ✅ **轻量化**: 不转存镜像，实时代理转发
- ✅ **认证保护**: htpasswd 用户认证
- ✅ **防滥用**: Rate Limiting 限流保护
- ✅ **只读模式**: 仅支持拉取，禁止推送
- ✅ **环境变量配置**: 通过 .env 文件灵活配置

## 架构

```
客户端 → Traefik (HTTPS) → Nginx (限流) → Registry:2 (代理) → Docker Hub
```

## 前置要求

- ✅ Docker 和 Docker Compose
- ✅ **已部署的 Traefik**（必须）
- ✅ 域名已解析到服务器

## 快速开始

### 1. 克隆或下载项目

```bash
cd /path/to/docker-registry-proxy
```

### 2. 运行初始化脚本

生成用户认证文件：

```bash
./setup.sh
```

按提示输入用户名和密码（用于 `docker login`）。

### 3. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env` 文件，修改以下配置：

```bash
# TODO: 修改为您的实际域名
REGISTRY_DOMAIN=docker-proxy.yourdomain.com

# TODO: 确认 Traefik 网络名称
TRAEFIK_NETWORK=traefik-net

# TODO: 确认 Traefik certresolver 名称（在 Traefik 配置中定义）
TRAEFIK_CERTRESOLVER=letsencrypt

# TODO: 确认 Traefik HTTPS entrypoint 名称
TRAEFIK_ENTRYPOINT=websecure
```

### 4. 启动服务

```bash
docker-compose up -d
```

## 使用

### 登录

```bash
docker login registry.example.com
```

### 拉取镜像

```bash
# 官方镜像（需要 library/ 前缀）
docker pull registry.example.com/library/nginx:alpine
docker pull registry.example.com/library/redis:latest

# 第三方镜像
docker pull registry.example.com/bitnami/nginx:latest
```

### 用户管理

```bash
# 添加用户
./manage-users.sh add username

# 删除用户
./manage-users.sh delete username

# 列出用户
./manage-users.sh list

# 修改密码
./manage-users.sh change username
```

### 代理其他 Registry

修改 `config/registry-config.yml`:

```yaml
proxy:
  remoteurl: https://gcr.io  # 或 ghcr.io, quay.io 等
```

重启：

```bash
docker-compose restart registry
```
