# 🦞 OpenClaw k8s

用于在 Kubernetes 上部署 OpenClaw 的 Helm chart —— OpenClaw 是一个 AI 助手，可连接到消息平台并自主执行任务。

---

## 架构

OpenClaw 以单实例部署运行（无法水平扩展）：

| 组件 | 端口 | 描述 |
|-----------|------|-------------|
| Gateway | 18789 | 主要的 HTTP/WebSocket 接口 |
| Chromium | 9222 | 用于自动化的无头浏览器 (CDP，可选) |

**应用版本:** 2026.3.2

---

## 安装

### 前提条件

- Kubernetes `>=1.26.0-0`
- Helm 3.0+
- 支持的 LLM 提供商接口密钥 (Anthropic, OpenAI 等)

### 步骤

1. 添加仓库：

```bash
helm repo add openclaw https://serhanekicii.github.io/openclaw-helm
helm repo update
```

2. 创建命名空间和 Secret：

```bash
kubectl create namespace openclaw
kubectl create secret generic openclaw-env-secret -n openclaw \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-xxx \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=your-token
```

3. 获取默认配置值：

```bash
helm show values openclaw/openclaw > values.yaml
```

4. 在 values.yaml 中引用你的 Secret：

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          envFrom:
            - secretRef:
                name: openclaw-env-secret
```

5. 安装：

```bash
helm install openclaw openclaw/openclaw -n openclaw -f values.yaml
```

6. 配对你的设备：

```bash
# 访问 Web UI
kubectl port-forward -n openclaw svc/openclaw 18789:18789
# 打开 http://localhost:18789，输入你的 Gateway Token，点击 Connect

# 批准配对请求
kubectl exec -n openclaw deployment/openclaw -c main -- node dist/index.js devices list
kubectl exec -n openclaw deployment/openclaw -c main -- node dist/index.js devices approve <REQUEST_ID>
```

如果通过 Ingress/反向代理暴露 OpenClaw，还需要把 ingress controller 的 Pod IP 加到 `app-template.gateway.trustedProxies`。OpenClaw 目前仅支持精确 IP，不支持 CIDR。

如果集群出口会对 HTTPS 做证书代理/解密，请额外挂载企业根证书，否则网页抓取和浏览器访问可能报 TLS 错误。可在部署脚本中传入：

```bash
OPENCLAW_CA_CERT_FILE=/path/to/your-root-ca.crt bash openclaw-helm/deploy/install.sh
```

这会创建 `openclaw-ca-bundle` ConfigMap，并把证书挂载到主容器和 Chromium 侧车的 `/etc/ssl/certs/ca-bundle.crt`。

---

<details>
<summary><b>使用 Fork 或本地镜像</b></summary>

如果你维护 OpenClaw 的副本或构建了自己的镜像，请指向你的容器镜像仓库：

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          image:
            repository: ghcr.io/your-org/openclaw-fork
            tag: "2026.3.2"
```

对于托管在集群内私有仓库的镜像：

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          image:
            repository: registry.internal/openclaw
            tag: "2026.3.2"
            pullPolicy: Always
