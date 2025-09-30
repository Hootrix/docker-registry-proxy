# 项目结构说明

```
docker-registry-proxy/
├── docker-compose.yml          # Docker Compose 编排文件（TODO: 修改域名和 Traefik 配置）
├── .env.example                # 环境变量模板（TODO: 复制为 .env 并修改）
├── .gitignore                  # Git 忽略文件
│
├── config/                     # 配置文件目录
│   ├── nginx.conf              # Nginx 配置（包含 rate limiting）
│   └── registry-config.yml     # Registry 代理配置（TODO: 如需私有镜像，配置凭证）
│
├── auth/                       # 认证文件目录（由 setup.sh 生成）
│   └── htpasswd                # 用户认证文件（不提交到 Git）
│
├── setup.sh                    # 初始化脚本（生成 htpasswd）
├── manage-users.sh             # 用户管理脚本（添加/删除/列出用户）
├── test.sh                     # 测试脚本（验证服务状态）
│
├── README.md                   # 完整文档
└── STRUCTURE.md                # 本文件（项目结构说明）
```

## 文件说明

### 核心配置文件

#### `docker-compose.yml`
- 定义两个服务：`registry` 和 `nginx`
- 配置 Traefik labels 用于自动 HTTPS
- **TODO 项**:
  - 修改域名（`Host()` 规则）
  - 确认 Traefik 网络名称
  - 确认 certresolver 名称
  - 确认 entrypoint 名称

#### `config/nginx.conf`
- Nginx 反向代理配置
- Rate limiting 规则（防滥用）
- 代理 `/v2/` API 到 Registry
- **可调整参数**:
  - `rate=10r/s`: 每秒请求数限制
  - `burst=20`: 突发请求数
  - `limit_conn 10`: 并发连接数

#### `config/registry-config.yml`
- Registry 代理模式配置
- 上游地址：`https://registry-1.docker.io`
- htpasswd 认证配置
- **TODO 项**:
  - 如需代理私有镜像，配置 `username` 和 `password`

#### `.env.example`
- 环境变量模板
- 需要复制为 `.env` 并修改
- **TODO 项**:
  - `REGISTRY_DOMAIN`: 实际域名
  - `TRAEFIK_CERTRESOLVER`: 证书解析器名称
  - `TRAEFIK_ENTRYPOINT`: HTTPS 入口名称

### 脚本文件

#### `setup.sh`
- 初始化脚本
- 生成 `auth/htpasswd` 文件
- 创建第一个用户
- **使用**: `./setup.sh`

#### `manage-users.sh`
- 用户管理工具
- 支持添加、删除、列出、修改用户
- **使用**:
  - `./manage-users.sh add <username>`
  - `./manage-users.sh delete <username>`
  - `./manage-users.sh list`
  - `./manage-users.sh change <username>`

#### `test.sh`
- 服务测试脚本
- 检查服务状态、健康检查、上游连接
- **使用**: `./test.sh`

## 数据持久化

### Docker Volumes

```yaml
volumes:
  registry-data:    # Registry 临时数据和缓存
  nginx-logs:       # Nginx 访问和错误日志
```

### 挂载目录

```yaml
volumes:
  - ./config/registry-config.yml:/etc/docker/registry/config.yml:ro
  - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
  - ./auth/htpasswd:/auth/htpasswd:ro
```

## 网络架构

### 内部网络 (`internal`)
- Nginx ↔ Registry 通信
- 不暴露到外部

### 外部网络 (`traefik-net`)
- Traefik ↔ Nginx 通信
- 需要预先创建：`docker network create traefik-net`

## 部署流程

1. **初始化**
   ```bash
   ./setup.sh
   ```

2. **配置环境变量**
   ```bash
   cp .env.example .env
   # 编辑 .env 文件
   ```

3. **修改 docker-compose.yml**
   - 搜索 `TODO` 注释
   - 修改域名和 Traefik 配置

4. **创建 Traefik 网络**
   ```bash
   docker network create traefik-net
   ```

5. **启动服务**
   ```bash
   docker-compose up -d
   ```

6. **测试服务**
   ```bash
   ./test.sh
   ```

7. **客户端测试**
   ```bash
   docker login docker-proxy.yourdomain.com
   docker pull docker-proxy.yourdomain.com/library/nginx:alpine
   ```

## 维护操作

### 添加用户
```bash
./manage-users.sh add newuser
```

### 删除用户
```bash
./manage-users.sh delete olduser
```

### 查看日志
```bash
docker-compose logs -f
```

### 重启服务
```bash
docker-compose restart
```

### 更新配置
```bash
# 修改配置文件后
docker-compose restart nginx    # 如果修改了 nginx.conf
docker-compose restart registry # 如果修改了 registry-config.yml
```

### 清理数据
```bash
docker-compose down
docker volume rm docker-registry-proxy_registry-data
docker-compose up -d
```

## 安全注意事项

1. **不要提交敏感文件到 Git**
   - `.env` 文件
   - `auth/htpasswd` 文件
   - 已在 `.gitignore` 中配置

2. **定期更新密码**
   ```bash
   ./manage-users.sh change <username>
   ```

3. **监控日志**
   ```bash
   docker exec -it docker-registry-nginx tail -f /var/log/nginx/access.log
   ```

4. **备份配置**
   ```bash
   tar -czf backup-$(date +%Y%m%d).tar.gz config/ auth/
   ```

## 扩展功能

### 代理其他 Registry

修改 `config/registry-config.yml`:

```yaml
proxy:
  remoteurl: https://gcr.io  # 或其他 Registry
```

### 调整限流参数

修改 `config/nginx.conf`:

```nginx
limit_req_zone $binary_remote_addr zone=registry_limit:10m rate=20r/s;
limit_req zone=registry_limit burst=50 nodelay;
limit_conn registry_conn 20;
```

### 添加 IP 白名单

在 `config/nginx.conf` 的 `location /v2/` 块中添加:

```nginx
allow 192.168.1.0/24;
allow 10.0.0.0/8;
deny all;
```

## 故障排查

### 检查服务状态
```bash
docker-compose ps
```

### 查看详细日志
```bash
docker-compose logs -f nginx
docker-compose logs -f registry
```

### 测试内部连接
```bash
# 测试 Nginx -> Registry
docker exec docker-registry-nginx wget -O- http://registry:5000/v2/

# 测试 Registry -> Docker Hub
docker exec docker-registry-proxy wget -O- https://registry-1.docker.io/v2/
```

### 验证认证
```bash
# 应该返回 401 Unauthorized
curl http://localhost/v2/
```

## 性能调优

### Nginx Worker 进程
```nginx
worker_processes auto;  # 自动根据 CPU 核心数
```

### Registry 缓存
```yaml
storage:
  cache:
    blobdescriptor: inmemory  # 使用内存缓存
```

### 连接保持
```nginx
keepalive_timeout 65;
proxy_http_version 1.1;
proxy_set_header Connection "";
```

## 相关资源

- [Docker Registry 官方文档](https://docs.docker.com/registry/)
- [Nginx 反向代理文档](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Traefik 文档](https://doc.traefik.io/traefik/)
- [Docker Registry API](https://docs.docker.com/registry/spec/api/)
