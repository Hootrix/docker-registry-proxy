.PHONY: help init start stop restart logs status test clean add-user list-users backup

# 默认目标
help:
	@echo "Docker Registry Proxy - 管理命令"
	@echo ""
	@echo "使用方法: make <命令>"
	@echo ""
	@echo "可用命令:"
	@echo "  init          - 初始化项目（生成 htpasswd）"
	@echo "  start         - 启动服务"
	@echo "  stop          - 停止服务"
	@echo "  restart       - 重启服务"
	@echo "  logs          - 查看实时日志"
	@echo "  status        - 查看服务状态"
	@echo "  test          - 运行测试脚本"
	@echo "  clean         - 清理数据卷和容器"
	@echo "  add-user      - 添加新用户"
	@echo "  list-users    - 列出所有用户"
	@echo "  backup        - 备份配置文件"
	@echo ""
	@echo "示例:"
	@echo "  make init     # 初始化项目"
	@echo "  make start    # 启动服务"
	@echo "  make logs     # 查看日志"
	@echo ""

# 初始化项目
init:
	@echo "🚀 初始化 Docker Registry Proxy..."
	@./setup.sh
	@echo ""
	@echo "✅ 初始化完成！"
	@echo "📝 下一步: 编辑 docker-compose.yml 修改域名和 Traefik 配置"
	@echo "🚀 然后运行: make start"

# 启动服务
start:
	@echo "🚀 启动服务..."
	@docker-compose up -d
	@echo ""
	@echo "✅ 服务已启动！"
	@echo "📊 查看状态: make status"
	@echo "📋 查看日志: make logs"

# 停止服务
stop:
	@echo "🛑 停止服务..."
	@docker-compose down
	@echo "✅ 服务已停止"

# 重启服务
restart:
	@echo "🔄 重启服务..."
	@docker-compose restart
	@echo "✅ 服务已重启"

# 查看日志
logs:
	@docker-compose logs -f

# 查看服务状态
status:
	@echo "📊 服务状态:"
	@docker-compose ps
	@echo ""
	@echo "📈 资源使用:"
	@docker stats --no-stream docker-registry-nginx docker-registry-proxy 2>/dev/null || true

# 运行测试
test:
	@./test.sh

# 清理数据
clean:
	@echo "⚠️  警告: 此操作将删除所有容器和数据卷！"
	@read -p "确认继续？(y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "🧹 清理中..."
	@docker-compose down -v
	@echo "✅ 清理完成"

# 添加用户
add-user:
	@./manage-users.sh add

# 列出用户
list-users:
	@./manage-users.sh list

# 备份配置
backup:
	@echo "💾 备份配置文件..."
	@mkdir -p backups
	@tar -czf backups/backup-$$(date +%Y%m%d-%H%M%S).tar.gz config/ auth/ docker-compose.yml .env 2>/dev/null || true
	@echo "✅ 备份完成: backups/backup-$$(date +%Y%m%d-%H%M%S).tar.gz"
	@ls -lh backups/ | tail -5
