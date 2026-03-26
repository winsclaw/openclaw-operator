#!/bin/bash

# 退出脚本如果任何命令执行失败，未定义变量也报错
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE="openclaw-node"

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

require_env() {
    local name="$1"
    local example_file="$SCRIPT_DIR/.env.example"

    if [[ -z "${!name:-}" ]]; then
        echo "错误：未设置环境变量 $name。"
        echo "请参考示例文件配置: $example_file"
        echo "你也可以通过 OPENCLAW_ENV_FILE 指定自定义 env 文件路径。"
        exit 1
    fi
}

load_env_file

require_env "OPENCLAW_INSTANCE_NAME"

INSTANCE_NAME="${OPENCLAW_INSTANCE_NAME}"
SECRET_NAME="${INSTANCE_NAME}-env-secret"

echo "=== 开始删除 OpenClaw 实例 ($INSTANCE_NAME) ==="

# 检查 kubectl
if ! command -v kubectl > /dev/null 2>&1; then
    echo "错误：未找到 kubectl 命令，请先安装并配置集群访问凭证。"
    exit 1
fi

# 1. 删除 OpenClawNode CR
echo "[1/2] 正在删除 OpenClawNode 资源 '${INSTANCE_NAME}'..."
if kubectl get openclawnode "${INSTANCE_NAME}" -n "${NAMESPACE}" > /dev/null 2>&1; then
    kubectl delete openclawnode "${INSTANCE_NAME}" -n "${NAMESPACE}"
    echo "OpenClawNode '${INSTANCE_NAME}' 已删除。"
else
    echo "OpenClawNode '${INSTANCE_NAME}' 不存在，跳过。"
fi

# 2. 删除 Secret
echo "[2/2] 正在删除应用密钥 (Secret ${SECRET_NAME})..."
kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found
echo "Secret '${SECRET_NAME}' 已删除（如存在）。"

echo ""
echo "=== 实例删除完成 ==="
echo "命名空间 '${NAMESPACE}' 保留。如需一并删除，请手动执行："
echo "kubectl delete namespace ${NAMESPACE}"
