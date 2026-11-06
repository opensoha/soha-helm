#!/bin/sh
set -eu

if [ "${GITHUB_ACTIONS:-}" != true ] && [ -z "${OPENSOHA_VERIFY_ACTIVE:-}" ] &&
  { command -v opensoha-verify >/dev/null 2>&1 || [ -n "${OPENSOHA_LOCAL_VERIFY_REQUIRED:-}" ]; }; then
  exec opensoha-verify run -- sh "$0" "$@"
fi

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

default_render="$tmp_dir/default.yaml"
feature_render="$tmp_dir/feature.yaml"
restart_render="$tmp_dir/restart.yaml"
replica_render="$tmp_dir/replica.yaml"
logger_render="$tmp_dir/logger.yaml"
network_ingest_query_render="$tmp_dir/network-ingest-query.yaml"
network_runtime_render="$tmp_dir/network-runtime.yaml"
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
cli_render="$tmp_dir/cli.yaml"
helm template soha "$root_dir/charts/soha" \
  --set replicaCount=2 \
  --set config.auth.cli.enabled=true \
  --set config.auth.cli.allowPassword=false \
  --set-string config.auth.cli.publicURL=https://soha.example.com/team \
  >"$cli_render"
grep -q 'public_url: "https://soha.example.com/team"' "$cli_render"
grep -q 'allow_password: false' "$cli_render"
grep -q 'absolute_ttl: "720h"' "$cli_render"
if helm template soha "$root_dir/charts/soha" --set config.auth.cli.enabled=true \
  >"$tmp_dir/invalid-cli.yaml" 2>/dev/null; then
  echo "CLI authentication accepted an empty public URL" >&2; exit 1
fi
if helm template soha "$root_dir/charts/soha" --set config.auth.cli.activeGrantLimit=0 \
  >"$tmp_dir/invalid-cli-budget.yaml" 2>/dev/null; then
  echo "CLI authentication accepted an unbounded grant budget" >&2; exit 1
fi
assert_invalid_cli() {
  if helm template soha "$root_dir/charts/soha" --set-string "config.auth.cli.$1=$2" \
    >"$tmp_dir/invalid-cli-case.yaml" 2>/dev/null; then
    echo "CLI authentication accepted invalid $1" >&2; exit 1
  fi
}
assert_invalid_cli publicURL http://soha.example.com/team
assert_invalid_cli publicURL http://127.0.0.1.example.com/team
assert_invalid_cli publicURL http://127.0.0.256/team
assert_invalid_cli publicURL https://soha.example.com:abc/team
assert_invalid_cli publicURL https://soha.example.com/team?handle=private
assert_invalid_cli deviceTTL 29s
assert_invalid_cli deviceTTL 10m1ms
assert_invalid_cli pollInterval 999ms
assert_invalid_cli pollInterval 30s1ms
assert_invalid_cli accessTTL 999ms
assert_invalid_cli idleTTL 1m
assert_invalid_cli absoluteTTL 1h
assert_invalid_cli absoluteTTL 8760h1ms
for public_url in http://localhost:18080/team http://127.12.34.56:18080/team 'http://[::1]:18080/team' 'https://[2001:db8::1]:8443/team'; do
  helm template soha "$root_dir/charts/soha" --set config.auth.cli.enabled=true \
    --set-string "config.auth.cli.publicURL=$public_url" \
    >"$tmp_dir/cli-loopback.yaml"
done
helm template soha "$root_dir/charts/soha" \
  --set-string config.auth.cli.deviceTTL=30000ms \
  --set-string config.auth.cli.pollInterval=1s \
  --set-string config.auth.cli.accessTTL=1m30s \
  --set-string config.auth.cli.idleTTL=2m \
  --set-string config.auth.cli.absoluteTTL=8760h >"$tmp_dir/cli-duration-boundaries.yaml"
helm template soha "$root_dir/charts/soha" \
  --set-string config.auth.cli.deviceTTL=0s \
  --set-string config.auth.cli.pollInterval=0ms \
  --set-string config.auth.cli.accessTTL=0h \
  --set-string config.auth.cli.idleTTL=0m \
  --set-string config.auth.cli.absoluteTTL=0s >"$tmp_dir/cli-duration-defaults.yaml"

# Simulate the data returned by lookup without contacting any cluster. This proves
# template precedence only; the release acceptance still requires a live upgrade.
cp -R "$root_dir/charts/soha" "$tmp_dir/persisted-identity"
cat >"$tmp_dir/persisted-identity/templates/000-test-existing-config.tpl" <<'EOF'
{{- define "soha.existingConfig" -}}
database:
  password: task115-existing-db
