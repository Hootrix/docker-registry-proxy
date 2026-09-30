#!/usr/bin/env bash
# manage-upstreams.sh — 多上游管理：声明式配置（config/registries/*.yml）→ 生成 → 一条命令生效
# 设计文档: docs/superpowers/specs/2026-09-30-multi-upstream-design.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 目录可被测试覆盖（REGISTRIES_DIR=/tmp/fixtures ./manage-upstreams.sh list）
REGISTRIES_DIR="${REGISTRIES_DIR:-config/registries}"
GEN_DIR="${GEN_DIR:-config/generated}"
GEN_REGISTRY="$GEN_DIR/registry"
GEN_HTTP="$GEN_DIR/nginx/http-upstreams"
GEN_LOC="$GEN_DIR/nginx/locations"
OVERRIDE="${OVERRIDE:-docker-compose.override.yml}"

DEFAULT_UPSTREAM="docker.io"   # 固定：模板默认路由/补全语义仅对 docker.io 成立

RED=$'\033[0;31m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
info() { printf '%s\n' "${GREEN}[INFO]${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}[WARN]${NC} $*"; }
die()  { printf '%s\n' "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Docker Registry Proxy — 多上游管理

用法: ./manage-upstreams.sh <命令> [参数]

命令:
  add <host> [--remoteurl URL] [--username USER] [--password PASS] [--force]
                                   新增上游（host 如 ghcr.io），写入声明并立即生效
                                   已存在时报错；--force 覆盖；--password 不安全（会进 history）
  remove <host>                    移除非默认上游（数据卷保留）
  list                             列出所有上游
  apply                            重新生成全部配置并生效（手改 yml 后执行）

示例:
  ./manage-upstreams.sh add docker.io          # 首次初始化（默认上游必配）
  ./manage-upstreams.sh add ghcr.io            # 新增 ghcr
  ./manage-upstreams.sh add ghcr.io --username me   # 私有镜像（交互输 PAT）
USAGE
}

# ---- 环境与声明文件解析 ----

# 只导出 .env 中 KEY=VALUE 行（不 source 整个文件，避免执行任意内容）
load_env() {
    [ -f .env ] || die "缺少 .env，先执行: cp .env.example .env"
    local k v
    while IFS='=' read -r k v; do
        case "$k" in ''|\#*) continue ;; esac
        # 值清洗顺序（确定性，对齐 compose 语义）：去行尾 CR → 截掉行内注释（首个 " #" 起）→ 去一层成对引号
        # 已知取舍：带引号的值自身含 " #" 时会被截断（注释先于引号处理）
        v="${v%$'\r'}"
        v="${v%% \#*}"
        case "$v" in
            \"*\") v="${v#\"}"; v="${v%\"}" ;;
            \'*\') v="${v#\'}"; v="${v%\'}" ;;
        esac
        # env 优先：调用方已设置（含空值）的变量不被 .env 覆盖
        # （目录变量的测试覆盖契约依赖此语义；也防止 .env 意外覆盖 PATH 等）
        if [ -z "${!k+x}" ]; then export "$k=$v"; fi
    done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env)
    # 边界：DEFAULT_UPSTREAM 仅支持 docker.io（默认 location 的 library/ 补全语义）
    [ "${DEFAULT_UPSTREAM:-docker.io}" = "docker.io" ] \
        || die "DEFAULT_UPSTREAM 当前仅支持 docker.io"
}

# 平面 YAML 解析：输出 "key<TAB>value"；按首个冒号切分（remoteurl 值含 ://）；跳过注释/空行
# 值规则：含 " #"（行内注释）→ 整行拒绝（fail-closed：不支持值内注释，避免静默截断 URL）；
#        成对引号去一层；重复键由 get_field 取最后值（对齐 YAML 覆盖语义）
parse_flat_yaml() {
    awk -v sq="'" '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            i = index($0, ":")
            if (i == 0) next
            key = tolower(trim(substr($0, 1, i - 1)))
            val = trim(substr($0, i + 1))
            if (key == "" || val == "") next
            if (val ~ / #/) next
            q = substr(val, 1, 1)
            if (length(val) >= 2 && (q == "\"" || q == sq) && substr(val, length(val)) == q)
                val = substr(val, 2, length(val) - 2)
            print key "\t" val
        }
    ' "$1"
}

# get_field <file> <key> [default]（同键多行取最后一个，符合 YAML 常规覆盖语义）
get_field() {
    local val
    val=$(parse_flat_yaml "$1" | awk -F'\t' -v k="$2" '$1 == k { v = $2 } END { print v }')
    printf '%s' "${val:-${3:-}}"
}

# ---- 命名派生（单点：服务名/容器名/卷名/upstream 名都从这里出）----

