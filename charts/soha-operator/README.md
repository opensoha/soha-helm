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

Helm installs CRDs from `crds/` before chart templates. Review and apply CRD schema upgrades explicitly when upgrading across API versions.