auth:
  jwt:
    secret: task115-existing-jwt-12345678901234567890
security:
  credential_encryption_key: task115-existing-encryption-123456789012345
{{- end -}}
EOF
helm template soha "$tmp_dir/persisted-identity" \
  --set-string config.auth.jwtSecret=task115-other-jwt-12345678901234567890 \
  --set-string config.security.credentialEncryptionKey=task115-other-encryption-123456789012345 \
  >"$tmp_dir/persisted-identity.yaml"
grep -q 'secret: "task115-existing-jwt-12345678901234567890"' "$tmp_dir/persisted-identity.yaml"
grep -q 'credential_encryption_key: "task115-existing-encryption-123456789012345"' "$tmp_dir/persisted-identity.yaml"
if grep -q 'task115-other-' "$tmp_dir/persisted-identity.yaml"; then
  echo "Helm upgrade replaced persistent signing or encryption identity" >&2; exit 1
fi
helm template soha "$root_dir/charts/soha" \
  --set-string config.loggerLevel=debug >"$logger_render"
helm template soha "$root_dir/charts/soha" \
  --set config.networkIngestQuery.enabled=true \
  --set-string config.networkIngestQuery.url=https://soha-ingest.soha.svc:8083 \
  --set-string config.networkIngestQuery.serverName=soha-ingest.soha.svc \
  --set-string config.networkIngestQuery.existingSecret=soha-core-ingest-query-tls \
  >"$network_ingest_query_render"
helm template soha "$root_dir/charts/soha" \
  --set networkRuntime.enabled=true \
  --set-string image.tag=local \
  --set-string networkRuntime.existingTLSSecret=soha-network-runtime-tls \
  >"$network_runtime_render"
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
network_ingest_query_checksum=$(checksum "$network_ingest_query_render")

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
[ "$default_checksum" != "$network_ingest_query_checksum" ] || {
  echo "network ingest query change did not update config checksum" >&2
  exit 1
}

grep -q 'assistant.global: false' "$feature_render"
grep -q 'replicas: 2' "$replica_render"
grep -q 'name: wait-for-postgres' "$default_render"
grep -q -- '--host=soha-postgres' "$default_render"
grep -q -- '--port=5432' "$default_render"
grep -q 'image: "ghcr.io/opensoha/soha:v0.1.12"' "$default_render"
grep -q '^  name: soha-data$' "$default_render"
grep -q 'helm.sh/resource-policy: keep' "$default_render"
grep -q 'mountPath: /app/data' "$default_render"
grep -q 'claimName: soha-data' "$default_render"
if grep -q 'mountPath: /app/data' "$persistence_disabled_render" || grep -q '^  name: soha-data$' "$persistence_disabled_render"; then
  echo "disabled application persistence still rendered a volume" >&2
  exit 1
fi
grep -q 'claimName: existing-soha-data' "$persistence_existing_render"
if grep -q 'network_ingest_query:\|network-ingest-query-tls' "$default_render"; then
  echo "disabled network ingest query still rendered configuration or TLS volume" >&2
  exit 1
fi
if grep -q 'name: soha-network-control\|name: soha-ingest-postgres' "$default_render"; then
  echo "disabled network runtime still rendered workloads" >&2
  exit 1
