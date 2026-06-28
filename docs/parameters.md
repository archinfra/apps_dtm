# DTM Kubernetes 离线安装参数说明

本文档和 `.run -h` 保持一致，用于现场部署前评审参数。

## 动作

| 动作 | 说明 |
| --- | --- |
| `help` | 显示中文帮助。 |
| `show-defaults` | 输出安装器默认值。 |
| `precheck` | 检查 kubectl、docker、tar 和集群访问，不改动集群。 |
| `install` | 导入镜像、推送内网仓库、渲染 YAML 并部署 DTM。 |
| `uninstall` | 删除本安装器创建的 DTM 资源。 |
| `status` | 查看 DTM 的 Deployment、Pod、Service、ConfigMap、Secret 状态。 |

## 通用参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-n, --namespace` | `dtm-system` | 安装命名空间。 |
| `--name` | `dtm` | DTM 实例名，也是 Deployment/Service 等资源名前缀。 |
| `--kubeconfig` | 空 | 指定 kubeconfig 文件路径。 |
| `--context` | 空 | 指定 kubeconfig context。 |
| `--wait-timeout` | `180s` | 等待 Deployment rollout 的超时时间。 |
| `-y, --yes` | `false` | 跳过确认。 |
| `--dry-run` | `false` | 只做渲染和 kubectl client dry-run。 |

## 镜像与仓库参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--registry` | `sealos.hub:5000/kube4` | 目标内网镜像仓库前缀。 |
| `--registry-user` | 空 | 仓库用户名。 |
| `--registry-pass` | 空 | 仓库密码。 |
| `--skip-image-prepare` | `false` | 跳过 `docker load/tag/push`，用于镜像已准备好的环境。 |

## DTM 服务参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--replicas` | `1` | DTM 副本数。生产多副本建议使用外部存储。 |
| `--image-pull-policy` | `IfNotPresent` | 镜像拉取策略。 |
| `--service-type` | `ClusterIP` | Service 类型：`ClusterIP`、`NodePort`、`LoadBalancer`。 |
| `--http-port` | `36789` | DTM HTTP 端口。 |
| `--grpc-port` | `36790` | DTM gRPC 端口。 |
| `--jsonrpc-port` | `36791` | DTM JSON-RPC 端口。 |
| `--http-node-port` | 空 | NodePort 模式下指定 HTTP NodePort。 |
| `--grpc-node-port` | 空 | NodePort 模式下指定 gRPC NodePort。 |
| `--jsonrpc-node-port` | 空 | NodePort 模式下指定 JSON-RPC NodePort。 |

## 资源参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--request-cpu` | `100m` | CPU request。 |
| `--request-memory` | `128Mi` | 内存 request。 |
| `--limit-cpu` | `1000m` | CPU limit。 |
| `--limit-memory` | `512Mi` | 内存 limit。 |

## 存储参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--store-driver` | `boltdb` | 存储引擎：`boltdb`、`mysql`、`postgres`、`redis`。 |
| `--store-host` | 空 | 外部存储地址。 |
| `--store-port` | 空 | 外部存储端口。 |
| `--store-user` | 空 | 外部存储用户名。 |
| `--store-pass` | 空 | 外部存储密码，会写入 Kubernetes Secret。 |
| `--store-db` | 空 | 数据库名。 |
| `--store-schema` | `public` | Postgres schema。 |
| `--redis-prefix` | `{a}` | Redis key 前缀。 |
| `--data-expire` | `604800` | 事务数据过期时间，单位秒。 |
| `--finished-data-expire` | `86400` | 已完成事务过期时间，单位秒。 |

## 运行参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--micro-service-endpoint` | `<name>.<namespace>.svc.cluster.local:<grpc-port>` | DTM 对外注册或暴露的微服务端点。 |
| `--trans-cron-interval` | `3` | 扫描未完成全局事务的间隔，单位秒。 |
| `--timeout-to-fail` | `35` | XA/TCC 超时转失败时间，单位秒。 |
| `--retry-interval` | `10` | 分支事务重试间隔，单位秒。 |
| `--request-timeout` | `3` | DTM 调用分支服务的超时时间，单位秒。 |
| `--log-level` | `info` | 日志级别。 |
| `--admin-base-path` | 空 | DTM Admin UI 基础路径。 |
