#!/bin/bash

# 退出脚本如果任何命令执行失败，未定义变量也报错
set -euo pipefail

# 获取当前脚本所在的绝对路径，并推导本地 Chart 目录位置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../charts/openclaw"

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

# 定义部署使用的变量
NAMESPACE="aiops-openclaw"
RELEASE_NAME="openclaw"
# 必须从环境变量或 env 文件读取大模型配置，如果没有设置则退出
require_env "OPENAI_API_KEY"
API_KEY="$OPENAI_API_KEY"

require_env "OPENAI_BASE_URL"
API_BASE_URL="$OPENAI_BASE_URL"

require_env "OPENCLAW_GATEWAY_TOKEN"
GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN"
PRIMARY_MODEL_RAW="${OPENCLAW_PRIMARY_MODEL:-qwen3.5-plus}"
TRUSTED_PROXIES_RAW="${OPENCLAW_TRUSTED_PROXIES:-}"
CA_CERT_FILE="${OPENCLAW_CA_CERT_FILE:-}"
CA_BUNDLE_CONFIGMAP_NAME="${OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME:-openclaw-ca-bundle}"
INGRESS_ENABLED_RAW="${OPENCLAW_INGRESS_ENABLED:-auto}"
INGRESS_HOST="${OPENCLAW_INGRESS_HOST:-}"
INGRESS_CLASS_NAME="${OPENCLAW_INGRESS_CLASS_NAME:-nginx}"
INGRESS_TLS_SECRET_NAME="${OPENCLAW_INGRESS_TLS_SECRET_NAME:-openclaw-tls}"
# OpenClaw 运行时需要 provider/model 形式；openai provider 会负责路由到 OpenAI 兼容后端。
if [[ "$PRIMARY_MODEL_RAW" == */* ]]; then
    PRIMARY_MODEL="$PRIMARY_MODEL_RAW"
else
    PRIMARY_MODEL="openai/$PRIMARY_MODEL_RAW"
fi

case "$INGRESS_ENABLED_RAW" in
    auto)
        if [[ -n "$INGRESS_HOST" ]]; then
            INGRESS_ENABLED="true"
        else
            INGRESS_ENABLED="false"
        fi
        ;;
    true|false)
        INGRESS_ENABLED="$INGRESS_ENABLED_RAW"
        ;;
    *)
        echo "错误：OPENCLAW_INGRESS_ENABLED 仅支持 true、false 或 auto。"
        exit 1
        ;;
esac

if [[ "$INGRESS_ENABLED" == "true" && -z "$INGRESS_HOST" ]]; then
    echo "错误：启用 Ingress 时必须设置 OPENCLAW_INGRESS_HOST。"
    exit 1
fi

discover_trusted_proxies() {
    if [[ -n "$TRUSTED_PROXIES_RAW" ]]; then
        tr ',' '\n' <<<"$TRUSTED_PROXIES_RAW" | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        return 0
    fi

    kubectl get pods -A \
      -l app.kubernetes.io/component=controller \
      -o jsonpath='{range .items[*]}{.metadata.labels.app\.kubernetes\.io/name}{"\t"}{.status.podIP}{"\n"}{end}' 2>/dev/null \
      | awk -F '\t' '$1 == "ingress-nginx" && $2 != "" {print $2}' \
      | sort -u
}

TRUSTED_PROXIES_LIST="$(discover_trusted_proxies || true)"
TRUSTED_PROXIES_JSON="[]"
if [[ -n "$TRUSTED_PROXIES_LIST" ]]; then
    mapfile -t TRUSTED_PROXIES_ARRAY <<<"$TRUSTED_PROXIES_LIST"
    TRUSTED_PROXIES_JSON="["
    for ip in "${TRUSTED_PROXIES_ARRAY[@]}"; do
        [[ -z "$ip" ]] && continue
        if [[ "$TRUSTED_PROXIES_JSON" != "[" ]]; then
            TRUSTED_PROXIES_JSON+=", "
        fi
        TRUSTED_PROXIES_JSON+="\"$ip\""
    done
    TRUSTED_PROXIES_JSON+="]"
fi

echo "=== 开始部署 OpenClaw ==="
if [[ "$TRUSTED_PROXIES_JSON" == "[]" ]]; then
    echo "警告：未自动发现 ingress-nginx controller Pod IP；trustedProxies 将保持为空。"
    echo "      如需通过外部 Ingress 访问，请设置 OPENCLAW_TRUSTED_PROXIES=ip1,ip2 或在 values 中配置 app-template.gateway.trustedProxies。"
else
    echo "检测到 trustedProxies: $TRUSTED_PROXIES_JSON"
fi

if [[ "$INGRESS_ENABLED" == "true" ]]; then
    echo "Ingress 已启用: host=$INGRESS_HOST, class=$INGRESS_CLASS_NAME"
else
    echo "Ingress 未启用；如需创建 Ingress，请设置 OPENCLAW_INGRESS_HOST 或 OPENCLAW_INGRESS_ENABLED=true。"
fi

print_debug_info() {
    echo "=== 部署失败诊断信息开始 ==="
    kubectl get pods -n "$NAMESPACE" -o wide || true
    kubectl get pvc -n "$NAMESPACE" -o wide || true
    kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 50 || true
    echo "=== 部署失败诊断信息结束 ==="
}

# 1. 检查本地 Chart 目录并更新依赖
echo "[1/5] 正在检查本地 Helm Chart并更新依赖..."
if [ ! -d "$CHART_DIR" ]; then
    echo "错误：未找到本地 Chart 目录 '$CHART_DIR'！"
    exit 1
fi
# 优先使用本地依赖包，离线环境下避免因仓库不可达而失败
if ! helm dependency build "$CHART_DIR"; then
    if ls "$CHART_DIR"/charts/*.tgz >/dev/null 2>&1; then
        echo "警告：无法在线刷新 Helm 依赖，继续使用本地缓存的 charts/*.tgz。"
    else
        echo "错误：Helm 依赖构建失败，且本地不存在可用的 charts/*.tgz。"
        echo "请检查网络/DNS，或先手动执行: helm dependency update \"$CHART_DIR\""
        exit 1
    fi
fi

# 2. 创建用于部署的 Kubernetes 命名空间（如果它不存在的话）
echo "[2/5] 正在准备命名空间 '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    # 命名空间不存在，创建它
    kubectl create namespace "$NAMESPACE"
    echo "命名空间 '$NAMESPACE' 已创建。"
else
    # 命名空间已经存在，无需操作
    echo "命名空间 '$NAMESPACE' 已存在。"
fi

# 3. 创建或更新运行应用所需的 Secret (敏感信息)
echo "[3/6] 正在配置应用密钥 (Secret)..."
# 首先尝试删除旧的 secret（如果存在旧的，避免重复创建报错），然后重建
kubectl delete secret openclaw-env-secret -n "$NAMESPACE" --ignore-not-found
# 将 API Key 和 Gateway Token 储存在 Secret 里，供内部容器挂载使用
kubectl create secret generic openclaw-env-secret -n "$NAMESPACE" \
  --from-literal=OPENAI_API_KEY="$API_KEY" \
  --from-literal=OPENAI_BASE_URL="$API_BASE_URL" \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN" \
  --from-literal=OPENCLAW_PRIMARY_MODEL="$PRIMARY_MODEL"
echo "应用密钥已配置完成。"

if [[ -n "$CA_CERT_FILE" ]]; then
    echo "[4/6] 正在配置自定义 CA 证书 (ConfigMap)..."
    if [[ ! -f "$CA_CERT_FILE" ]]; then
        echo "错误：未找到 CA 证书文件 '$CA_CERT_FILE'。"
        exit 1
    fi
    kubectl delete configmap "$CA_BUNDLE_CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found
    kubectl create configmap "$CA_BUNDLE_CONFIGMAP_NAME" -n "$NAMESPACE" \
      --from-file=ca-bundle.crt="$CA_CERT_FILE"
    echo "自定义 CA 证书已配置完成。"
else
    echo "[4/6] 未设置 OPENCLAW_CA_CERT_FILE，跳过自定义 CA 证书配置。"
fi


# 5. 使用 Helm 安装或升级 Release
echo "[5/6] 正在使用本地 Chart 安装/升级 OpenClaw..."
# upgrade --install 表示如果不存在则安装，如果已存在则更新配置
HELM_ARGS=(
    upgrade --install "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE"
    --reset-values
    --set-json "app-template.gateway.trustedProxies=$TRUSTED_PROXIES_JSON"
    --set "app-template.ingress.main.enabled=$INGRESS_ENABLED"
    --wait --timeout 10m --atomic
)

if [[ "$INGRESS_ENABLED" == "true" ]]; then
    HELM_ARGS+=(
        --set-string "app-template.ingress.main.className=$INGRESS_CLASS_NAME"
        --set-string "app-template.ingress.main.hosts[0].host=$INGRESS_HOST"
        --set-string "app-template.ingress.main.hosts[0].paths[0].path=/"
        --set-string "app-template.ingress.main.hosts[0].paths[0].pathType=Prefix"
        --set-string "app-template.ingress.main.hosts[0].paths[0].service.identifier=main"
        --set-string "app-template.ingress.main.hosts[0].paths[0].service.port=http"
        --set-string "app-template.ingress.main.tls[0].hosts[0]=$INGRESS_HOST"
        --set-string "app-template.ingress.main.tls[0].secretName=$INGRESS_TLS_SECRET_NAME"
    )
fi

if [[ -n "$CA_CERT_FILE" ]]; then
    HELM_ARGS+=(
        --set app-template.persistence.ca-bundle.enabled=true
        --set "app-template.persistence.ca-bundle.name=$CA_BUNDLE_CONFIGMAP_NAME"
    )
fi

if ! helm "${HELM_ARGS[@]}"; then
    print_debug_info
    exit 1
fi

echo "[6/6] 正在重启 Deployment 以加载最新环境变量和证书..."
kubectl rollout restart deployment/"$RELEASE_NAME" -n "$NAMESPACE"
kubectl rollout status deployment/"$RELEASE_NAME" -n "$NAMESPACE" --timeout=10m

echo "=== 部署完成 ==="
echo "部署操作提示："
echo "1. 你可以通过执行以下命令来进行端口转发，以便在本地访问 Web UI："
echo "   kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME 18789:18789"
if [[ "$INGRESS_ENABLED" == "true" ]]; then
    echo "   或通过 Ingress 访问："
    echo "   https://$INGRESS_HOST/?token=$GATEWAY_TOKEN"
fi
echo "2. 要批准设备配对请求，请另开一个终端执行："
echo "   kubectl exec -n $NAMESPACE deployment/$RELEASE_NAME -c main -- node dist/index.js devices list"
echo "   kubectl exec -n $NAMESPACE deployment/$RELEASE_NAME -c main -- node dist/index.js devices approve <REQUEST_ID>"
