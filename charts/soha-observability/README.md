# Soha Observability

This chart is an optional add-on. The core `soha` chart does not install it.

Profiles:

- `starter`: OpenTelemetry Collector plus a single-replica Loki with retained PVC storage. It is not an HA production backend.
- `collector_only`: OpenTelemetry Collector forwarding to an external Loki OTLP endpoint.
- `production_external`: the external profile with production-oriented resource sizing supplied by Soha.

The collector mounts `/var/log/pods` read-only and does not use the Kubernetes API. Set
`collector.namespaceAllowlist` to restrict file discovery to authorized namespaces. External
credentials must already exist as a Kubernetes Secret with a `bearer_token` key; only the Secret
name is stored in Helm values. The non-root collector joins host group `0` by default so it can
read root-grouped Pod logs on K3s; set `collector.podLogGroupId` when the node uses another log group.

The default `collector.signalAllowlist` contains only `logs`, so upgrading keeps the original
filelog-to-Loki behavior. To receive application OTLP, enable `collector.otlp` and provide an
existing Secret containing `bearer_token`, `tls.crt`, and `tls.key`. Metrics use Prometheus Remote
Write. The optional generic trace exporter uses OTLP/gRPC for external consumers; it does not
configure a Soha trace provider or enable Trace Explore or service topology in Core. Each external
bearer token comes from its own Secret. The collector adds
`soha.workspace.id`, `k8s.cluster.name`, and optional `deployment.environment.name`, preserves
application-provided service identity, drops metrics and traces without `service.name`, removes
credential attributes, and hashes configured user identifiers.

```yaml
workspaceId: default
clusterId: production-a
environment: production
collector:
  signalAllowlist: [logs, metrics, traces]
  otlp:
    enabled: true
    existingSecret: otel-ingest-tls-and-token
  metrics:
    endpoint: https://prometheus.example.com/api/v1/write
    existingSecret: prometheus-write-token
  traces:
    endpoint: otel-traces.example.com:4317
    existingSecret: external-otlp-trace-token
```

OTLP/gRPC uses TLS by default. Set `collector.traces.insecure: true` only for a trusted private
network whose OAP endpoint intentionally serves plaintext gRPC; never use it across an untrusted
network.

Configure the external trace consumer and its OTLP receiver according to that system's own
requirements. Soha Core currently has no built-in trace or service-topology query integration;
related routes and query DTOs remain for compatibility and report the capability as unavailable
until a future external provider integration is delivered.

`production_external` only changes ownership: retention, replication, capacity, backup, upgrade,
credential rotation, and recovery remain responsibilities of the external backends. Soha never
exposes Loki, Prometheus, or external trace backend credentials to the browser.

```bash
helm repo add opensoha https://opensoha.github.io/soha-helm
helm install soha-observability opensoha/soha-observability \
  --namespace soha-observability --create-namespace
```

Uninstalling keeps the Loki PVC through `helm.sh/resource-policy: keep`. Delete that PVC explicitly
only after its retained history is no longer required.
