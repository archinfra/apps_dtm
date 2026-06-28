# DTM Kubernetes 离线安装参数说明

本文档用于现场部署前评审参数。v0.2.0 开始，安装器支持 MySQL/Postgres 自动建库建表。

## 动作

| 动作 | 说明 |
| --- | --- |
| `help` | 显示中文帮助。 |
| `show-defaults` | 输出安装器默认值。 |
| `precheck` | 检查 kubectl、docker、tar 和集群访问，不改动集群。 |
| `install` | 导入镜像、推送内网仓库、先初始化 MySQL/Postgres 库表，再部署 DTM。 |
| `uninstall` | 删除本包创建的 DTM 资源。默认不会删除外部 MySQL/Postgres 数据。 |
| `status` | 查看 Deployment、Pod、Service、ConfigMap、Secret、DB init Job 状态。 |

## DTM 自身账号说明

DTM 本身默认没有 Web 登录账号和密码。它暴露的是 HTTP、gRPC、JSON-RPC 服务，访问控制应放在 Kubernetes NetworkPolicy、Ingress/Gateway 鉴权、内网 ACL 或上层 IAM。

## 通用参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-n, --namespace` | `dtm-system` | 安装命名空间。 |
| `--name` | `dtm` | DTM 实例名，也是 Deployment/Service/ConfigMap/Secret 名称前缀。 |
| `--kubeconfig` | 空 | 指定 kubeconfig 文件路径。 |
| `--context` | 空 | 指定 kubeconfig context。 |
| `--wait-timeout` | `180s` | 等待 Deployment rollout 的超时时间。 |
| `-y, --yes` | `false` | 跳过确认。 |
| `--dry-run` | `false` | 只做 kubectl client dry-run。 |

## 镜像与仓库参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--registry` | `sealos.hub:5000/kube4` | 目标内网镜像仓库前缀。 |
| `--registry-user` | 空 | 仓库用户名，仅用于安装机 docker login/push。 |
| `--registry-pass` | 空 | 仓库口令，仅用于安装机 docker login/push。 |
| `--skip-image-prepare` | `false` | 跳过 `docker load/tag/push`，用于镜像已准备好的环境。 |

## DTM 服务参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--replicas` | `1` | DTM 副本数。`boltdb` 只允许单副本；多副本请使用 MySQL/Postgres/Redis。 |
| `--image-pull-policy` | `IfNotPresent` | 镜像拉取策略。 |
| `--service-type` | `ClusterIP` | Service 类型：`ClusterIP`、`NodePort`、`LoadBalancer`。 |
| `--http-port` | `36789` | DTM HTTP 端口。 |
| `--grpc-port` | `36790` | DTM gRPC 端口。 |
| `--jsonrpc-port` | `36791` | DTM JSON-RPC 端口。 |
| `--http-node-port` | 空 | NodePort 模式下指定 HTTP NodePort。 |
| `--grpc-node-port` | 空 | NodePort 模式下指定 gRPC NodePort。 |
| `--jsonrpc-node-port` | 空 | NodePort 模式下指定 JSON-RPC NodePort。 |

## 存储参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--store-driver` | `boltdb` | 存储引擎：`boltdb`、`mysql`、`postgres`、`redis`。 |
| `--store-host` | 空 | 外部存储地址；MySQL/Postgres/Redis 需要填写。 |
| `--store-port` | MySQL `3306` / Postgres `5432` | 外部存储端口。 |
| `--store-user` | 空 | DTM 运行时连接数据库的账号。 |
| `--store-pass` | 空 | DTM 运行时连接数据库的口令，会写入 Kubernetes Secret。 |
| `--store-db` | MySQL/Postgres 默认 `dtm` | DTM 使用的数据库名。 |
| `--store-schema` | `public` | Postgres schema。 |
| `--redis-prefix` | `{a}` | Redis key 前缀。 |
| `--data-expire` | `604800` | 事务数据过期时间，单位秒。 |
| `--finished-data-expire` | `86400` | 已完成事务过期时间，单位秒。 |

## 自动建库建表参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--skip-db-init` | `false` | 跳过 MySQL/Postgres 初始化 Job。 |
| `--db-admin-user` | 默认等于 `--store-user` | 用于建库建表的账号。可与 DTM 运行账号分离。 |
| `--db-admin-pass` | 默认等于 `--store-pass` | 建库建表账号口令，会写入 Kubernetes Secret。 |
| `--db-init-timeout` | `180s` | 等待初始化 Job 完成的超时时间。 |
| `--db-init-backoff-limit` | `3` | 初始化 Job 失败重试次数。 |
| `--db-init-ttl-seconds` | `600` | 初始化 Job 完成后的保留秒数。 |

初始化流程：

1. 安装器先 apply `Namespace/Secret/ConfigMap`。
2. 如果 `--store-driver=mysql|postgres` 且没有 `--skip-db-init`，创建一次性 Kubernetes Job。
3. MySQL Job 使用打包进 `.run` 的 `mysql:8.4` 客户端镜像。
4. Postgres Job 使用打包进 `.run` 的 `postgres:16-alpine` 客户端镜像。
5. Job 自动创建数据库/schema，并执行非破坏式 `CREATE ... IF NOT EXISTS` 表结构初始化。
6. Job 成功后再部署 DTM Deployment/Service。

## 资源参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--request-cpu` | `100m` | CPU request。 |
| `--request-memory` | `128Mi` | 内存 request。 |
| `--limit-cpu` | `1000m` | CPU limit。 |
| `--limit-memory` | `512Mi` | 内存 limit。 |

## 运行参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--micro-service-endpoint` | `<name>.<namespace>.svc.cluster.local:<grpc-port>` | DTM 对外注册或暴露的微服务端点。 |
| `--trans-cron-interval` | `3` | 扫描未完成全局事务的间隔，单位秒。 |
| `--timeout-to-fail` | `35` | XA/TCC 超时转失败时间，单位秒。 |
| `--retry-interval` | `10` | 分支事务重试间隔，单位秒。 |
| `--request-timeout` | `3` | DTM 调用分支服务的超时时间。 |
| `--log-level` | `info` | 日志级别。 |
| `--admin-base-path` | 空 | DTM Admin UI 基础路径。 |

## 示例

### Postgres 自动建库建表

```bash
./dtm-k8s-0.2.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
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
```

### MySQL 自动建库建表

```bash
./dtm-k8s-0.2.0-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --store-driver mysql \
  --store-host mysql.default.svc \
  --store-port 3306 \
  --store-user dtm \
  --store-pass '<dtm-db-password>' \
  --db-admin-user root \
  --db-admin-pass '<mysql-root-password>' \
  --store-db dtm \
  -y
```
