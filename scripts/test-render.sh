#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

default_render="$tmp_dir/default.yaml"
feature_render="$tmp_dir/feature.yaml"
restart_render="$tmp_dir/restart.yaml"
replica_render="$tmp_dir/replica.yaml"
logger_render="$tmp_dir/logger.yaml"
external_postgres_render="$tmp_dir/external-postgres.yaml"
persistence_disabled_render="$tmp_dir/persistence-disabled.yaml"
persistence_existing_render="$tmp_dir/persistence-existing.yaml"
agent_render="$tmp_dir/agent.yaml"
agent_without_terminal_render="$tmp_dir/agent-without-terminal.yaml"
standalone_agent_render="$tmp_dir/standalone-agent.yaml"
outpost_render="$tmp_dir/outpost.yaml"
observability_render="$tmp_dir/observability.yaml"
observability_external_render="$tmp_dir/observability-external.yaml"
observability_scoped_render="$tmp_dir/observability-scoped.yaml"
observability_three_signal_render="$tmp_dir/observability-three-signal.yaml"
operator_render="$tmp_dir/operator.yaml"
operator_external_rbac_render="$tmp_dir/operator-external-rbac.yaml"
operator_crd="$root_dir/charts/soha-operator/crds/workloads.soha.io_workloadcronjobs.yaml"

helm template soha "$root_dir/charts/soha" >"$default_render"
helm template soha "$root_dir/charts/soha" \
  --set config.modules.ai.features.globalAssistant=false >"$feature_render"
helm template soha "$root_dir/charts/soha" \
  --set-string config.idleTimeout=180s >"$restart_render"
helm template soha "$root_dir/charts/soha" \
  --set replicaCount=2 >"$replica_render"
helm template soha "$root_dir/charts/soha" \
  --set-string config.loggerLevel=debug >"$logger_render"
helm template soha "$root_dir/charts/soha" \
  --set postgres.enabled=false \
  --set postgres.port=15432 \
  --set-string postgres.host=postgres.example.com >"$external_postgres_render"
helm template soha "$root_dir/charts/soha" \
  --set persistence.enabled=false >"$persistence_disabled_render"
helm template soha "$root_dir/charts/soha" \
  --set-string persistence.existingClaim=existing-soha-data >"$persistence_existing_render"
helm template soha-agent "$root_dir/charts/soha-agent" >"$agent_render"
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set 'config.security.allowedActions={platform.deployments.restart}' >"$agent_without_terminal_render"
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set config.controlPlane.enabled=false >"$standalone_agent_render"
helm template soha-outpost "$root_dir/charts/soha-agent" \
  --set mode=outpost \
  --set replicaCount=2 \
  --set-string config.controlPlane.outpost.trustKeyId=test-key \
  --set-string config.controlPlane.outpost.trustPublicKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
  --set-string secrets.controlPlaneBearerToken=12345678901234567890123456789012 \
  --set-string secrets.agentBearerToken=abcdefghijklmnopqrstuvwxyz123456 >"$outpost_render"
helm template soha-observability "$root_dir/charts/soha-observability" >"$observability_render"
helm template soha-observability "$root_dir/charts/soha-observability" \
  --set profile=production_external \
  --set-string collector.destination.endpoint=https://loki.example.com/otlp >"$observability_external_render"
helm template soha-observability "$root_dir/charts/soha-observability" \
  --set 'collector.namespaceAllowlist={team-a,team-b}' \
  --set collector.podLogGroupId=1234 >"$observability_scoped_render"
helm template soha-observability "$root_dir/charts/soha-observability" \
  --set profile=production_external \
  --set-string workspaceId=workspace-a \
  --set-string clusterId=cluster-a \
  --set-string environment=production \
  --set-string collector.destination.endpoint=https://loki.example.com/otlp \
  --set 'collector.signalAllowlist={logs,metrics,traces}' \
  --set collector.otlp.enabled=true \
  --set-string collector.otlp.existingSecret=otel-ingest \
  --set-string collector.metrics.endpoint=https://prometheus.example.com/api/v1/write \
  --set-string collector.metrics.existingSecret=metrics-token \
  --set-string collector.traces.endpoint=skywalking.example.com:11800 \
  --set-string collector.traces.existingSecret=traces-token \
  --set collector.traces.insecure=true >"$observability_three_signal_render"
helm template soha-operator "$root_dir/charts/soha-operator" \
  --include-crds >"$operator_render"
