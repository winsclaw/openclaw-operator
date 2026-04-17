#!/bin/bash

# 退出脚本如果任何命令执行失败，未定义变量也报错
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 定义部署使用的变量
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

require_env "OPENAI_API_KEY"
require_env "OPENAI_BASE_URL"
require_env "OPENCLAW_GATEWAY_TOKEN"
require_env "OPENCLAW_PRIMARY_MODEL"
require_env "OPENCLAW_INSTANCE_NAME"

INSTANCE_NAME="${OPENCLAW_INSTANCE_NAME}"
SECRET_NAME="${INSTANCE_NAME}-env-secret"
PRIMARY_MODEL_RAW="${OPENCLAW_PRIMARY_MODEL}"

compose_ingress_host() {
    local suffix="${OPENCLAW_INGRESS_HOST:-}"
    suffix="${suffix#.}"

    if [[ -z "$suffix" ]]; then
        return 0
    fi

    if [[ "$suffix" == "$INSTANCE_NAME" || "$suffix" == "$INSTANCE_NAME".* ]]; then
        printf '%s\n' "$suffix"
        return 0
    fi

    printf '%s.%s\n' "$INSTANCE_NAME" "$suffix"
}

compose_ingress_annotations() {
    local annotations=""

    if [[ -n "${OPENCLAW_INGRESS_CLUSTER_ISSUER:-}" && -n "${OPENCLAW_INGRESS_ISSUER:-}" ]]; then
        echo "错误：OPENCLAW_INGRESS_CLUSTER_ISSUER 和 OPENCLAW_INGRESS_ISSUER 不能同时设置。"
        exit 1
    fi

    if [[ -n "${OPENCLAW_INGRESS_CLUSTER_ISSUER:-}" || -n "${OPENCLAW_INGRESS_ISSUER:-}" ]]; then
        annotations="    annotations:"
        if [[ -n "${OPENCLAW_INGRESS_CLUSTER_ISSUER:-}" ]]; then
            annotations="${annotations}\n      cert-manager.io/cluster-issuer: \"${OPENCLAW_INGRESS_CLUSTER_ISSUER}\""
        fi
        if [[ -n "${OPENCLAW_INGRESS_ISSUER:-}" ]]; then
            annotations="${annotations}\n      cert-manager.io/issuer: \"${OPENCLAW_INGRESS_ISSUER}\""
        fi
        annotations="$(printf '%b' "${annotations}")"
    fi

    printf '%s' "$annotations"
}

