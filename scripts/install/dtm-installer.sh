#!/usr/bin/env bash
set -Eeuo pipefail

WORKDIR="${1:-}"; shift || true
[[ -n "$WORKDIR" && -d "$WORKDIR" ]] || { echo "[dtm-installer][ERROR] missing workdir" >&2; exit 1; }

NS="dtm-system"; NAME="dtm"; REGISTRY="sealos.hub:5000/kube4"; REG_USER=""; REG_SECRET=""; SKIP_IMAGE=false
WAIT_TIMEOUT="180s"; YES=false; DRY=false; KCFG=""; KCTX=""; IMAGE_PULL_POLICY="IfNotPresent"
REPLICAS="1"; SERVICE_TYPE="ClusterIP"; HTTP_PORT="36789"; GRPC_PORT="36790"; JSONRPC_PORT="36791"
HTTP_NODE_PORT=""; GRPC_NODE_PORT=""; JSONRPC_NODE_PORT=""
STORE_DRIVER="boltdb"; STORE_HOST=""; STORE_PORT=""; STORE_USER=""; STORE_SECRET=""; STORE_DB=""; STORE_SCHEMA="public"
DB_INIT=true; DB_ADMIN_USER=""; DB_ADMIN_SECRET=""; DB_INIT_TIMEOUT="180s"; DB_INIT_BACKOFF_LIMIT="3"; DB_INIT_TTL_SECONDS="600"
REDIS_PREFIX="{a}"; DATA_EXPIRE="604800"; FINISHED_DATA_EXPIRE="86400"
MICRO_SERVICE_END_POINT=""; TRANS_CRON_INTERVAL="3"; TIMEOUT_TO_FAIL="35"; RETRY_INTERVAL="10"; REQUEST_TIMEOUT="3"; LOG_LEVEL="info"; ADMIN_BASE_PATH=""
REQUEST_CPU="100m"; REQUEST_MEMORY="128Mi"; LIMIT_CPU="1000m"; LIMIT_MEMORY="512Mi"
ACTION="help"; IMAGE_INDEX="$WORKDIR/images/image-index.tsv"
BASE_TEMPLATE="$WORKDIR/manifests/dtm-base.yaml.tmpl"; APP_TEMPLATE="$WORKDIR/manifests/dtm.yaml.tmpl"; DB_JOB_TEMPLATE="$WORKDIR/manifests/dtm-db-init-job.yaml.tmpl"
BASE_RENDERED="$WORKDIR/rendered-dtm-base.yaml"; APP_RENDERED="$WORKDIR/rendered-dtm.yaml"; DB_JOB_RENDERED="$WORKDIR/rendered-dtm-db-init-job.yaml"
DTM_IMAGE=""; MYSQL_CLIENT_IMAGE=""; POSTGRES_CLIENT_IMAGE=""; DB_INIT_IMAGE=""; INIT_SQL_B64=""

