#!/bin/bash

# 定义卸载使用的变量，确保与安装时的名称对应
NAMESPACE="aiops-openclaw"
RELEASE_NAME="openclaw"

echo "=== 开始卸载 OpenClaw ==="

# 1. 使用 Helm 卸载 Release
echo "[1/3] 正在卸载 Helm Release '$RELEASE_NAME'..."
# 尝试卸载，如果没找到则提示（通过 || 实现错误兜底）
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || echo "未找到该 Release 或已彻底卸载。"

# 2. 清理 PVC（持久化存储的数据卷）
echo "[2/3] 正在清理持久化存储卷 (PVC)..."
# 提示用户确认，防止误删重要数据
read -p "是否删除所有相关的 PVC 数据卷？这会导致历史配置与数据永久丢失！(y/N): " confirm
if [[ -n "$confirm" && ( "$confirm" == "y" || "$confirm" == "Y" ) ]]; then
    # 通过标签精准查找当前 release (实例) 对应的 PVC 并删除
    kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    echo "PVC 数据已彻底清理。"
else
    echo "已跳过，保留了 PVC 数据。若重新部署，可挂载原数据。"
fi

# 3. 清理敏感信息的 Secret
echo "[3/3] 正在清理配置的 Secret..."
# 忽略未找到的情况，尝试安全删除
kubectl delete secret openclaw-env-secret -n "$NAMESPACE" --ignore-not-found
echo "Secret 已清理。"

echo "=== 卸载完成 ==="
echo "注意：目前没有强制删除整个命名空间。如果你想彻底删除整个命名空间，请手动执行命令："
echo "kubectl delete namespace $NAMESPACE"
