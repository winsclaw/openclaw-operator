# アクセスとペアリング

プロジェクトは完全に Kubernetes Operator パターンに移行したため、インスタンスへのアクセスと設定フローが標準化されました。

## 1. OpenClaw インスタンスノードへのアクセス

### ローカルポートフォワーディング
プライベートネットワークにいる場合や公開ドメインがない場合は、ポートフォワーディングを使用できます。

```bash
# <instance-name> を .env で設定した OPENCLAW_INSTANCE_NAME に置き換えてください
kubectl port-forward -n openclaw-node svc/<instance-name> 18789:18789
```

次に、ブラウザを開いて以下にアクセスします。
```text
http://localhost:18789
```

### Ingress 経由のアクセス
デプロイ時に Ingress を構成した場合（`OPENCLAW_INGRESS_ENABLED=true`）、ドメイン経由で直接アクセスできます。セキュリティのため、URL にトークンを含めることをお勧めします。

```text
https://<your-ingress-host>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

## 2. ブラウザデバイスのペアリング承認

セキュリティのため、OpenClaw はデフォルトでデバイスペアリング検証を有効にしています。正しいトークンを使用しても、初回アクセス時には `pairing required` と表示されます。現在のブラウザのペアリング要求を手動で承認する必要があります。

### 保留中の要求を表示する
```bash
# <instance-name> はインスタンス名です。デフォルトの名前空間は openclaw-node です
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices list
```

### 特定の要求を承認する
リストから要求 ID を見つけ（通常は最新のもの）、以下を実行します。
```bash
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

承認後、ページをリロードすると Web UI にアクセスできるようになります。

## 3. ペアリング承認のスキップ（本番環境では非推奨）

信頼できる内部ネットワークで使用しており、ブラウザのキャッシュをクリアするたびに再承認したくない場合は、デプロイ前に `.env` で以下を設定できます。

```bash
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true
```

これにより、生成される `OpenClawNode` リソースに以下の構成が含まれます。

```yaml
spec:
  gateway:
    controlUi:
      allowInsecureAuth: true
```

このモードでは、アクセス URL に正しい `?token=...` が含まれている限り、ページに直接アクセスでき、デバイスペアリングの手順をスキップできます。

> [!WARNING]
> このモードを有効にするとセキュリティが低下します。Gateway トークンを入手した第三者がブラウザ経由で OpenClaw ノードを直接制御できるようになります。