```

</details>

---

## 卸载

```bash
helm uninstall openclaw -n openclaw
kubectl delete pvc -n openclaw -l app.kubernetes.io/name=openclaw  # 可选：删除数据
```

---

## 配置

所有配置值都嵌套在 `app-template:` 下。完整参考请参阅 [values.yaml](values.yaml)。

<details>
<summary><b>配置值表格</b></summary>

## 配置值

| 键 | 类型 | 默认值 | 描述 |
|-----|------|---------|-------------|
| app-template.chromiumVersion | string | `"146.0.7680.31"` | Chromium 边车镜像版本 |
| app-template.configMaps.config.data."openclaw.json" | string | `"{\n  // Gateway 配置\n  \"gateway\": {\n    \"port\": 18789,\n    \"mode\": \"local\",\n    // 重要：trustedProxies 仅使用精确的 IP 匹配\n    // - 不支持 CIDR 表示法 - 请单独列出每个代理 IP\n    // - IPv6 精确地址可能有效但未经测试\n    // - 为简单起见，建议使用单栈 IPv4 部署\n    \"trustedProxies\": [\"10.0.0.1\"]\n  },\n\n  // 浏览器配置 (Chromium 边车)\n  \"browser\": {\n    \"enabled\": true,\n    \"defaultProfile\": \"default\",\n    \"profiles\": {\n      \"default\": {\n        \"cdpUrl\": \"http://localhost:9222\",\n        \"color\": \"#4285F4\"\n      }\n    }\n  },\n\n  // 智能体配置\n  \"agents\": {\n    \"defaults\": {\n      \"workspace\": \"/home/node/.openclaw/workspace\",\n      \"model\": {\n        // 使用环境中的 ANTHROPIC_API_KEY\n        \"primary\": \"anthropic/claude-opus-4-6\"\n      },\n      \"userTimezone\": \"UTC\",\n      \"timeoutSeconds\": 600,\n      \"maxConcurrent\": 1\n    },\n    \"list\": [\n      {\n        \"id\": \"main\",\n        \"default\": true,\n        \"identity\": {\n          \"name\": \"OpenClaw\",\n          \"emoji\": \"🦞\"\n        }\n      }\n    ]\n  },\n\n  // 会话管理\n  \"session\": {\n    \"scope\": \"per-sender\",\n    \"store\": \"/home/node/.openclaw/sessions\",\n    \"reset\": {\n      \"mode\": \"idle\",\n      \"idleMinutes\": 60\n    }\n  },\n\n  // 日志\n  \"logging\": {\n    \"level\": \"info\",\n    \"consoleLevel\": \"info\",\n    \"consoleStyle\": \"compact\",\n    \"redactSensitive\": \"tools\"\n  },\n\n  // 工具配置\n  \"tools\": {\n    \"profile\": \"full\",\n    \"web\": {\n      \"search\": {\n        \"enabled\": false\n      },\n      \"fetch\": {\n        \"enabled\": true\n      }\n    }\n  }\n\n  // 可以在此处添加频道配置：\n  // \"channels\": {\n  //   \"telegram\": {\n  //     \"botToken\": \"${TELEGRAM_BOT_TOKEN}\",\n  //     \"enabled\": true\n  //   },\n  //   \"discord\": {\n  //     \"token\": \"${DISCORD_BOT_TOKEN}\"\n  //   },\n  //   \"slack\": {\n  //     \"botToken\": \"${SLACK_BOT_TOKEN}\",\n  //     \"appToken\": \"${SLACK_APP_TOKEN}\"\n  //   }\n  // }\n}\n"` |  |
| app-template.configMaps.config.data.bash_aliases | string | `"alias openclaw='node /app/dist/index.js'\n"` |  |
| app-template.configMaps.config.enabled | bool | `true` |  |
| app-template.configMode | string | `"merge"` | 配置模式：`merge` 保留运行时更改，`overwrite` 用于严格的 GitOps |
| app-template.controllers.main.containers.chromium | object | `{"enabled":true,"env":{"XDG_CACHE_HOME":"/tmp"},"image":{"repository":"chromedp/headless-shell","tag":"{{ .Values.chromiumVersion }}"},"probes":{"liveness":{"custom":true,"enabled":true,"spec":{"failureThreshold":6,"httpGet":{"path":"/json/version","port":9222},"initialDelaySeconds":10,"periodSeconds":30,"timeoutSeconds":5}},"readiness":{"custom":true,"enabled":true,"spec":{"httpGet":{"path":"/json/version","port":9222},"initialDelaySeconds":5,"periodSeconds":10}},"startup":{"custom":true,"enabled":true,"spec":{"failureThreshold":12,"httpGet":{"path":"/json/version","port":9222},"initialDelaySeconds":5,"periodSeconds":5,"timeoutSeconds":5}}},"resources":{"limits":{"cpu":"1000m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}}` | 用于浏览器自动化的 Chromium 边车 (端口 9222 上的 CDP) |
| app-template.controllers.main.containers.chromium.enabled | bool | `true` | 启用/禁用 Chromium 浏览器边车 |
| app-template.controllers.main.containers.chromium.image.repository | string | `"chromedp/headless-shell"` | Chromium 镜像仓库 |
| app-template.controllers.main.containers.chromium.image.tag | string | `"{{ .Values.chromiumVersion }}"` | Chromium 镜像标签 |
| app-template.controllers.main.containers.main | object | `{"args":["gateway","--bind","lan","--port","18789"],"command":["node","dist/index.js"],"env":{},"envFrom":[],"image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/openclaw/openclaw","tag":"{{ .Values.openclawVersion }}"},"probes":{"liveness":{"enabled":true,"spec":{"failureThreshold":3,"initialDelaySeconds":30,"periodSeconds":30,"tcpSocket":{"port":18789},"timeoutSeconds":5},"type":"TCP"},"readiness":{"enabled":true,"spec":{"failureThreshold":3,"initialDelaySeconds":10,"periodSeconds":10,"tcpSocket":{"port":18789},"timeoutSeconds":5},"type":"TCP"},"startup":{"enabled":true,"spec":{"failureThreshold":30,"initialDelaySeconds":5,"periodSeconds":5,"tcpSocket":{"port":18789},"timeoutSeconds":5},"type":"TCP"}},"resources":{"limits":{"cpu":"2000m","memory":"2Gi"},"requests":{"cpu":"200m","memory":"512Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}}` | OpenClaw 主容器 |
| app-template.controllers.main.containers.main.image.pullPolicy | string | `"IfNotPresent"` | 镜像拉取策略 |
| app-template.controllers.main.containers.main.image.repository | string | `"ghcr.io/openclaw/openclaw"` | 容器镜像仓库 |
| app-template.controllers.main.containers.main.image.tag | string | `"{{ .Values.openclawVersion }}"` | 容器镜像标签 |
| app-template.controllers.main.containers.main.resources | object | `{"limits":{"cpu":"2000m","memory":"2Gi"},"requests":{"cpu":"200m","memory":"512Mi"}}` | 资源请求和限制 |
| app-template.controllers.main.initContainers.init-config.command | list | 见 values.yaml | Init-config 启动脚本 |
| app-template.controllers.main.initContainers.init-config.env.CONFIG_MODE | string | `"{{ .Values.configMode | default \"merge\" }}"` |  |
| app-template.controllers.main.initContainers.init-config.image.repository | string | `"ghcr.io/openclaw/openclaw"` |  |
| app-template.controllers.main.initContainers.init-config.image.tag | string | `"{{ .Values.openclawVersion }}"` |  |
| app-template.controllers.main.initContainers.init-config.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| app-template.controllers.main.initContainers.init-config.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| app-template.controllers.main.initContainers.init-config.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| app-template.controllers.main.initContainers.init-config.securityContext.runAsGroup | int | `1000` |  |
| app-template.controllers.main.initContainers.init-config.securityContext.runAsNonRoot | bool | `true` |  |
| app-template.controllers.main.initContainers.init-config.securityContext.runAsUser | int | `1000` |  |
| app-template.controllers.main.initContainers.init-skills.command | list | 见 values.yaml | Init-skills 启动脚本 |
| app-template.controllers.main.initContainers.init-skills.env.HOME | string | `"/tmp"` |  |
| app-template.controllers.main.initContainers.init-skills.env.NPM_CONFIG_CACHE | string | `"/tmp/.npm"` |  |
| app-template.controllers.main.initContainers.init-skills.image.repository | string | `"ghcr.io/openclaw/openclaw"` |  |
| app-template.controllers.main.initContainers.init-skills.image.tag | string | `"{{ .Values.openclawVersion }}"` |  |
| app-template.controllers.main.initContainers.init-skills.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| app-template.controllers.main.initContainers.init-skills.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| app-template.controllers.main.initContainers.init-skills.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| app-template.controllers.main.initContainers.init-skills.securityContext.runAsGroup | int | `1000` |  |
| app-template.controllers.main.initContainers.init-skills.securityContext.runAsNonRoot | bool | `true` |  |
| app-template.controllers.main.initContainers.init-skills.securityContext.runAsUser | int | `1000` |  |
| app-template.controllers.main.replicas | int | `1` | 副本数量 (必须为 1，OpenClaw 不支持水平扩展) |
| app-template.controllers.main.strategy | string | `"Recreate"` | 部署策略 |
| app-template.defaultPodOptions.securityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch"}` | Pod 安全上下文 |
| app-template.ingress.main.enabled | bool | `false` | 启用 Ingress 资源创建 |
| app-template.networkpolicies.main.controller | string | `"main"` |  |
| app-template.networkpolicies.main.enabled | bool | `false` | 启用网络策略 (默认全拒绝并带有显式允许规则) |
| app-template.networkpolicies.main.policyTypes[0] | string | `"Ingress"` |  |
| app-template.networkpolicies.main.policyTypes[1] | string | `"Egress"` |  |
| app-template.networkpolicies.main.rules.egress[0].ports[0].port | int | `53` |  |
| app-template.networkpolicies.main.rules.egress[0].ports[0].protocol | string | `"UDP"` |  |
| app-template.networkpolicies.main.rules.egress[0].ports[1].port | int | `53` |  |
| app-template.networkpolicies.main.rules.egress[0].ports[1].protocol | string | `"TCP"` |  |
| app-template.networkpolicies.main.rules.egress[0].to[0].namespaceSelector.matchLabels."kubernetes.io/metadata.name" | string | `"kube-system"` |  |
| app-template.networkpolicies.main.rules.egress[0].to[0].podSelector.matchLabels.k8s-app | string | `"kube-dns"` |  |
| app-template.networkpolicies.main.rules.egress[1].to[0].ipBlock.cidr | string | `"0.0.0.0/0"` |  |
| app-template.networkpolicies.main.rules.egress[1].to[0].ipBlock.except[0] | string | `"10.0.0.0/8"` |  |
| app-template.networkpolicies.main.rules.egress[1].to[0].ipBlock.except[1] | string | `"172.16.0.0/12"` |  |
| app-template.networkpolicies.main.rules.egress[1].to[0].ipBlock.except[2] | string | `"192.168.0.0/16"` |  |
| app-template.networkpolicies.main.rules.egress[1].to[0].ipBlock.except[3] | string | `"169.254.0.0/16"` |  |
| app-template.networkpolicies.main.rules.egress[1].to[0].ipBlock.except[4] | string | `"100.64.0.0/10"` |  |
| app-template.networkpolicies.main.rules.ingress[0].from[0].namespaceSelector.matchLabels."kubernetes.io/metadata.name" | string | `"gateway-system"` |  |
| app-template.networkpolicies.main.rules.ingress[0].ports[0].port | int | `18789` |  |
| app-template.networkpolicies.main.rules.ingress[0].ports[0].protocol | string | `"TCP"` |  |
| app-template.openclawVersion | string | `"2026.3.2"` | OpenClaw 镜像版本 (用于所有 OpenClaw 容器) |
| app-template.persistence.bash-aliases.advancedMounts.main.main[0].path | string | `"/home/node/.bash_aliases"` |  |
| app-template.persistence.bash-aliases.advancedMounts.main.main[0].readOnly | bool | `true` |  |
| app-template.persistence.bash-aliases.advancedMounts.main.main[0].subPath | string | `"bash_aliases"` |  |
| app-template.persistence.bash-aliases.enabled | bool | `true` |  |
| app-template.persistence.bash-aliases.identifier | string | `"config"` |  |
| app-template.persistence.bash-aliases.type | string | `"configMap"` |  |
| app-template.persistence.config.advancedMounts.main.init-config[0].path | string | `"/config"` |  |
| app-template.persistence.config.advancedMounts.main.init-config[0].readOnly | bool | `true` |  |
| app-template.persistence.config.enabled | bool | `true` |  |
| app-template.persistence.config.identifier | string | `"config"` |  |
| app-template.persistence.config.type | string | `"configMap"` |  |
| app-template.persistence.data.accessMode | string | `"ReadWriteOnce"` | PVC 访问模式 |
| app-template.persistence.data.advancedMounts.main.init-config[0].path | string | `"/home/node/.openclaw"` |  |
| app-template.persistence.data.advancedMounts.main.init-skills[0].path | string | `"/home/node/.openclaw"` |  |
| app-template.persistence.data.advancedMounts.main.main[0].path | string | `"/home/node/.openclaw"` |  |
| app-template.persistence.data.enabled | bool | `true` |  |
| app-template.persistence.data.size | string | `"5Gi"` | PVC 存储大小 |
| app-template.persistence.data.type | string | `"persistentVolumeClaim"` |  |
| app-template.persistence.tmp.advancedMounts.main.chromium[0].path | string | `"/tmp"` |  |
| app-template.persistence.tmp.advancedMounts.main.init-config[0].path | string | `"/tmp"` |  |
| app-template.persistence.tmp.advancedMounts.main.init-skills[0].path | string | `"/tmp"` |  |
| app-template.persistence.tmp.advancedMounts.main.main[0].path | string | `"/tmp"` |  |
| app-template.persistence.tmp.enabled | bool | `true` |  |
| app-template.persistence.tmp.type | string | `"emptyDir"` |  |
| app-template.service.main.controller | string | `"main"` |  |
| app-template.service.main.ipFamilies[0] | string | `"IPv4"` |  |
| app-template.service.main.ipFamilyPolicy | string | `"SingleStack"` | 仅 IPv4 (见网关配置中的 trustedProxies 说明) |
| app-template.service.main.ports.http.port | int | `18789` | 网关服务端口 |

</details>

### 配置模式

`configMode` 设置控制 Helm 管理的配置如何与运行时更改合并：

| 模式 | 行为 |
|------|----------|
| `merge` (默认) | Helm 值与现有配置深度合并。保留运行时更改（例如，配对的设备、UI 设置）。 |
| `overwrite` | Helm 值完全替换现有配置。用于严格的 GitOps，其中配置应与 values.yaml 完全匹配。 |

```yaml
app-template:
  configMode: overwrite  # 或 "merge" (默认)
```

<details>
<summary><b>使用配置合并的 ArgoCD</b></summary>

在 ArgoCD 中使用 `configMode: merge` 时，通过忽略 ConfigMap 来防止 ArgoCD 覆盖运行时配置更改：

```yaml
# 应用清单
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openclaw
spec:
  ignoreDifferences:
    - group: ""
      kind: ConfigMap
      name: openclaw
      jsonPointers:
        - /data
```

这允许：
- ArgoCD 管理部署、服务等。
- 运行时配置更改（配对设备、UI 设置）持久化在 PVC 上
- Helm 值在 pod 重启时仍然合并

</details>

### 安全

本 Chart 遵循安全最佳实践：

- 所有容器作为非 root 用户运行 (UID 1000)
- 所有容器均使用只读根文件系统
- 删除所有能力 (capabilities)
- 禁用特权提升
- 可通过网络策略进行工作负载隔离

> **重要：** OpenClaw 具有 shell 访问权限并处理不可信输入。请使用网络策略并限制其暴露。有关最佳实践，请参阅 [OpenClaw 安全指南](https://docs.openclaw.ai/gateway/security)。

### 网络策略

网络策略将 OpenClaw 与内部集群服务隔离，从而在遭到破坏时限制受影响范围：

```yaml
app-template:
  networkpolicies:
    main:
      enabled: true
```

默认策略允许：
- 来自 `gateway-system` 命名空间在 18789 端口上的入站 (Ingress)
- 到 kube-dns 的出站 (Egress)
- 到公共互联网的出站 (Egress) (阻止私有/预留范围)

需要具有网络策略支持的 CNI (Calico, Cilium)。

<details>
<summary><b>允许内部服务</b></summary>

要允许 OpenClaw 访问内部服务 (例如 Vault, Ollama)，请添加出站规则：

```yaml
app-template:
  networkpolicies:
    main:
      enabled: true
      rules:
        egress:
          # DNS (必需)
          - to:
              - namespaceSelector:
                  matchLabels:
                    kubernetes.io/metadata.name: kube-system
                podSelector:
                  matchLabels:
                    k8s-app: kube-dns
            ports:
              - protocol: UDP
                port: 53
          # 公共互联网 (阻止 RFC1918)
          - to:
              - ipBlock:
                  cidr: 0.0.0.0/0
                  except:
                    - 10.0.0.0/8
                    - 172.16.0.0/12
                    - 192.168.0.0/16
          # Vault
          - to:
              - namespaceSelector:
                  matchLabels:
                    kubernetes.io/metadata.name: vault
            ports:
              - protocol: TCP
                port: 8200
          # Ollama
          - to:
              - namespaceSelector:
                  matchLabels:
                    kubernetes.io/metadata.name: ollama
            ports:
              - protocol: TCP
                port: 11434
```

</details>

### 浏览器自动化

Chromium 边车通过 9222 端口上的 CDP 提供无头浏览器。

禁用方法：

```yaml
app-template:
  controllers:
    main:
      containers:
        chromium:
          enabled: false
```

### 技能 (Skills)

`init-skills` 容器提供来自 [ClawHub](https://clawhub.com) 的声明式技能管理：

```yaml
app-template:
  controllers:
    main:
      initContainers:
        init-skills:
          command:
            - sh
            - -c
            - |
              cd /home/node/.openclaw/workspace && mkdir -p skills
              for skill in weather; do
                if ! npx -y clawhub install "$skill" --no-input; then
                  echo "警告: 安装技能失败: $skill"
                fi
              done
```

### 运行时依赖

某些功能 (接口、技能) 需要基础镜像中未包含的其他运行时 or 软件包。`init-skills` 初始化容器处理此问题 —— 将额外的工具安装到 PVC 的 `/home/node/.openclaw`，以便它在 pod 重启后保持存在并可在运行时使用。

这种方法很有必要，因为所有容器都作为非 root 用户 (UID 1000) 以 **只读根文件系统** 运行。默认的软件包管理路径 (例如 `/usr/local/lib/node_modules`) 不可写。将安装路径重定向到 PVC 解决了这个问题。

<details>
<summary><b>pnpm (例如 MS Teams 接口)</b></summary>

MS Teams 等接口需要 pnpm 软件包。只读根文件系统阻止写入默认的 pnpm 路径 (`/usr/local/lib/node_modules`, `~/.local/share/pnpm` 等)。解决方法是将 pnpm 安装到 PVC 并在可写挂载中重定向其目录。

`init-skills` 容器已经设置了 `HOME=/tmp`，因此 pnpm 的缓存、状态和配置写入落在 `/tmp` (可写 emptyDir)。内容可寻址存储放在 PVC 上，以便硬链接可以工作 (与 `node_modules` 同一文件系统) 并在重启后保持。

**1. 在 `init-skills` 中安装 pnpm 和软件包：**

```yaml
app-template:
  controllers:
    main:
      initContainers:
        init-skills:
          command:
            - sh
            - -c
            - |
              PNPM_HOME=/home/node/.openclaw/pnpm
              mkdir -p "$PNPM_HOME"
              if [ ! -f "$PNPM_HOME/pnpm" ]; then
                echo "正在安装 pnpm..."
                curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" SHELL=/bin/sh sh -
              fi
              export PATH="$PNPM_HOME:$PATH"
              echo "正在安装接口依赖..."
              cd /home/node/.openclaw
              pnpm install <your-package> --store-dir /home/node/.openclaw/.pnpm-store
```

**2. 将 pnpm 暴露给主容器：**

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          env:
            PATH: /home/node/.openclaw/pnpm:/home/node/.openclaw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            PNPM_HOME: /home/node/.openclaw/pnpm
            PNPM_STORE_DIR: /home/node/.openclaw/.pnpm-store
```

</details>

<details>
<summary><b>uv (Python 软件包管理器)</b></summary>

对于需要 Python 的技能：

**1. 在 `init-skills` 中安装 uv：**

```yaml
app-template:
  controllers:
    main:
      initContainers:
        init-skills:
          command:
            - sh
            - -c
            - |
              mkdir -p /home/node/.openclaw/bin
              if [ ! -f /home/node/.openclaw/bin/uv ]; then
                echo "正在安装 uv..."
                curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/home/node/.openclaw/bin sh
              fi
```

**2. 在主容器中添加到 PATH：**

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          env:
            PATH: /home/node/.openclaw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

</details>

### ConfigMap/Secret 更改后自动重启

要在 ConfigMap/Secret 更改时自动重启 Pod，请使用 [Stakater Reloader](https://github.com/stakater/Reloader) 或 [ArgoCD](https://argo-cd.readthedocs.io/)。详细设置请参阅 [博客文章](https://serhanekici.com/openclaw-helm.html)。

```yaml
app-template:
  defaultPodOptions:
    annotations:
      reloader.stakater.com/auto: "true"
```

### 持久化

持久化存储默认已启用 (5Gi)。

禁用方法 (重启后数据丢失)：

```yaml
app-template:
  persistence:
    data:
      enabled: false
```

<details>
<summary><b>Ingress</b></summary>

```yaml
app-template:
  gateway:
    trustedProxies:
      - 10.233.66.230
  ingress:
    main:
      enabled: true
      className: your-ingress-class
      hosts:
        - host: openclaw.example.com
          paths:
            - path: /
              pathType: Prefix
              service:
                identifier: main
                port: http
      tls:
        - secretName: openclaw-tls
          hosts:
            - openclaw.example.com
```

</details>

<details>
<summary><b>受信任的内部 CA</b></summary>

对于带有私有 CA 的内部服务进行 HTTPS 访问：

```yaml
app-template:
  persistence:
    ca-bundle:
      enabled: true
      type: configMap
      name: ca-bundle
      advancedMounts:
        main:
          main:
            - path: /etc/ssl/certs/ca-bundle.crt
              subPath: ca-bundle.crt
              readOnly: true
  controllers:
    main:
      containers:
        main:
          env:
            REQUESTS_CA_BUNDLE: /etc/ssl/certs/ca-bundle.crt
```

</details>

<details>
<summary><b>资源限制</b></summary>

主容器的默认资源：

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 2000m
              memory: 2Gi
```

</details>

---

## 故障排除

<details>
<summary><b>调试命令</b></summary>

```bash
# Pod 状态
kubectl get pods -n openclaw

# 日志
kubectl logs -n openclaw deployment/openclaw

# 端口转发
kubectl port-forward -n openclaw svc/openclaw 18789:18789
```

</details>

---

## 开发

```bash
helm lint charts/openclaw
helm dependency update charts/openclaw
helm template test charts/openclaw --debug
```

---

## 依赖关系

| 仓库 | 名称 | 版本 |
|------------|------|---------|
| https://bjw-s-labs.github.io/helm-charts/ | app-template | 4.6.2 |

## 许可证

MIT
