# 部署检查清单

在部署前，请按照此清单逐项检查，确保配置正确。

## ✅ 前置条件检查

- [ ] Docker 已安装（`docker --version`）
- [ ] Docker Compose 已安装（`docker-compose --version`）
- [ ] Traefik 已部署并正常运行
- [ ] 域名已解析到服务器 IP
- [ ] 服务器防火墙已开放 80 和 443 端口
- [ ] Traefik 网络已创建（`docker network ls | grep traefik-net`）

## ✅ 配置文件检查

### 1. docker-compose.yml

打开 `docker-compose.yml`，确认以下配置：

- [ ] **域名已修改**
  ```yaml
  - "traefik.http.routers.docker-proxy.rule=Host(`docker-proxy.yourdomain.com`)"
  ```
  ✏️ 改为您的实际域名

- [ ] **Traefik entrypoint 正确**
  ```yaml
  - "traefik.http.routers.docker-proxy.entrypoints=websecure"
  ```
  ✏️ 确认您的 Traefik HTTPS 入口名称（常见：`websecure`, `https`）

- [ ] **Traefik certresolver 正确**
  ```yaml
  - "traefik.http.routers.docker-proxy.tls.certresolver=letsencrypt"
  ```
  ✏️ 确认您的 Traefik 证书解析器名称

- [ ] **Traefik 网络名称正确**
  ```yaml
  networks:
    traefik-net:
      external: true
  ```
  ✏️ 确认网络名称为 `traefik-net`

### 2. config/nginx.conf

- [ ] **Rate limiting 参数合理**
  ```nginx
  limit_req_zone $binary_remote_addr zone=registry_limit:10m rate=10r/s;
  ```
  ✏️ 根据使用规模调整（个人：10r/s，团队：20-50r/s）

- [ ] **并发连接数合理**
  ```nginx
  limit_conn registry_conn 10;
  ```
  ✏️ 根据使用规模调整（个人：10，团队：20-50）

### 3. config/registry-config.yml

- [ ] **上游 Registry 地址正确**
  ```yaml
  proxy:
    remoteurl: https://registry-1.docker.io
  ```
  ✏️ 默认为 Docker Hub，如需代理其他 Registry 请修改

- [ ] **认证配置正确**
  ```yaml
  auth:
    htpasswd:
      realm: "Docker Registry Proxy"
      path: /auth/htpasswd
  ```
  ✏️ 无需修改

## ✅ 初始化检查

- [ ] **运行初始化脚本**
  ```bash
  ./setup.sh
  ```
  ✏️ 创建第一个用户

- [ ] **auth/htpasswd 文件已生成**
  ```bash
  ls -l auth/htpasswd
  ```
  ✏️ 确认文件存在且不为空

- [ ] **记录用户名和密码**
  ✏️ 用于后续 `docker login`

## ✅ 网络检查

- [ ] **Traefik 网络存在**
  ```bash
  docker network ls | grep traefik-net
  ```
  ✏️ 如不存在，运行 `docker network create traefik-net`

- [ ] **DNS 解析正确**
  ```bash
  nslookup docker-proxy.yourdomain.com
  ```
  ✏️ 确认返回正确的服务器 IP

## ✅ 启动服务

- [ ] **启动服务**
  ```bash
  docker-compose up -d
  ```

- [ ] **检查容器状态**
  ```bash
  docker-compose ps
  ```
  ✏️ 确认两个容器都是 `Up` 状态

- [ ] **查看日志无错误**
  ```bash
  docker-compose logs
  ```
  ✏️ 确认没有 ERROR 级别的日志

## ✅ 功能测试

- [ ] **运行测试脚本**
  ```bash
  ./test.sh
  ```
  ✏️ 所有测试项应该通过

- [ ] **测试 Nginx 健康检查**
  ```bash
  docker exec docker-registry-nginx wget -O- http://localhost/health
  ```
  ✏️ 应返回 `healthy`

- [ ] **测试 Registry 健康检查**
  ```bash
  docker exec docker-registry-proxy wget -O- http://localhost:5000/v2/
  ```
  ✏️ 应返回 401 或 JSON 响应