log(){ printf '[dtm-installer] %s\n' "$*"; }
warn(){ printf '[dtm-installer][WARN] %s\n' "$*" >&2; }
die(){ printf '[dtm-installer][ERROR] %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

usage(){ cat <<'USAGE'
DTM Kubernetes 离线安装器

用法:
  ./dtm-k8s-<version>-<arch>.run <动作> [参数]

动作:
  help            显示本帮助。
  show-defaults   输出默认参数。
  precheck        检查 kubectl/docker/tar 和集群连通性，不修改集群。
  install         导入镜像、初始化 MySQL/Postgres 库表、部署 DTM。
  uninstall       删除本安装器创建的 DTM 资源。
  status          查看 Deployment、Pod、Service、ConfigMap、Secret、DB init Job。

通用参数:
  -n, --namespace <ns>              命名空间，默认 dtm-system。
  --name <name>                     实例名，默认 dtm。
  --registry <repo-prefix>          目标内网仓库前缀，如 sealos.hub:5000/kube4。
  --registry-user <user>            目标仓库用户名。
  --registry-pass <pass>            目标仓库口令。
  --skip-image-prepare              跳过 docker load/tag/push。
  --kubeconfig <path>               指定 kubeconfig。
  --context <name>                  指定 kube context。
  --wait-timeout <duration>         等待 DTM rollout 超时，默认 180s。
  -y, --yes                         跳过确认。
  --dry-run                         只做 kubectl client dry-run。

DTM 服务参数:
  --replicas <n>                    副本数，默认 1。boltdb 只允许 1 副本。
  --image-pull-policy <policy>      IfNotPresent、Always、Never。
  --service-type <type>             ClusterIP、NodePort、LoadBalancer。
  --http-port <port>                HTTP 端口，默认 36789。
  --grpc-port <port>                gRPC 端口，默认 36790。
  --jsonrpc-port <port>             JSON-RPC 端口，默认 36791。
  --http-node-port <port>           NodePort 模式固定 HTTP NodePort。
  --grpc-node-port <port>           NodePort 模式固定 gRPC NodePort。
  --jsonrpc-node-port <port>        NodePort 模式固定 JSON-RPC NodePort。

存储参数:
  --store-driver <driver>           boltdb、mysql、postgres、redis，默认 boltdb。
  --store-host <host>               外部存储地址；mysql/postgres/redis 需要填写。
  --store-port <port>               外部存储端口；mysql 默认 3306，postgres 默认 5432。
  --store-user <user>               DTM 连接数据库的账号。
  --store-pass <pass>               DTM 连接数据库的口令，写入 Kubernetes Secret。
  --store-db <db>                   库名；mysql/postgres 默认 dtm。
  --store-schema <schema>           Postgres schema，默认 public。
  --redis-prefix <prefix>           Redis key 前缀，默认 {a}。

自动初始化库表参数:
  --skip-db-init                    跳过 MySQL/Postgres 初始化 Job。
  --db-admin-user <user>            建库建表账号；默认等于 --store-user。
  --db-admin-pass <pass>            建库建表口令；默认等于 --store-pass。
  --db-init-timeout <duration>      等待初始化 Job 完成超时，默认 180s。
  --db-init-backoff-limit <n>       初始化 Job 失败重试次数，默认 3。
  --db-init-ttl-seconds <n>         初始化 Job 完成后的保留秒数，默认 600。

账号说明:
  DTM 本身默认没有 Web 登录账号和密码；它只暴露 HTTP/gRPC/JSON-RPC 服务。
  请通过 Kubernetes NetworkPolicy、Ingress 鉴权、网关或上层 IAM 控制访问。
USAGE
}

show_defaults(){ cat <<EOF_DEFAULTS
namespace=$NS
name=$NAME
registry=$REGISTRY
service-type=$SERVICE_TYPE
replicas=$REPLICAS
store-driver=$STORE_DRIVER
store-db=mysql/postgres default: dtm
store-schema=$STORE_SCHEMA
db-init=$DB_INIT
db-init-timeout=$DB_INIT_TIMEOUT
EOF_DEFAULTS
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0;;
      -n|--namespace) NS="$2"; shift 2;; --name) NAME="$2"; shift 2;;
      --registry) REGISTRY="${2%/}"; shift 2;; --registry-user) REG_USER="$2"; shift 2;; --registry-pass) REG_SECRET="$2"; shift 2;; --skip-image-prepare) SKIP_IMAGE=true; shift;;
      --kubeconfig) KCFG="$2"; shift 2;; --context) KCTX="$2"; shift 2;; --wait-timeout) WAIT_TIMEOUT="$2"; shift 2;; -y|--yes) YES=true; shift;; --dry-run) DRY=true; shift;;
      --replicas) REPLICAS="$2"; shift 2;; --image-pull-policy) IMAGE_PULL_POLICY="$2"; shift 2;; --service-type) SERVICE_TYPE="$2"; shift 2;;
      --http-port) HTTP_PORT="$2"; shift 2;; --grpc-port) GRPC_PORT="$2"; shift 2;; --jsonrpc-port) JSONRPC_PORT="$2"; shift 2;;
      --http-node-port) HTTP_NODE_PORT="$2"; shift 2;; --grpc-node-port) GRPC_NODE_PORT="$2"; shift 2;; --jsonrpc-node-port) JSONRPC_NODE_PORT="$2"; shift 2;;
      --request-cpu) REQUEST_CPU="$2"; shift 2;; --request-memory) REQUEST_MEMORY="$2"; shift 2;; --limit-cpu) LIMIT_CPU="$2"; shift 2;; --limit-memory) LIMIT_MEMORY="$2"; shift 2;;
      --store-driver) STORE_DRIVER="$2"; shift 2;; --store-host) STORE_HOST="$2"; shift 2;; --store-port) STORE_PORT="$2"; shift 2;; --store-user) STORE_USER="$2"; shift 2;; --store-pass) STORE_SECRET="$2"; shift 2;; --store-db) STORE_DB="$2"; shift 2;; --store-schema) STORE_SCHEMA="$2"; shift 2;;
      --skip-db-init) DB_INIT=false; shift;; --db-admin-user) DB_ADMIN_USER="$2"; shift 2;; --db-admin-pass) DB_ADMIN_SECRET="$2"; shift 2;; --db-init-timeout) DB_INIT_TIMEOUT="$2"; shift 2;; --db-init-backoff-limit) DB_INIT_BACKOFF_LIMIT="$2"; shift 2;; --db-init-ttl-seconds) DB_INIT_TTL_SECONDS="$2"; shift 2;;
      --redis-prefix) REDIS_PREFIX="$2"; shift 2;; --data-expire) DATA_EXPIRE="$2"; shift 2;; --finished-data-expire) FINISHED_DATA_EXPIRE="$2"; shift 2;;
      --micro-service-endpoint) MICRO_SERVICE_END_POINT="$2"; shift 2;; --trans-cron-interval) TRANS_CRON_INTERVAL="$2"; shift 2;; --timeout-to-fail) TIMEOUT_TO_FAIL="$2"; shift 2;; --retry-interval) RETRY_INTERVAL="$2"; shift 2;; --request-timeout) REQUEST_TIMEOUT="$2"; shift 2;; --log-level) LOG_LEVEL="$2"; shift 2;; --admin-base-path) ADMIN_BASE_PATH="$2"; shift 2;;
      *) die "未知参数: $1；请执行 -h 查看中文说明";;
    esac
  done
}

