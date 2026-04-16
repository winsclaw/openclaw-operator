#!/bin/bash

set -euo pipefail

OPERATOR_NAMESPACE="openclaw-system"
DEPLOYMENT_NAME="controller-manager"

if ! command -v kubectl >/dev/null 2>&1; then
    echo "错误：未找到 kubectl 命令，请先安装并配置集群访问凭证。"
    exit 1
fi

echo "=== 重启 OpenClaw Operator ==="
echo "命名空间: $OPERATOR_NAMESPACE"
echo "Deployment: $DEPLOYMENT_NAME"

echo "说明：如果你更新的是同一个镜像标签（例如 latest），Deployment 规格没有变化，Kubernetes 不会自动重建 Pod。"
echo "执行 rollout restart 会强制重建 controller-manager Pod，从而重新拉取并运行最新镜像。"

echo "[1/2] 触发滚动重启..."
kubectl rollout restart deployment/$DEPLOYMENT_NAME -n "$OPERATOR_NAMESPACE"

echo "[2/2] 等待 controller-manager 就绪..."
if ! kubectl rollout status deployment/$DEPLOYMENT_NAME -n "$OPERATOR_NAMESPACE" --timeout=5m; then
    echo "错误：等待 controller-manager 重启完成超时。"
    echo "诊断信息："
    kubectl get deploy,pod -n "$OPERATOR_NAMESPACE" -o wide
    kubectl get events -n "$OPERATOR_NAMESPACE" --sort-by=.lastTimestamp | tail -n 20
    exit 1
fi

echo "=== Operator 重启完成 ==="

