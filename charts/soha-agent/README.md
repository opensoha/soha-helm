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

## Kubernetes workbench action presets

New installations default to `config.security.profile: auto` with `allowedActions: null`. This uses the workbench action list for resource CRUD, node drain, workload actions, Pod exec and port forwarding. The ServiceAccount receives named workbench permissions and read access to ControllerRevisions for workload history.

| Profile | Runtime actions and Kubernetes permissions |
| --- | --- |
| `auto` (default) and `custom` | An explicit array is used as supplied. `[]` disables all actions. Omitted or null uses the prior chart's default action list. |
| `workbench` | Uses the workbench preset independently of `allowedActions`. |
| `read-only` | Disables writes and execution. Retains custom-resource listing and authorization reviews for diagnostics. Custom resource rules containing write verbs are rejected. |

An ordinary upgrade preserves the effective action list when old saved values omit the profile or use `profile: custom`, including deployments with an explicit list. Review `helm template` and `helm diff` before applying changes.

Existing workbench deployments that need Helm writes must add the corresponding action names explicitly when upgrading. Helm mutations require individual action names such as `platform.helm_releases.install` in an `auto` or `custom` list and cluster-wide Helm permission in Core. Treat this as privileged chart execution. A chart can run hooks and manage resources in multiple namespaces or at cluster scope using the Agent ServiceAccount. The chart grants the SDK's release-state Secret verbs and named object permissions when the corresponding actions are selected. Add reviewed RBAC for charts that need other resources.

CRD definition deletion remains a separate opt-in. Custom CRD groups require explicit `rbac.customResourceRules`. The presets preserve Core authorization and Kubernetes RBAC. Secret-data access requires its independent Core permission. An image update alone leaves the installed RBAC unchanged.

## Pod terminal access

Agent mode enables `platform.pods.exec` by default and grants the Agent ServiceAccount `create` on `pods/exec`. Select `profile: custom` with an explicit action list excluding `platform.pods.exec` to remove both the action and its RBAC rule. Identity Outpost mode never renders Kubernetes RBAC.

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

The same chart runs the Proxy forward-auth runtime as an independent Service
and Deployment. Set `mode=outpost`, configure the control-plane endpoint and
credentials, and pin `config.controlPlane.outpost.trustKeyId`/`trustPublicKey`
or an overlapping `trustPublicKeys` map. Use an Agent image with Identity Outpost
protocol v1, durable per-instance state and runtime control v1 support; the
published default image tag alone is not evidence of those capabilities.

`outpostRuntime.owner=external` is the default: Helm preserves `replicaCount`
and managed runtime control stays disabled. Explicit `owner=soha` omits
`spec.replicas` and enables the signed runtime control gate. It does not
implicitly adopt an external instance or a new slot in Core. Both require
installer-verified ownership handoff (`allowAdoption=true` and
`previousOwnerStopped=true`) and a user binding with `explicitAdoption=true`
before lifecycle start. Unverified slots keep both installation flags false:
they can be bound and read as external, but cannot be started by Soha. Follow the
[slot installation and handoff procedure](../soha/OUTPOST.md) before transferring
ownership; flags never replace stopping an active prior controller.

Outpost state is persistent. The chart creates a retained PVC by default, or
uses `outpostRuntime.existingStateClaim`. For one replica, RWO storage is
supported with `outpostRuntime.accessMode=ReadWriteOnce` (default) and Recreate rollouts;
the executor slot ceiling must then be 1. Multiple replicas require verified
RWX storage (`accessMode=ReadWriteMany`). Every Pod UID has its own
0700 `.soha/outpost` directory on the volume. Container restarts retain it;
replacement Pods leave old state available for installer retention/recovery.
This runtime is not stateless. Disabling persistence without an existing claim
fails rendering. Chart uninstall does not delete the retained Outpost claim.

Outpost mode renders `/readyz` readiness, disables Kubernetes ClusterRole and
ServiceAccount token automount, and creates a PodDisruptionBudget when more
than one replica is requested. The ingress controller calls
`/api/v1/outpost/forward-auth` with `Authorization: Bearer <agent token>` or
`X-Soha-Outpost-Token: <agent token>`.

The control plane and Agent need compatible protocol versions and trust keys,
not matching SemVer. Trust-key map changes trigger a Pod rollout; there is no
configuration hot reload. Add the next public key and roll first, rotate the
Core signer, then remove the old public key after overlap with another rollout.
