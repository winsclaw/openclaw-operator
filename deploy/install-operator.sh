#!/bin/bash

# 退出脚本如果任何命令执行失败，未定义变量也报错
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPERATOR_DIR="$REPO_ROOT/operator"
OPERATOR_NAMESPACE="openclaw-system"

load_env_file() {
    local env_file="${OPENCLAW_ENV_FILE:-$SCRIPT_DIR/.env}"

    if [[ -f "$env_file" ]]; then
        echo "检测到环境变量文件: $env_file"
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
}

operator_image() {
    if [[ -n "${OPENCLAW_OPERATOR_IMAGE:-}" ]]; then
        printf '%s\n' "$OPENCLAW_OPERATOR_IMAGE"
        return 0
    fi

    local registry="${IMAGE_REGISTRY}"
    local repository="${OPENCLAW_OPERATOR_IMAGE_REPOSITORY}"
    local tag="${OPENCLAW_OPERATOR_IMAGE_TAG}"
    printf '%s/%s:%s\n' "$registry" "$repository" "$tag"
}

load_env_file
OPERATOR_IMAGE="$(operator_image)"

echo "=== 开始安装 OpenClaw Operator ==="
echo "使用 Operator 镜像: $OPERATOR_IMAGE"

# 检查 kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo "错误：未找到 kubectl 命令，请先安装并配置集群访问凭证。"
    exit 1
fi

echo "[1/3] 正在向集群应用 Operator 清单 (CRDs, RBAC, Controller)..."
if ! kubectl apply -k "$OPERATOR_DIR/config/default"; then
    echo "错误：应用 Operator 清单失败。"
    exit 1
fi

echo "[2/3] 正在切换 controller-manager 镜像..."
kubectl set image deployment/controller-manager \
    manager="$OPERATOR_IMAGE" \
    -n "$OPERATOR_NAMESPACE"

echo "[3/3] 正在等待 controller-manager 启动就绪..."
if ! kubectl rollout status deployment/controller-manager -n "$OPERATOR_NAMESPACE" --timeout=5m; then
    echo "错误：等待 controller-manager 启动超时。"
    echo "诊断信息："
    kubectl get deploy,pod -n "$OPERATOR_NAMESPACE" -o wide
    kubectl get events -n "$OPERATOR_NAMESPACE" --sort-by=.lastTimestamp | tail -n 20
    exit 1
fi

echo "=== Operator 安装完成 ==="
echo "Operator 已经成功部署在命名空间: $OPERATOR_NAMESPACE"
echo "你可以运行如下命令查看状态："
echo "kubectl get pods -n $OPERATOR_NAMESPACE"
echo ""
echo "下一步：请使用 deploy/install-instance.sh 来启动具体的 OpenClaw 实例节点。"
