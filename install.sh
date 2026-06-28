#!/usr/bin/env bash
set -Eeuo pipefail

WORKDIR="${TMPDIR:-/tmp}/apps-dtm-installer.$$"
trap 'rm -rf "${WORKDIR}" >/dev/null 2>&1 || true' EXIT

die(){ printf '[dtm-installer][ERROR] %s\n' "$*" >&2; exit 1; }

usage(){ cat <<'USAGE'
DTM Kubernetes 离线安装器

用法:
  ./dtm-k8s-<version>-<arch>.run <动作> [参数]

动作:
  help            显示帮助。
  show-defaults   输出默认参数。
  precheck        检查 kubectl/docker/tar 和集群连通性。
  install         导入镜像、初始化 MySQL/Postgres 库表、部署 DTM。
  uninstall       删除本安装器创建的 DTM 资源。
  status          查看 Deployment、Pod、Service、ConfigMap、Secret、DB init Job。

常用安装示例:
  ./dtm-k8s-0.2.0-amd64.run install --registry sealos.hub:5000/kube4 -y

Postgres 自动建库建表示例:
  ./dtm-k8s-0.2.0-amd64.run install \
    --store-driver postgres \
    --store-host postgres.default.svc \
    --store-port 5432 \
    --store-user dtm \
    --store-pass '<dtm-db-password>' \
    --db-admin-user postgres \
    --db-admin-pass '<postgres-admin-password>' \
    --store-db dtm \
    --store-schema public \
    -y

MySQL 自动建库建表示例:
  ./dtm-k8s-0.2.0-amd64.run install \
    --store-driver mysql \
    --store-host mysql.default.svc \
    --store-port 3306 \
    --store-user dtm \
    --store-pass '<dtm-db-password>' \
    --db-admin-user root \
    --db-admin-pass '<mysql-root-password>' \
    --store-db dtm \
    -y

关键参数:
  -n, --namespace <ns>              命名空间，默认 dtm-system。
  --name <name>                     实例名，默认 dtm。
  --registry <repo-prefix>          目标内网仓库前缀。
  --skip-image-prepare              跳过 docker load/tag/push。
  --store-driver <driver>           boltdb、mysql、postgres、redis。
  --store-db <db>                   库名；mysql/postgres 默认 dtm。
  --store-schema <schema>           Postgres schema，默认 public。
  --skip-db-init                    跳过 MySQL/Postgres 初始化 Job。
  --db-admin-user <user>            建库建表账号；默认等于 --store-user。
  --db-admin-pass <pass>            建库建表口令；默认等于 --store-pass。
  --db-init-timeout <duration>      等待初始化 Job 完成超时，默认 180s。

账号说明:
  DTM 本身默认没有 Web 登录账号和密码；它只暴露 HTTP/gRPC/JSON-RPC 服务。
  需要通过 Kubernetes NetworkPolicy、Ingress 鉴权、网关或上层 IAM 控制访问。
USAGE
}

payload_start_offset(){
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || die "Payload marker not found"
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"
  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in
      0a|0d) skip_bytes=$((skip_bytes + 1)) ;;
      "") die "Payload is empty. 请执行构建后的 .run 文件，而不是源码 install.sh。" ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$((payload_offset + skip_bytes))"
}

extract_payload(){
  rm -rf "${WORKDIR}"
  mkdir -p "${WORKDIR}"
  tail -c +"$(payload_start_offset)" "$0" | tar -xzf - -C "${WORKDIR}" || die "Failed to extract payload"
  [[ -f "${WORKDIR}/scripts/install/dtm-installer.sh" ]] || die "Payload is missing scripts/install/dtm-installer.sh"
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

extract_payload
bash "${WORKDIR}/scripts/install/dtm-installer.sh" "${WORKDIR}" "$@"
exit $?

__PAYLOAD_BELOW__