# 归一化：. 和 - 统一为 -（ghcr.io → ghcr-io）
# 注意必须输出换行：validate_all 的归一化冲突检测靠管道按行处理；
# 命令替换 $(norm_host ...) 会自动剥掉尾部换行，故对其他调用点无影响
norm_host() { printf '%s\n' "$1" | tr '.-' '-'; }
# nginx upstream 标识符：. 和 - → _（同样依赖换行保证按行输出）
upstream_id() { printf '%s\n' "$1" | tr '.-' '__'; }
# 服务名：默认上游固定 registry（docker-compose.yml 的 depends_on / manage-users.sh 依赖此名）
service_name() {
    if [ "$1" = "$DEFAULT_UPSTREAM" ]; then echo "registry"
    else echo "registry-$(norm_host "$1")"; fi
}
# 容器名：默认沿用 docker-registry-proxy（外部脚本/监控可能引用）
container_name() {
    if [ "$1" = "$DEFAULT_UPSTREAM" ]; then echo "docker-registry-proxy"
    else echo "docker-registry-$(norm_host "$1")"; fi
}
# 卷名：默认沿用 registry-data（保留现有缓存卷）
volume_name() {
    if [ "$1" = "$DEFAULT_UPSTREAM" ]; then echo "registry-data"
    else echo "registry-data-$(norm_host "$1")"; fi
}
# nginx 正则转义（点 → \.）；与其余取值函数一致按行输出（命令替换会剥掉换行）
regex_escape() { printf '%s\n' "$1" | sed 's/[.]/\\./g'; }

list_hosts() {
    [ -d "$REGISTRIES_DIR" ] || return 0
    # /^$/d：basename 恰为 ".yml" 的文件会产出空行
    find "$REGISTRIES_DIR" -maxdepth 1 -name '*.yml' -type f | sed 's|.*/||; s|\.yml$||; /^$/d' | sort
}

# ---- 校验 ----

validate_all() {
    local hosts host dup culprits
    hosts=$(list_hosts)
    [ -n "$hosts" ] || die "$REGISTRIES_DIR 为空——先执行: ./manage-upstreams.sh add $DEFAULT_UPSTREAM"
    # 默认上游必配：模板默认路由（无前缀请求）指向其实例，缺失会导致 nginx 起不来
    [ -f "$REGISTRIES_DIR/${DEFAULT_UPSTREAM}.yml" ] \
        || die "缺少 ${DEFAULT_UPSTREAM}.yml（默认上游必配）"
    # 逐行 read 而非 for 分词迭代：host 未过校验前不能分词/glob
    # （"a b.yml" 会被拆成两个"host"、含 * 的名字会被展开），字符集校验必须针对原始文件名
    while IFS= read -r host; do
        [ -n "$host" ] || continue
        # 边界：host 字符集（服务名/DNS/location 正则安全）
        [[ "$host" =~ ^[a-z0-9][a-z0-9.-]*$ ]] \
            || die "非法 host 名: ${host}（需匹配 ^[a-z0-9][a-z0-9.-]*\$）"
        # 注：变量后紧跟全角括号必须加 {}，否则 macOS 自带 bash 3.2 会把多字节字符
        # 当作变量名的一部分 → "unbound variable"，错误信息本身都打不出来
        case "$host" in _*) die "非法 host 名: ${host}（不允许下划线开头）";; esac
        [ "$host" = "_catalog" ] && die "保留名: $host"
        [ -n "$(get_field "$REGISTRIES_DIR/$host.yml" remoteurl)" ] \
            || die "$host: 缺少 remoteurl"
    done < <(list_hosts)
    # 边界：归一化冲突（a-b.com 与 a.b.com 同归一化 → 静默指向同一实例，必须拒绝）
    dup=$(list_hosts | while IFS= read -r h; do norm_host "$h"; done | sort | awk 'seen[$0]++{print; exit}')
    [ -z "$dup" ] || {
        # 找出归一化后撞名的来源 host，便于定位声明文件
        # 用 if 而非 "&& echo"：最后一个 host 不匹配时循环退出码为 1，
        # 叠加 pipefail 会让整个命令替换"失败"，set -e 下冲突报错反而打不出来
        culprits=$(list_hosts | while IFS= read -r h; do
            if [ "$(norm_host "$h")" = "$dup" ]; then echo "$h"; fi
        done | paste -sd' ' -)
        die "归一化名冲突: ${dup}（来自: ${culprits}）"
    }
}

# ---- list ----

cmd_list() {
    local host url mark auth
    printf '%-24s %-8s %-36s %s\n' HOST DEFAULT REMOTEURL AUTH
    while IFS= read -r host; do
        [ -n "$host" ] || continue
        url=$(get_field "$REGISTRIES_DIR/$host.yml" remoteurl "-")
        if [ "$host" = "$DEFAULT_UPSTREAM" ]; then mark="yes"; else mark=""; fi
        if [ -n "$(get_field "$REGISTRIES_DIR/$host.yml" username)" ]; then auth="user/pass"; else auth="anon"; fi
        printf '%-24s %-8s %-36s %s\n' "$host" "$mark" "$url" "$auth"
    done < <(list_hosts)
}
