# 快速启动指南

5 分钟内完成 Docker Registry 代理服务的部署。

## 前置检查

- ✅ Docker 和 Docker Compose 已安装
- ✅ Traefik 已部署并正常运行
- ✅ 域名已解析到服务器（用于 HTTPS）
- ✅ Traefik 网络已创建（`traefik-net`）

## 部署步骤

### 1. 初始化认证（1 分钟）

```bash
cd /path/to/docker-registry-proxy
./setup.sh
```

按提示输入用户名和密码（用于 `docker login`）。

### 2. 配置环境变量（1 分钟）

```bash
cp .env.example .env
```

**不需要修改 `.env` 文件**（所有配置在 `docker-compose.yml` 中）。

### 3. 修改 docker-compose.yml（2 分钟）

打开 `docker-compose.yml`，搜索 `TODO`，修改以下 4 处：

```yaml
# 1. 修改域名
- "traefik.http.routers.docker-proxy.rule=Host(`docker-proxy.yourdomain.com`)"
  # 改为您的实际域名，例如：
  # - "traefik.http.routers.docker-proxy.rule=Host(`registry.example.com`)"

# 2. 确认 Traefik HTTPS entrypoint（通常是 websecure）
- "traefik.http.routers.docker-proxy.entrypoints=websecure"

# 3. 确认 Traefik certresolver 名称
- "traefik.http.routers.docker-proxy.tls.certresolver=letsencrypt"
  # 改为您在 Traefik 中配置的 certresolver 名称

# 4. 确认 Traefik 网络名称（通常是 traefik-net）
networks:
  traefik-net:
    external: true
```

**如何查找 Traefik 配置？**

```bash
# 查看 Traefik 容器的 labels
docker inspect <traefik-container-name> | grep -i certresolver
docker inspect <traefik-container-name> | grep -i entrypoint

# 或查看其他使用 Traefik 的服务
docker-compose -f /path/to/other-service/docker-compose.yml config
```

### 4. 确保 Traefik 网络存在（30 秒）

```bash
docker network create traefik-net
```

如果网络已存在，会提示错误，可忽略。

### 5. 启动服务（30 秒）

```bash
docker-compose up -d
```

查看日志确认启动成功：

```bash
docker-compose logs -f
```

看到类似输出表示成功：

```
registry_1  | time="..." level=info msg="listening on [::]:5000"
nginx_1     | ... "GET /v2/ HTTP/1.1" 401 ...
```

按 `Ctrl+C` 退出日志查看。

### 6. 测试服务（1 分钟）

#### 本地测试

```bash
./test.sh
```

#### 客户端测试

在**任意客户端机器**上执行：

```bash
# 登录代理服务器
docker login docker-proxy.yourdomain.com
# 输入在 setup.sh 中创建的用户名和密码

# 拉取测试镜像
docker pull docker-proxy.yourdomain.com/library/alpine:latest

# 验证镜像
docker images | grep alpine
```

## 完成！🎉

您的 Docker Registry 代理服务已成功部署。

---

## 常用命令

### 添加新用户

```bash
./manage-users.sh add <username>
```

### 查看所有用户

```bash
./manage-users.sh list
```

### 删除用户

```bash
./manage-users.sh delete <username>
```

### 查看日志

```bash
# 实时日志
docker-compose logs -f

# 仅查看 Nginx 日志
docker-compose logs -f nginx

# 查看最近 100 行
docker-compose logs --tail=100
```

### 重启服务

```bash
docker-compose restart
```

### 停止服务

```bash
docker-compose down
```

### 更新配置后重启

```bash
# 修改 nginx.conf 后
docker-compose restart nginx

# 修改 registry-config.yml 后
docker-compose restart registry
```

---

## 故障排查

### 问题 1: 无法登录

**症状**: `docker login` 提示 `unauthorized`

**解决**:

```bash
# 1. 检查 htpasswd 文件是否存在
ls -l auth/htpasswd

# 2. 查看 Registry 日志
docker-compose logs registry | grep -i auth

# 3. 重新生成 htpasswd
./setup.sh
docker-compose restart
```

### 问题 2: 无法拉取镜像

**症状**: `docker pull` 失败

**解决**:

