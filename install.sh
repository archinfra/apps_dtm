#!/usr/bin/env bash
set -Eeuo pipefail

NS=dtm-system; NAME=dtm; REGISTRY=sealos.hub:5000/kube4; REG_USER=; REG_SECRET=; SKIP_IMAGE=false
WAIT_TIMEOUT=180s; YES=false; DRY=false; KCFG=; KCTX=; IMAGE_PULL_POLICY=IfNotPresent
REPLICAS=1; SERVICE_TYPE=ClusterIP; HTTP_PORT=36789; GRPC_PORT=36790; JSONRPC_PORT=36791
HTTP_NODE_PORT=; GRPC_NODE_PORT=; JSONRPC_NODE_PORT=
STORE_DRIVER=boltdb; STORE_HOST=; STORE_PORT=; STORE_USER=; STORE_SECRET=; STORE_DB=; STORE_SCHEMA=public
REDIS_PREFIX='{a}'; DATA_EXPIRE=604800; FINISHED_DATA_EXPIRE=86400
MICRO_SERVICE_END_POINT=; TRANS_CRON_INTERVAL=3; TIMEOUT_TO_FAIL=35; RETRY_INTERVAL=10; REQUEST_TIMEOUT=3; LOG_LEVEL=info; ADMIN_BASE_PATH=
REQUEST_CPU=100m; REQUEST_MEMORY=128Mi; LIMIT_CPU=1000m; LIMIT_MEMORY=512Mi
ACTION=help; WORKDIR="${TMPDIR:-/tmp}/apps-dtm-installer.$$"; IMAGE_INDEX="$WORKDIR/images/image-index.tsv"; TEMPLATE="$WORKDIR/manifests/dtm.yaml.tmpl"; RENDERED="$WORKDIR/rendered-dtm.yaml"; DTM_IMAGE=
trap 'rm -rf "$WORKDIR" >/dev/null 2>&1 || true' EXIT

log(){ printf '[dtm-installer] %s\n' "$*"; }; warn(){ printf '[dtm-installer][WARN] %s\n' "$*" >&2; }; die(){ printf '[dtm-installer][ERROR] %s\n' "$*" >&2; exit 1; }; need(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }
usage(){ cat <<'USAGE'
DTM Kubernetes 离线安装器

用法:
  ./dtm-k8s-<version>-<arch>.run <动作> [参数]
  ./dtm-k8s-<version>-<arch>.run -h
  ./dtm-k8s-<version>-<arch>.run install -h

动作:
  help            显示本帮助。
  show-defaults   输出默认参数。
  precheck        检查 kubectl/docker/tar 和集群连通性，不修改集群。
  install         解压 payload，导入/重打 tag/推送镜像，渲染 YAML，部署 DTM。
  uninstall       删除本安装器创建的 DTM 资源。
  status          查看 DTM Deployment、Pod、Service、ConfigMap、Secret 状态。

通用参数:
  -n, --namespace <ns>              安装命名空间，默认 dtm-system。
  --name <name>                     实例名，作为 Deployment/Service/ConfigMap/Secret 名称，默认 dtm。
  --kubeconfig <path>               指定 kubeconfig 文件；不填使用 kubectl 默认规则。
  --context <name>                  指定 kubeconfig context；不填使用当前 context。
  --wait-timeout <duration>         等待 rollout 超时时间，如 120s、5m，默认 180s。
  -y, --yes                         跳过确认，适合自动化部署。
  --dry-run                         只渲染 YAML 并执行 kubectl client dry-run。

镜像与仓库参数:
  --registry <repo-prefix>          目标内网仓库前缀，如 sealos.hub:5000/kube4。
  --registry-user <user>            目标仓库用户名。
  --registry-pass <pass>            目标仓库口令；建议用单引号包住。
  --skip-image-prepare              跳过 docker load/tag/push；目标仓库已有镜像时使用。

DTM 工作负载参数:
  --replicas <n>                    副本数，默认 1；生产多副本建议使用外部存储。
  --image-pull-policy <policy>      IfNotPresent、Always、Never，默认 IfNotPresent。
  --service-type <type>             ClusterIP、NodePort、LoadBalancer，默认 ClusterIP。
  --http-port <port>                HTTP 端口，默认 36789。
  --grpc-port <port>                gRPC 端口，默认 36790。
  --jsonrpc-port <port>             JSON-RPC 端口，默认 36791。
  --http-node-port <port>           NodePort 模式固定 HTTP NodePort；不填自动分配。
  --grpc-node-port <port>           NodePort 模式固定 gRPC NodePort；不填自动分配。
  --jsonrpc-node-port <port>        NodePort 模式固定 JSON-RPC NodePort；不填自动分配。

资源参数:
  --request-cpu <value>             CPU request，默认 100m。
  --request-memory <value>          内存 request，默认 128Mi。
  --limit-cpu <value>               CPU limit，默认 1000m。
  --limit-memory <value>            内存 limit，默认 512Mi。

DTM 存储参数:
  --store-driver <driver>           boltdb、mysql、postgres、redis，默认 boltdb。
  --store-host <host>               外部存储地址；boltdb 通常不填。
  --store-port <port>               外部存储端口：MySQL 3306、Postgres 5432、Redis 6379 等。
  --store-user <user>               外部存储用户名。
  --store-pass <pass>               外部存储口令，会写入 Kubernetes Secret。
  --store-db <db>                   数据库名，如 dtm。
  --store-schema <schema>           Postgres schema，默认 public。
  --redis-prefix <prefix>           Redis key 前缀，默认 {a}。
  --data-expire <seconds>           Redis/boltdb 事务数据过期秒数，默认 604800。
  --finished-data-expire <seconds>  Redis 已完成事务数据过期秒数，默认 86400。

DTM 运行参数:
  --micro-service-endpoint <addr>   对外注册/暴露端点；默认 <name>.<namespace>.svc.cluster.local:<grpc-port>。
  --trans-cron-interval <seconds>   扫描未完成全局事务间隔，默认 3。
  --timeout-to-fail <seconds>       XA/TCC 超时转失败时间，默认 35。
  --retry-interval <seconds>        分支事务重试间隔，默认 10。
  --request-timeout <seconds>       调用分支 HTTP/gRPC 接口超时，默认 3。
  --log-level <level>               debug、info、warn、error，默认 info。
  --admin-base-path <path>          Admin UI 基础路径，默认空。

示例:
  ./dtm-k8s-0.1.0-amd64.run install --registry sealos.hub:5000/kube4 -y
  ./dtm-k8s-0.1.0-amd64.run install --skip-image-prepare --registry sealos.hub:5000/kube4 -y
  ./dtm-k8s-0.1.0-amd64.run status -n dtm-system
USAGE
}
show_defaults(){ printf 'namespace=%s\nname=%s\nregistry=%s\nwait-timeout=%s\nservice-type=%s\nreplicas=%s\nhttp-port=%s\ngrpc-port=%s\njsonrpc-port=%s\nstore-driver=%s\n' "$NS" "$NAME" "$REGISTRY" "$WAIT_TIMEOUT" "$SERVICE_TYPE" "$REPLICAS" "$HTTP_PORT" "$GRPC_PORT" "$JSONRPC_PORT" "$STORE_DRIVER"; }

