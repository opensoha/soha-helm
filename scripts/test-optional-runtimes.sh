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
 --set-string image.tag=v0.1.12-test-runtime-compatible \
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
for runtime in dsh hindsight; do
 case "$runtime" in
  dsh) disable_other=hindsight ;;
  hindsight) disable_other=dshRuntime ;;
 esac
 if render_enabled --set "$disable_other.enabled=false" --set-string image.tag=v0.1.12 > "$tmp/incompatible" 2>&1; then
  echo "$runtime accepted the incompatible Core image" >&2; exit 1
 fi
 grep -q 'require a compatible Core image' "$tmp/incompatible"
done
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

dsh_template=templates/dsh-runtime.yaml
render_enabled --show-only "$dsh_template" > "$tmp/dsh-managed"
grep -q 'helm.sh/resource-policy: keep' "$tmp/dsh-managed"
grep -q 'claimName: "soha-dsh"' "$tmp/dsh-managed"
render_enabled --is-upgrade --set dshRuntime.enabled=false > "$tmp/disabled"
if grep -q 'name: soha-dsh$' "$tmp/disabled"; then exit 1; fi
render_enabled --is-upgrade --show-only "$dsh_template" > "$tmp/reenabled"
cmp "$tmp/dsh-managed" "$tmp/reenabled"

render_enabled --show-only "$dsh_template" --set-string dshRuntime.existingClaim=retained-journal \
 --set 'imagePullSecrets[0].name=registry-login' \
 --set-string dshRuntime.pluginAssets.configMap=plugin-assets-v1 \
 --set-string dshRuntime.pluginAssets.credentialSecret=mcp-credentials-v1 \
 --set-json 'dshRuntime.pluginAssets.skillFiles={"observability/SKILL.md":"obs-skill","observability/ref/query.txt":"obs-query"}' \
 > "$tmp/dsh-existing"
grep -q 'claimName: "retained-journal"' "$tmp/dsh-existing"
grep -q 'name: registry-login' "$tmp/dsh-existing"
grep -q 'name: SOHA_DSH_PLUGIN_ASSETS_FILE, value: /run/dsh-registry/registry.json' "$tmp/dsh-existing"
grep -q 'mountPath: "/run/dsh-skills/observability/ref/query.txt"' "$tmp/dsh-existing"
grep -q 'subPath: "skills/observability/ref/query.txt"' "$tmp/dsh-existing"
grep -q 'key: "obs-query", path: "skills/observability/ref/query.txt"' "$tmp/dsh-existing"
grep -q 'name: "plugin-assets-v1"' "$tmp/dsh-existing"
grep -q 'secretName: "mcp-credentials-v1"' "$tmp/dsh-existing"
grep -q 'name: mcp-credentials, mountPath: /run/dsh-credentials, readOnly: true' "$tmp/dsh-existing"
grep -q 'install -m 0400' "$tmp/dsh-existing"
if grep -q 'kind: PersistentVolumeClaim\|hostPath:' "$tmp/dsh-existing"; then exit 1; fi
if grep -q 'SOHA_DSH_PLUGIN_ASSETS_FILE\|name: mcp-credentials' "$tmp/dsh-managed"; then exit 1; fi

# Simulate a Kubernetes Secret projection and an init retry without exposing credentials.
mkdir -p "$tmp/credential-source/..generation" "$tmp/credentials"
printf 'synthetic\n' > "$tmp/credential-source/..generation/test-token"
ln -s ..generation "$tmp/credential-source/..data"
ln -s ..data/test-token "$tmp/credential-source/test-token"
sed -n '/for file in \/run\/dsh-credential-source\//,/done/p' "$tmp/dsh-existing" \
 | sed "s|/run/dsh-credential-source|$tmp/credential-source|g; s|/run/dsh-credentials|$tmp/credentials|g" \
 > "$tmp/stage-credentials"
sh -e "$tmp/stage-credentials"
sh -e "$tmp/stage-credentials"
cmp "$tmp/credential-source/test-token" "$tmp/credentials/test-token"
test ! -L "$tmp/credentials/test-token"
test -n "$(find "$tmp/credentials" -type f -name test-token -perm 0400)"

render_enabled --show-only templates/app-deployment.yaml \
 --set-string dshRuntime.pluginAssets.configMap=plugin-assets-v1 \
 --set-string dshRuntime.pluginAssets.credentialSecret=mcp-credentials-v1 > "$tmp/core"
if grep -q 'plugin-assets-v1\|mcp-credentials-v1\|SOHA_DSH_PLUGIN_ASSETS_FILE' "$tmp/core"; then exit 1; fi
if render_enabled --set-string dshRuntime.pluginAssets.credentialSecret=mcp-credentials-v1 \
 > "$tmp/missing-registry" 2>&1; then exit 1; fi
grep -q 'configMap' "$tmp/missing-registry"
if render_enabled --set-string dshRuntime.pluginAssets.configMap=plugin-assets-v1 \
 --set-json 'dshRuntime.pluginAssets.skillFiles={"../SKILL.md":"escape"}' > "$tmp/unsafe-path" 2>&1; then exit 1; fi
grep -Fq '../SKILL.md' "$tmp/unsafe-path"
if render_enabled --set-string dshRuntime.pluginAssets.configMap=plugin-assets-v1 \
 --set-string dshRuntime.pluginAssets.credentialSecret=dsh > "$tmp/shared-secret" 2>&1; then exit 1; fi
grep -q 'must be separate from the dsh service-token Secret' "$tmp/shared-secret"
printf '%s\n' 'optional runtimes render checks passed'
