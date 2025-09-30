# Docker Registry Proxy

轻量级 Docker Hub 镜像代理服务，基于 Nginx + Docker Registry 2.0，支持 Traefik 自动 HTTPS。

## 功能特性

- ✅ **轻量化架构**: Nginx + Registry:2，无需转存镜像
- ✅ **认证保护**: 基于 htpasswd 的用户认证，防止未授权访问
- ✅ **防滥用**: Nginx rate limiting 限流保护
- ✅ **自动 HTTPS**: 集成 Traefik，自动申请和续期 Let's Encrypt 证书
- ✅ **实时代理**: 按需转发请求到 Docker Hub，无需预先同步
- ✅ **支持公开镜像**: 代理所有 Docker Hub 公开镜像
- ✅ **容器化部署**: 一键启动，易于维护

## 架构说明

```
Internet → Traefik (HTTPS + 自动证书) → Nginx (反向代理 + 限流) → Registry:2 (代理模式) → Docker Hub
```

**工作流程**:
1. 用户通过 `docker login` 登录代理服务器（认证）
2. 用户执行 `docker pull` 拉取镜像
3. Traefik 终止 HTTPS，转发到 Nginx
4. Nginx 进行限流检查，转发到 Registry
5. Registry 从 Docker Hub 实时拉取镜像并返回
6. 不在本地存储完整镜像（仅临时缓存）

## 前置要求

- Docker 和 Docker Compose
- 已部署的 Traefik（带自动证书申请）
- 一个指向服务器的域名（用于 HTTPS）

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

### 4. 修改 docker-compose.yml

打开 `docker-compose.yml`，搜索 `TODO` 注释，根据实际情况修改：

- **域名**: 修改 `Host()` 规则中的域名
- **Traefik 网络**: 确认网络名称
- **certresolver**: 确认证书解析器名称
- **entrypoint**: 确认 HTTPS 入口名称

### 5. 确保 Traefik 网络存在

```bash
docker network create traefik-net
```

如果网络已存在，会提示错误，可忽略。

### 6. 启动服务

```bash
docker-compose up -d
```

查看日志：

```bash
docker-compose logs -f
```

### 7. 测试服务

#### 登录代理服务器

```bash
docker login docker-proxy.yourdomain.com
```

输入在 `setup.sh` 中创建的用户名和密码。

#### 拉取镜像测试

```bash
# 拉取官方 nginx 镜像
docker pull docker-proxy.yourdomain.com/library/nginx:alpine

# 拉取第三方镜像
docker pull docker-proxy.yourdomain.com/bitnami/nginx:latest
```

**注意**: 
- 官方镜像需要加 `library/` 前缀，如 `library/nginx`
- 第三方镜像直接使用组织名，如 `bitnami/nginx`

## 配置说明

### Rate Limiting（限流配置）

在 `config/nginx.conf` 中调整限流参数：

```nginx
# 每秒请求数限制
limit_req_zone $binary_remote_addr zone=registry_limit:10m rate=10r/s;

# 并发连接数限制
limit_conn_zone $binary_remote_addr zone=registry_conn:10m;
```

**建议值**:
- **个人使用**: `rate=10r/s`, `burst=20`, `conn=10`
- **小团队**: `rate=20r/s`, `burst=50`, `conn=20`
- **中等规模**: `rate=50r/s`, `burst=100`, `conn=50`

### 添加更多用户

```bash
# 方法 1: 使用 Docker 命令
docker run --rm --entrypoint htpasswd httpd:2 -Bbn <username> <password> >> auth/htpasswd

# 方法 2: 重新运行 setup.sh（会覆盖现有用户）
./setup.sh
```

### 删除用户

编辑 `auth/htpasswd` 文件，删除对应行，然后重启服务：

```bash
docker-compose restart
```

## 扩展到其他 Registry

如需代理其他 Registry（如 gcr.io, ghcr.io），修改 `config/registry-config.yml`:

```yaml
proxy:
  # 修改为目标 Registry
  remoteurl: https://gcr.io
  # 或
  # remoteurl: https://ghcr.io
```

