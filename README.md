# OpenClaw Kubernetes Operator

> Enterprise-Grade Cloud-Native AI Browser Automation on Kubernetes

**[中文文档](./README.zh.md)**

---

### What is openclaw-operator?

`openclaw-operator` is a Kubernetes Operator for [OpenClaw](https://github.com/openclaw/openclaw) — a cloud-native AI browser automation platform. It brings the full power of the Kubernetes Operator pattern to managing OpenClaw node lifecycles at enterprise scale.

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

If you access the instance through Ingress, use:

```text
https://<your-ingress-host>/?token=<OPENCLAW_GATEWAY_TOKEN>
```

Seeing `pairing required` on first access is expected. The token only authenticates the browser to the Gateway; you still need to approve the device pairing request once:

```bash
kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices list

kubectl exec -n openclaw-node deployment/my-openclaw-node -c main -- \
  node dist/index.js devices approve <REQUEST_ID>
```

After approval, refresh the page and the Web UI will open normally.

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

## License

Apache 2.0
