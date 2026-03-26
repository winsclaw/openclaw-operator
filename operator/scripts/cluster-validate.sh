#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OPERATOR_DIR="$REPO_ROOT/operator"
DEPLOY_DIR="$REPO_ROOT/deploy"

OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-openclaw-system}"
WORKLOAD_NAMESPACE="${WORKLOAD_NAMESPACE:-aiops-openclaw}"
RUNTIME_SECRET_NAME="${RUNTIME_SECRET_NAME:-openclaw-env-secret}"
VALIDATION_CR_NAME="${VALIDATION_CR_NAME:-operator-e2e}"
VALIDATION_TIMEOUT="${VALIDATION_TIMEOUT:-5m}"

load_env_file() {
  local env_file="${OPENCLAW_ENV_FILE:-$DEPLOY_DIR/.env}"

  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

operator_image() {
  if [[ -n "${OPENCLAW_OPERATOR_IMAGE:-}" ]]; then
    printf '%s\n' "$OPENCLAW_OPERATOR_IMAGE"
    return 0
  fi

  local registry="${OPENCLAW_OPERATOR_IMAGE_REGISTRY:-docker.ops.fzyun.io:5000}"
  local repository="${OPENCLAW_OPERATOR_IMAGE_REPOSITORY:-openclaw/openclaw-operator}"
  local tag="${OPENCLAW_OPERATOR_IMAGE_TAG:-latest}"
  printf '%s/%s:%s\n' "$registry" "$repository" "$tag"
}

load_env_file

DEFAULT_OPERATOR_IMAGE="$(operator_image)"
PUSH_IMAGE="${PUSH_IMAGE:-$DEFAULT_OPERATOR_IMAGE}"
PULL_IMAGE="${PULL_IMAGE:-$DEFAULT_OPERATOR_IMAGE}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

usage() {
  cat <<'EOF'
Usage:
  cluster-validate.sh build-push
  cluster-validate.sh install-operator
  cluster-validate.sh verify-cr
  cluster-validate.sh all
  cluster-validate.sh cleanup

Environment:
  PUSH_IMAGE           Push registry image used by build-push
  PULL_IMAGE           Public pull image used by install-operator
  OPERATOR_NAMESPACE   Operator namespace, default openclaw-system
  WORKLOAD_NAMESPACE   Validation workload namespace, default aiops-openclaw
  RUNTIME_SECRET_NAME  Existing runtime Secret in WORKLOAD_NAMESPACE
  VALIDATION_CR_NAME   Temporary OpenClawNode name, default operator-e2e
  VALIDATION_TIMEOUT   Wait timeout, default 5m

Notes:
  1. By default PUSH_IMAGE and PULL_IMAGE come from deploy/.env operator image settings.
  2. install-operator does not create imagePullSecrets. The image must be pullable by the cluster.
  3. cleanup only removes the temporary OpenClawNode and its owned resources.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

build_push() {
  require_cmd go
  require_cmd docker

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  log "building manager binary"
  (
    cd "$OPERATOR_DIR"
    env GOCACHE=/tmp/go-build-cache GOMODCACHE=/tmp/go-mod-cache CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
      go build -o "$tmpdir/manager" .
  )

  cp "$OPERATOR_DIR/Dockerfile.scratch" "$tmpdir/Dockerfile"

  log "building image $PUSH_IMAGE"
  docker build -t "$PUSH_IMAGE" "$tmpdir"

  log "pushing image $PUSH_IMAGE"
  docker push "$PUSH_IMAGE"

  log "push complete; confirm the same tag is reachable from $PULL_IMAGE before install"
}

install_operator() {
  require_cmd kubectl

  log "installing CRD/RBAC/manager manifests into $OPERATOR_NAMESPACE"
  kubectl apply -k "$OPERATOR_DIR/config/default"

  log "switching controller-manager image to $PULL_IMAGE"
  kubectl patch deployment controller-manager -n "$OPERATOR_NAMESPACE" --type=merge \
    -p "{\"spec\":{\"template\":{\"spec\":{\"imagePullSecrets\":null,\"containers\":[{\"name\":\"manager\",\"image\":\"$PULL_IMAGE\"}]}}}}"

  log "waiting for controller-manager rollout"
  kubectl rollout status deployment/controller-manager -n "$OPERATOR_NAMESPACE" --timeout="$VALIDATION_TIMEOUT"

  log "operator is ready"
  kubectl get deploy,pod -n "$OPERATOR_NAMESPACE" -o wide
}

apply_validation_cr() {
  cat <<EOF | kubectl apply -f -
apiVersion: apps.openclaw.io/v1alpha1
kind: OpenClawNode
metadata:
  name: ${VALIDATION_CR_NAME}
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  runtimeSecretRef:
    name: ${RUNTIME_SECRET_NAME}
  configMode: merge
  chromium:
    enabled: false
  storage:
    size: 1Gi
EOF
}

verify_cr() {
  require_cmd kubectl

  log "creating validation OpenClawNode ${VALIDATION_CR_NAME} in ${WORKLOAD_NAMESPACE}"
  apply_validation_cr

  log "waiting for deployment/${VALIDATION_CR_NAME}"
  kubectl rollout status "deployment/${VALIDATION_CR_NAME}" -n "$WORKLOAD_NAMESPACE" --timeout="$VALIDATION_TIMEOUT"

  log "waiting for OpenClawNode phase=Ready"
  kubectl wait --for=jsonpath='{.status.phase}'=Ready \
    "openclawnode/${VALIDATION_CR_NAME}" -n "$WORKLOAD_NAMESPACE" --timeout="$VALIDATION_TIMEOUT"

  kubectl get "openclawnode/${VALIDATION_CR_NAME}" -n "$WORKLOAD_NAMESPACE" -o yaml
  kubectl get deploy,pod,svc,pvc,configmap -n "$WORKLOAD_NAMESPACE" \
    -l "openclaw.io/node=${VALIDATION_CR_NAME}" -o wide
}

cleanup() {
  require_cmd kubectl

  log "deleting validation OpenClawNode ${VALIDATION_CR_NAME}"
  kubectl delete "openclawnode/${VALIDATION_CR_NAME}" -n "$WORKLOAD_NAMESPACE" --ignore-not-found

  log "waiting for owned resources to disappear"
  kubectl wait --for=delete \
    "deployment/${VALIDATION_CR_NAME}" \
    "service/${VALIDATION_CR_NAME}" \
    "persistentvolumeclaim/${VALIDATION_CR_NAME}" \
    "configmap/${VALIDATION_CR_NAME}" \
    -n "$WORKLOAD_NAMESPACE" --timeout="$VALIDATION_TIMEOUT" >/dev/null 2>&1 || true
}

main() {
  local cmd="${1:-}"

  case "$cmd" in
    build-push)
      build_push
      ;;
    install-operator)
      install_operator
      ;;
    verify-cr)
      verify_cr
      ;;
    all)
      install_operator
      verify_cr
      ;;
    cleanup)
      cleanup
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