然后重启服务：

```bash
docker-compose restart registry
```

## 监控和维护

### 查看日志

```bash
# 所有服务日志
docker-compose logs -f

# 仅查看 Nginx 日志
docker-compose logs -f nginx

# 仅查看 Registry 日志
docker-compose logs -f registry
```

### 查看 Nginx 访问日志

```bash
docker exec -it docker-registry-nginx tail -f /var/log/nginx/access.log
```

### 健康检查

```bash
# 检查服务状态
docker-compose ps

# 测试 Nginx 健康端点
curl http://localhost/health
```

### 清理临时数据

Registry 在代理模式下会缓存一些临时数据，定期清理：

```bash
docker-compose down
docker volume rm docker-registry-proxy_registry-data
docker-compose up -d
```

## 故障排查

### 无法登录

**问题**: `docker login` 失败，提示 `unauthorized`

**解决**:
1. 检查 `auth/htpasswd` 文件是否存在
2. 确认用户名密码正确
3. 查看 Registry 日志: `docker-compose logs registry`

### 无法拉取镜像

**问题**: `docker pull` 失败

**解决**:
1. 确认已成功 `docker login`
2. 检查镜像名称格式（官方镜像需要 `library/` 前缀）
3. 查看 Nginx 和 Registry 日志
4. 测试上游连接: `docker exec -it docker-registry-proxy wget -O- https://registry-1.docker.io/v2/`

### HTTPS 证书问题

**问题**: 提示证书错误

**解决**:
1. 确认域名 DNS 已正确解析到服务器
2. 检查 Traefik 是否正常运行
3. 查看 Traefik 日志确认证书申请状态
4. 确认 `docker-compose.yml` 中的 certresolver 名称正确

### Rate Limiting 触发

**问题**: 提示 `503 Service Temporarily Unavailable`

**解决**:
1. 检查 Nginx 日志中的 `limiting requests` 消息
2. 调整 `config/nginx.conf` 中的限流参数
3. 重启服务: `docker-compose restart nginx`

## 安全建议

1. **定期更新密码**: 定期修改 htpasswd 中的用户密码
2. **监控日志**: 定期检查访问日志，发现异常行为
3. **限制访问**: 如果可能，使用防火墙限制访问 IP 范围
4. **备份配置**: 定期备份 `auth/htpasswd` 和配置文件
5. **不支持私有镜像**: 避免配置 Docker Hub 凭证，降低安全风险

## 性能优化

1. **增加 worker 进程**: 在 `nginx.conf` 中调整 `worker_processes`
2. **启用 HTTP/2**: 在 Traefik 中启用 HTTP/2 支持
3. **调整超时时间**: 根据网络情况调整 `proxy_read_timeout`
4. **使用 SSD**: 将 `registry-data` 卷挂载到 SSD 存储

## 卸载

```bash
# 停止并删除容器
docker-compose down

# 删除数据卷
docker volume rm docker-registry-proxy_registry-data
docker volume rm docker-registry-proxy_nginx-logs

# 删除项目目录
cd ..
rm -rf docker-registry-proxy
```

## 常见问题

### Q: 是否会占用大量磁盘空间？

A: 不会。Registry 在代理模式下不会完整存储镜像，只会缓存临时数据。磁盘占用通常在几百 MB 到几 GB 之间。

### Q: 可以代理私有镜像吗？

A: 技术上可以，但不推荐。需要在 `config/registry-config.yml` 中配置 Docker Hub 凭证，存在安全风险。

### Q: 如何限制特定用户的访问？

A: 当前版本所有认证用户权限相同。如需细粒度权限控制，需要实现自定义认证服务。

### Q: 可以同时代理多个 Registry 吗？

A: 当前版本一个实例只能代理一个上游 Registry。如需代理多个，需要部署多个实例（不同域名）。

### Q: 性能如何？

A: 首次拉取镜像时，速度取决于到 Docker Hub 的网络连接。Nginx 的反向代理开销很小，几乎不影响性能。

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 联系方式

如有问题，请提交 GitHub Issue。