is_sql_driver(){ [[ "$STORE_DRIVER" == "mysql" || "$STORE_DRIVER" == "postgres" ]]; }
db_init_required(){ $DB_INIT && is_sql_driver; }
validate_identifier(){ [[ "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "$1 只能包含字母、数字、下划线，并以字母或下划线开头"; }

validate(){
  case "$SERVICE_TYPE" in ClusterIP|NodePort|LoadBalancer);; *) die "--service-type 只支持 ClusterIP、NodePort、LoadBalancer";; esac
  case "$IMAGE_PULL_POLICY" in IfNotPresent|Always|Never);; *) die "--image-pull-policy 只支持 IfNotPresent、Always、Never";; esac
  case "$STORE_DRIVER" in boltdb|mysql|postgres|redis);; *) die "--store-driver 只支持 boltdb、mysql、postgres、redis";; esac
  case "$LOG_LEVEL" in debug|info|warn|error);; *) die "--log-level 只支持 debug、info、warn、error";; esac
  [[ "$REPLICAS" =~ ^[0-9]+$ ]] || die "--replicas 必须是数字"
  if [[ "$STORE_DRIVER" == "mysql" ]]; then [[ -n "$STORE_PORT" ]] || STORE_PORT="3306"; [[ -n "$STORE_DB" ]] || STORE_DB="dtm"; fi
  if [[ "$STORE_DRIVER" == "postgres" ]]; then [[ -n "$STORE_PORT" ]] || STORE_PORT="5432"; [[ -n "$STORE_DB" ]] || STORE_DB="dtm"; fi
  if is_sql_driver; then
    [[ -n "$STORE_HOST" ]] || die "--store-driver=$STORE_DRIVER 时必须指定 --store-host"
    [[ -n "$STORE_USER" ]] || die "--store-driver=$STORE_DRIVER 时必须指定 --store-user"
    validate_identifier "--store-db" "$STORE_DB"
    [[ "$STORE_DRIVER" != "postgres" ]] || validate_identifier "--store-schema" "$STORE_SCHEMA"
    [[ -n "$DB_ADMIN_USER" ]] || DB_ADMIN_USER="$STORE_USER"
    [[ -n "$DB_ADMIN_SECRET" ]] || DB_ADMIN_SECRET="$STORE_SECRET"
  fi
  if [[ "$STORE_DRIVER" == "boltdb" && "$REPLICAS" != "1" ]]; then die "boltdb 只适合单副本开发测试；多副本请使用 mysql/postgres/redis"; fi
  [[ -n "$MICRO_SERVICE_END_POINT" ]] || MICRO_SERVICE_END_POINT="$NAME.$NS.svc.cluster.local:$GRPC_PORT"
}

k(){ local a=(); [[ -n "$KCFG" ]] && a+=(--kubeconfig "$KCFG"); [[ -n "$KCTX" ]] && a+=(--context "$KCTX"); kubectl "${a[@]}" "$@"; }
confirm(){ $YES && return 0; printf '即将执行 %s: namespace=%s name=%s，继续？[y/N] ' "$ACTION" "$NS" "$NAME"; read -r ans || true; [[ "$ans" =~ ^[Yy](es)?$ ]] || die "用户取消"; }
target_ref_for(){ local suffix="${1##*/}"; [[ -n "$REGISTRY" ]] && printf '%s/%s\n' "${REGISTRY%/}" "$suffix" || printf '%s\n' "$1"; }

