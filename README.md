# OpenClaw Kubernetes Operator

> **Enterprise-Grade Cloud-Native AI Browser Automation on Kubernetes**
>
> **企业级云原生 AI 浏览器自动化 Kubernetes Operator**

---

## English

### What is openclaw-k8s?

`openclaw-k8s` is a Kubernetes Operator for [OpenClaw](https://github.com/openclaw/openclaw) — a cloud-native AI browser automation platform. It brings the full power of the Kubernetes Operator pattern to managing OpenClaw node lifecycles at enterprise scale.

Instead of manually managing Deployments, Services, ConfigMaps, PVCs, and Ingress resources, you declare a single `OpenClawNode` custom resource and let the Operator handle everything.

### ✨ Highlights

| Feature | Description |
|---|---|
| 🤖 **Operator Pattern** | Declarative lifecycle management via `OpenClawNode` CRD — no manual resource wrangling |
| 🔒 **Secret-driven Config** | AI credentials (API key, base URL, token) are injected via Kubernetes Secrets — never in plaintext config |
| 🌐 **Ingress Auto-Provisioning** | One field enables a production-ready HTTPS Ingress with TLS |
| 💾 **Persistent Storage** | Each node gets its own PVC for durable browser profile and state storage |
| 🧩 **Multi-Instance** | Run dozens of isolated OpenClaw nodes in the same cluster, each independently configured |
| 🔭 **Status Conditions** | Fine-grained `DependenciesReady` and `Ready` status conditions for observability |
| 🛡️ **Enterprise Security** | Trusted proxy configuration, custom CA bundle injection, and TLS-ready by default |
| ⚙️ **Chromium Integration** | Optional headless Chromium embedded in each node for full browser automation |

### Architecture

```
┌──────────────────────────────────────────────────┐
│                Kubernetes Cluster                │
│                                                  │
│  ┌───────────────────────────────────────────┐   │
│  │          openclaw-system namespace        │   │
│  │   ┌──────────────────────────────────┐   │   │
│  │   │   OpenClaw Operator (Controller) │   │   │
│  │   └──────────┬───────────────────────┘   │   │
│  └──────────────│───────────────────────────┘   │
│                 │ watches & reconciles           │
│  ┌──────────────▼───────────────────────────┐   │
│  │         OpenClawNode CR (your ns)        │   │
│  │  ┌────────┐ ┌───────┐ ┌───┐ ┌─────────┐ │   │
│  │  │Deploym.│ │Service│ │PVC│ │Ingress  │ │   │
│  │  └────────┘ └───────┘ └───┘ └─────────┘ │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

### Prerequisites

- Kubernetes cluster (v1.24+)
- `kubectl` configured and connected to your cluster
- Docker (for building and pushing the operator image)
- An OpenAI-compatible API endpoint (e.g., DashScope, Azure OpenAI)

### Quickstart

#### Step 1: Configure your environment

```bash
cp deploy/.env.example deploy/.env
# Edit deploy/.env with your actual values
```

Key fields to fill in:

```bash
OPENAI_API_KEY=sk-your-api-key
OPENAI_BASE_URL=https://your-openai-compatible-endpoint/v1
OPENCLAW_GATEWAY_TOKEN=your-random-secure-token
OPENCLAW_PRIMARY_MODEL=qwen3.5-plus

OPENCLAW_INSTANCE_NAME=my-openclaw-node
IMAGE_REGISTRY=your.registry.io
IMAGE_PUSH_REGISTRY=push.your.registry.io
OPENCLAW_OPERATOR_IMAGE_REPOSITORY=your-org/openclaw-operator
OPENCLAW_OPERATOR_IMAGE_TAG=latest
```

#### Step 2: Build and push the Operator image

```bash
./deploy/push-operator-image.sh
```

#### Step 3: Install the Operator

This installs the CRDs, RBAC, and the controller into the `openclaw-system` namespace:

```bash
./deploy/install-operator.sh
```

Verify the Operator is running:

```bash
kubectl get pods -n openclaw-system
# NAME                                  READY   STATUS    RESTARTS   AGE
# controller-manager-xxxxx-xxxxx        1/1     Running   0          30s
```

#### Step 4: Deploy an OpenClaw Node Instance

```bash
./deploy/install-instance.sh
```

The script will:
1. Create the target namespace
2. Create a Secret with your AI credentials
3. Apply the `OpenClawNode` custom resource
4. Wait until the instance is `Ready`

#### Step 5: Access the Web UI

```bash
kubectl port-forward -n openclaw-node svc/my-openclaw-node 18789:18789
# Open http://localhost:18789 and enter your Gateway Token to pair
```

### OpenClawNode Custom Resource Reference

```yaml
apiVersion: apps.openclaw.io/v1alpha1
kind: OpenClawNode
metadata:
  name: my-node
  namespace: my-namespace
spec:
  # Required: reference to a Secret with OPENAI_API_KEY, OPENAI_BASE_URL,
  # OPENCLAW_GATEWAY_TOKEN, and optionally OPENCLAW_PRIMARY_MODEL
  runtimeSecretRef:
    name: my-node-env-secret

  # Gateway configuration
  gateway:
    port: 18789
    trustedProxies:        # Optional: IPs of your ingress controllers
      - 10.1.1.10

  # Optional: auto-provision an Ingress
  ingress:
    enabled: true
    host: my-node.example.com
    className: nginx
    tlsSecretName: my-node-tls

  # Storage for browser profiles and state
  storage:
    size: 20Gi

  # Enable headless Chromium
  chromium:
    enabled: true

  # Config merge mode: "merge" | "replace"
  configMode: merge

  # Optional: inject a custom CA bundle
  caBundle:
    configMapName: my-ca-bundle
```

### Environment Variables Reference (`.env`)

| Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | ✅ | Your OpenAI-compatible API key |
| `OPENAI_BASE_URL` | ✅ | API endpoint base URL |
| `OPENCLAW_GATEWAY_TOKEN` | ✅ | Random token to protect the gateway UI |
| `OPENCLAW_PRIMARY_MODEL` | ✅ | Primary LLM model name |
| `OPENCLAW_INSTANCE_NAME` | ✅ | Name of the OpenClawNode instance |
| `IMAGE_REGISTRY` | ✅ | Registry to pull the operator image from |
| `IMAGE_PUSH_REGISTRY` | ✅ | Registry to push the built operator image to |
| `OPENCLAW_OPERATOR_IMAGE_REPOSITORY` | ✅ | Image repository path |
| `OPENCLAW_OPERATOR_IMAGE_TAG` | ✅ | Image tag (e.g., `latest`) |
| `OPENCLAW_INGRESS_ENABLED` | Optional | `auto`, `true`, or `false` |
| `OPENCLAW_INGRESS_HOST` | Optional | Public hostname for HTTPS access |
| `OPENCLAW_INGRESS_CLASS_NAME` | Optional | Ingress class (default: `nginx`) |
| `OPENCLAW_INGRESS_TLS_SECRET_NAME` | Optional | TLS Secret for HTTPS |
| `OPENCLAW_TRUSTED_PROXIES` | Optional | Comma-separated IPs of your load balancers |
| `OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME` | Optional | ConfigMap with custom CA certificates |

---

## 中文

### 什么是 openclaw-k8s？

`openclaw-k8s` 是一个基于 [OpenClaw](https://github.com/openclaw/openclaw) 的 Kubernetes Operator —— 一个企业级云原生 AI 浏览器自动化平台。它将 Kubernetes Operator 模式的强大能力带到了 OpenClaw 节点的全生命周期管理中，适用于企业规模的生产部署。

告别手动管理 Deployment、Service、ConfigMap、PVC 和 Ingress，你只需声明一个 `OpenClawNode` 自定义资源，剩下的一切交给 Operator 处理。

### ✨ 核心亮点

| 亮点 | 说明 |
|---|---|
| 🤖 **Operator 模式** | 通过 `OpenClawNode` CRD 进行声明式生命周期管理，无需手动操作资源 |
| 🔒 **密钥驱动配置** | AI 凭证（API Key、Token）通过 Kubernetes Secret 安全注入，永不明文存储 |
| 🌐 **自动 Ingress 配置** | 一个字段即可开启带 TLS 的生产级 HTTPS 接入 |
| 💾 **持久化存储** | 每个节点独立 PVC，浏览器 profile 和状态持久化保存 |
| 🧩 **多实例隔离** | 同一集群可部署数十个独立配置的 OpenClaw 节点 |
| 🔭 **精细状态感知** | 细粒度的 `DependenciesReady` 和 `Ready` 状态条件，便于可观测性 |
| 🛡️ **企业安全** | 可信代理配置、自定义 CA 证书注入、默认 TLS 就绪 |
| ⚙️ **Chromium 集成** | 每个节点可内嵌 headless Chromium，支持完整浏览器自动化 |

### 快速开始

#### 第 1 步：配置环境变量

```bash
cp deploy/.env.example deploy/.env
# 编辑 deploy/.env，填入真实配置
```

必填项说明：

```bash
OPENAI_API_KEY=sk-your-api-key            # OpenAI 兼容 API 密钥
OPENAI_BASE_URL=https://your-endpoint/v1   # API 端点地址
OPENCLAW_GATEWAY_TOKEN=随机安全令牌         # 访问 Gateway UI 的令牌
OPENCLAW_PRIMARY_MODEL=qwen3.5-plus        # 主要 LLM 模型名称

OPENCLAW_INSTANCE_NAME=my-openclaw-node   # 实例名称
IMAGE_REGISTRY=your.registry.io           # 拉取镜像的镜像仓库
IMAGE_PUSH_REGISTRY=push.your.registry.io # 推送镜像的镜像仓库
OPENCLAW_OPERATOR_IMAGE_REPOSITORY=your-org/openclaw-operator
OPENCLAW_OPERATOR_IMAGE_TAG=latest
```

#### 第 2 步：构建并推送 Operator 镜像

```bash
./deploy/push-operator-image.sh
```

#### 第 3 步：安装 Operator

将 CRD、RBAC 和控制器安装到 `openclaw-system` 命名空间：

```bash
./deploy/install-operator.sh
```

验证 Operator 是否正常运行：

```bash
kubectl get pods -n openclaw-system
# NAME                                  READY   STATUS    RESTARTS   AGE
# controller-manager-xxxxx-xxxxx        1/1     Running   0          30s
```

#### 第 4 步：部署 OpenClaw 节点实例

```bash
./deploy/install-instance.sh
```

该脚本将自动完成：
1. 创建目标命名空间
2. 创建包含 AI 凭证的 Secret
3. 应用 `OpenClawNode` 自定义资源
4. 等待实例变为 `Ready` 状态

#### 第 5 步：访问 Web UI

```bash
kubectl port-forward -n openclaw-node svc/my-openclaw-node 18789:18789
# 打开 http://localhost:18789，输入 Gateway Token 完成配对
```

### OpenClawNode 资源定义参考

```yaml
apiVersion: apps.openclaw.io/v1alpha1
kind: OpenClawNode
metadata:
  name: my-node
  namespace: my-namespace
spec:
  # 必填：指向包含 OPENAI_API_KEY / OPENAI_BASE_URL /
  # OPENCLAW_GATEWAY_TOKEN / OPENCLAW_PRIMARY_MODEL 的 Secret
  runtimeSecretRef:
    name: my-node-env-secret

  # Gateway 配置
  gateway:
    port: 18789
    trustedProxies:        # 可选：你的 Ingress 控制器 IP
      - 10.1.1.10

  # 可选：自动创建 Ingress
  ingress:
    enabled: true
    host: my-node.example.com
    className: nginx
    tlsSecretName: my-node-tls

  # 浏览器 Profile 存储
  storage:
    size: 20Gi

  # 启用 headless Chromium
  chromium:
    enabled: true

  # 配置合并模式：merge（合并）| replace（覆盖）
  configMode: merge

  # 可选：挂载自定义 CA 证书
  caBundle:
    configMapName: my-ca-bundle
```

### 环境变量说明（`.env`）

| 变量名 | 是否必填 | 说明 |
|---|---|---|
| `OPENAI_API_KEY` | ✅ 必填 | OpenAI 兼容 API 密钥 |
| `OPENAI_BASE_URL` | ✅ 必填 | API 端点地址 |
| `OPENCLAW_GATEWAY_TOKEN` | ✅ 必填 | Gateway UI 访问令牌 |
| `OPENCLAW_PRIMARY_MODEL` | ✅ 必填 | 主要 LLM 模型名称 |
| `OPENCLAW_INSTANCE_NAME` | ✅ 必填 | OpenClawNode 实例名称 |
| `IMAGE_REGISTRY` | ✅ 必填 | 拉取 Operator 镜像的仓库地址 |
| `IMAGE_PUSH_REGISTRY` | ✅ 必填 | 推送构建镜像的仓库地址 |
| `OPENCLAW_OPERATOR_IMAGE_REPOSITORY` | ✅ 必填 | 镜像仓库路径 |
| `OPENCLAW_OPERATOR_IMAGE_TAG` | ✅ 必填 | 镜像标签（如 `latest`） |
| `OPENCLAW_INGRESS_ENABLED` | 可选 | `auto`、`true` 或 `false` |
| `OPENCLAW_INGRESS_HOST` | 可选 | HTTPS 公网域名 |
| `OPENCLAW_INGRESS_CLASS_NAME` | 可选 | Ingress 类名（默认 `nginx`） |
| `OPENCLAW_INGRESS_TLS_SECRET_NAME` | 可选 | HTTPS TLS Secret 名称 |
| `OPENCLAW_TRUSTED_PROXIES` | 可选 | 负载均衡器 IP，逗号分隔 |
| `OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME` | 可选 | 自定义 CA 证书的 ConfigMap 名称 |

---

## License

Apache 2.0
