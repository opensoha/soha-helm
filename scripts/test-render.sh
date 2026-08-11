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
agent_render="$tmp_dir/agent.yaml"
standalone_agent_render="$tmp_dir/standalone-agent.yaml"
outpost_render="$tmp_dir/outpost.yaml"
observability_render="$tmp_dir/observability.yaml"
observability_external_render="$tmp_dir/observability-external.yaml"
observability_scoped_render="$tmp_dir/observability-scoped.yaml"

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
helm template soha-agent "$root_dir/charts/soha-agent" >"$agent_render"
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
if grep -q 'kind: ClusterRole' "$observability_render"; then
  echo "observability collector unexpectedly rendered cluster RBAC" >&2
  exit 1
fi

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
