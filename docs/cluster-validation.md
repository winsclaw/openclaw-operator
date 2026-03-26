# Operator 集群安装与验收

这份文档整理了当前 Operator 在真实集群上的安装和验收步骤。

## 适用场景

- 需要把本地代码构建成镜像并推到镜像仓库
- 需要把 Operator 安装到集群中的 `openclaw-system`
- 需要在业务命名空间创建一个临时 `OpenClawNode` 做验收

## 前置条件

1. 当前 kubeconfig 可以访问目标集群。
2. `.env` 中配置的 Operator 镜像仓库可被集群正常拉取。
3. 业务命名空间里已经有符合约定的 runtime Secret。
   当前默认使用 `aiops-openclaw/openclaw-env-secret`。
4. 本机安装了 `go`、`docker`、`kubectl`。

## 关键约定

- 默认通过 `deploy/.env` 里的 Operator 镜像变量确定推送/拉取地址。
- 安装脚本不会向集群写入任何个人镜像凭据。
- 验收 CR 默认名为 `operator-e2e`，命名空间默认是 `aiops-openclaw`。

## 一键脚本

脚本位置：

- [cluster-validate.sh](/opt/k8s-openclaw-work/openclaw-k8s/operator/scripts/cluster-validate.sh)

常用命令：

```bash
# 1. 同步 upstream latest 到 .env 指定仓库
bash deploy/push-operator-image.sh

# 2. 安装 Operator
bash operator/scripts/cluster-validate.sh install-operator

# 3. 创建临时 OpenClawNode 并等待 Ready
bash operator/scripts/cluster-validate.sh verify-cr

# 4. 清理临时验收资源
bash operator/scripts/cluster-validate.sh cleanup
```

也可以直接跑完整流程：

```bash
bash operator/scripts/cluster-validate.sh all
```

## 手工步骤

### 1. 安装 Operator 清单

```bash
kubectl apply -k operator/config/default
kubectl patch deployment controller-manager -n openclaw-system --type=merge \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":null,"containers":[{"name":"manager","image":"docker.ops.fzyun.io:5000/openclaw/openclaw-operator:latest"}]}}}}'
kubectl rollout status deployment/controller-manager -n openclaw-system --timeout=5m
kubectl get deploy,pod -n openclaw-system -o wide
```

期望结果：

- `deployment/controller-manager` 为 `1/1`
- Pod 为 `Running`

### 2. 创建验收用 OpenClawNode

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps.openclaw.io/v1alpha1
kind: OpenClawNode
metadata:
  name: operator-e2e
  namespace: aiops-openclaw
spec:
  runtimeSecretRef:
    name: openclaw-env-secret
  configMode: merge
  chromium:
    enabled: false
  storage:
    size: 1Gi
EOF
```

### 3. 等待业务负载和 CR 就绪

```bash
kubectl rollout status deployment/operator-e2e -n aiops-openclaw --timeout=5m
kubectl wait --for=jsonpath='{.status.phase}'=Ready openclawnode/operator-e2e -n aiops-openclaw --timeout=5m
kubectl get openclawnode/operator-e2e -n aiops-openclaw -o yaml
kubectl get deploy,pod,svc,pvc,configmap -n aiops-openclaw -l openclaw.io/node=operator-e2e -o wide
```

期望结果：

- `openclawnode.status.phase=Ready`
- `openclawnode.status.readyReplicas=1`
- `DependenciesReady=True`
- `Ready=True`
- 子资源全部存在，业务 Pod 为 `1/1 Running`

## 当前已验证通过的镜像

当前默认镜像地址来自 `deploy/.env`：

- `OPENCLAW_OPERATOR_IMAGE`
- 或 `OPENCLAW_OPERATOR_IMAGE_REGISTRY/REPOSITORY/TAG`

对应修复包括：

- `gateway.trustedProxies` 默认输出为空数组，而不是 `null`
- 已绑定 PVC 不再在后续 reconcile 中重写 `storageClassName`

## 清理

只清理临时验收资源：

```bash
bash operator/scripts/cluster-validate.sh cleanup
```

或手工清理：

```bash
kubectl delete openclawnode/operator-e2e -n aiops-openclaw
```

如果还要移除 Operator：

```bash
kubectl delete -k operator/config/default
```
