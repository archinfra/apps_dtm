#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="apps_dtm"
RUN_NAME="dtm-k8s"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/.build-payload"
PAYLOAD_TGZ="${ROOT_DIR}/payload.tar.gz"
IMAGE_JSON="${ROOT_DIR}/images/image.json"
INSTALL_SH="${ROOT_DIR}/install.sh"

usage() {
  cat <<'USAGE'
用法:
  bash build.sh --arch amd64
  bash build.sh --arch arm64
  bash build.sh --arch all

参数:
  --arch <amd64|arm64|all>  构建目标架构。all 会分别生成 amd64 和 arm64 两个 .run 包。
  -h, --help                显示本帮助。

构建产物:
  dist/dtm-k8s-<version>-amd64.run
  dist/dtm-k8s-<version>-amd64.run.sha256
  dist/dtm-k8s-<version>-arm64.run
  dist/dtm-k8s-<version>-arm64.run.sha256

说明:
  构建端允许依赖 docker、tar、sha256sum、python3。
  安装端不会依赖 jq/yq/python/node/npm/npx，只依赖基础 shell、tar、docker、kubectl。
USAGE
}

log() { printf '[build] %s\n' "$*"; }
die() { printf '[build][ERROR] %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

ARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || die "--arch 需要参数"
      ARCH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1"
      ;;
  esac
done

[[ -n "${ARCH}" ]] || die "必须指定 --arch amd64|arm64|all"
[[ "${ARCH}" == "amd64" || "${ARCH}" == "arm64" || "${ARCH}" == "all" ]] || die "--arch 只支持 amd64、arm64、all"

precheck() {
  need_cmd docker
  need_cmd tar
  need_cmd sha256sum
  need_cmd python3
  [[ -f "${INSTALL_SH}" ]] || die "缺少 install.sh"
  [[ -f "${IMAGE_JSON}" ]] || die "缺少 images/image.json"
  [[ -d "${ROOT_DIR}/manifests" ]] || die "缺少 manifests/"
  [[ -d "${ROOT_DIR}/scripts/install" ]] || die "缺少 scripts/install/"
  python3 -m json.tool "${IMAGE_JSON}" >/dev/null || die "images/image.json 不是合法 JSON"
  grep -qx '__PAYLOAD_BELOW__' "${INSTALL_SH}" || die "install.sh 必须包含独立行 __PAYLOAD_BELOW__"
  bash -n "${INSTALL_SH}" || die "install.sh 语法检查失败"
  bash -n "${ROOT_DIR}/scripts/install/dtm-installer.sh" || die "scripts/install/dtm-installer.sh 语法检查失败"
}

json_to_index() {
  local arch="$1"
  python3 - "${IMAGE_JSON}" "${arch}" <<'PY'
import json, sys
path, arch = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
rows = [x for x in data if x.get('arch') == arch]
if not rows:
    raise SystemExit(f'images/image.json 中没有架构 {arch} 的镜像')
for item in rows:
    name = item.get('name', '')
    tar = item.get('tar')
    tag = item.get('tag')
    pull = item.get('pull', '')
    dockerfile = item.get('dockerfile', '')
    platform = item.get('platform', '')
    if not tar or not tag:
        raise SystemExit('每个镜像必须包含 tar 和 tag')
    if bool(pull) == bool(dockerfile):
        raise SystemExit('每个镜像必须在 pull 和 dockerfile 中二选一')
    print('|'.join([name, tar, tag, tag, platform, pull, dockerfile]))
PY
}

copy_payload_files() {
  local payload_dir="$1"
  mkdir -p "${payload_dir}/manifests" "${payload_dir}/images" "${payload_dir}/scripts/install"
  cp -a "${ROOT_DIR}/manifests/." "${payload_dir}/manifests/"
  cp -a "${ROOT_DIR}/scripts/install/." "${payload_dir}/scripts/install/"
  cp "${IMAGE_JSON}" "${payload_dir}/images/image.json"
  cp "${ROOT_DIR}/VERSION" "${payload_dir}/VERSION"
}

prepare_images() {
  local arch="$1"
  local payload_dir="$2"
  local index_file="${payload_dir}/images/image-index.tsv"
  : > "${index_file}"

  while IFS='|' read -r name tar_name load_ref default_target_ref platform pull dockerfile; do
    [[ -n "${tar_name}" ]] || continue
    log "处理镜像: ${name:-unknown} arch=${arch} platform=${platform:-auto}"
    if [[ -n "${pull}" ]]; then
      if [[ -n "${platform}" ]]; then
        docker pull --platform "${platform}" "${pull}"
      else
        docker pull "${pull}"
      fi
      docker tag "${pull}" "${load_ref}"
    else
      local dockerfile_path="${ROOT_DIR}/${dockerfile}"
      [[ -f "${dockerfile_path}" ]] || die "Dockerfile 不存在: ${dockerfile}"
      local build_args=(buildx build --load)
      [[ -n "${platform}" ]] && build_args+=(--platform "${platform}")
      build_args+=(-f "${dockerfile_path}" -t "${load_ref}" "${ROOT_DIR}")
      docker "${build_args[@]}"
    fi
    docker save -o "${payload_dir}/images/${tar_name}" "${load_ref}"
    printf '%s|%s|%s|%s|%s|%s|%s\n' "${name}" "${tar_name}" "${load_ref}" "${default_target_ref}" "${platform}" "${pull}" "${dockerfile}" >> "${index_file}"
  done < <(json_to_index "${arch}")
}

build_one_arch() {
  local arch="$1"
  local run_file="${DIST_DIR}/${RUN_NAME}-${VERSION}-${arch}.run"
  local sha_file="${run_file}.sha256"

  log "开始构建 ${RUN_NAME} ${VERSION} ${arch}"
  rm -rf "${BUILD_DIR}" "${PAYLOAD_TGZ}"
  mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

  copy_payload_files "${BUILD_DIR}"
  prepare_images "${arch}" "${BUILD_DIR}"

  (cd "${BUILD_DIR}" && tar -czf "${PAYLOAD_TGZ}" .)
  tar -tzf "${PAYLOAD_TGZ}" >/dev/null || die "payload.tar.gz 校验失败"

  cat "${INSTALL_SH}" "${PAYLOAD_TGZ}" > "${run_file}"
  chmod +x "${run_file}"
  (cd "${DIST_DIR}" && sha256sum "$(basename "${run_file}")" > "$(basename "${sha_file}")")
  log "完成: ${run_file}"
  log "校验: ${sha_file}"
}

main() {
  precheck
  case "${ARCH}" in
    amd64|arm64) build_one_arch "${ARCH}" ;;
    all)
      build_one_arch amd64
      build_one_arch arm64
      ;;
  esac
}

main "$@"
