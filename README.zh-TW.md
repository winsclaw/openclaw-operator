# OpenClaw Kubernetes Operator

> 企業級雲端原生 AI 瀏覽器自動化 Kubernetes Operator

**[English](./README.md) | [简体中文](./README.zh.md) | 繁體中文 | [日本語](./README.ja.md)**

---

### 什麼是 openclaw-operator？

`openclaw-operator` 是一個基於 [OpenClaw](https://github.com/openclaw/openclaw) 的 Kubernetes Operator —— 一個企業級雲端原生 AI 瀏覽器自動化平台。它將 Kubernetes Operator 模式的強大能力帶到了 OpenClaw 節點的全生命週期管理中，適用於企業規模的生產部署。

告別手動管理 Deployment、Service、ConfigMap、PVC 和 Ingress，你只需聲明一個 `OpenClawNode` 自定義資源，剩下的一切交給 Operator 處理。

### ✨ 核心亮點

| 亮點 | 說明 |
|---|---|
| 🤖 **Operator 模式** | 透過 `OpenClawNode` CRD 進行聲明式生命週期管理，無需手動操作資源 |
| 🔒 **金鑰驅動配置** | AI 憑證（API Key、Token）透過 Kubernetes Secret 安全注入，永不明文存儲 |
| 🌐 **自動 Ingress 配置** | 一個欄位即可開啟帶 TLS 的生產級 HTTPS 接入 |
| 💾 **持久化存儲** | 每個節點獨立 PVC，瀏覽器 profile 和狀態持久化保存 |
| 🧩 **多實例隔離** | 同一集群可部署數十個獨立配置的 OpenClaw 節點 |
| 🔭 **精細狀態感知** | 細粒度的 `DependenciesReady` 和 `Ready` 狀態條件，便於可觀測性 |
| 🛡️ **企業安全** | 可信代理配置、自定義 CA 證書注入、預設 TLS 就緒 |
| ⚙️ **Chromium 集成** | 每個節點可內嵌 headless Chromium，支持完整瀏覽器自動化 |

### 架構

```
┌──────────────────────────────────────────────────┐
│                Kubernetes 集群                   │
│                                                  │
│  ┌───────────────────────────────────────────┐   │
│  │          openclaw-system 命名空間          │   │
│  │   ┌──────────────────────────────────┐   │   │
│  │   │    OpenClaw Operator（控制器）    │   │   │
│  │   └──────────┬───────────────────────┘   │   │
│  └──────────────│───────────────────────────┘   │
│                 │ 監聽並協調                     │
│  ┌──────────────▼───────────────────────────┐   │
│  │       OpenClawNode CR（你的命名空間）     │   │
│  │  ┌────────┐ ┌───────┐ ┌───┐ ┌─────────┐ │   │
│  │  │Deploym.│ │Service│ │PVC│ │Ingress  │ │   │
│  │  └────────┘ └───────┘ └───┘ └─────────┘ │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

### 前置條件

- Kubernetes 集群（v1.24+）
- 已配置並連接集群的 `kubectl`
- Docker（用於構建和推送 Operator 鏡像）
- OpenAI 兼容的 API 端點（如阿里雲百煉、Azure OpenAI）

### 快速開始

#### 第 1 步：配置環境變數

```bash
cp deploy/.env.example deploy/.env
# 編輯 deploy/.env，填入真實配置
```

必填項說明：

```bash
OPENAI_API_KEY=sk-your-api-key            # OpenAI 兼容 API 金鑰
OPENAI_BASE_URL=https://your-endpoint/v1   # API 端點地址
OPENCLAW_GATEWAY_TOKEN=隨機安全令牌         # 訪問 Gateway UI 的令牌
OPENCLAW_PRIMARY_MODEL=qwen3.5-plus        # 主要 LLM 模型名稱

OPENCLAW_INSTANCE_NAME=my-openclaw-node   # 實例名稱
IMAGE_REGISTRY=your.registry.io           # 拉取鏡像的鏡像倉庫
IMAGE_PUSH_REGISTRY=push.your.registry.io # 推送鏡像的鏡像倉庫
OPENCLAW_OPERATOR_IMAGE_REPOSITORY=your-org/openclaw-operator
OPENCLAW_OPERATOR_IMAGE_TAG=latest
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=false
```

#### 第 2 步：構建並推送 Operator 鏡像

```bash
./deploy/push-operator-image.sh
```

#### 第 3 步：安裝 Operator

將 CRD、RBAC 和控制器安裝到 `openclaw-system` 命名空間：

```bash
./deploy/install-operator.sh
```

驗證 Operator 是否正常運行：

```bash
kubectl get pods -n openclaw-system
# NAME                                  READY   STATUS    RESTARTS   AGE
# controller-manager-xxxxx-xxxxx        1/1     Running   0          30s
```

#### 第 4 步：部署 OpenClaw 節點實例

```bash
./deploy/install-instance.sh
```

該腳本將自動完成：
1. 創建目標命名空間
2. 創建包含 AI 憑證的 Secret
3. 應用 `OpenClawNode` 自定義資源
4. 等待實例變為 `Ready` 狀態

#### 第 5 步：訪問 Web UI

```bash
kubectl port-forward -n openclaw-node svc/my-openclaw-node 18789:18789
# 打開 http://localhost:18789，輸入 Gateway Token 完成配對
```

如果你是透過 `deploy/.env` 的 `OPENCLAW_INGRESS_HOST` 啟用 Ingress，腳本會自動拼接訪問域名：

```text
https://<OPENCLAW_INSTANCE_NAME>.<OPENCLAW_INGRESS_HOST>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

首次訪問時看到 `pairing required` 是正常現象。`token` 只負責網關鑑權，不會自動信任當前瀏覽器，還需要審批一次設備配對請求：

```bash
kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices list

kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

審批完成後刷新頁面，Web UI 就可以正常進入。

### 📚 文檔指南

- **[訪問與配對指南](./docs/zh-TW/access-and-pairing.md)**：包含本地端口轉發、Ingress 訪問以及設備配對審批的詳細步驟。

如果你只是需要在本機調試時放寬 Control UI 的設備身份要求，可以在執行 `./deploy/install-instance.sh` 前設置 `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true`。這會讓實例生成 `gateway.controlUi.allowInsecureAuth: true`。這個開關不會關閉經由 Ingress 的遠端瀏覽器設備配對檢查。

如果你確實要完全關閉 Control UI 的設備身份檢查、只依賴 Gateway Token 或密碼訪問 UI，需要設置 `OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH=true`。這會讓實例生成 `gateway.controlUi.dangerouslyDisableDeviceAuth: true`。這個模式風險很高，只適合短期調試或完全受信任網絡，因為任何拿到 token 的人都可以直接進入 UI。

#### 第 6 步：卸載

刪除 OpenClaw 實例：

```bash
./deploy/uninstall-instance.sh
```

卸載 Operator 及 CRD：

```bash
./deploy/uninstall-operator.sh
```

> [!WARNING]
> 卸載 Operator 會移除控制器和 CRD，但不會自動刪除已有的 `OpenClawNode` 實例。建議先刪除實例。

### OpenClawNode 資源定義參考

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
    trustedProxies:        # 可選：你的 Ingress 控制器 IP
      - 10.1.1.10
    controlUi:
      allowInsecureAuth: false              # 可選：僅用於本機調試時放寬設備身份要求
      dangerouslyDisableDeviceAuth: false   # 可選且危險：徹底關閉 Control UI 設備配對

  # 可選：自動創建 Ingress
  ingress:
    enabled: true
    host: my-node.example.com
    className: nginx
    tlsSecretName: my-node-tls
    annotations:
      cert-manager.io/cluster-issuer: ca-issuer

  # 瀏覽器 Profile 存儲
  storage:
    size: 20Gi

  # 啟用 headless Chromium
  chromium:
    enabled: true

  # 配置合併模式：merge（合併）| replace（覆蓋）
  configMode: merge

  # 可選：掛載自定義 CA 證書
  caBundle:
    configMapName: my-ca-bundle
```

### 環境變數說明（`.env`）

| 變數名 | 是否必填 | 說明 |
|---|---|---|
| `OPENAI_API_KEY` | ✅ 必填 | OpenAI 兼容 API 金鑰 |
| `OPENAI_BASE_URL` | ✅ 必填 | API 端點地址 |
| `OPENCLAW_GATEWAY_TOKEN` | ✅ 必填 | Gateway UI 訪問令牌 |
| `OPENCLAW_PRIMARY_MODEL` | ✅ 必填 | 主要 LLM 模型名稱 |
| `OPENCLAW_INSTANCE_NAME` | ✅ 必填 | OpenClawNode 實例名稱 |
| `IMAGE_REGISTRY` | ✅ 必填 | 拉取 Operator 鏡像的倉庫地址 |
| `IMAGE_PUSH_REGISTRY` | ✅ 必填 | 推送構建鏡像的倉庫地址 |
| `OPENCLAW_OPERATOR_IMAGE_REPOSITORY` | ✅ 必填 | 鏡像倉庫路徑 |
| `OPENCLAW_OPERATOR_IMAGE_TAG` | ✅ 必填 | 鏡像標籤（如 `latest`） |
| `OPENCLAW_IMAGE_REPOSITORY` | 可選 | OpenClaw 應用鏡像倉庫（預設 `ghcr.io/openclaw/openclaw`） |
| `OPENCLAW_IMAGE_TAG` | 可選 | OpenClaw 應用鏡像標籤（預設 `2026.3.2`） |
| `OPENCLAW_IMAGE_PULL_POLICY` | 可選 | 應用鏡像拉取策略（預設 `IfNotPresent`） |
| `OPENCLAW_CHROMIUM_IMAGE_REPOSITORY` | 可選 | Chromium 鏡像倉庫（預設 `chromedp/headless-shell`） |
| `OPENCLAW_CHROMIUM_IMAGE_TAG` | 可選 | Chromium 鏡像標籤（預設 `146.0.7680.31`） |
| `OPENCLAW_CHROMIUM_IMAGE_PULL_POLICY` | 可選 | Chromium 鏡像拉取策略 |
| `OPENCLAW_INGRESS_ENABLED` | 可選 | `auto`、`true` 或 `false` |
| `OPENCLAW_INGRESS_HOST` | 可選 | Ingress 公網域名後綴；腳本會拼成 `<OPENCLAW_INSTANCE_NAME>.<OPENCLAW_INGRESS_HOST>` |
| `OPENCLAW_INGRESS_CLASS_NAME` | 可選 | Ingress 類名（預設 `nginx`） |
| `OPENCLAW_INGRESS_TLS_SECRET_NAME` | 可選 | HTTPS TLS Secret 名稱（預設 `<OPENCLAW_INSTANCE_NAME>-tls`） |
| `OPENCLAW_INGRESS_CLUSTER_ISSUER` | 可選 | cert-manager 的 ClusterIssuer 名稱；設定後安裝腳本會為生成的 Ingress 寫入 `cert-manager.io/cluster-issuer` |
| `OPENCLAW_INGRESS_ISSUER` | 可選 | cert-manager 的 Issuer 名稱；設定後安裝腳本會為生成的 Ingress 寫入 `cert-manager.io/issuer` |
| `OPENCLAW_TRUSTED_PROXIES` | 可選 | 負載均衡器 IP，逗號分隔 |
| `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` | 可選 | 設為 `true` 後僅對本機調試場景放寬 Control UI 設備身份要求，不會關閉 Ingress 遠端訪問的設備配對 |
| `OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH` | 可選 | 設為 `true` 後徹底關閉 Control UI 設備身份檢查，僅依賴 Gateway Token/Password，風險很高 |
| `OPENCLAW_CA_CERT_FILE` | 可選 | 自定義 CA 證書路徑 |
| `OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME` | 可選 | 自定義 CA 證書的 ConfigMap 名稱 |
| `OPENCLAW_ENV_FILE` | 可選 | 自定義環境變數文件路徑（預設 `deploy/.env`） |

---

## License

MIT