```bash
# 1. 确认已登录
docker login docker-proxy.yourdomain.com

# 2. 检查镜像名称格式
# 正确：docker-proxy.yourdomain.com/library/nginx
# 错误：docker-proxy.yourdomain.com/nginx

# 3. 查看日志
docker-compose logs -f

# 4. 测试上游连接
docker exec docker-registry-proxy wget -O- https://registry-1.docker.io/v2/
```

### 问题 3: HTTPS 证书错误

**症状**: 提示证书无效

**解决**:

```bash
# 1. 确认域名 DNS 已解析
nslookup docker-proxy.yourdomain.com

# 2. 检查 Traefik 日志
docker logs <traefik-container-name> | grep -i certificate

# 3. 确认 certresolver 名称正确
docker inspect <traefik-container-name> | grep -i certresolver

# 4. 手动触发证书申请（等待几分钟）
docker-compose restart nginx
```

### 问题 4: Rate Limiting 触发

**症状**: `503 Service Temporarily Unavailable`

**解决**:

```bash
# 1. 查看 Nginx 日志
docker-compose logs nginx | grep limiting

# 2. 临时调整限流参数
# 编辑 config/nginx.conf，修改：
# rate=10r/s -> rate=50r/s
# burst=20 -> burst=100

# 3. 重启 Nginx
docker-compose restart nginx
```

---

## 使用示例

### 拉取官方镜像

```bash
# 官方镜像需要加 library/ 前缀
docker pull docker-proxy.yourdomain.com/library/nginx:alpine
docker pull docker-proxy.yourdomain.com/library/redis:latest
docker pull docker-proxy.yourdomain.com/library/postgres:15
```

### 拉取第三方镜像

```bash
# 第三方镜像直接使用组织名
docker pull docker-proxy.yourdomain.com/bitnami/nginx:latest
docker pull docker-proxy.yourdomain.com/grafana/grafana:latest
```

### 在 Docker Compose 中使用

```yaml
version: '3.8'

services:
  web:
    # 使用代理拉取镜像
    image: docker-proxy.yourdomain.com/library/nginx:alpine
    ports:
      - "80:80"
```

### 在 Dockerfile 中使用

```dockerfile
# 使用代理的基础镜像
FROM docker-proxy.yourdomain.com/library/node:18-alpine

WORKDIR /app
COPY . .
RUN npm install
CMD ["node", "index.js"]
```

---

## 性能优化建议

### 1. 调整 Rate Limiting

根据实际使用情况调整 `config/nginx.conf`:

```nginx
# 个人使用
limit_req_zone $binary_remote_addr zone=registry_limit:10m rate=10r/s;

# 小团队（5-10 人）
limit_req_zone $binary_remote_addr zone=registry_limit:10m rate=20r/s;

# 中等规模（10-50 人）
limit_req_zone $binary_remote_addr zone=registry_limit:10m rate=50r/s;
```

### 2. 增加 Nginx Worker 进程

编辑 `config/nginx.conf`:

```nginx
worker_processes auto;  # 自动根据 CPU 核心数
```

### 3. 启用 HTTP/2

在 Traefik 中启用 HTTP/2（通常默认启用）。

---

## 安全建议

1. **定期更新密码**
   ```bash
   ./manage-users.sh change <username>
   ```

2. **监控访问日志**
   ```bash
   docker exec -it docker-registry-nginx tail -f /var/log/nginx/access.log
   ```

3. **限制访问 IP**（可选）
   
   编辑 `config/nginx.conf`，在 `location /v2/` 中添加：
   ```nginx
   allow 192.168.1.0/24;  # 允许内网
   allow 1.2.3.4;         # 允许特定 IP
   deny all;              # 拒绝其他
   ```

4. **定期备份配置**
   ```bash
   tar -czf backup-$(date +%Y%m%d).tar.gz config/ auth/
   ```

---

## 下一步

- 📖 阅读完整文档：[README.md](README.md)
- 🏗️ 了解项目结构：[STRUCTURE.md](STRUCTURE.md)
- 🔧 添加更多用户：`./manage-users.sh add <username>`
- 📊 监控服务状态：`docker-compose logs -f`

---

**需要帮助？** 查看 [README.md](README.md) 中的故障排查章节。
