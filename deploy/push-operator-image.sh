#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_env_file() {
    local env_file="${OPENCLAW_ENV_FILE:-$SCRIPT_DIR/.env}"

    if [[ -f "$env_file" ]]; then
        echo "检测到环境变量文件: $env_file"
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "错误：未找到命令 $1"
        exit 1
    fi
}

operator_image() {
    if [[ -n "${OPENCLAW_OPERATOR_IMAGE:-}" ]]; then
        printf '%s\n' "$OPENCLAW_OPERATOR_IMAGE"
        return 0
    fi

    local registry="${IMAGE_PUSH_REGISTRY}"
    local repository="${OPENCLAW_OPERATOR_IMAGE_REPOSITORY}"
    local tag="${OPENCLAW_OPERATOR_IMAGE_TAG:-latest}"
    printf '%s/%s:%s\n' "$registry" "$repository" "$tag"
}

load_env_file

require_cmd docker

TARGET_IMAGE="$(operator_image)"
OPERATOR_DIR="$(cd "$SCRIPT_DIR/../operator" && pwd)"

echo "=== 开始构建 OpenClaw Operator 镜像 ==="
echo "目录: $OPERATOR_DIR"
echo "目标镜像: $TARGET_IMAGE"

docker build -t "$TARGET_IMAGE" "$OPERATOR_DIR"

echo "=== 开始推送 OpenClaw Operator 镜像 ==="
docker push "$TARGET_IMAGE"

echo "=== 镜像构建并推送确认完成 ==="