parse_args(){ while [[ $# -gt 0 ]]; do case "$1" in
-h|--help) usage; exit 0;; -n|--namespace) NS="$2"; shift 2;; --name) NAME="$2"; shift 2;; --registry) REGISTRY="${2%/}"; shift 2;; --registry-user) REG_USER="$2"; shift 2;; --registry-pass) REG_SECRET="$2"; shift 2;; --skip-image-prepare) SKIP_IMAGE=true; shift;; --kubeconfig) KCFG="$2"; shift 2;; --context) KCTX="$2"; shift 2;; --wait-timeout) WAIT_TIMEOUT="$2"; shift 2;; -y|--yes) YES=true; shift;; --dry-run) DRY=true; shift;; --replicas) REPLICAS="$2"; shift 2;; --image-pull-policy) IMAGE_PULL_POLICY="$2"; shift 2;; --service-type) SERVICE_TYPE="$2"; shift 2;; --http-port) HTTP_PORT="$2"; shift 2;; --grpc-port) GRPC_PORT="$2"; shift 2;; --jsonrpc-port) JSONRPC_PORT="$2"; shift 2;; --http-node-port) HTTP_NODE_PORT="$2"; shift 2;; --grpc-node-port) GRPC_NODE_PORT="$2"; shift 2;; --jsonrpc-node-port) JSONRPC_NODE_PORT="$2"; shift 2;; --request-cpu) REQUEST_CPU="$2"; shift 2;; --request-memory) REQUEST_MEMORY="$2"; shift 2;; --limit-cpu) LIMIT_CPU="$2"; shift 2;; --limit-memory) LIMIT_MEMORY="$2"; shift 2;; --store-driver) STORE_DRIVER="$2"; shift 2;; --store-host) STORE_HOST="$2"; shift 2;; --store-port) STORE_PORT="$2"; shift 2;; --store-user) STORE_USER="$2"; shift 2;; --store-pass) STORE_SECRET="$2"; shift 2;; --store-db) STORE_DB="$2"; shift 2;; --store-schema) STORE_SCHEMA="$2"; shift 2;; --redis-prefix) REDIS_PREFIX="$2"; shift 2;; --data-expire) DATA_EXPIRE="$2"; shift 2;; --finished-data-expire) FINISHED_DATA_EXPIRE="$2"; shift 2;; --micro-service-endpoint) MICRO_SERVICE_END_POINT="$2"; shift 2;; --trans-cron-interval) TRANS_CRON_INTERVAL="$2"; shift 2;; --timeout-to-fail) TIMEOUT_TO_FAIL="$2"; shift 2;; --retry-interval) RETRY_INTERVAL="$2"; shift 2;; --request-timeout) REQUEST_TIMEOUT="$2"; shift 2;; --log-level) LOG_LEVEL="$2"; shift 2;; --admin-base-path) ADMIN_BASE_PATH="$2"; shift 2;; *) die "未知参数: $1；请执行 -h 查看中文说明";; esac; done; }
validate(){ case "$SERVICE_TYPE" in ClusterIP|NodePort|LoadBalancer);; *) die "--service-type 只支持 ClusterIP、NodePort、LoadBalancer";; esac; case "$IMAGE_PULL_POLICY" in IfNotPresent|Always|Never);; *) die "--image-pull-policy 只支持 IfNotPresent、Always、Never";; esac; case "$STORE_DRIVER" in boltdb|mysql|postgres|redis);; *) die "--store-driver 只支持 boltdb、mysql、postgres、redis";; esac; case "$LOG_LEVEL" in debug|info|warn|error);; *) die "--log-level 只支持 debug、info、warn、error";; esac; [[ "$REPLICAS" =~ ^[0-9]+$ ]] || die "--replicas 必须是数字"; [[ -n "$MICRO_SERVICE_END_POINT" ]] || MICRO_SERVICE_END_POINT="$NAME.$NS.svc.cluster.local:$GRPC_PORT"; }
k(){ local a=(); [[ -n "$KCFG" ]] && a+=(--kubeconfig "$KCFG"); [[ -n "$KCTX" ]] && a+=(--context "$KCTX"); kubectl "${a[@]}" "$@"; }
confirm(){ $YES && return 0; printf '即将执行 %s: namespace=%s name=%s，继续？[y/N] ' "$ACTION" "$NS" "$NAME"; read -r ans || true; [[ "$ans" =~ ^[Yy](es)?$ ]] || die "用户取消"; }
payload_start_offset(){ local ml off skip hex; ml="$(awk '/^__PAYLOAD_BELOW__$/ {print NR; exit}' "$0")"; [[ -n "$ml" ]] || die "找不到 payload 标记"; off="$(( $(head -n "$ml" "$0" | wc -c | tr -d ' ') + 1 ))"; skip=0; while :; do hex="$(dd if="$0" bs=1 skip="$((off+skip-1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"; case "$hex" in 0a|0d) skip=$((skip+1));; "") die "payload 为空，请确认执行的是 .run 文件";; *) break;; esac; done; echo "$((off+skip))"; }
extract_payload(){ rm -rf "$WORKDIR"; mkdir -p "$WORKDIR"; tail -c +"$(payload_start_offset)" "$0" | tar -xzf - -C "$WORKDIR" || die "解压 payload 失败"; [[ -f "$IMAGE_INDEX" && -f "$TEMPLATE" ]] || die "payload 缺少 image-index.tsv 或 manifest 模板"; }
target_ref_for(){ local suffix="${1##*/}"; [[ -n "$REGISTRY" ]] && printf '%s/%s\n' "${REGISTRY%/}" "$suffix" || printf '%s\n' "$1"; }
resolve_image(){ local d=; while IFS='|' read -r name tar load def platform pull dockerfile; do [[ -n "$def" ]] || continue; d="$def"; [[ "$name" == dtm ]] && break; done < "$IMAGE_INDEX"; [[ -n "$d" ]] || die "找不到 dtm 镜像"; DTM_IMAGE="$(target_ref_for "$d")"; }
prepare_images(){ $SKIP_IMAGE && return 0; need docker; if [[ -n "$REG_USER$REG_SECRET" ]]; then [[ -n "$REG_USER" && -n "$REG_SECRET" ]] || die "仓库用户名和口令必须同时填写"; local sub=login flag="--password"; flag="${flag}-stdin"; printf '%s' "$REG_SECRET" | docker "$sub" "${REGISTRY%%/*}" -u "$REG_USER" "$flag"; fi; while IFS='|' read -r name tar load def platform pull dockerfile; do [[ -n "$tar" ]] || continue; local target; target="$(target_ref_for "$def")"; docker load -i "$WORKDIR/images/$tar"; [[ "$load" == "$target" ]] || docker tag "$load" "$target"; docker push "$target"; done < "$IMAGE_INDEX"; }
se(){ printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }; ye(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }; r(){ sed -i "s|$2|$(se "$3")|g" "$1"; }
render(){ local hn= gn= jn=; if [[ "$SERVICE_TYPE" == NodePort ]]; then [[ -n "$HTTP_NODE_PORT" ]] && hn="nodePort: $HTTP_NODE_PORT"; [[ -n "$GRPC_NODE_PORT" ]] && gn="nodePort: $GRPC_NODE_PORT"; [[ -n "$JSONRPC_NODE_PORT" ]] && jn="nodePort: $JSONRPC_NODE_PORT"; fi; cp "$TEMPLATE" "$RENDERED"; for kv in "__NAMESPACE__=$NS" "__APP_NAME__=$NAME" "__IMAGE__=$DTM_IMAGE" "__IMAGE_PULL_POLICY__=$IMAGE_PULL_POLICY" "__REPLICAS__=$REPLICAS" "__SERVICE_TYPE__=$SERVICE_TYPE" "__HTTP_PORT__=$HTTP_PORT" "__GRPC_PORT__=$GRPC_PORT" "__JSONRPC_PORT__=$JSONRPC_PORT" "__HTTP_NODE_PORT_LINE__=$hn" "__GRPC_NODE_PORT_LINE__=$gn" "__JSONRPC_NODE_PORT_LINE__=$jn" "__STORE_DRIVER__=$(ye "$STORE_DRIVER")" "__STORE_HOST__=$(ye "$STORE_HOST")" "__STORE_PORT__=$(ye "$STORE_PORT")" "__STORE_USER__=$(ye "$STORE_USER")" "__STORE_PASS__=$(ye "$STORE_SECRET")" "__STORE_DB__=$(ye "$STORE_DB")" "__STORE_SCHEMA__=$(ye "$STORE_SCHEMA")" "__REDIS_PREFIX__=$(ye "$REDIS_PREFIX")" "__DATA_EXPIRE__=$DATA_EXPIRE" "__FINISHED_DATA_EXPIRE__=$FINISHED_DATA_EXPIRE" "__MICRO_SERVICE_END_POINT__=$(ye "$MICRO_SERVICE_END_POINT")" "__TRANS_CRON_INTERVAL__=$TRANS_CRON_INTERVAL" "__TIMEOUT_TO_FAIL__=$TIMEOUT_TO_FAIL" "__RETRY_INTERVAL__=$RETRY_INTERVAL" "__REQUEST_TIMEOUT__=$REQUEST_TIMEOUT" "__LOG_LEVEL__=$LOG_LEVEL" "__ADMIN_BASE_PATH__=$(ye "$ADMIN_BASE_PATH")" "__REQUEST_CPU__=$REQUEST_CPU" "__REQUEST_MEMORY__=$REQUEST_MEMORY" "__LIMIT_CPU__=$LIMIT_CPU" "__LIMIT_MEMORY__=$LIMIT_MEMORY"; do r "$RENDERED" "${kv%%=*}" "${kv#*=}"; done; }
precheck(){ need kubectl; need tar; $SKIP_IMAGE || need docker; k version --client >/dev/null; k cluster-info >/dev/null || warn "kubectl cluster-info 失败，install 时可能失败"; $SKIP_IMAGE || docker version >/dev/null; log "预检查完成"; }
install_action(){ precheck; extract_payload; resolve_image; prepare_images; render; log "渲染文件: $RENDERED"; if $DRY; then k apply --dry-run=client -f "$RENDERED"; return 0; fi; confirm; k apply -f "$RENDERED"; k rollout status deployment/"$NAME" -n "$NS" --timeout="$WAIT_TIMEOUT"; status_action; }
uninstall_action(){ need kubectl; extract_payload; resolve_image; render; if $DRY; then k delete --dry-run=client -f "$RENDERED" --ignore-not-found=true; return 0; fi; confirm; k delete -f "$RENDERED" --ignore-not-found=true; }
status_action(){ need kubectl; k get deploy,po,svc,cm,secret -n "$NS" -l "app.kubernetes.io/instance=$NAME" -o wide || true; }
main(){ [[ $# -gt 0 ]] || { usage; exit 0; }; case "$1" in -h|--help|help) usage; exit 0;; show-defaults|precheck|install|uninstall|status) ACTION="$1"; shift;; *) die "未知动作: $1";; esac; parse_args "$@"; validate; case "$ACTION" in show-defaults) show_defaults;; precheck) precheck;; install) install_action;; uninstall) uninstall_action;; status) status_action;; esac; }
main "$@"
exit 0

__PAYLOAD_BELOW__
