#!/bin/bash

# Docker Registry Proxy - 用户管理脚本

set -e

HTPASSWD_FILE="auth/htpasswd"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "Docker Registry Proxy - 用户管理工具"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  add <username>        添加新用户"
    echo "  delete <username>     删除用户"
    echo "  list                  列出所有用户"
    echo "  change <username>     修改用户密码"
    echo "  help                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 add john           # 添加用户 john"
    echo "  $0 delete john        # 删除用户 john"
    echo "  $0 list               # 列出所有用户"
    echo "  $0 change john        # 修改 john 的密码"
    echo ""
}

# 检查 htpasswd 文件
check_htpasswd_file() {
    if [ ! -f "$HTPASSWD_FILE" ]; then
        echo -e "${RED}❌ 错误: $HTPASSWD_FILE 文件不存在${NC}"
        echo "请先运行 ./setup.sh 初始化"
        exit 1
    fi
}

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ 错误: Docker 未安装${NC}"
        exit 1
    fi
}

# 添加用户
add_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}❌ 错误: 请指定用户名${NC}"
        echo "用法: $0 add <username>"
        exit 1
    fi
    
    # 检查用户是否已存在
    if grep -q "^${username}:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  警告: 用户 '$username' 已存在${NC}"
        read -p "是否要更新密码？(y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
        delete_user "$username" "silent"
    fi
    
    # 输入密码
    echo -n "请输入密码: "
    stty -echo
    read password
    stty echo
    echo ""
    
    if [ -z "$password" ]; then
        echo -e "${RED}❌ 错误: 密码不能为空${NC}"
        exit 1
    fi
    
    # 生成密码哈希并添加到文件
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$username" "$password" >> "$HTPASSWD_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 用户 '$username' 添加成功${NC}"
        echo ""
        echo "用户可以使用以下命令登录:"
        echo "  docker login docker-proxy.yourdomain.com"
        echo "  用户名: $username"
        echo "  密码: ********"
    else
        echo -e "${RED}❌ 错误: 添加用户失败${NC}"
        exit 1
    fi
}

# 删除用户
delete_user() {
    local username=$1
    local silent=$2
    
    if [ -z "$username" ]; then
        echo -e "${RED}❌ 错误: 请指定用户名${NC}"
        echo "用法: $0 delete <username>"
        exit 1
    fi
    
    check_htpasswd_file
    
    # 检查用户是否存在
    if ! grep -q "^${username}:" "$HTPASSWD_FILE"; then
        if [ "$silent" != "silent" ]; then
            echo -e "${RED}❌ 错误: 用户 '$username' 不存在${NC}"
            exit 1
        fi
        return
    fi
    
    # 删除用户
    sed -i.bak "/^${username}:/d" "$HTPASSWD_FILE"
    rm -f "${HTPASSWD_FILE}.bak"
    
    if [ "$silent" != "silent" ]; then
        echo -e "${GREEN}✅ 用户 '$username' 已删除${NC}"
    fi
}

# 列出所有用户
list_users() {
    check_htpasswd_file
    
    echo "=========================================="
    echo "Registry 用户列表"
    echo "=========================================="
    echo ""
    
    local count=0
    while IFS=: read -r username hash; do
        count=$((count + 1))
        echo "  $count. $username"
    done < "$HTPASSWD_FILE"
    
    echo ""
    echo "总计: $count 个用户"
    echo "=========================================="
}

# 修改密码
change_password() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}❌ 错误: 请指定用户名${NC}"
        echo "用法: $0 change <username>"
        exit 1
    fi
    
    check_htpasswd_file
    
    # 检查用户是否存在
    if ! grep -q "^${username}:" "$HTPASSWD_FILE"; then
        echo -e "${RED}❌ 错误: 用户 '$username' 不存在${NC}"
        exit 1
    fi
    
    # 删除旧用户并添加新密码
    delete_user "$username" "silent"
    add_user "$username"
}

# 主逻辑
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    check_docker
    
    local command=$1
    shift
    
    case $command in
        add)
            mkdir -p auth
            add_user "$@"
            ;;
        delete)
            delete_user "$@"
            ;;
        list)
            list_users
            ;;
        change)
            change_password "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}❌ 错误: 未知命令 '$command'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
