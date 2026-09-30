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

# YAML 双引号纯量：转义 \ 与 " 后包裹——挡住值含 ": "、前导 &、不成对引号等破坏非引号纯量的字符
yaml_quote() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

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

# ---- 生成器（全部写入临时目录，apply 统一原子切换）----

# generate_registry_conf <host> <outfile>
# 基于原 config/registry-config.yml 结构；凭据存在时附加 proxy.username/password
generate_registry_conf() {
    local host=$1 out=$2 remoteurl user pass auth_block=""
    remoteurl=$(get_field "$REGISTRIES_DIR/$host.yml" remoteurl)
    user=$(get_field "$REGISTRIES_DIR/$host.yml" username)
    pass=$(get_field "$REGISTRIES_DIR/$host.yml" password)
    # 边界：username/password 必须成对，半边缺失时按匿名处理并警告（仅手改 yml 会出现，add 不会写出这种状态）
    if [ -n "$user" ] && [ -z "$pass" ]; then
        warn "$host: 有 username 无 password，按匿名上游处理"
        user=""
    fi
    # 旧写法只挡了"有 username 无 password"一侧；补对称分支，否则孤密码会被静默写入配置
    if [ -n "$pass" ] && [ -z "$user" ]; then
        warn "$host: 有 password 无 username，按匿名上游处理"
        pass=""
    fi
    # 旧写法 auth_block 直接内插裸值（username: $user）——密码含 ": " 即产出非法 YAML，
    # 前导 & 会被解析为锚点致密码变 null；统一经 yaml_quote 包裹
    if [ -n "$user" ]; then
        auth_block=$'\n  username: '"$(yaml_quote "$user")"$'\n  password: '"$(yaml_quote "$pass")"
    fi
    # 旧写法 heredoc 内裸内插（level: ${REGISTRY_LOG_LEVEL:-info} / remoteurl: $remoteurl），
    # 同样有 ": " / & / 引号破坏 YAML 的问题；改经 yaml_quote
    cat > "$out" <<EOF
# 自动生成（apply 会覆盖）——上游: $host
version: 0.1
log:
  level: $(yaml_quote "${REGISTRY_LOG_LEVEL:-info}")
  formatter: text
  fields:
    service: registry
    environment: production
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
  cache:
    blobdescriptor: inmemory
  redirect:
    disable: true
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
proxy:
  remoteurl: $(yaml_quote "$remoteurl")$auth_block
auth:
  htpasswd:
    realm: "Docker Registry Proxy"
    path: /auth/htpasswd
EOF
}

# generate_nginx_confs <host> <http_out> <loc_out>
# http 级 upstream + server 级 location；限流值从 .env 烘焙为字面量（生成文件不经 envsubst）
generate_nginx_confs() {
    local host=$1 http_out=$2 loc_out=$3
    local svc up escaped burst conn completion=""
    svc=$(service_name "$host")
    up="upstream_$(upstream_id "$host")"
    escaped=$(regex_escape "$host")
    burst=${RATE_LIMIT_BURST:-20}
    conn=${RATE_LIMIT_CONN:-10}
    # 边界：非数字值原样烘焙只会在容器内 nginx -t 才暴露（报错行号对应合并后配置，难定位）——生成期直接拒绝
    # 旧写法无校验；case 字符类匹配 macOS bash 3.2 可用（regex 需 [[ =~ ]]，此处不必）
    case "$burst" in ''|*[!0-9]*) die "RATE_LIMIT_BURST 非法: ${burst}（需为非负整数）" ;; esac
    case "$conn" in ''|*[!0-9]*) die "RATE_LIMIT_CONN 非法: ${conn}（需为非负整数）" ;; esac

    cat > "$http_out" <<EOF
# 自动生成（apply 会覆盖）——上游: $host
upstream $up {
    server $svc:5000;
    keepalive 32;
}
EOF

    # docker.io 专属：library/ 补全（官方镜像单段名），置于剥离规则前（rewrite break 首个命中即停）
    # 字符类 [^./]+：[^.] 单用会误捕 bitnami/nginx 这类多段 repo
    if [ "$host" = "$DEFAULT_UPSTREAM" ]; then
        completion="    rewrite ^/v2/$escaped/([^./]+)/(manifests|blobs|tags)/(.*)\$ /v2/library/\$1/\$2/\$3 break;"$'\n'
    fi

    cat > "$loc_out" <<EOF
# 自动生成（apply 会覆盖）——上游: $host
location ~ ^/v2/($escaped)(?<prefix_rest>/.*)?\$ {
    include /etc/nginx/snippets/proxy-common.conf;
    # 裸前缀（/v2/${host}）兜底：避免 rewrite 出 /v2 被 301 丢前缀（花括号必加，坑见 validate_all 注释）
    if (\$prefix_rest = "") { return 404; }
    # 限流值为生成时烘焙的字面量；改 .env 后需重新 apply
    limit_req zone=registry_limit burst=$burst nodelay;
    limit_conn registry_conn $conn;
$completion    rewrite ^ /v2\$prefix_rest break;
    proxy_pass http://$up;
}
EOF
}

# generate_override <outfile> <host...>
# 每上游一个 registry 实例；nginx 追加 depends_on（启动时 DNS 名已存在，upstream 解析不失败）
generate_override() {
    local out=$1; shift
    local host svc cname vol extra_vols="" svc_blocks="" deps="" vols_section=""
    for host in "$@"; do
        svc=$(service_name "$host")
        cname=$(container_name "$host")
        vol=$(volume_name "$host")
        if [ "$host" != "$DEFAULT_UPSTREAM" ]; then
            extra_vols+="  $vol:"$'\n'
        fi
        deps+="      - $svc"$'\n'
        svc_blocks+="  $svc:
    image: registry:2
    container_name: $cname
    restart: unless-stopped
    # 覆盖镜像默认 config 路径（目录挂载 + 指定文件，避免单文件挂载的 inode 问题）
    command: /etc/docker/registry-custom/$host.yml
    volumes:
      - ./config/generated/registry:/etc/docker/registry-custom:ro
      - ./auth/htpasswd:/auth/htpasswd:ro
      - $vol:/var/lib/registry
    networks:
      - internal
    healthcheck:
      test: [\"CMD-SHELL\", \"code=\$\$(wget -S --spider -q http://localhost:5000/v2/ 2>&1 | awk '/^  HTTP\\\\//{print \$\$2; exit}'); [ \\\"\$\$code\\\" = \\\"200\\\" ] || [ \\\"\$\$code\\\" = \\\"401\\\" ]\"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: \"json-file\"
      options:
        max-size: \"10m\"
        max-file: \"3\"
"$'\n'
    done
    # 旧写法恒输出 volumes:（$extra_vols）——仅默认上游时是尾随的空 null 段（compose 容忍但难看）；
    # 改为仅存在非默认上游时才组装并输出 volumes 段
    if [ -n "$extra_vols" ]; then
        vols_section=$'volumes:\n'"$extra_vols"
    fi
    cat > "$out" <<EOF
# 自动生成（apply 会覆盖）——多上游 registry 实例
services:
$svc_blocks
  nginx:
    depends_on:
$deps$vols_section
EOF
}
