#!/bin/bash

# 退出脚本如果任何命令执行失败，未定义变量也报错
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPERATOR_DIR="$REPO_ROOT/operator"
OPERATOR_NAMESPACE="openclaw-system"

# 检查 kubectl
if ! command -v kubectl > /dev/null 2>&1; then
    echo "错误：未找到 kubectl 命令，请先安装并配置集群访问凭证。"
    exit 1
fi

echo "=== 开始卸载 OpenClaw Operator ==="

# 1. 删除 Operator 全部清单（CRDs, RBAC, Controller）
echo "[1/2] 正在从集群删除 Operator 清单 (CRDs, RBAC, Controller)..."
if ! kubectl delete -k "$OPERATOR_DIR/config/default" --ignore-not-found; then
    echo "警告：部分资源删除失败，请手动检查。"
fi

# 2. 等待命名空间中 pod 全部消失
echo "[2/2] 正在等待 ${OPERATOR_NAMESPACE} 命名空间资源清理..."
if kubectl get namespace "${OPERATOR_NAMESPACE}" > /dev/null 2>&1; then
    kubectl wait --for=delete pod --all \
        -n "${OPERATOR_NAMESPACE}" \
        --timeout=2m 2>/dev/null || true
    echo "命名空间 ${OPERATOR_NAMESPACE} 下的 Pod 已清理完毕。"
else
    echo "命名空间 '${OPERATOR_NAMESPACE}' 不存在，跳过等待。"
fi

echo ""
echo "=== Operator 卸载完成 ==="
echo "CRDs、RBAC 及 controller-manager 已从集群移除。"
echo ""
echo "注意：已部署的 OpenClawNode 实例不会被自动删除。"
echo "如需删除实例，请先运行 deploy/uninstall-instance.sh，"
echo "或手动执行：kubectl delete openclawnodes --all -A"
