# Soha Observability

This chart is an optional add-on. The core `soha` chart does not install it.

Profiles:

- `starter`: OpenTelemetry Collector plus a single-replica Loki with retained PVC storage.
- `collector_only`: OpenTelemetry Collector forwarding to an external Loki OTLP endpoint.
- `production_external`: the external profile with production-oriented resource sizing supplied by Soha.

The collector mounts `/var/log/pods` read-only and does not use the Kubernetes API. Set
`collector.namespaceAllowlist` to restrict file discovery to authorized namespaces. External
credentials must already exist as a Kubernetes Secret with a `bearer_token` key; only the Secret
name is stored in Helm values. The non-root collector joins host group `0` by default so it can
read root-grouped Pod logs on K3s; set `collector.podLogGroupId` when the node uses another log group.

```bash
helm repo add opensoha https://opensoha.github.io/soha-helm
helm install soha-observability opensoha/soha-observability \
  --namespace soha-observability --create-namespace
```

Uninstalling keeps the Loki PVC through `helm.sh/resource-policy: keep`. Delete that PVC explicitly
only after its retained history is no longer required.
