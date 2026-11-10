# Soha

## Usage

The chart is distributed through the OpenSoha Helm repository.

- Helm Repository: `https://opensoha.github.io/soha-helm` with chart `soha`

Install from the Helm repository:

```bash
helm repo add opensoha https://opensoha.github.io/soha-helm
helm repo update
helm install soha opensoha/soha --namespace soha --create-namespace
```

Chart `0.1.12` defaults to `ghcr.io/opensoha/soha:v0.1.12`. If you
reuse values from an earlier release with `--reuse-values` or supply an
explicit image pin, set `image.tag` to `v0.1.12` to select the new image.

When the bundled PostgreSQL deployment is enabled, the Soha Pod waits for the
database to accept connections before starting the control-plane container.
External PostgreSQL deployments remain the operator's responsibility.

## Application data

The chart mounts a persistent volume at `/app/data` for uploaded software
packages and companion data. Set `persistence.storageClass` and
`persistence.size` for a new claim, or set `persistence.existingClaim` to reuse
one. The chart keeps claims when a release is uninstalled.

## Optional dsh and Hindsight runtimes

Both runtimes are opt-in. Set `image.repository` and `image.tag` to a tested
Core build that supports the selected runtime and apply the matching Core
migrations before enabling it. The published `ghcr.io/opensoha/soha:v0.1.12`
image is rejected for either runtime. Publish and verify the matching Core and
dsh images before cutting a new chart release. Keep the runtime and its
configuration pinned to the tested versions. Enabling dsh also requires
`config.security.protectedDurableStorage: true`, set after every Core worker
supports encrypted checkpoints. Keep the setting and the installation's
encryption key while any encrypted checkpoint may need recovery.

### Journal storage

The single dsh replica mounts its journal under `/var/lib/soha-dsh/journal`.
By default, the chart creates a ReadWriteOnce claim named `<fullname>-dsh`
using `dshRuntime.storageSize` and `dshRuntime.storageClass`. Helm's
`helm.sh/resource-policy: keep` retains it across runtime disable or release
uninstall. Set `dshRuntime.existingClaim` to the retained claim name when
re-enabling or reinstalling. This references the same volume in the same
namespace without transferring ownership to the new release. You can also
pre-provision an operator-managed claim and use `existingClaim` from the first
install. Verify that the claim is bound to the expected volume and has no other
writer before starting dsh. Back up the journal independently of the release.

If an earlier candidate already manages the claim without the keep policy,
pause new runs, drain dsh and back up the journal. Upgrade first with dsh
still enabled and the same release name, claim name, and storage settings.
Confirm the keep annotation on the live claim and in `helm get manifest` before
disabling dsh, uninstalling, or switching to `existingClaim`. Exercise
retention on an isolated release with the Helm client or GitOps controller
that manages the installation. When the controller does not honor the policy,
use a backed-up, verified operator-managed claim before retiring the old
release. For a rollback, use a retention-aware chart revision and the tested
Core/dsh pairing. Preserve the claim and the encryption key through rollback.

### Hosted MCP and Skill files

Use an existing, versioned ConfigMap in the release namespace with a
`registry.json` key and the files declared by the registry's Skill manifests.
Use a separate Secret for HTTP MCP credentials, with each token in its own
key. Only the dsh Pod receives these asset references.

```yaml
dshRuntime:
  pluginAssets:
    configMap: dsh-plugin-assets-v1
    skillFiles:
      observability/SKILL.md: observability-skill
      observability/references/query.txt: observability-query
    credentialSecret: dsh-http-mcp-v1
```

In `registry.json`, the example Skill uses
`/run/dsh-skills/observability` as its root, declares the files by relative
path, and carries their SHA-256 digests. The chart mounts each listed file
read-only at its mapped path. A registry MCP entry may refer to a Secret key
such as `read-metrics` using
`"credentialFile": "/run/dsh-credentials/read-metrics"`. Use keys starting
with a letter or digit. Dot-prefixed keys are skipped along with Kubernetes
volume projection metadata. A non-root init container stages the dedicated
Secret into a memory-backed volume as regular files owned by UID 1000 with
mode 0400. The dsh container mounts that volume read-only. Use a new
ConfigMap or Secret name when changing assets or credentials to recreate the
dsh Pod. The chart supports hosted HTTP MCP and Skill files through these
mounts. Hosted stdio needs its own qualified execution environment.

