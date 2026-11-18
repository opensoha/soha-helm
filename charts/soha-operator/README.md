# Soha Operator Helm Chart

Installs the optional Soha Operator and the `workloads.soha.io/v1alpha1 WorkloadCronJob` CRD.

```sh
helm repo add opensoha https://opensoha.github.io/soha-helm
helm repo update
helm install soha-operator opensoha/soha-operator \
  --namespace soha-operator \
  --create-namespace
```

The controller watches `Deployment`, `StatefulSet`, and `DaemonSet` sources across the cluster and owns native CronJobs in the same namespace as each WorkloadCronJob. The selected container image, `env`, `envFrom`, `volumeMounts`, and referenced Pod volumes follow the source; commands, arguments, scheduling, security context, sidecars, and unrelated volumes remain the declared `spec.cronJobSpec` snapshot.

The cluster-wide role can read source workloads and reconcile CronJobs. Leader-election `Lease` and event permissions are restricted to the Helm release namespace through a namespaced Role.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `replicaCount` | `1` | Controller replicas. Leader election is enabled by default. |
| `image.repository` | `ghcr.io/opensoha/soha-operator` | Operator image repository. |
| `image.tag` | chart `appVersion` | Operator image tag. |
| `leaderElection` | `true` | Enable controller-runtime leader election. |
| `serviceAccount.create` | `true` | Create the controller ServiceAccount. |
| `rbac.create` | `true` | Create ClusterRole, Role, and bindings. |

## Schema and controller pairing

This chart bundles the exact CRD from Operator `v0.1.1` (commit
`1ab625355a8555fd54f363dac6edbcf0e5e9b334`) and defaults to image `0.1.1`.
That release uses Kubernetes Go modules 0.35.1: its native Pod schema includes
`workloadRef`, not the current source fields `schedulingGroup` and `defaultUser`.
The Soha `spec.sourceRef` field is independent and remains supported.

Helm installs CRDs from `crds/` on first installation and does not upgrade existing
CRDs. Keep existing CRDs paired with their matching controller. **Do not apply
this bundled stable CRD over an installed Kubernetes 0.37 schema, downgrade its
controller to `0.1.1`, or delete/recreate the CRD to change profiles.** Such a
downgrade can lose stored fields. This chart does not migrate or prune CRs.

### Current source schema with a custom image

The Operator repository preserves its generated Kubernetes 0.37.1 schema at
`config/crd/bases` and offers `config/development` for a matching source build.
The chart intentionally does not install that unreleased schema by default.
To use it, build an image from the same Operator source checkout and review CRD
changes and any existing stored CRs before applying that schema. Native fields
also require support from your target Kubernetes cluster.

For example, from a matching Operator source checkout and a development cluster:

```sh
make docker-build  # builds ghcr.io/opensoha/soha-operator:local
# Load that locally built image into the development cluster first.
kubectl apply -k config/crd
helm upgrade --install soha-operator opensoha/soha-operator \
  --namespace soha-operator --create-namespace --skip-crds \
  --set image.tag=local
```

For a registry-backed custom image, set both `image.repository` and `image.tag`
explicitly to that build. Never overwrite the published `0.1.1` image tag. Keep
`--skip-crds` so a fresh Helm installation cannot install the bundled stable
schema; future CRD upgrades remain an explicit operation from the matching
Operator source. Existing current-schema installations should retain their
matching custom image and schema rather than apply the stable defaults.

The current schema replaced the native `workloadRef` with `schedulingGroup`.
External CRs using the old native field need a reviewed migration before moving
to that schema; `spec.sourceRef` still selects the source workload and container.
