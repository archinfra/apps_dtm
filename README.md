# apps_dtm

`apps_dtm` 用于把 DTM 打成 Kubernetes 一键离线部署 `.run` 包。

v0.2.0 开始，安装器支持 MySQL/Postgres 自动建库建表：先部署 Namespace/Secret/ConfigMap，再跑一次性 DB init Job，最后部署 DTM Deployment/Service。

## 本仓库交付形态

- 构建端执行 `bash build.sh --arch amd64|arm64|all` 生成 `.run` 和 `.sha256`。
- 构建端根据 `images/image.json` 拉取 DTM、MySQL 客户端、Postgres 客户端镜像，保存到 payload，并生成 `images/image-index.tsv`。
- 安装端执行 `.run install -y`，自动解压 payload、`docker load/tag/push`、渲染 Kubernetes YAML、初始化数据库并安装 DTM。
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
│   ├── dtm-base.yaml.tmpl
│   ├── dtm-db-init-job.yaml.tmpl
│   └── dtm.yaml.tmpl
├── scripts/install/
│   ├── dtm-installer.sh
│   └── sql/
│       ├── mysql.b64
│       └── postgres.b64
├── docs/
│   └── parameters.md
└── .github/workflows/offline-run-packages.yml
```

## 本地构建

构建机需要能访问上游镜像仓库，并安装 Docker、tar、sha256sum、python3。

```bash
bash -n build.sh install.sh scripts/install/dtm-installer.sh
python3 -m json.tool images/image.json >/dev/null

bash build.sh --arch amd64
bash build.sh --arch arm64
bash build.sh --arch all

ls -lh dist/
sha256sum -c dist/*.sha256
```

生成产物示例：

```text
dist/dtm-k8s-0.2.0-amd64.run
dist/dtm-k8s-0.2.0-amd64.run.sha256
dist/dtm-k8s-0.2.0-arm64.run
dist/dtm-k8s-0.2.0-arm64.run.sha256
```

## 安装流程

1. 从 `.run` 自身解压 payload。
2. 按 `images/image-index.tsv` 执行 `docker load`。
3. 将 DTM、MySQL 客户端、Postgres 客户端镜像重新 tag 到 `--registry` 指定的目标仓库前缀。
4. 执行 `docker push`。
5. 渲染并 apply `dtm-base.yaml.tmpl`，创建 Namespace、Secret、ConfigMap。
6. 如果 `--store-driver=mysql|postgres` 且没有 `--skip-db-init`，渲染并执行 `dtm-db-init-job.yaml.tmpl`。
7. DB init Job 成功后，渲染并 apply `dtm.yaml.tmpl`，创建 Deployment/Service。
8. 等待 Deployment rollout 完成。

## 快速安装

默认 `boltdb` 仅适合开发/测试单副本：

```bash
./dtm-k8s-0.2.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  -n dtm-system \
  -y
```

## 使用 Postgres 并自动建库建表

```bash
./dtm-k8s-0.2.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --store-driver postgres \
  --store-host postgres.default.svc \
  --store-port 5432 \
  --store-user dtm \
  --store-pass '<dtm-db-secret>' \
  --db-admin-user postgres \
  --db-admin-pass '<postgres-admin-secret>' \
  --store-db dtm \
  --store-schema public \
  -y
```

## 使用 MySQL 并自动建库建表

```bash
./dtm-k8s-0.2.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --store-driver mysql \
  --store-host mysql.default.svc \
  --store-port 3306 \
  --store-user dtm \
  --store-pass '<dtm-db-secret>' \
  --db-admin-user root \
  --db-admin-pass '<mysql-admin-secret>' \
  --store-db dtm \
  -y
```

## 参数说明

完整参数见：`docs/parameters.md`。

关键点：

- `--store-user/--store-pass` 是 DTM 运行时连接数据库的账号口令。
- `--db-admin-user/--db-admin-pass` 是初始化 Job 用于建库建表的账号口令。
- 如果不传 DB admin 参数，默认复用 store 参数。
- `--store-db` 在 MySQL/Postgres 下默认是 `dtm`。
- `--store-schema` 在 Postgres 下默认是 `public`。
- 可用 `--skip-db-init` 跳过自动初始化。

## DTM 自身账号密码

DTM 本身默认没有 Web 登录账号和密码。它暴露的是 HTTP、gRPC、JSON-RPC 服务，访问控制应由 Kubernetes NetworkPolicy、Ingress/Gateway 鉴权、内网 ACL 或上层 IAM 处理。

## GitHub Actions

工作流 `.github/workflows/offline-run-packages.yml` 支持：

- `workflow_dispatch` 手动选择 `amd64`、`arm64` 或 `all`。
- push 到 `main` 时构建双架构 artifact。
- push `v*` tag 时构建双架构 artifact 并发布 GitHub Release。

触发 Release 示例：

```bash
git tag v0.2.0
git push origin v0.2.0
```
