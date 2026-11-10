# Optional dsh and Hindsight (B3 startup wiring)

`dshRuntime.enabled` and `hindsight.enabled` default to false. Apply Core migration
0143 before enabling either backend, and apply all Core migrations through 0145 before Hindsight cutover. New production Chat/Heya always requires dsh;
disabled or unavailable means explicit unavailable, never Native fallback. Drain
Native work with the prior runtime before upgrading; the candidate cannot resume
the removed loop. B4 maintenance tooling is implemented; business-data migration
has not been performed.

Enabling a chart block creates its optional service and sets the matching Core
startup-only environment entries. Core mounts only the matching `service-token`
key from existing Secrets. It receives neither Hindsight DB credentials nor its
Gateway PAT. Runtime failures remain bootstrap/end-to-end acceptance concerns.

For dsh, provide a validated image built with Agent `deploy/Dockerfile.dsh-runtime`,
an existing Secret with `service-token` (32+ characters, shared with Core).
Core freezes the service-authenticated `Start.tools` catalog per run and binds its
opaque revision. Production core mode needs no startup catalog file or ConfigMap. Production Node defaults to `SOHA_DSH_MODEL_AUTH_MODE=core`, requires no
PAT and uses only virtual model `soha-workbench`; Core selects the actual route.
Empty gatewayURL/callbackURL derive the Core Service's
`/api/v1/copilot/dsh/model/v1` and `/api/v1/copilot/dsh/tools` URLs. Both must be
reachable from Node directly, not via an Agent cluster proxy.
One replica owns one PVC; Recreate prevents overlapping writers. The journal is
created beneath the fsGroup-writable PVC root so UID 1000 owns the directory.

Core's `SOHA_DSH_RUNTIME_{ENABLED,BASE_URL,SERVICE_TOKEN_FILE,TIMEOUT,ALLOW_INSECURE_HTTP}`
entries derive from dshRuntime values and the shared secret mount. Empty baseURL
uses the private dsh Service. Explicitly set `allowInsecureHTTP: true` only on an
isolated trusted service network; otherwise provide HTTPS baseURL and retain false.
The chart rejects an enabled plaintext endpoint without this opt-in.
Core's `SOHA_HINDSIGHT_{ENABLED,BASE_URL,TOKEN_FILE,INSTANCE_NAMESPACE,TIMEOUT}`
entries derive from hindsight values. Instance namespace is required, stable,
unique and server-owned; never take it from user input. Both timeouts default to
15s; Hindsight permits at most 30s. Config changes take effect at Core startup.

For Hindsight, the image is fixed to 1.2.0 plus its qualified index digest. Provide
an existing Secret with `service-token`, `gateway-pat`, and `database-url`. The DB
must be independently provisioned with its own role, pgvector/pg_trgm and migration
privileges, never Core's DB/schema. There is no bundled DB or business migration.
`gatewayURL` is the extraction route. Optional `embeddingGatewayURL` overrides
only the embedding route; empty preserves the shared URL. The qualified Qwen pair
uses `/api/v1/ai-gateway/llm/qwen/v1` for both: extraction model
`Qwen/Qwen3-30B-A3B-Instruct-2507`, embedding model `Qwen/Qwen3-Embedding-0.6B`,
dimensions `1024`. Hindsight's protocol provider remains `openai`; `qwen` is the
Gateway route kind. An independent OpenAI extraction URL is also supported.
Limit the PAT to the selected models/providers. The reviewed startup
script requests float vectors through Hindsight's official extra-body setting.
Build the deployment ConfigMap from the reviewed Core deployment artifacts:

```sh
kubectl -n YOUR_NAMESPACE create configmap soha-hindsight-deploy \
  --from-file=gateway.py=/YOUR_REVIEWED_ARTIFACTS/gateway.py \
  --from-file=start.py=/YOUR_REVIEWED_ARTIFACTS/start.py
```

Those two files are delivered in Core `deploy/dsh-hindsight/`; copy the reviewed
release artifacts matching the deployed Core version into your operational bundle. The
matching protective gateway must support retain-operation purge receipts: Core requires
`X-Soha-Retain-Operation-Purged` to match the requested operation ID. Ensure any
intermediary preserves this response header; an older gateway or a stripped receipt
causes the operation to fail rather than confirming the purge. The chart consumes existing
ConfigMaps and Secrets without a sibling source dependency or generated secret values.
Do not replace the protective scripts with a direct upstream entrypoint: the
published API does not authenticate a generic bearer token by default.
The gateway authenticates health and the raw API allowlist, rejecting reflect,
management, config overrides, encoded paths, redirects and unbounded request bodies.
The raw API listens at 127.0.0.1:8888 in the same Pod; only port 8889 gets a Service.

Example non-secret values (operator supplies existing Secret/ConfigMap contents):

```yaml
config:
  security:
    protectedDurableStorage: true
dshRuntime:
  enabled: true
  image: registry.internal.example/soha-dsh@sha256:REPLACE_WITH_VALIDATED_DIGEST
  existingSecret: soha-dsh
  # Private chart Service links; explicitly opt into plaintext only in isolation.
  allowInsecureHTTP: true
  models: soha-workbench
hindsight:
  enabled: true
  existingSecret: soha-hindsight
  deploymentConfigMap: soha-hindsight-deploy
  gatewayURL: https://gateway.internal.example/v1
  llmModel: operator-allowed-extraction-model
  embeddingModel: operator-allowed-embedding-model
  embeddingDimensions: 1536 # must match the actual Gateway embedding model
  instanceNamespace: production-installation-unique-id
```

Enable protected storage after upgrading all Core workers to a version that reads
encrypted checkpoints. Use a stable installation-specific
`config.security.credentialEncryptionKey`. Keep protected storage and the same key
enabled when disabling dsh while encrypted checkpoints still need recovery.

Both workloads run non-root with read-only root filesystems and no Kubernetes API
token. Restrict network ingress to Core/health operators and outbound traffic to the
private Gateway and separate DB via your existing network policy/firewall controls.
ClusterIP is private networking, not TLS. Use private authenticated transport where
required. No Docker socket or host workspace is mounted. Hindsight disables automatic
consolidation and model downloads, uses rrf and no UI/standalone worker. Never attach
a preexisting Hindsight DB with provider overrides or mental-model schedules without
a separate reviewed migration. Core owns all bank and source ACL decisions.

Restart optional workloads after external Secret/ConfigMap changes; back up dsh's
single-writer journal and the independent Hindsight DB separately. Retain their
storage when stopping services. Prove stale writers dead before removing journal locks.
Real image startup, rootless/read-only permissions, model cache availability,
DB/Gateway behavior and B3 integration remain runtime gates. Helm lint/render and
the gateway unit check do not replace them. No release/publishing is performed here.
