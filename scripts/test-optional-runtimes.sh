#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
helm template optional "$root/charts/soha" > "$tmp/default"
if grep -q 'component: dsh-runtime\|component: hindsight\|SOHA_DSH_RUNTIME_ENABLED\|SOHA_HINDSIGHT_ENABLED' "$tmp/default"; then exit 1; fi
grep -q 'protected_durable_storage: false' "$tmp/default"
if helm template optional "$root/charts/soha" --set dshRuntime.enabled=true > "$tmp/rejected" 2>&1; then exit 1; fi
if helm template optional "$root/charts/soha" --set hindsight.enabled=true > "$tmp/rejected" 2>&1; then exit 1; fi
render_enabled() {
helm template optional "$root/charts/soha" \
 --set dshRuntime.enabled=true --set-string dshRuntime.image=example.invalid/dsh:test \
 --set dshRuntime.existingSecret=dsh \
 --set dshRuntime.allowInsecureHTTP=true \
 --set config.security.protectedDurableStorage=true \
 --set hindsight.enabled=true --set hindsight.existingSecret=hindsight \
 --set hindsight.deploymentConfigMap=deploy \
 --set-string hindsight.gatewayURL=https://gateway.invalid/v1 \
 --set-string hindsight.embeddingGatewayURL=https://gateway.invalid/llm/qwen/v1 \
 --set hindsight.llmModel=extract --set hindsight.embeddingModel=embed \
 --set hindsight.embeddingDimensions=32 --set hindsight.instanceNamespace=test-installation "$@"
}
render_enabled > "$tmp/enabled"
grep -q 'protected_durable_storage: true' "$tmp/enabled"
if render_enabled --set config.security.protectedDurableStorage=false > "$tmp/unprotected" 2>&1; then exit 1; fi
grep -q 'requires config.security.protectedDurableStorage=true' "$tmp/unprotected"
helm template optional "$root/charts/soha" --set config.security.protectedDurableStorage=true > "$tmp/protected-only"
grep -q 'protected_durable_storage: true' "$tmp/protected-only"
if grep -q 'SOHA_DSH_RUNTIME_ENABLED' "$tmp/protected-only"; then exit 1; fi
for expected in 'component: dsh-runtime' 'component: hindsight' 'readOnlyRootFilesystem: true' 'automountServiceAccountToken: false' 'SOHA_DSH_SERVICE_TOKEN_FILE' 'SOHA_HINDSIGHT_TOKEN_FILE' 'kind: PersistentVolumeClaim' 'type: Recreate' '8889' 'SOHA_DSH_MODEL_AUTH_MODE' 'value: core' 'soha-workbench' '/api/v1/copilot/dsh/model/v1' '/api/v1/copilot/dsh/tools' 'SOHA_DSH_RUNTIME_ENABLED' 'SOHA_DSH_RUNTIME_SERVICE_TOKEN_FILE' 'SOHA_HINDSIGHT_ENABLED' 'SOHA_HINDSIGHT_INSTANCE_NAMESPACE' 'items:.*key: service-token'; do
 grep -q "$expected" "$tmp/enabled"
done
grep -q 'name: SOHA_HINDSIGHT_EMBEDDING_GATEWAY_URL, value: "https://gateway.invalid/llm/qwen/v1"' "$tmp/enabled"
if grep -q 'hostPath:\|docker.sock\|SOHA_DSH_GATEWAY_PAT_FILE\|SOHA_DSH_TOOL_CATALOG_FILE' "$tmp/enabled"; then exit 1; fi
if helm template optional "$root/charts/soha" \
 --set dshRuntime.enabled=true --set-string dshRuntime.image=example.invalid/dsh:test \
 --set dshRuntime.existingSecret=dsh > "$tmp/insecure" 2>&1; then exit 1; fi
grep -q 'explicit allowInsecureHTTP=true' "$tmp/insecure"
long_name=abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk
render_enabled --set-string fullnameOverride="$long_name" > "$tmp/long"
dsh_name="$(printf '%s' "$long_name" | cut -c1-59)-dsh"
hindsight_name="$(printf '%s' "$long_name" | cut -c1-53)-hindsight"
grep -q "name: $dsh_name" "$tmp/long"
grep -q "name: $hindsight_name" "$tmp/long"
grep -q "http://$dsh_name:8097" "$tmp/long"
grep -q "http://$hindsight_name:8889" "$tmp/long"
grep -q 'name: api-secrets' "$tmp/enabled"
grep -q 'name: gateway-secret' "$tmp/enabled"
printf '%s\n' 'optional runtimes render checks passed'
