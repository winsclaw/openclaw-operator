# 访问与配对

由于工程已全面转向 Kubernetes Operator 模式，实例的访问与配置流程现已标准化。

## 1. 访问 OpenClaw 实例节点

### 本地端口转发访问
如果你在内网环境或没有公网域名，可以使用端口转发：

```bash
# 将 <instance-name> 替换为你在 .env 中设置的 OPENCLAW_INSTANCE_NAME
kubectl port-forward -n openclaw-node svc/<instance-name> 18789:18789
```

然后打开浏览器访问：
```text
http://localhost:18789
```

### 通过 Ingress 访问
如果在部署时配置了 Ingress（`OPENCLAW_INGRESS_ENABLED=true`），可以直接通过域名访问。为了安全，建议直接带上 Token：

```text
https://<your-ingress-host>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

## 2. 浏览器设备配对审批

为了安全，OpenClaw 默认开启了设备配对验证。首次访问即便输入了正确的 Token，页面也会提示 `pairing required`。你需要手动审批一次当前浏览器的配对请求。

### 查看待审批请求
```bash
# <instance-name> 对应你的实例名，默认命名空间为 openclaw-node
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices list
```

### 批准指定请求
从列表中找到你的请求 ID（通常是最近的一个），执行：
```bash
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

审批完成后，刷新网页即可进入 Web UI。

## 3. 跳过配对审批（不推荐用于生产）

如果你在受信任的内部网络使用，且不希望每次清理浏览器缓存后都重新审批，可以在部署实例前在 `.env` 中设置：

```bash
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true
```

这会使生成的 `OpenClawNode` 资源包含如下配置：

```yaml
spec:
  gateway:
    controlUi:
      allowInsecureAuth: true
```

此时，只要访问地址中携带了正确的 `?token=...`，浏览器将直接获得访问权限，跳过设备配对步骤。

> [!WARNING]
> 开启此模式会降低安全性。任何获取到 Gateway Token 的人都可以直接通过浏览器控制你的 OpenClaw 节点。
