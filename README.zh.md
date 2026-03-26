# OpenClaw Kubernetes Operator

> 企业级云原生 AI 浏览器自动化 Kubernetes Operator

**[English](./README.md) | 简体中文 | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md)**

---

### 什么是 openclaw-operator？

`openclaw-operator` 是一个基于 [OpenClaw](https://github.com/openclaw/openclaw) 的 Kubernetes Operator —— 一个企业级云原生 AI 浏览器自动化平台。它将 Kubernetes Operator 模式的强大能力带到了 OpenClaw 节点的全生命周期管理中，适用于企业规模的生产部署。

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

### 架构

```
┌──────────────────────────────────────────────────┐
│                Kubernetes 集群                   │
│                                                  │
│  ┌───────────────────────────────────────────┐   │
│  │          openclaw-system 命名空间          │   │
│  │   ┌──────────────────────────────────┐   │   │
│  │   │    OpenClaw Operator（控制器）    │   │   │
│  │   └──────────┬───────────────────────┘   │   │
│  └──────────────│───────────────────────────┘   │
│                 │ 监听并协调                     │
│  ┌──────────────▼───────────────────────────┐   │
│  │       OpenClawNode CR（你的命名空间）     │   │
│  │  ┌────────┐ ┌───────┐ ┌───┐ ┌─────────┐ │   │
│  │  │Deploym.│ │Service│ │PVC│ │Ingress  │ │   │
│  │  └────────┘ └───────┘ └───┘ └─────────┘ │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

### 前置条件

- Kubernetes 集群（v1.24+）
- 已配置并连接集群的 `kubectl`
- Docker（用于构建和推送 Operator 镜像）
- OpenAI 兼容的 API 端点（如阿里云百炼、Azure OpenAI）

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
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=false
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

如果你是通过 `deploy/.env` 的 `OPENCLAW_INGRESS_HOST` 启用 Ingress，脚本会自动拼接访问域名：

```text
https://<OPENCLAW_INSTANCE_NAME>.<OPENCLAW_INGRESS_HOST>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

首次访问时看到 `pairing required` 是正常现象。`token` 只负责网关鉴权，不会自动信任当前浏览器，还需要审批一次设备配对请求：

```bash
kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices list

kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

审批完成后刷新页面，Web UI 就可以正常进入。

如果你只是需要在本机调试时放宽 Control UI 的设备身份要求，可以在执行 `./deploy/install-instance.sh` 前设置 `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true`。这会让实例生成 `gateway.controlUi.allowInsecureAuth: true`。这个开关不会关闭经由 Ingress 的远程浏览器设备配对检查。

如果你确实要完全关闭 Control UI 的设备身份检查、只依赖 Gateway Token 或密码访问 UI，需要设置 `OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH=true`。这会让实例生成 `gateway.controlUi.dangerouslyDisableDeviceAuth: true`。这个模式风险很高，只适合短期调试或完全受信任网络，因为任何拿到 token 的人都可以直接进入 UI。

#### 第 6 步：卸载

删除 OpenClaw 实例：

```bash
./deploy/uninstall-instance.sh
```

卸载 Operator 及 CRD：

```bash
./deploy/uninstall-operator.sh
```

> [!WARNING]
> 卸载 Operator 会移除控制器和 CRD，但不会自动删除已有的 `OpenClawNode` 实例。建议先删除实例。

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
    controlUi:
      allowInsecureAuth: false              # 可选：仅用于本机调试时放宽设备身份要求
      dangerouslyDisableDeviceAuth: false   # 可选且危险：彻底关闭 Control UI 设备配对

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
| `OPENCLAW_IMAGE_REPOSITORY` | 可选 | OpenClaw 应用镜像仓库（默认 `ghcr.io/openclaw/openclaw`） |
| `OPENCLAW_IMAGE_TAG` | 可选 | OpenClaw 应用镜像标签（默认 `2026.3.2`） |
| `OPENCLAW_IMAGE_PULL_POLICY` | 可选 | 应用镜像拉取策略（默认 `IfNotPresent`） |
| `OPENCLAW_CHROMIUM_IMAGE_REPOSITORY` | 可选 | Chromium 镜像仓库（默认 `chromedp/headless-shell`） |
| `OPENCLAW_CHROMIUM_IMAGE_TAG` | 可选 | Chromium 镜像标签（默认 `146.0.7680.31`） |
| `OPENCLAW_CHROMIUM_IMAGE_PULL_POLICY` | 可选 | Chromium 镜像拉取策略 |
| `OPENCLAW_INGRESS_ENABLED` | 可选 | `auto`、`true` 或 `false` |
| `OPENCLAW_INGRESS_HOST` | 可选 | Ingress 公网域名后缀；脚本会拼成 `<OPENCLAW_INSTANCE_NAME>.<OPENCLAW_INGRESS_HOST>` |
| `OPENCLAW_INGRESS_CLASS_NAME` | 可选 | Ingress 类名（默认 `nginx`） |
| `OPENCLAW_INGRESS_TLS_SECRET_NAME` | 可选 | HTTPS TLS Secret 名称 |
| `OPENCLAW_TRUSTED_PROXIES` | 可选 | 负载均衡器 IP，逗号分隔 |
| `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` | 可选 | 设为 `true` 后仅对本机调试场景放宽 Control UI 设备身份要求，不会关闭 Ingress 远程访问的设备配对 |
| `OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH` | 可选 | 设为 `true` 后彻底关闭 Control UI 设备身份检查，仅依赖 Gateway Token/Password，风险很高 |
| `OPENCLAW_CA_CERT_FILE` | 可选 | 自定义 CA 证书文件路径 |
| `OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME` | 可选 | 挂载到节点的自定义 CA 证书 ConfigMap 名称 |
| `OPENCLAW_ENV_FILE` | 可选 | 自定义环境变量文件路径（默认 `deploy/.env`） |

---

## License

MIT