helm template soha-operator "$root_dir/charts/soha-operator" \
  --set rbac.create=false \
  --set serviceAccount.create=false \
  --set-string serviceAccount.name=existing-operator >"$operator_external_rbac_render"

checksum() {
  sed -n 's/^[[:space:]]*checksum\/config: "\([0-9a-f][0-9a-f]*\)"$/\1/p' "$1" | head -n 1
}

default_checksum=$(checksum "$default_render")
feature_checksum=$(checksum "$feature_render")
restart_checksum=$(checksum "$restart_render")
replica_checksum=$(checksum "$replica_render")
logger_checksum=$(checksum "$logger_render")

case "$default_checksum" in
  [0-9a-f][0-9a-f]*) ;;
  *) echo "missing config checksum in app Deployment" >&2; exit 1 ;;
esac

[ "${#default_checksum}" -eq 64 ] || {
  echo "config checksum is not a SHA-256 digest" >&2
  exit 1
}
rendered_config=$(awk '
  /^  config.yaml: \|-$/ { in_config = 1; next }
  in_config && /^    / { sub(/^    /, ""); print; next }
  in_config { exit }
' "$default_render")
rendered_checksum=$(printf '%s' "$rendered_config" | shasum -a 256 | awk '{print $1}')
[ "$default_checksum" = "$rendered_checksum" ] || {
  echo "Deployment checksum does not match the rendered config.yaml payload" >&2
  exit 1
}
[ "$default_checksum" != "$feature_checksum" ] || {
  echo "feature baseline change did not update config checksum" >&2
  exit 1
}
[ "$default_checksum" != "$restart_checksum" ] || {
  echo "restart-required baseline change did not update config checksum" >&2
  exit 1
}
[ "$default_checksum" = "$replica_checksum" ] || {
  echo "replica count unexpectedly changed config checksum" >&2
  exit 1
}
[ "$default_checksum" != "$logger_checksum" ] || {
  echo "rendered config change did not update config checksum" >&2
  exit 1
}

grep -q 'assistant.global: false' "$feature_render"
grep -q 'replicas: 2' "$replica_render"
grep -q 'name: wait-for-postgres' "$default_render"
grep -q -- '--host=soha-postgres' "$default_render"
grep -q -- '--port=5432' "$default_render"
grep -q 'image: "ghcr.io/opensoha/soha:v0.1.7"' "$default_render"
grep -q '^  name: soha-data$' "$default_render"
grep -q 'helm.sh/resource-policy: keep' "$default_render"
grep -q 'mountPath: /app/data' "$default_render"
grep -q 'claimName: soha-data' "$default_render"
if grep -q 'mountPath: /app/data' "$persistence_disabled_render" || grep -q '^  name: soha-data$' "$persistence_disabled_render"; then
  echo "disabled application persistence still rendered a volume" >&2
  exit 1
fi
grep -q 'claimName: existing-soha-data' "$persistence_existing_render"
if grep -q '^  name: soha-data$' "$persistence_existing_render"; then
  echo "existing application claim still rendered a new PVC" >&2
  exit 1
fi
if grep -q 'name: wait-for-postgres' "$external_postgres_render"; then
  echo "external PostgreSQL mode rendered the bundled database wait container" >&2
  exit 1
fi
grep -q 'enabled: true' "$outpost_render"
grep -q 'protocol_version: "v1"' "$outpost_render"
grep -q 'path: /readyz' "$outpost_render"
grep -q 'kind: PodDisruptionBudget' "$outpost_render"
if grep -q 'kind: ClusterRole' "$outpost_render" || grep -q 'kind: PersistentVolumeClaim' "$outpost_render"; then
  echo "outpost mode rendered cluster RBAC or persistent state" >&2
  exit 1
fi
grep -q 'kind: ClusterRole' "$agent_render"
grep -q -- '- "platform.pods.exec"' "$agent_render"
grep -A2 'resources: \["pods/exec"\]' "$agent_render" | grep -q 'verbs: \["create"\]'
if grep -q 'pods/exec\|platform.pods.exec' "$agent_without_terminal_render"; then
  echo "agent terminal RBAC rendered without the platform.pods.exec action" >&2
  exit 1
fi
if grep -q 'pods/exec\|platform.pods.exec' "$outpost_render"; then
  echo "outpost mode rendered Pod terminal access" >&2
  exit 1
fi
for resource in serviceaccounts endpointslices storageclasses priorityclasses runtimeclasses mutatingwebhookconfigurations gatewayclasses; do
  grep -q "$resource" "$agent_render"
done
if grep -q 'SOHA_AGENT_CONTROL_PLANE_BEARER_TOKEN' "$standalone_agent_render"; then
  echo "standalone agent rendered an unused control-plane token reference" >&2
  exit 1
fi
grep -q 'kind: DaemonSet' "$observability_render"
grep -q 'kind: Deployment' "$observability_render"
grep -q 'type: Recreate' "$observability_render"
grep -q 'kind: PersistentVolumeClaim' "$observability_render"
grep -q 'helm.sh/resource-policy: keep' "$observability_render"
grep -q 'path: /var/log/pods' "$observability_render"
grep -q 'readOnly: true' "$observability_render"
grep -q 'runAsUser: 10001' "$observability_render"
grep -A1 'supplementalGroups:' "$observability_render" | grep -q -- '- 0'
grep -q 'type: RuntimeDefault' "$observability_render"
if grep -q 'bearertokenauth/ingest' "$observability_render" || grep -q 'name: otlp-grpc' "$observability_render"; then
  echo "default observability profile unexpectedly exposed OTLP ingestion" >&2
  exit 1
fi
grep -q 'endpoint: "https://loki.example.com/otlp"' "$observability_external_render"
helm template soha-observability "$root_dir/charts/soha-observability" \
  --set profile=production_external \
  --set-string collector.destination.endpoint=https://loki.example.com/otlp \
  --set-string collector.destination.existingSecret=loki-credentials \
  | grep -Fq 'Authorization: "Bearer ${env:LOKI_BEARER_TOKEN}"'
if grep -q 'kind: Deployment' "$observability_external_render" || grep -q 'kind: PersistentVolumeClaim' "$observability_external_render"; then
  echo "external observability profile rendered an in-cluster Loki backend" >&2
  exit 1
fi
grep -q '/var/log/pods/team-a_' "$observability_scoped_render"
grep -q '/var/log/pods/team-b_' "$observability_scoped_render"
grep -A1 'supplementalGroups:' "$observability_scoped_render" | grep -q -- '- 1234'
grep -q 'bearertokenauth/ingest:' "$observability_three_signal_render"
grep -q 'filename: /etc/otel-auth/bearer_token' "$observability_three_signal_render"
grep -q 'cert_file: /etc/otel-auth/tls.crt' "$observability_three_signal_render"
grep -q 'key_file: /etc/otel-auth/tls.key' "$observability_three_signal_render"
grep -q 'name: otlp-grpc' "$observability_three_signal_render"
grep -q 'name: otlp-http' "$observability_three_signal_render"
grep -q 'secretName: "otel-ingest"' "$observability_three_signal_render"
grep -q 'key: soha.workspace.id' "$observability_three_signal_render"
grep -q 'value: "workspace-a"' "$observability_three_signal_render"
grep -q 'key: deployment.environment.name' "$observability_three_signal_render"
grep -q 'filter/require_service:' "$observability_three_signal_render"
grep -q 'resource.attributes\["service.name"\] == nil' "$observability_three_signal_render"
grep -q 'prometheusremotewrite:' "$observability_three_signal_render"
grep -q 'endpoint: "https://prometheus.example.com/api/v1/write"' "$observability_three_signal_render"
grep -q 'otlp/traces:' "$observability_three_signal_render"
grep -q 'endpoint: "skywalking.example.com:11800"' "$observability_three_signal_render"
grep -A3 'otlp/traces:' "$observability_three_signal_render" | grep -q 'insecure: true'
grep -q 'name: METRICS_BEARER_TOKEN' "$observability_three_signal_render"
grep -q 'name: TRACES_BEARER_TOKEN' "$observability_three_signal_render"
grep -q 'key: "http.request.header.authorization"' "$observability_three_signal_render"
grep -A1 'key: "http.request.header.authorization"' "$observability_three_signal_render" | grep -q 'action: delete'
grep -q 'key: "enduser.id"' "$observability_three_signal_render"
grep -A1 'key: "enduser.id"' "$observability_three_signal_render" | grep -q 'action: hash'
if grep -q 'metrics-token-value\|traces-token-value\|otel-ingest-token-value' "$observability_three_signal_render"; then
  echo "observability render leaked credential plaintext" >&2
  exit 1
fi
if grep -q 'kind: ClusterRole' "$observability_render"; then
  echo "observability collector unexpectedly rendered cluster RBAC" >&2
  exit 1
fi
grep -q 'name: workloadcronjobs.workloads.soha.io' "$operator_render"
grep -q 'kind: ClusterRole' "$operator_render"
grep -q 'kind: Role' "$operator_render"
grep -q 'resources: \[leases\]' "$operator_render"
grep -q -- '--leader-elect=true' "$operator_render"
grep -q 'runAsNonRoot: true' "$operator_render"
grep -q 'runAsUser: 10001' "$operator_render"
grep -q 'readOnlyRootFilesystem: true' "$operator_render"
if ! grep -q '^                          annotations:$' "$operator_crd" ||
  ! grep -q '^                          labels:$' "$operator_crd"; then
  echo "operator CRD does not preserve WorkloadCronJob job template metadata" >&2
  exit 1
fi
if grep -q '^[[:space:]]*description:' "$operator_crd"; then
  echo "operator CRD was not generated with maxDescLen=0" >&2
  exit 1
fi
if grep -q 'kind: ClusterRole\|kind: Role\|kind: ClusterRoleBinding\|kind: RoleBinding' "$operator_external_rbac_render"; then
  echo "operator rendered RBAC while rbac.create=false" >&2
  exit 1
fi
grep -q 'serviceAccountName: existing-operator' "$operator_external_rbac_render"

if grep 'checksum/config:' "$default_render" | grep -q 'soha-123456'; then
  echo "config checksum annotation leaked credential plaintext" >&2
  exit 1
fi

if helm template soha "$root_dir/charts/soha" \
  --set-string config.modules.ai.features.globalAssistant=not-a-boolean \
  >"$tmp_dir/invalid-feature.yaml" 2>/dev/null; then
  echo "module feature schema accepted a non-boolean value" >&2
  exit 1
fi

if helm template soha "$root_dir/charts/soha" \
  --set postgres.port=15432 \
  >"$tmp_dir/invalid-bundled-postgres-port.yaml" 2>/dev/null; then
  echo "bundled PostgreSQL accepted a port other than 5432" >&2
  exit 1
fi

if helm template soha-outpost "$root_dir/charts/soha-agent" \
  --set mode=outpost \
  >"$tmp_dir/invalid-outpost.yaml" 2>/dev/null; then
  echo "outpost mode accepted missing trust key configuration" >&2
  exit 1
fi

if helm template soha-observability "$root_dir/charts/soha-observability" \
  --set profile=collector_only \
  >"$tmp_dir/invalid-observability.yaml" 2>/dev/null; then
  echo "external observability profile accepted an empty destination endpoint" >&2
  exit 1
fi

if helm template soha-observability "$root_dir/charts/soha-observability" \
  --set collector.otlp.enabled=true \
  >"$tmp_dir/invalid-observability-otlp-secret.yaml" 2>/dev/null; then
  echo "OTLP ingestion accepted a missing TLS and bearer Secret" >&2
  exit 1
fi

if helm template soha-observability "$root_dir/charts/soha-observability" \
  --set 'collector.signalAllowlist={logs,metrics}' \
  --set collector.otlp.enabled=true \
  --set-string collector.otlp.existingSecret=otel-ingest \
  >"$tmp_dir/invalid-observability-metrics-endpoint.yaml" 2>/dev/null; then
  echo "metrics pipeline accepted a missing remote write endpoint" >&2
  exit 1
fi

if helm template soha-observability "$root_dir/charts/soha-observability" \
  --set 'collector.signalAllowlist={logs,traces}' \
  --set collector.otlp.enabled=true \
  --set-string collector.otlp.existingSecret=otel-ingest \
  >"$tmp_dir/invalid-observability-traces-endpoint.yaml" 2>/dev/null; then
  echo "traces pipeline accepted a missing OTLP endpoint" >&2
  exit 1
fi

if helm template soha-observability "$root_dir/charts/soha-observability" \
  --set 'collector.signalAllowlist={logs,metrics}' \
  --set-string collector.metrics.endpoint=https://prometheus.example.com/api/v1/write \
  >"$tmp_dir/invalid-observability-metrics-receiver.yaml" 2>/dev/null; then
  echo "metrics pipeline accepted disabled OTLP ingestion" >&2
  exit 1
fi

for removed_key in \
  prometheusUrl \
  prometheusBearerToken \
  prometheusDefaultRangeMinutes \
  prometheusStepSeconds \
  prometheusClusterLabel \
  grafanaBaseUrl
do
  if helm template soha "$root_dir/charts/soha" \
    --set-string "config.monitoring.$removed_key=legacy" \
    >"$tmp_dir/removed-$removed_key.yaml" 2>/dev/null; then
    echo "schema accepted removed config.monitoring.$removed_key" >&2
    exit 1
  fi
done

echo "render tests passed"