fi
grep -q '^    network_ingest_query:$' "$network_ingest_query_render"
grep -q 'url: "https://soha-ingest.soha.svc:8083"' "$network_ingest_query_render"
grep -q 'server_name: "soha-ingest.soha.svc"' "$network_ingest_query_render"
grep -q 'mountPath: /run/soha-network-ingest-query' "$network_ingest_query_render"
grep -q 'secretName: "soha-core-ingest-query-tls"' "$network_ingest_query_render"
grep -A18 'name: network-ingest-query-tls' "$network_ingest_query_render" | grep -q 'key: tls.key'
grep -q '^  name: soha-network-control$' "$network_runtime_render"
grep -q '^  name: soha-ingest$' "$network_runtime_render"
grep -q '^  name: soha-ingest-postgres$' "$network_runtime_render"
grep -q -- '- /app/network-control' "$network_runtime_render"
grep -q -- '- /app/ingest' "$network_runtime_render"
grep -A3 'name: SOHA_NETWORK_CONTROL_DATABASE_HOST' "$network_runtime_render" | grep -q 'value: "soha-postgres"'
grep -A3 'name: SOHA_INGEST_DATABASE_HOST' "$network_runtime_render" | grep -q 'value: "soha-ingest-postgres"'
grep -q 'key: ingest-postgres-password' "$network_runtime_render"
grep -q 'secretName: "soha-network-runtime-tls"' "$network_runtime_render"
grep -q 'key: network-control.crt' "$network_runtime_render"
grep -q 'key: ingest.crt' "$network_runtime_render"
grep -q 'automountServiceAccountToken: false' "$network_runtime_render"
grep -q 'helm.sh/resource-policy: keep' "$network_runtime_render"
grep -q 'type: Recreate' "$network_runtime_render"
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
grep -q '"replicationcontrollers"' "$agent_render"
grep -A1 'resources: \["subjectaccessreviews", "selfsubjectaccessreviews"\]' "$agent_render" | grep -q 'verbs: \["create"\]'
grep -A1 'resources: \["pods/eviction"\]' "$agent_render" | grep -q 'verbs: \["create"\]'
grep -B1 'resources: \["pods/eviction"\]' "$agent_render" | grep -q 'apiGroups: \[""\]'
grep -q 'verbs: \["create","update","patch","delete"\]' "$agent_render"
if grep -q 'pods/eviction\|pods/portforward\|verbs: \["create","update","patch","delete"\]' "$agent_without_terminal_render"; then
  echo "agent mutation RBAC rendered without its action allowlist" >&2
  exit 1
fi

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
if grep -q '^[[:space:]]*workloadRef:' "$operator_crd" ||
  ! grep -q '^[[:space:]]*schedulingGroup:' "$operator_crd" ||
  ! grep -q '^[[:space:]]*sourceRef:' "$operator_crd"; then
  echo "operator CRD must use native schedulingGroup and retain Soha sourceRef" >&2
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

if helm template soha "$root_dir/charts/soha" \
  --set config.networkIngestQuery.enabled=true \
  >"$tmp_dir/invalid-network-ingest-query.yaml" 2>/dev/null; then
  echo "network ingest query accepted missing endpoint, server name, or TLS Secret" >&2
  exit 1
fi

if helm template soha "$root_dir/charts/soha" \
  --set networkRuntime.enabled=true \
  --set-string image.tag=local \
  >"$tmp_dir/invalid-network-runtime.yaml" 2>/dev/null; then
  echo "network runtime accepted a missing mTLS Secret" >&2
  exit 1
fi

for old_runtime_tag in v0.1.7 v0.1.8; do
  if helm template soha "$root_dir/charts/soha" \
    --set networkRuntime.enabled=true \
    --set-string image.tag="$old_runtime_tag" \
    --set-string networkRuntime.existingTLSSecret=soha-network-runtime-tls \
    >"$tmp_dir/invalid-network-image.yaml" 2>"$tmp_dir/invalid-network-image.err"; then
    echo "network runtime accepted an image without runtime binaries" >&2
    exit 1
  fi
  grep -q 'networkRuntime requires an image' "$tmp_dir/invalid-network-image.err"
done

if helm template soha "$root_dir/charts/soha" \
  --set config.networkIngestQuery.enabled=true \
  --set-string config.networkIngestQuery.url=http://soha-ingest:8083 \
  --set-string config.networkIngestQuery.serverName=soha-ingest \
  --set-string config.networkIngestQuery.existingSecret=soha-core-ingest-query-tls \
  >"$tmp_dir/invalid-network-ingest-query-url.yaml" 2>/dev/null; then
  echo "network ingest query accepted a non-HTTPS endpoint" >&2
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

# Named custom resource grants and credential changes must affect the rendered workload.
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set-string 'rbac.customResourceRules[0].apiGroup=apps--demo.example.io' \
  --set 'rbac.customResourceRules[0].resources={widget-sets}' \
  --set 'rbac.customResourceRules[0].verbs={get,list}' \
  --set 'rbac.customResourceRules[0].namespaces={team-a}' \
  --set-string config.prometheus.baseUrl=http://prometheus.monitoring.svc:9090 \
  --set-string secrets.prometheusBearerToken=test-prom-token >"$tmp_dir/custom-agent.yaml"
