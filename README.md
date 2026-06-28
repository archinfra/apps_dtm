# apps_dtm

`apps_dtm` 用于把 [DTM](https://github.com/dtm-labs/dtm) 打成 Kubernetes 一键离线部署 `.run` 包。

本仓库遵循 `archinfra` 离线交付规范：

- 构建端执行 `bash build.sh --arch amd64|arm64|all` 生成 `.run` 和 `.sha256`。
- 构建端根据 `images/image.json` 拉取 DTM 镜像，保存到 payload，并生成 `images/image-index.tsv`。
- 安装端执行 `.run install -y`，自动解压 payload、`docker load/tag/push`、按 `--registry` 渲染 Kubernetes YAML 并执行 `kubectl apply`。
- 安装端不依赖 `jq/yq/python/node/npm/npx`，只使用基础 shell、tar、docker、kubectl。

## 目录结构

```text
.
├── VERSION
├── build.sh
├── install.sh
├── images/
│   └── image.json
├── manifests/
│   └── dtm.yaml.tmpl
├── docs/
│   └── parameters.md
└── .github/workflows/offline-run-packages.yml
```

## 本地构建

构建机需要能访问上游镜像仓库，并安装 Docker、tar、sha256sum、python3。

```bash
bash -n build.sh install.sh
python3 -m json.tool images/image.json >/dev/null

bash build.sh --arch amd64
bash build.sh --arch arm64
# 或一次性构建双架构
bash build.sh --arch all

ls -lh dist/
sha256sum -c dist/*.sha256
```

生成产物示例：

```text
dist/dtm-k8s-0.1.0-amd64.run
dist/dtm-k8s-0.1.0-amd64.run.sha256
dist/dtm-k8s-0.1.0-arm64.run
dist/dtm-k8s-0.1.0-arm64.run.sha256
```

## 一键安装

```bash
chmod +x dtm-k8s-0.1.0-amd64.run

./dtm-k8s-0.1.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --registry-user admin \
  --registry-pass '<registry-password>' \
  -n dtm-system \
  -y
```

安装逻辑：

1. 从 `.run` 自身解压 payload。
2. 按 `images/image-index.tsv` 执行 `docker load`。
3. 将镜像重新 tag 到 `--registry` 指定的目标仓库前缀。
4. 执行 `docker push`。
5. 渲染 `manifests/dtm.yaml.tmpl`。
6. 执行 `kubectl apply -f rendered-dtm.yaml`。
7. 等待 Deployment rollout 完成。

## 已有镜像时跳过导入推送

如果现场内网仓库已经提前准备好 DTM 镜像，可以跳过 `docker load/tag/push`：

```bash
./dtm-k8s-0.1.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

YAML 里的镜像地址仍会渲染为 `sealos.hub:5000/kube4/dtm:latest`。

## 使用外部 Postgres

DTM 默认使用 `boltdb`，适合开发或测试单副本。生产建议使用 MySQL、Postgres 或 Redis 等外部存储。

```bash
./dtm-k8s-0.1.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --store-driver postgres \
  --store-host postgres.default.svc \
  --store-port 5432 \
  --store-user postgres \
  --store-pass '<postgres-password>' \
  --store-db dtm \
  --store-schema public \
  -y
```

## 暴露 NodePort

```bash
./dtm-k8s-0.1.0-amd64.run install \
  --service-type NodePort \
  --http-node-port 30089 \
  --grpc-node-port 30090 \
  --jsonrpc-node-port 30091 \
  -y
```

## 查看帮助

所有参数都有中文说明：

```bash
./dtm-k8s-0.1.0-amd64.run -h
./dtm-k8s-0.1.0-amd64.run install -h
./dtm-k8s-0.1.0-amd64.run show-defaults
```

## 查看状态与卸载

```bash
./dtm-k8s-0.1.0-amd64.run status -n dtm-system

./dtm-k8s-0.1.0-amd64.run uninstall \
  -n dtm-system \
  -y
```

## GitHub Actions

工作流 `.github/workflows/offline-run-packages.yml` 支持：

- `workflow_dispatch` 手动选择 `amd64`、`arm64` 或 `all`。
- push 到 `main` 时构建双架构 artifact。
- push `v*` tag 时构建双架构 artifact 并发布 GitHub Release。

触发 Release 示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 维护镜像版本

DTM 镜像入口在 `images/image.json`：

```json
{
  "name": "dtm",
  "arch": "amd64",
  "platform": "linux/amd64",
  "pull": "yedf/dtm:latest",
  "tag": "sealos.hub:5000/kube4/dtm:latest",
  "tar": "dtm-latest-amd64.tar"
}
```

如果后续要固定到某个版本，先确认 Docker registry 中该 tag 存在，再同步修改：

1. `images/image.json` 中 `pull/tag/tar`。
2. 必要时更新 `VERSION`。
3. 本地执行 `bash build.sh --arch amd64` 做最小验证。
