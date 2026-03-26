# OpenClaw Kubernetes Operator

> Kubernetes 上でのエンタープライズグレードのクラウドネイティブ AI ブラウザ自動化

**[English](./README.md) | [简体中文](./README.zh.md) | [繁體中文](./README.zh-TW.md) | 日本語**

---

### openclaw-operator とは？

`openclaw-operator` は、クラウドネイティブな AI ブラウザ自動化プラットフォームである [OpenClaw](https://github.com/openclaw/openclaw) のための Kubernetes Operator です。Kubernetes Operator パターンのパワーを OpenClaw ノードのライフサイクル管理にもたらし、エンタープライズ規模での運用を可能にします。

Deployment、Service、ConfigMap、PVC、Ingress リソースを手動で管理する代わりに、単一の `OpenClawNode` カスタムリソースを定義するだけで、あとは Operator がすべてを処理します。

### ✨ 主な特徴

| 特徴 | 説明 |
|---|---|
| 🤖 **Operator パターン** | `OpenClawNode` CRD による宣言的なライフサイクル管理 — 手動のリソース操作は不要 |
| 🔒 **Secret ベースの構成** | AI 認証情報（API キー、ベース URL、トークン）は Kubernetes Secret 経由で注入 — 平文での設定は不要 |
| 🌐 **Ingress 自動プロビジョニング** | フィールド一つで TLS 対応のプロダクション環境向け HTTPS Ingress を有効化 |
| 💾 **永続ストレージ** | 各ノードに専用の PVC を割り当て、ブラウザのプロファイルと状態を永続化 |
| 🧩 **マルチインスタンス** | 同一クラスタ内で、それぞれ独立して構成された数十の OpenClaw ノードを稼働可能 |
| 🔭 **ステータス条件** | `DependenciesReady` や `Ready` などの詳細なステータス条件による高い可観測性 |
| 🛡️ **エンタープライズセキュリティ** | 信頼できるプロキシ設定、カスタム CA バンドルの注入、デフォルトでの TLS 対応 |
| ⚙️ **Chromium 統合** | 各ノードにヘッドレス Chromium をオプションで組み込み、完全なブラウザ自動化をサポート |

### アーキテクチャ

```
┌──────────────────────────────────────────────────┐
│                Kubernetes クラスタ                │
│                                                  │
│  ┌───────────────────────────────────────────┐   │
│  │          openclaw-system 名前空間          │   │
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

### 前提条件

- Kubernetes クラスタ (v1.24+)
- 接続設定済みの `kubectl`
- Docker (Operator イメージのビルドおよびプッシュ用)
- OpenAI 互換の API エンドポイント (例: DashScope, Azure OpenAI)

### クイックスタート

#### ステップ 1: 環境の設定

```bash
cp deploy/.env.example deploy/.env
# deploy/.env を開き、実際の値を設定します
```

主な設定項目:

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
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=false
```

#### ステップ 2: Operator イメージのビルドとプッシュ

```bash
./deploy/push-operator-image.sh
```

#### ステップ 3: Operator のインストール

CRD、RBAC、およびコントローラーを `openclaw-system` 名前空間にインストールします。

```bash
./deploy/install-operator.sh
```

Operator が実行されていることを確認します。

```bash
kubectl get pods -n openclaw-system
# NAME                                  READY   STATUS    RESTARTS   AGE
# controller-manager-xxxxx-xxxxx        1/1     Running   0          30s
```

#### ステップ 4: OpenClaw ノードインスタンスのデプロイ

```bash
./deploy/install-instance.sh
```

このスクリプトは以下の処理を自動的に行います:
1. ターゲット名前空間の作成
2. AI 認証情報を含む Secret の作成
3. `OpenClawNode` カスタムリソースの適用
4. インスタンスが `Ready` になるまで待機

#### ステップ 5: Web UI へのアクセス

```bash
kubectl port-forward -n openclaw-node svc/my-openclaw-node 18789:18789
# http://localhost:18789 を開き、Gateway Token を入力してペアリングします
```

`deploy/.env` の `OPENCLAW_INGRESS_HOST` で Ingress を有効にしている場合、スクリプトは自動的にアクセス URL を生成します:

```text
https://<OPENCLAW_INSTANCE_NAME>.<OPENCLAW_INGRESS_HOST>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

初回アクセス時に `pairing required` と表示されるのは仕様です。トークンは Gateway への認証のみを行い、ブラウザを自動的に信頼することはありません。デバイスのペアリング要求を一度承認する必要があります。

```bash
kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices list

kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

承認後、ページをリロードすると Web UI が通常通り開きます。

### 📚 ドキュメント

- **[アクセスとペアリングガイド](./docs/ja/access-and-pairing.md)**: ローカルポートフォワーディング、Ingress アクセス、デバイスペアリング承認の詳細な手順。

ローカルデバッグのために Control UI のデバイス認証を緩和する必要がある場合は、`./deploy/install-instance.sh` を実行する前に `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true` を設定してください。これにより、インスタンスは `gateway.controlUi.allowInsecureAuth: true` で構成されます。これは Ingress 経由のリモートブラウザアクセスのペアリングチェックを無効にするものではありません。

Control UI のデバイス認証を完全に無効にし、Gateway トークンまたはパスワードのみに依存させる必要がある場合は、`OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH=true` を設定してください。これにより、インスタンスは `gateway.controlUi.dangerouslyDisableDeviceAuth: true` で構成されます。これはリスクが高いため、短時間のデバッグまたは完全に信頼されたネットワーク内でのみ使用してください。トークンを知っている全員が UI にアクセス可能になります。

#### ステップ 6: アンインストール

OpenClaw インスタンスを削除する場合:

```bash
./deploy/uninstall-instance.sh
```

Operator と CRD を削除する場合:

```bash
./deploy/uninstall-operator.sh
```

> [!WARNING]
> Operator をアンインストールするとコントローラーと CRD が削除されますが、既存の `OpenClawNode` インスタンスは自動的には削除されません。先にインスタンスを削除することをお勧めします。

### OpenClawNode カスタムリソースリファレンス

```yaml
apiVersion: apps.openclaw.io/v1alpha1
kind: OpenClawNode
metadata:
  name: my-node
  namespace: my-namespace
spec:
  # 必須: OPENAI_API_KEY, OPENAI_BASE_URL,
  # OPENCLAW_GATEWAY_TOKEN, OPENCLAW_PRIMARY_MODEL を含む Secret への参照
  runtimeSecretRef:
    name: my-node-env-secret

  # Gateway 設定
  gateway:
    port: 18789
    trustedProxies:        # オプション: Ingress コントローラーの IP
      - 10.1.1.10
    controlUi:
      allowInsecureAuth: false              # オプション: ローカルデバッグ用にデバイス認証を緩和
      dangerouslyDisableDeviceAuth: false   # オプション (危険): デバイス認証を完全に無効化

  # オプション: Ingress の自動プロビジョニング
  ingress:
    enabled: true
    host: my-node.example.com
    className: nginx
    tlsSecretName: my-node-tls

  # ブラウザプロファイルと状態のストレージ
  storage:
    size: 20Gi

  # ヘッドレス Chromium を有効化
  chromium:
    enabled: true

  # 設定のマージモード: "merge" | "replace"
  configMode: merge

  # オプション: カスタム CA バンドルの注入
  caBundle:
    configMapName: my-ca-bundle
```

### 環境変数リファレンス (`.env`)

| 変数名 | 必須 | 説明 |
|---|---|---|
| `OPENAI_API_KEY` | ✅ | OpenAI 互換の API キー |
| `OPENAI_BASE_URL` | ✅ | API エンドポイントのベース URL |
| `OPENCLAW_GATEWAY_TOKEN` | ✅ | Gateway UI を保護するためのランダムなトークン |
| `OPENCLAW_PRIMARY_MODEL` | ✅ | プライマリ LLM モデル名 |
| `OPENCLAW_INSTANCE_NAME` | ✅ | OpenClawNode インスタンスの名前 |
| `IMAGE_REGISTRY` | ✅ | Operator イメージをプルするレジストリ |
| `IMAGE_PUSH_REGISTRY` | ✅ | ビルドした Operator イメージをプッシュするレジストリ |
| `OPENCLAW_OPERATOR_IMAGE_REPOSITORY` | ✅ | イメージレポジトリパス |
| `OPENCLAW_OPERATOR_IMAGE_TAG` | ✅ | イメージタグ (例: `latest`) |
| `OPENCLAW_IMAGE_REPOSITORY` | オプション | OpenClaw アプリケーションイメージレポジトリ (デフォルト: `ghcr.io/openclaw/openclaw`) |
| `OPENCLAW_IMAGE_TAG` | オプション | OpenClaw アプリケーションイメージタグ (デフォルト: `2026.3.2`) |
| `OPENCLAW_IMAGE_PULL_POLICY` | オプション | アプリケーションイメージのプルポリシー (デフォルト: `IfNotPresent`) |
| `OPENCLAW_CHROMIUM_IMAGE_REPOSITORY` | オプション | Chromium サイドカーイメージレポジトリ (デフォルト: `chromedp/headless-shell`) |
| `OPENCLAW_CHROMIUM_IMAGE_TAG` | オプション | Chromium サイドカーイメージタグ (デフォルト: `146.0.7680.31`) |
| `OPENCLAW_CHROMIUM_IMAGE_PULL_POLICY` | オプション | Chromium イメージのプルポリシー |
| `OPENCLAW_INGRESS_ENABLED` | オプション | `auto`, `true`, または `false` |
| `OPENCLAW_INGRESS_HOST` | オプション | 公開 Ingress ドメインのサフィックス。スクリプトは `<OPENCLAW_INSTANCE_NAME>.<OPENCLAW_INGRESS_HOST>` を生成します |
| `OPENCLAW_INGRESS_CLASS_NAME` | オプション | Ingress クラス (デフォルト: `nginx`) |
| `OPENCLAW_INGRESS_TLS_SECRET_NAME` | オプション | HTTPS 用の TLS Secret |
| `OPENCLAW_TRUSTED_PROXIES` | オプション | ロードバランサーの IP (カンマ区切り) |
| `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH` | オプション | `true` に設定すると、ローカルデバッグ用にのみデバイス認証を緩和します |
| `OPENCLAW_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH` | オプション | `true` に設定すると、デバイス認証を完全に無効化し、トークン/パスワードのみに依存します (高リスク) |
| `OPENCLAW_CA_CERT_FILE` | オプション | カスタム CA 署名ファイルへのパス |
| `OPENCLAW_CA_BUNDLE_CONFIGMAP_NAME` | オプション | カスタム CA 証明書を含む ConfigMap 名 |
| `OPENCLAW_ENV_FILE` | オプション | カスタム環境変数ファイルへのパス (デフォルト: `deploy/.env`) |

---

## ライセンス

MIT