grep -q 'kind: Role$' "$tmp_dir/custom-agent.yaml"
grep -q 'kind: RoleBinding$' "$tmp_dir/custom-agent.yaml"
grep -q 'namespace: "team-a"' "$tmp_dir/custom-agent.yaml"
grep -q '"widget-sets"' "$tmp_dir/custom-agent.yaml"
grep -q 'base_url: "http://prometheus.monitoring.svc:9090"' "$tmp_dir/custom-agent.yaml"
grep -q 'SOHA_AGENT_PROMETHEUS_BEARER_TOKEN' "$tmp_dir/custom-agent.yaml"
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set-string secrets.prometheusBearerToken=test-prom-token >"$tmp_dir/secret-agent.yaml"
if [ "$(sed -n 's/.*checksum\/secret: //p' "$agent_render")" = "$(sed -n 's/.*checksum\/secret: //p' "$tmp_dir/secret-agent.yaml")" ]; then
  echo "Agent credential change did not roll the workload" >&2
  exit 1
fi
if helm template soha-agent "$root_dir/charts/soha-agent" \
  --set-string 'rbac.customResourceRules[0].apiGroup=*' \
  --set 'rbac.customResourceRules[0].resources={widgets}' \
  --set 'rbac.customResourceRules[0].verbs={get}' >"$tmp_dir/invalid.yaml" 2>"$tmp_dir/invalid.err"; then
  echo "wildcard custom resource grant was accepted" >&2
  exit 1
fi

# New installs use workbench; explicit legacy lists and profiles keep their boundaries.
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set config.security.profile=workbench \
  --set 'config.security.allowedActions={platform.deployments.restart}' >"$tmp_dir/agent-workbench.yaml"
for action in platform.nodes.drain platform.resources.create platform.resources.apply platform.resources.delete platform.port_forwards.tunnel; do
  grep -q -- "- \"$action\"" "$tmp_dir/agent-workbench.yaml"
  grep -q -- "- \"$action\"" "$agent_render"
done
helm template soha-agent "$root_dir/charts/soha-agent" --is-upgrade \
  --set 'config.security.allowedActions={platform.deployments.restart}' >"$tmp_dir/agent-legacy-upgrade.yaml"
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set config.security.profile=custom \
  --set 'config.security.allowedActions={platform.deployments.restart}' >"$tmp_dir/agent-custom.yaml"
for render in "$tmp_dir/agent-legacy-upgrade.yaml" "$tmp_dir/agent-custom.yaml"; do
  grep -q -- '- "platform.deployments.restart"' "$render"
  if grep -q 'platform.resources.create\|platform.helm_releases.install\|pods/exec\|pods/portforward\|pods/eviction' "$render"; then
    echo "legacy/custom Agent actions were expanded to workbench" >&2
    exit 1
  fi
done
for profile in auto custom; do
  helm template soha-agent "$root_dir/charts/soha-agent" --is-upgrade \
    --set config.security.profile="$profile" \
    --set-json 'config.security.allowedActions=[]' >"$tmp_dir/agent-empty-$profile.yaml"
  if grep -q -- '- "platform\.\|- "runtime\.\|pods/exec\|pods/portforward\|pods/eviction\|verbs: \["update", "patch"\]' "$tmp_dir/agent-empty-$profile.yaml"; then
    echo "empty explicit Agent allowlist gained actions or write rules" >&2
    exit 1
  fi
done
agent_action_lines() {
  grep -E -- '- "(platform|runtime)\.' "$1"
}
for profile in auto custom; do
  helm template soha-agent "$root_dir/charts/soha-agent" --is-upgrade \
    --set config.security.profile="$profile" >"$tmp_dir/agent-omitted-$profile.yaml"
  if [ "$(agent_action_lines "$agent_render")" != "$(agent_action_lines "$tmp_dir/agent-omitted-$profile.yaml")" ]; then
    echo "omitted $profile Agent action list changed on upgrade" >&2
    exit 1
  fi
done
if grep -q 'platform.helm_releases' "$agent_render" "$tmp_dir/agent-workbench.yaml"; then
  echo "default Agent profiles enabled Helm mutations" >&2
  exit 1
fi
# Helm-only custom actions receive the supported object verbs needed by the SDK.
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set config.security.profile=custom \
  --set 'config.security.allowedActions={platform.helm_releases.values_update}' >"$tmp_dir/agent-helm-only.yaml"
grep -q 'verbs: \["create","update","patch","delete"\]' "$tmp_dir/agent-helm-only.yaml"
if grep -q 'pods/exec\|pods/portforward\|pods/eviction\|platform.resources.create' "$tmp_dir/agent-helm-only.yaml"; then
  echo "Helm-only custom actions enabled unrelated execution actions" >&2
  exit 1