resolve_images(){
  while IFS='|' read -r name tar load def platform pull dockerfile; do
    [[ -n "$def" ]] || continue
    case "$name" in
      dtm) DTM_IMAGE="$(target_ref_for "$def")";;
      mysql-client) MYSQL_CLIENT_IMAGE="$(target_ref_for "$def")";;
      postgres-client) POSTGRES_CLIENT_IMAGE="$(target_ref_for "$def")";;
    esac
  done < "$IMAGE_INDEX"
  [[ -n "$DTM_IMAGE" ]] || die "找不到 dtm 镜像"
  if [[ "$STORE_DRIVER" == "mysql" ]]; then [[ -n "$MYSQL_CLIENT_IMAGE" ]] || die "找不到 mysql-client 镜像"; DB_INIT_IMAGE="$MYSQL_CLIENT_IMAGE"; INIT_SQL_B64="$(tr -d '\n' < "$WORKDIR/scripts/install/sql/mysql.b64")"; fi
  if [[ "$STORE_DRIVER" == "postgres" ]]; then [[ -n "$POSTGRES_CLIENT_IMAGE" ]] || die "找不到 postgres-client 镜像"; DB_INIT_IMAGE="$POSTGRES_CLIENT_IMAGE"; INIT_SQL_B64="$(tr -d '\n' < "$WORKDIR/scripts/install/sql/postgres.b64")"; fi
}

prepare_images(){
  $SKIP_IMAGE && return 0
  need docker
  if [[ -n "$REG_USER$REG_SECRET" ]]; then
    [[ -n "$REG_USER" && -n "$REG_SECRET" ]] || die "仓库用户名和口令必须同时填写"
    local flag="--password"; flag="${flag}-stdin"
    printf '%s' "$REG_SECRET" | docker login "${REGISTRY%%/*}" -u "$REG_USER" "$flag"
  fi
  while IFS='|' read -r name tar load def platform pull dockerfile; do
    [[ -n "$tar" ]] || continue
    local target; target="$(target_ref_for "$def")"
    docker load -i "$WORKDIR/images/$tar"
    [[ "$load" == "$target" ]] || docker tag "$load" "$target"
    docker push "$target"
  done < "$IMAGE_INDEX"
}

