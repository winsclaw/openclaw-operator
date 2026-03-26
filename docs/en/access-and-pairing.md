# Access and Pairing

Since the project has fully transitioned to the Kubernetes Operator pattern, the access and configuration flow for instances has been standardized.

## 1. Accessing OpenClaw Instance Nodes

### Local Port Forwarding
If you are in a private network or don't have a public domain, you can use port forwarding:

```bash
# Replace <instance-name> with the OPENCLAW_INSTANCE_NAME set in your .env
kubectl port-forward -n openclaw-node svc/<instance-name> 18789:18789
```

Then open your browser and access:
```text
http://localhost:18789
```

### Accessing via Ingress
If Ingress was configured during deployment (`OPENCLAW_INGRESS_ENABLED=true`), you can access it directly via the domain. For security, it's recommended to include the token in the URL:

```text
https://<your-ingress-host>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

## 2. Browser Device Pairing Approval

For security, OpenClaw enables device pairing verification by default. Even with the correct Token, first-time access will prompt `pairing required`. You need to manually approve the pairing request for your current browser.

### View Pending Requests
```bash
# <instance-name> is your instance name; default namespace is openclaw-node
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices list
```

### Approve a Specific Request
Find your request ID from the list (usually the most recent one) and run:
```bash
kubectl exec -n openclaw-node deployment/<instance-name> -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

After approval, refresh the page to enter the Web UI.

## 3. Skipping Pairing Approval (Not Recommended for Production)

If you are using it in a trusted internal network and don't want to re-approve every time you clear browser cache, you can set the following in `.env` before deploying:

```bash
OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true
```

This will make the generated `OpenClawNode` resource include the following configuration:

```yaml
spec:
  gateway:
    controlUi:
      allowInsecureAuth: true
```

In this mode, as long as the access URL contains the correct `?token=...`, the browser will be granted access immediately, skipping the device pairing step.

> [!WARNING]
> Enabling this mode reduces security. Anyone who obtains the Gateway Token can directly control your OpenClaw node through their browser.
