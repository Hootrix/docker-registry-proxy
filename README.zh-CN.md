[English](README.md) | **简体中文**

# Docker Registry Proxy

基于 Traefik + Nginx + Docker Registry 2.0 的 Docker Hub 镜像代理服务。

## 特性

- **Traefik**: 自动化申请 HTTPS 证书
- **轻量化**: 不转存镜像，实时代理转发
- **认证保护**: htpasswd 用户认证
- **防滥用**: Rate Limiting 限流保护
- **只读模式**: 仅支持拉取，禁止推送
- **自动 `library/`**: 官方镜像无需手动加 `library/` 前缀
- **多上游**: 通过 `manage-upstreams.sh` 一条命令接入 ghcr.io / quay.io 等上游
- **环境变量配置**: 通过 `.env` 文件灵活配置

## 架构

```
客户端 → Traefik (HTTPS) → Nginx (限流) → Registry:2 (代理，每上游一个实例) → 上游 Registry（docker.io / ghcr.io / …）
```

## 前置要求

- Docker 和 Docker Compose
- **已部署的 Traefik**（必须）
- 域名已解析到服务器

## 快速开始

### 1. 克隆项目

```bash
cd /path/to/docker-registry-proxy
```

### 2. 生成认证文件

```bash
./manage-users.sh add username
```

### 3. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`：

```bash
REGISTRY_DOMAIN=docker-proxy.yourdomain.com
TRAEFIK_NETWORK=traefik-net
TRAEFIK_CERTRESOLVER=letsencrypt
TRAEFIK_ENTRYPOINT=websecure
```

### 4. 初始化并启动

```bash
./manage-upstreams.sh add docker.io
```

该命令创建默认上游声明 `config/registries/docker.io.yml`，生成 registry 配置、nginx 片段与 `docker-compose.override.yml`，并启动整套服务。

> 注意：初始化前直接 `docker compose up -d` 会失败——`registry` 服务由脚本生成的 `docker-compose.override.yml` 提供，首次启动必须经过 `add docker.io`。

## 使用

### 登录

```bash
docker login docker.yourdomain.com
```

### 拉取镜像

```bash
# 默认上游（docker.io）— 无需前缀，官方镜像自动补全 library/
docker pull docker.yourdomain.com/alpine:latest
docker pull docker.yourdomain.com/nginx:alpine
docker pull docker.yourdomain.com/bitnami/nginx:latest

# 其他上游 — 上游域名作路径前缀
docker pull docker.yourdomain.com/ghcr.io/fluxcd/source-controller:latest
docker pull docker.yourdomain.com/quay.io/prometheus/node-exporter:latest
```

### 用户管理

```bash
./manage-users.sh add username      # 添加用户
./manage-users.sh delete username   # 删除用户
./manage-users.sh list              # 列出用户
./manage-users.sh change username   # 修改密码
```

### 多上游管理

通过 `manage-upstreams.sh` 管理多个上游 Registry（声明式配置，一条命令生效）：

```bash
./manage-upstreams.sh list                        # 列出所有上游
./manage-upstreams.sh add ghcr.io                 # 新增上游，nginx 优雅 reload 即时生效
./manage-upstreams.sh add ghcr.io --username me   # 私有镜像上游（交互输入密码，不进 shell history）
./manage-upstreams.sh add myregistry.example.com --remoteurl https://api.myregistry.example.com   # 路由前缀与 API 端点不同时指定（默认 https://<host>，docker.io 默认 registry-1.docker.io）
./manage-upstreams.sh add ghcr.io --force         # 覆盖已存在的上游声明
./manage-upstreams.sh remove ghcr.io              # 移除非默认上游（缓存数据卷保留）
./manage-upstreams.sh apply                       # 重新生成全部配置并生效（手改声明后执行）
```

- 声明文件位于 `config/registries/<host>.yml`，已被 gitignore（可能包含凭据，请勿提交）
- 新增上游后以上游域名作路径前缀拉取：`docker pull docker.yourdomain.com/ghcr.io/org/image`
- 手改声明文件或修改 `.env` 中的限流参数后，执行 `./manage-upstreams.sh apply` 重新生成并生效

> **注意**
> - 默认上游固定为 docker.io（`library/` 自动补全语义仅对其成立），不允许 remove
> - Docker Hub 仓库首段路径与已配置上游域名同名时会被该上游遮蔽（如存在名为 `quay.io` 的仓库，`/quay.io/...` 会路由到 quay.io 上游）
> - 每个上游会增加一个常驻 registry 进程，约 30-60MB 内存

### 从旧版升级（单上游静态部署）

```bash
./manage-upstreams.sh add docker.io
```

- `registry` 服务改由生成的 `docker-compose.override.yml` 提供，容器按新配置自动重建
- 缓存卷 `registry-data` 与服务名/容器名保持不变——缓存不丢，`manage-users.sh` 等外部引用不受影响