- [ ] **测试上游连接**
  ```bash
  docker exec docker-registry-proxy wget --spider https://registry-1.docker.io/v2/
  ```
  ✏️ 应返回 200 或 401

## ✅ 客户端测试

- [ ] **测试 HTTPS 访问**
  ```bash
  curl https://docker-proxy.yourdomain.com/v2/
  ```
  ✏️ 应返回 401 Unauthorized（证明 HTTPS 和认证都正常）

- [ ] **测试 Docker 登录**
  ```bash
  docker login docker-proxy.yourdomain.com
  ```
  ✏️ 输入用户名密码，应显示 `Login Succeeded`

- [ ] **测试拉取镜像**
  ```bash
  docker pull docker-proxy.yourdomain.com/library/alpine:latest
  ```
  ✏️ 应成功下载镜像

- [ ] **验证镜像**
  ```bash
  docker images | grep alpine
  ```
  ✏️ 应显示刚拉取的镜像

## ✅ 安全检查

- [ ] **未授权访问被拒绝**
  ```bash
  # 先登出
  docker logout docker-proxy.yourdomain.com
  # 尝试拉取（应该失败）
  docker pull docker-proxy.yourdomain.com/library/alpine:latest
  ```
  ✏️ 应提示需要认证

- [ ] **Rate limiting 生效**
  ```bash
  # 快速发送多个请求
  for i in {1..30}; do curl -s https://docker-proxy.yourdomain.com/v2/ > /dev/null & done
  # 查看日志
  docker-compose logs nginx | grep limiting
  ```
  ✏️ 应看到限流日志

- [ ] **.env 和 htpasswd 未提交到 Git**
  ```bash
  git status
  ```
  ✏️ 确认敏感文件在 `.gitignore` 中

## ✅ 监控和维护

- [ ] **设置日志轮转**（可选）
  ✏️ 防止日志文件过大

- [ ] **设置定期备份**
  ```bash
  # 添加到 crontab
  0 2 * * * cd /path/to/docker-registry-proxy && make backup
  ```
  ✏️ 每天凌晨 2 点备份配置

- [ ] **设置监控告警**（可选）
  ✏️ 监控服务可用性

## ✅ 文档检查

- [ ] **README.md 已阅读**
  ✏️ 了解完整功能和故障排查

- [ ] **QUICKSTART.md 已阅读**
  ✏️ 了解快速部署流程

- [ ] **快速开始.md 已阅读**（中文版）
  ✏️ 中文快速指南

## ✅ 后续操作

- [ ] **添加更多用户**
  ```bash
  ./manage-users.sh add <username>
  ```

- [ ] **调整限流参数**（根据实际使用情况）
  ✏️ 编辑 `config/nginx.conf`

- [ ] **配置监控**（可选）
  ✏️ 集成 Prometheus、Grafana 等

- [ ] **设置日志分析**（可选）
  ✏️ 使用 ELK、Loki 等

---

## 🎯 常见配置错误

### ❌ 域名未修改
**症状**: 无法访问服务

**检查**: `docker-compose.yml` 中的 `Host()` 规则

### ❌ certresolver 名称错误
**症状**: HTTPS 证书错误

**检查**: Traefik 配置中的 certresolver 名称

### ❌ 网络不存在
**症状**: 容器启动失败，提示网络不存在

**检查**: `docker network ls | grep traefik-net`

### ❌ htpasswd 文件不存在
**症状**: 登录失败，提示 unauthorized

**检查**: `ls -l auth/htpasswd`

### ❌ DNS 未解析
**症状**: 无法访问域名

**检查**: `nslookup docker-proxy.yourdomain.com`

---

## 📞 获取帮助

如果遇到问题：

1. 查看日志：`docker-compose logs -f`
2. 运行测试：`./test.sh`
3. 查看文档：[README.md](README.md)
4. 检查 Traefik 日志：`docker logs <traefik-container-name>`

---

**完成所有检查项后，您的 Docker Registry 代理服务应该可以正常工作了！** 🎉
