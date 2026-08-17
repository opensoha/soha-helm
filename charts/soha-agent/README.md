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

The control plane and agent do not need matching SemVer values. Both must support Identity Outpost protocol `v1`; the pinned Ed25519 key ID/public key must match the control plane signer. Chart `0.2.2` targets `soha-agent v0.1.6`.
