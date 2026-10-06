# Soha Agent

## Usage

The chart is distributed through the OpenSoha Helm repository.

- Helm Repository: `https://opensoha.github.io/soha-helm` with chart `soha-agent`

Install from the Helm repository:

```bash
helm repo add opensoha https://opensoha.github.io/soha-helm
helm repo update
helm install soha-agent opensoha/soha-agent \
  --namespace soha-agent \
  --create-namespace \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN"
```

## Pod terminal access

Agent mode enables `platform.pods.exec` by default and grants the Agent ServiceAccount `create` on `pods/exec`. Removing `platform.pods.exec` from `config.security.allowedActions` also removes that RBAC rule from the rendered chart. Identity Outpost mode never renders Kubernetes RBAC.

## Custom resources, Prometheus, and delivery targets

Custom resources require a matching saved cluster grant in Soha, the Agent action allowlist, and Kubernetes RBAC. Start with explicit read permissions; add write verbs only for resources that need them:

```yaml
rbac:
  customResourceRules:
    - apiGroup: example.io
      resources: [widgets]
      verbs: [get, list, watch]
      namespaces: [apps]
config:
  prometheus:
    baseUrl: http://prometheus.monitoring.svc:9090
  controlPlane:
    providerKinds: []
```

Empty `namespaces` grants the named resources throughout the cluster, including cluster-scoped resources. Wildcard groups, resources, and verbs are rejected. Helm manages the corresponding namespaced Roles and RoleBindings on upgrade. When using Soha's raw `kubectl apply` installation instead, remove obsolete namespaced Roles and RoleBindings explicitly after revoking their saved grants; apply alone does not prune them.

An Agent-connected cluster can choose **Core direct** or **Agent proxy** for Prometheus independently of Kubernetes access. Save the same endpoint in Soha and in `config.prometheus.baseUrl`. Supply an optional bearer token through `secrets.prometheusBearerToken` using a protected values file. The token is mounted from a Secret, never placed in the ConfigMap. Endpoint, configuration, and credential changes trigger a Pod rollout. The proxy uses the configured endpoint, standard TLS validation, bounded queries and responses, and rejects redirects; it never silently falls back to Core direct.

With `config.controlPlane.enabled=true`, the Kubernetes Agent automatically claims cluster-bound Manifest SSA and Helm SDK tasks using its configured Kubernetes cluster ID and Agent token. Keep the cluster ID and token aligned with the Soha registration. `providerKinds: []` disables generic CI task claims while retaining these cluster-bound claims. Existing heartbeat, callback, cancellation, timeout, and retry behavior is reused. Generic Kubernetes Job executors remain unavailable for Agent targets.

These features require updated Core and Agent binaries as well as the chart/installation configuration. Updating only the image does not add missing RBAC rules to existing installations.

## Identity Outpost mode

The same chart can run the lightweight Proxy forward-auth runtime without Kubernetes API RBAC or persistent state. Use an agent image release that advertises Identity Outpost protocol `v1` and pin the control-plane signing public key:

```bash
helm install soha-outpost opensoha/soha-agent \
  --namespace soha-outpost \
  --create-namespace \
  --set mode=outpost \
  --set replicaCount=2 \
  --set-string config.controlPlane.baseUrl=https://soha.example.com \
  --set-string config.controlPlane.outpost.agentId=production-outpost \
  --set-string config.controlPlane.outpost.trustKeyId="$SOHA_OUTPOST_KEY_ID" \
  --set-string config.controlPlane.outpost.trustPublicKey="$SOHA_OUTPOST_PUBLIC_KEY" \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN" \
  --set-string secrets.agentBearerToken="$SOHA_OUTPOST_AGENT_TOKEN"
```

Outpost mode renders `/readyz` readiness, disables Kubernetes ClusterRole and PVC resources, and creates a PodDisruptionBudget when more than one replica is requested. The ingress controller must call `/api/v1/outpost/forward-auth` with `Authorization: Bearer <agent token>` or `X-Soha-Outpost-Token: <agent token>`.

The control plane and agent do not need matching SemVer values. Both must support Identity Outpost protocol `v1`; the pinned Ed25519 key ID/public key must match the control plane signer. Chart `0.2.5` targets `soha-agent v0.1.9`.