fi
for action in install delete; do
  helm template soha-agent "$root_dir/charts/soha-agent" \
    --set config.security.profile=custom \
    --set "config.security.allowedActions={platform.helm_releases.$action}" >"$tmp_dir/agent-helm-$action.yaml"
  awk '/resources: \["secrets"\]/{getline; if ($0 ~ /"create"/ && $0 ~ /"update"/ && $0 ~ /"delete"/) allowed=1} END {if (!allowed) exit 1}' "$tmp_dir/agent-helm-$action.yaml"
done
if ! awk '/resources: \["customresourcedefinitions"\]/{getline; if ($0 ~ /create|update|patch|delete/) exit 1}' "$tmp_dir/agent-workbench.yaml"; then
  echo "workbench implicitly grants CRD definition mutations" >&2
  exit 1
fi
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set 'config.security.allowedActions={platform.crds.delete}' >"$tmp_dir/agent-crd-delete.yaml"
awk '/resources: \["customresourcedefinitions"\]/{getline; if ($0 ~ /create|update|patch/) exit 1; if ($0 ~ /"delete"/) allowed=1} END {if (!allowed) exit 1}' "$tmp_dir/agent-crd-delete.yaml"
helm template soha-agent "$root_dir/charts/soha-agent" \
  --set config.security.profile=read-only >"$tmp_dir/agent-read-only.yaml"
if grep -q 'platform.nodes.drain\|platform.resources.apply\|platform.helm_releases.install\|pods/exec\|pods/eviction\|pods/portforward\|verbs: \["create","update","patch","delete"\]\|verbs: \["update", "patch"\]' "$tmp_dir/agent-read-only.yaml"; then
  echo "read-only Agent profile rendered mutation permissions" >&2
  exit 1
fi
if helm template soha-agent "$root_dir/charts/soha-agent" \
  --set config.security.profile=read-only \
  --set-string 'rbac.customResourceRules[0].apiGroup=example.io' \
  --set-string 'rbac.customResourceRules[0].resources[0]=widgets' \
  --set-string 'rbac.customResourceRules[0].verbs[0]=create' >"$tmp_dir/read-only-invalid.yaml" 2>"$tmp_dir/read-only-invalid.err"; then
  echo "read-only Agent profile accepted custom mutations" >&2
  exit 1
fi
grep -q 'read-only Agent profile cannot grant custom resource mutations' "$tmp_dir/read-only-invalid.err"

# EndpointSlice YAML and Helm use the same action-derived workbench write rules.
for render in "$agent_render" "$tmp_dir/agent-workbench.yaml" "$tmp_dir/agent-helm-only.yaml"; do
  awk '/apiGroups: \["discovery.k8s.io"\]/{getline; if ($0 ~ /"endpointslices"/) {getline; if ($0 ~ /"create"/ && $0 ~ /"update"/ && $0 ~ /"patch"/ && $0 ~ /"delete"/) allowed=1}} END {if (!allowed) exit 1}' "$render"
done
for render in "$tmp_dir/agent-empty-auto.yaml" "$tmp_dir/agent-empty-custom.yaml" "$tmp_dir/agent-custom.yaml" "$tmp_dir/agent-read-only.yaml"; do
  awk '/apiGroups: \["discovery.k8s.io"\]/{getline; if ($0 ~ /"endpointslices"/) {getline; if ($0 ~ /"create"|"update"|"patch"|"delete"/) denied=1}} END {if (denied) exit 1}' "$render"
done

for render in "$agent_render" "$tmp_dir/agent-workbench.yaml" "$tmp_dir/agent-read-only.yaml" "$tmp_dir/agent-custom.yaml" "$tmp_dir/agent-helm-only.yaml"; do
  awk '/resources: .*"controllerrevisions"/{getline; if ($0 ~ /"get"/ && $0 ~ /"list"/ && $0 ~ /"watch"/) allowed=1} END {if (!allowed) exit 1}' "$render"
  if grep -Eq '"(impersonate|bind|escalate)"|cluster-admin|apiGroups:.*"\*"|resources:.*"\*"|verbs:.*"\*"' "$render"; then
    echo "Agent preset rendered unrestricted or escalation permissions" >&2
    exit 1
  fi
done
if grep -q 'controllerrevisions\|platform.helm_releases\|platform.resources.' "$outpost_render"; then
  echo "Outpost inherited workbench permissions" >&2
  exit 1
fi
