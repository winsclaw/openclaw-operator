# OpenClaw Operator

This directory contains a Kubebuilder-style operator for managing independent OpenClaw nodes on Kubernetes.

## Design

One `OpenClawNode` represents one standalone OpenClaw service instance.

The controller reconciles these child resources per node:

- `ConfigMap` for `openclaw.json` and shell aliases
- `PersistentVolumeClaim` for `/home/node/.openclaw`
- `Service` for the gateway port
- `Deployment` with one OpenClaw pod
- Optional `Ingress`

The operator intentionally does not model a horizontally scaled OpenClaw cluster. OpenClaw is stateful and the existing chart already documents the single-instance constraint. The API is built around "many independent nodes", not "many replicas of one node".

## Expected Secret Contract

`spec.runtimeSecretRef.name` must point to a Secret in the same namespace that contains:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `OPENCLAW_GATEWAY_TOKEN`
- optional `OPENCLAW_PRIMARY_MODEL`

The Deployment mounts this Secret via `envFrom`, which preserves compatibility with the current Helm-based runtime model.

## Current Scope

The operator now includes:

- Go API types with CRD schema for ingress, storage, CA bundle, Chromium, and config merge mode
- controller reconciliation for `ConfigMap`, `PersistentVolumeClaim`, `Service`, `Deployment`, and optional `Ingress`
- status conditions that distinguish dependency readiness from workload readiness
- manager/RBAC manifests and kustomize entrypoints
- sample custom resource and a container build `Dockerfile`

Remaining work for production hardening:

1. Add webhook/defaulting if you want server-side defaults and stronger validation.
2. Add finalizers if PVC retention should be decoupled from CR deletion.
3. Add e2e tests with `envtest`.
4. Decide whether the operator should create runtime Secrets or only consume pre-created ones.

## Cluster Validation

For the current cluster install and acceptance workflow, see:

- `operator/docs/cluster-validation.md`
- `operator/scripts/cluster-validate.sh`
