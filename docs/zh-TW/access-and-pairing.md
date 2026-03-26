# 訪問與配對

由於工程已全面轉向 Kubernetes Operator 模式，實例的訪問與配置流程現已標準化。

## 1. 訪問 OpenClaw 實例節點

### 本地端口轉發訪問
如果你在內網環境或沒有公網域名，可以使用端口轉發：

```bash
# 將 <instance-name> 替換為你在 .env 中設置的 OPENCLAW_INSTANCE_NAME
kubectl port-forward -n openclaw-node svc/<instance-name> 18789:18789
```

然後打開瀏覽器訪問：
```text
http://localhost:18789
```

### 通過 Ingress 訪問
如果在部署時配置了 Ingress（`OPENCLAW_INGRESS_ENABLED=true`），可以直接通過域名訪問。為了安全，建議直接帶上 Token：

```text
https://<your-ingress-host>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

## 2. 瀏覽器設備配對審批

為了安全，OpenClaw 預設開啟了設備配對驗證。首次訪問即便輸入了正確的 Token，頁面也會提示 `pairing required`。你需要手動審批一次當前瀏覽器的配對請求。

### 查看待審批請求
```bash
# <instance-name> 對應你的實例名，預設命名空間為 openclaw-node
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices list
```

### 批准指定請求
從列表中找到你的請求 ID（通常是最近的一個），執行：
```bash
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

審批完成後，刷新網頁即可進入 Web UI。

## 3. 跳過配對審批（不推薦用於生產）

如果你在受信任的內部網絡使用，且不希望每次清理瀏覽器快取後都重新審批，可以在部署實例前在 `.env` 中設置：

```bash
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true
```

這會使生成的 `OpenClawNode` 資源包含如下配置：

```yaml
spec:
  gateway:
    controlUi:
      allowInsecureAuth: true
```

此時，只要訪問地址中攜帶了正確的 `?token=...`，瀏覽器將直接獲得訪問權限，跳過設備配對步驟。

> [!WARNING]
> 開啟此模式會降低安全性。任何獲取到 Gateway Token 的人都可以直接通過瀏覽器控制你的 OpenClaw 節點。