### Service token rotation

The Core and runtime processes load shared service tokens at startup. Pause
new runs, drain the affected runtime, and create a new Secret in the release
namespace with a new name and the replacement `service-token` key.
Update `dshRuntime.existingSecret` or `hindsight.existingSecret` in one Helm
upgrade so both Core and the affected runtime reference it. For Hindsight,
carry forward the `gateway-pat` and `database-url` keys unless those are
also being rotated. Wait for all updated workloads, then verify authenticated
health and Core-to-runtime calls, plus the runtime-to-Core callbacks for dsh,
before resuming runs. Keep the previous Secret available through the rollback
window. Changing only the contents of the existing Secret does not coordinate
startup or restart both workloads.

## Configuration ownership

Values below `config` are the deployment baseline written to the control-plane
`config.yaml`. A checksum of the rendered file is added to the Pod template, so
a `helm upgrade` that changes its values or template automatically rolls the
control-plane Pods. The checksum is a SHA-256 digest and does not expose
configuration or credential plaintext in Deployment annotations.

Database settings, listener and asset settings, bootstrap and migration
settings, and system credentials are deployment-managed. In particular, do not
change `config.security.credentialEncryptionKey` until every stored credential
has been migrated to the replacement key and verified as decryptable. Changing
the Helm value first makes ciphertext written with the previous key unreadable.

## Network ingest summaries

High-frequency network telemetry remains in a separate `soha-ingest` process
and database. The chart can run the unprivileged control and ingest plane by
mounting an externally issued mTLS Secret:

```yaml
image:
  # Build and load this image before installation.
  tag: local
networkRuntime:
  enabled: true
  existingTLSSecret: soha-network-runtime-tls
```

The Secret must contain `network-control.crt`, `network-control.key`,
`ingest.crt`, `ingest.key`, and `client-ca.crt`. The chart then creates
`network-control`, `ingest`, and an isolated ingest PostgreSQL workload; none of
them shares a Pod with the Soha control plane or forwards user traffic.

Build and load `ghcr.io/opensoha/soha:local` from the current core checkout
before installing, or set `image.repository` and `image.tag` to your tested
registry build. The image must contain `/app/soha`, `/app/network-control`,
and `/app/ingest`. Enabling the runtime with the chart's old default image
is rejected; releases through v0.1.8 do not contain those runtime binaries.

To let the control plane query bounded aggregate summaries, create a separate
client Secret containing `ca.crt`, `tls.crt`, and `tls.key`, then configure:

```yaml
config:
  networkIngestQuery:
    enabled: true
    url: https://soha-ingest.soha.svc:8083
    serverName: soha-ingest.soha.svc
    existingSecret: soha-core-ingest-query-tls
    timeout: 5s
    maxResponseBytes: 1048576
```

The client certificate must use the exact URI SAN
`spiffe://opensoha.local/network-ingest/core/soha-server`. Issue it separately
from gateway and endpoint identities. The chart mounts both Secrets read-only.

The privileged WireGuard gateway and FreeRADIUS/NAS adapter are intentionally
not installed by this Chart. Deploy them from the version-matched raw manifests
after reviewing host networking, `NET_ADMIN`, UDP exposure, certificate, and
RADIUS shared-secret requirements.

## Prometheus and Grafana migration

The chart no longer accepts the legacy `config.monitoring.prometheusUrl`,
`prometheusBearerToken`, `prometheusDefaultRangeMinutes`,
`prometheusStepSeconds`, `prometheusClusterLabel`, or `grafanaBaseUrl` values.
Helm schema validation fails when any of these keys remain, rather than silently
discarding them. Remove them from the release values before upgrading, then
configure Prometheus and Grafana for each cluster through the Soha console or
API. Existing Helm values are not migrated automatically.