# 转换模型格式
if [[ "$PRIMARY_MODEL_RAW" == */* ]]; then
    PRIMARY_MODEL="$PRIMARY_MODEL_RAW"
else
    PRIMARY_MODEL="openai/$PRIMARY_MODEL_RAW"
fi

ALLOW_INSECURE_AUTH="${OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH:-false}"
case "$ALLOW_INSECURE_AUTH" in
    true|false)
        ;;
    *)
        echo "错误：OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH 仅支持 true 或 false。"
        exit 1
        ;;
esac

DANGEROUSLY_DISABLE_DEVICE_AUTH="${OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH:-false}"
case "$DANGEROUSLY_DISABLE_DEVICE_AUTH" in
    true|false)
        ;;
    *)
        echo "错误：OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH 仅支持 true 或 false。"
        exit 1
        ;;
esac

echo "=== 开始部署 OpenClaw 实例 ($INSTANCE_NAME) ==="

# 1. 创建命名空间
echo "[1/4] 正在准备命名空间 '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create namespace "$NAMESPACE"
    echo "命名空间 '$NAMESPACE' 已创建。"
else
    echo "命名空间 '$NAMESPACE' 已存在。"
fi

# 2. 创建或更新 Secret
echo "[2/4] 正在配置应用凭证 (Secret $SECRET_NAME)..."
kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
kubectl create secret generic "$SECRET_NAME" -n "$NAMESPACE" \
  --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
  --from-literal=OPENAI_BASE_URL="$OPENAI_BASE_URL" \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  --from-literal=OPENCLAW_PRIMARY_MODEL="$PRIMARY_MODEL"
echo "应用密钥已配置完成。"

# 3. 部署 OpenClawNode 实例
echo "[3/4] 正在部署 OpenClawNode 实例资源..."

# 构建动态 YAML 组件
INGRESS_HOST="$(compose_ingress_host)"
SPEC_INGRESS=""
if [[ "${OPENCLAW_INGRESS_ENABLED:-false}" != "false" ]]; then
    INGRESS_TLS_SECRET_NAME="${OPENCLAW_INGRESS_TLS_SECRET_NAME:-${INSTANCE_NAME}-tls}"
    SPEC_INGRESS_ANNOTATIONS="$(compose_ingress_annotations)"
    SPEC_INGRESS=$(cat <<EOF
  ingress:
    enabled: true
    host: "${INGRESS_HOST}"
    className: "${OPENCLAW_INGRESS_CLASS_NAME:-nginx}"
    tlsSecretName: "${INGRESS_TLS_SECRET_NAME}"
${SPEC_INGRESS_ANNOTATIONS}
EOF
)
fi

SPEC_PROXIES=""
if [[ -n "${OPENCLAW_TRUSTED_PROXIES:-}" ]]; then
    SPEC_PROXIES="    trustedProxies:"
    IFS=',' read -ra ADDR <<< "${OPENCLAW_TRUSTED_PROXIES}"
    for i in "${ADDR[@]}"; do
        SPEC_PROXIES="${SPEC_PROXIES}
    - ${i}"
    done
fi

SPEC_CONTROL_UI=""
if [[ "$ALLOW_INSECURE_AUTH" == "true" || "$DANGEROUSLY_DISABLE_DEVICE_AUTH" == "true" ]]; then
    SPEC_CONTROL_UI="    controlUi:"
    if [[ "$ALLOW_INSECURE_AUTH" == "true" ]]; then
        SPEC_CONTROL_UI="${SPEC_CONTROL_UI}\n      allowInsecureAuth: true"
    fi
    if [[ "$DANGEROUSLY_DISABLE_DEVICE_AUTH" == "true" ]]; then
        SPEC_CONTROL_UI="${SPEC_CONTROL_UI}\n      dangerouslyDisableDeviceAuth: true"
    fi
    SPEC_CONTROL_UI="$(printf '%b' "${SPEC_CONTROL_UI}")"
fi

SPEC_CA=""
if [[ -n "${OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME:-}" ]]; then
    SPEC_CA=$(cat <<EOF
  caBundle:
    configMapName: "${OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME}"
EOF
)
fi

# 构建 openclaw 应用镜像 spec（留空则 operator 使用内置默认值）
SPEC_IMAGE=""
if [[ -n "${OPENCLAW_IMAGE_REPOSITORY:-}" || -n "${OPENCLAW_IMAGE_TAG:-}" || -n "${OPENCLAW_IMAGE_PULL_POLICY:-}" ]]; then
    SPEC_IMAGE="  image:"
    [[ -n "${OPENCLAW_IMAGE_REPOSITORY:-}" ]] && SPEC_IMAGE="${SPEC_IMAGE}\n    repository: \"${OPENCLAW_IMAGE_REPOSITORY}\""
    [[ -n "${OPENCLAW_IMAGE_TAG:-}" ]]        && SPEC_IMAGE="${SPEC_IMAGE}\n    tag: \"${OPENCLAW_IMAGE_TAG}\""
    [[ -n "${OPENCLAW_IMAGE_PULL_POLICY:-}" ]] && SPEC_IMAGE="${SPEC_IMAGE}\n    pullPolicy: \"${OPENCLAW_IMAGE_PULL_POLICY}\""
    SPEC_IMAGE="$(printf '%b' "${SPEC_IMAGE}")"
fi

# 构建 chromium sidecar 镜像 spec
SPEC_CHROMIUM_IMAGE=""
if [[ -n "${OPENCLAW_CHROMIUM_IMAGE_REPOSITORY:-}" || -n "${OPENCLAW_CHROMIUM_IMAGE_TAG:-}" || -n "${OPENCLAW_CHROMIUM_IMAGE_PULL_POLICY:-}" ]]; then
    SPEC_CHROMIUM_IMAGE="    image:"
    [[ -n "${OPENCLAW_CHROMIUM_IMAGE_REPOSITORY:-}" ]] && SPEC_CHROMIUM_IMAGE="${SPEC_CHROMIUM_IMAGE}\n      repository: \"${OPENCLAW_CHROMIUM_IMAGE_REPOSITORY}\""
    [[ -n "${OPENCLAW_CHROMIUM_IMAGE_TAG:-}" ]]         && SPEC_CHROMIUM_IMAGE="${SPEC_CHROMIUM_IMAGE}\n      tag: \"${OPENCLAW_CHROMIUM_IMAGE_TAG}\""
    [[ -n "${OPENCLAW_CHROMIUM_IMAGE_PULL_POLICY:-}" ]]  && SPEC_CHROMIUM_IMAGE="${SPEC_CHROMIUM_IMAGE}\n      pullPolicy: \"${OPENCLAW_CHROMIUM_IMAGE_PULL_POLICY}\""
    SPEC_CHROMIUM_IMAGE="$(printf '%b' "${SPEC_CHROMIUM_IMAGE}")"
fi

cat <<EOF | kubectl apply -f -
apiVersion: apps.openclaw.io/v1alpha1
kind: OpenClawNode
metadata:
  name: ${INSTANCE_NAME}
  namespace: ${NAMESPACE}
spec:
  runtimeSecretRef:
    name: ${SECRET_NAME}
${SPEC_IMAGE}
  gateway:
    port: 18789
${SPEC_PROXIES}
${SPEC_CONTROL_UI}
${SPEC_INGRESS}
${SPEC_CA}
  configMode: merge
  chromium:
    enabled: true
${SPEC_CHROMIUM_IMAGE}
  storage:
    size: 5Gi
EOF

# 4. 等待实例就绪
echo "[4/4] 正在等待实例和对应负载就绪..."
if ! kubectl wait --for=jsonpath='{.status.phase}'=Ready openclawnode/"${INSTANCE_NAME}" -n "$NAMESPACE" --timeout=5m; then
    echo "错误：等待 OpenClawNode 就绪超时或失败。"
    echo "可以使用下述命令检查状态："
    echo "kubectl describe openclawnode/${INSTANCE_NAME} -n $NAMESPACE"
    echo "kubectl get pods -n $NAMESPACE -l openclaw.io/node=${INSTANCE_NAME}"
    exit 1
fi

echo "=== 实例部署完成 ==="
echo "对应的 OpenClaw 节点已成功启动！"
echo "你可以通过执行以下命令来进行端口转发并在本地访问 Web UI："
echo "kubectl port-forward -n $NAMESPACE svc/${INSTANCE_NAME} 18789:18789"
if [[ "$DANGEROUSLY_DISABLE_DEVICE_AUTH" == "true" ]]; then
    echo "然后访问 http://localhost:18789 并输入 Gateway Token 即可进入 Web UI。"
    echo "当前已启用 gateway.controlUi.dangerouslyDisableDeviceAuth=true，Control UI 将仅依赖 token/password，不再要求设备配对。"
elif [[ "$ALLOW_INSECURE_AUTH" == "true" ]]; then
    echo "然后访问 http://localhost:18789 并输入 Gateway Token 即可进入 Web UI。"
    echo "当前已启用 gateway.controlUi.allowInsecureAuth=true。该模式仅对本机调试场景放宽 Control UI 设备身份要求，经由 Ingress 的远程浏览器访问仍可能要求设备配对。"
else
    echo "然后访问 http://localhost:18789 并输入 Gateway Token 即可配对。"
fi

# 当 Ingress 启用且配置了访问域名时，打印公网访问地址
if [[ "${OPENCLAW_INGRESS_ENABLED:-false}" != "false" && -n "$INGRESS_HOST" ]]; then
    INGRESS_URL="https://${INGRESS_HOST}?token=${OPENCLAW_GATEWAY_TOKEN}"
    echo ""
    echo "─────────────────────────────────────────────────────────"
    echo "  Ingress 访问地址（已启用 HTTPS）："
    echo "  $INGRESS_URL"
    echo "─────────────────────────────────────────────────────────"
fi