se(){ printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
ye(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
r(){ sed -i "s|$2|$(se "$3")|g" "$1"; }

render_common(){
  local f="$1" hn="" gn="" jn="" db_init_value="false"
  if [[ "$SERVICE_TYPE" == NodePort ]]; then [[ -n "$HTTP_NODE_PORT" ]] && hn="nodePort: $HTTP_NODE_PORT"; [[ -n "$GRPC_NODE_PORT" ]] && gn="nodePort: $GRPC_NODE_PORT"; [[ -n "$JSONRPC_NODE_PORT" ]] && jn="nodePort: $JSONRPC_NODE_PORT"; fi
  db_init_required && db_init_value="true"
  for kv in "__NAMESPACE__=$NS" "__APP_NAME__=$NAME" "__IMAGE__=$DTM_IMAGE" "__IMAGE_PULL_POLICY__=$IMAGE_PULL_POLICY" "__REPLICAS__=$REPLICAS" "__SERVICE_TYPE__=$SERVICE_TYPE" "__HTTP_PORT__=$HTTP_PORT" "__GRPC_PORT__=$GRPC_PORT" "__JSONRPC_PORT__=$JSONRPC_PORT" "__HTTP_NODE_PORT_LINE__=$hn" "__GRPC_NODE_PORT_LINE__=$gn" "__JSONRPC_NODE_PORT_LINE__=$jn" "__STORE_DRIVER__=$(ye "$STORE_DRIVER")" "__STORE_HOST__=$(ye "$STORE_HOST")" "__STORE_PORT__=$(ye "$STORE_PORT")" "__STORE_USER__=$(ye "$STORE_USER")" "__STORE_PASS__=$(ye "$STORE_SECRET")" "__STORE_DB__=$(ye "$STORE_DB")" "__STORE_SCHEMA__=$(ye "$STORE_SCHEMA")" "__DB_INIT_ENABLED__=$db_init_value" "__DB_ADMIN_USER__=$(ye "$DB_ADMIN_USER")" "__DB_ADMIN_PASS__=$(ye "$DB_ADMIN_SECRET")" "__REDIS_PREFIX__=$(ye "$REDIS_PREFIX")" "__DATA_EXPIRE__=$DATA_EXPIRE" "__FINISHED_DATA_EXPIRE__=$FINISHED_DATA_EXPIRE" "__MICRO_SERVICE_END_POINT__=$(ye "$MICRO_SERVICE_END_POINT")" "__TRANS_CRON_INTERVAL__=$TRANS_CRON_INTERVAL" "__TIMEOUT_TO_FAIL__=$TIMEOUT_TO_FAIL" "__RETRY_INTERVAL__=$RETRY_INTERVAL" "__REQUEST_TIMEOUT__=$REQUEST_TIMEOUT" "__LOG_LEVEL__=$LOG_LEVEL" "__ADMIN_BASE_PATH__=$(ye "$ADMIN_BASE_PATH")" "__REQUEST_CPU__=$REQUEST_CPU" "__REQUEST_MEMORY__=$REQUEST_MEMORY" "__LIMIT_CPU__=$LIMIT_CPU" "__LIMIT_MEMORY__=$LIMIT_MEMORY" "__DB_INIT_IMAGE__=$DB_INIT_IMAGE" "__INIT_SQL_B64__=$INIT_SQL_B64" "__DB_INIT_BACKOFF_LIMIT__=$DB_INIT_BACKOFF_LIMIT" "__DB_INIT_TTL_SECONDS__=$DB_INIT_TTL_SECONDS"; do r "$f" "${kv%%=*}" "${kv#*=}"; done
}

render_all(){ cp "$BASE_TEMPLATE" "$BASE_RENDERED"; render_common "$BASE_RENDERED"; cp "$APP_TEMPLATE" "$APP_RENDERED"; render_common "$APP_RENDERED"; cp "$DB_JOB_TEMPLATE" "$DB_JOB_RENDERED"; render_common "$DB_JOB_RENDERED"; }
precheck(){ need kubectl; need tar; $SKIP_IMAGE || need docker; k version --client >/dev/null; k cluster-info >/dev/null || warn "kubectl cluster-info 失败，install 时可能失败"; $SKIP_IMAGE || docker version >/dev/null; log "预检查完成"; }
apply_or_dry(){ if $DRY; then k apply --dry-run=client -f "$1"; else k apply -f "$1"; fi; }
delete_or_dry(){ if $DRY; then k delete --dry-run=client -f "$1" --ignore-not-found=true; else k delete -f "$1" --ignore-not-found=true; fi; }

install_action(){
  precheck; resolve_images; prepare_images; render_all
  if $DRY; then apply_or_dry "$BASE_RENDERED"; db_init_required && apply_or_dry "$DB_JOB_RENDERED"; apply_or_dry "$APP_RENDERED"; return 0; fi
  confirm
  k apply -f "$BASE_RENDERED"
  if db_init_required; then
    log "初始化 $STORE_DRIVER 数据库和 DTM 表结构"
    k delete job "$NAME-db-init" -n "$NS" --ignore-not-found=true >/dev/null 2>&1 || true
    k apply -f "$DB_JOB_RENDERED"
    k wait --for=condition=complete job/"$NAME-db-init" -n "$NS" --timeout="$DB_INIT_TIMEOUT"
    k logs job/"$NAME-db-init" -n "$NS" --tail=-1 || true
  else
    log "跳过数据库初始化: store-driver=$STORE_DRIVER db-init=$DB_INIT"
  fi
  k apply -f "$APP_RENDERED"
  k rollout status deployment/"$NAME" -n "$NS" --timeout="$WAIT_TIMEOUT"
  status_action
}

uninstall_action(){ need kubectl; resolve_images; render_all; confirm; delete_or_dry "$APP_RENDERED"; delete_or_dry "$DB_JOB_RENDERED"; delete_or_dry "$BASE_RENDERED"; }
status_action(){ need kubectl; k get deploy,po,svc,cm,secret,job -n "$NS" -l "app.kubernetes.io/instance=$NAME" -o wide || true; }

main(){ [[ $# -gt 0 ]] || { usage; exit 0; }; case "$1" in -h|--help|help) usage; exit 0;; show-defaults|precheck|install|uninstall|status) ACTION="$1"; shift;; *) die "未知动作: $1";; esac; parse_args "$@"; validate; case "$ACTION" in show-defaults) show_defaults;; precheck) precheck;; install) install_action;; uninstall) uninstall_action;; status) status_action;; esac; }
main "$@"
