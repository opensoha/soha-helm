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
agent_render="$tmp_dir/agent.yaml"
outpost_render="$tmp_dir/outpost.yaml"

helm template soha "$root_dir/charts/soha" >"$default_render"
helm template soha "$root_dir/charts/soha" \
  --set config.modules.ai.features.globalAssistant=false >"$feature_render"
helm template soha "$root_dir/charts/soha" \
  --set-string config.idleTimeout=180s >"$restart_render"
helm template soha "$root_dir/charts/soha" \
  --set replicaCount=2 >"$replica_render"
helm template soha "$root_dir/charts/soha" \
  --set-string config.loggerLevel=debug >"$logger_render"
helm template soha-agent "$root_dir/charts/soha-agent" >"$agent_render"
helm template soha-outpost "$root_dir/charts/soha-agent" \
  --set mode=outpost \
  --set replicaCount=2 \
  --set-string config.controlPlane.outpost.trustKeyId=test-key \
  --set-string config.controlPlane.outpost.trustPublicKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
  --set-string secrets.controlPlaneBearerToken=12345678901234567890123456789012 \
  --set-string secrets.agentBearerToken=abcdefghijklmnopqrstuvwxyz123456 >"$outpost_render"

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
grep -q 'enabled: true' "$outpost_render"
grep -q 'protocol_version: "v1"' "$outpost_render"
grep -q 'path: /readyz' "$outpost_render"
grep -q 'kind: PodDisruptionBudget' "$outpost_render"
if grep -q 'kind: ClusterRole' "$outpost_render" || grep -q 'kind: PersistentVolumeClaim' "$outpost_render"; then
  echo "outpost mode rendered cluster RBAC or persistent state" >&2
  exit 1
fi
grep -q 'kind: ClusterRole' "$agent_render"

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

if helm template soha-outpost "$root_dir/charts/soha-agent" \
  --set mode=outpost \
  >"$tmp_dir/invalid-outpost.yaml" 2>/dev/null; then
  echo "outpost mode accepted missing trust key configuration" >&2
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
