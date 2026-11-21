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

Core startup and readiness use `/readyz`, including the database check. Startup
allows up to 300 seconds (60 attempts every 5 seconds). Liveness checks the named
`http` TCP port so a database outage removes readiness without restarting Core.
`/healthz` remains available as a database-aware diagnostic endpoint.

### External PostgreSQL TLS

`postgres.sslMode` defaults to `disable` for compatibility. Supported modes are
`disable`, `allow`, `prefer`, `require`, `verify-ca` and `verify-full`. For an
external database, use `verify-full` with its DNS hostname and trusted CA:

```yaml
postgres:
  enabled: false
  host: postgres.example.com
  sslMode: verify-full
  existingCASecret: postgres-ca
  caKey: ca.crt
```

Create the CA Secret in the release namespace and supply the database credentials
through your existing secured values workflow. The chart mounts only `caKey` as
`/run/soha-postgres/ca.crt` and sets `PGSSLROOTCERT` for Core and optional
network-control, which shares Core's database and TLS mode. It does not change
the independent bundled network-ingest database or configure client private keys.
Use a new Secret name when rotating the CA to roll the affected Pods.

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

Empty `dshRuntime.gatewayURL` and `dshRuntime.callbackURL` use the Core Service,
`config.basePath` (default `/api/v1`) and `/copilot/dsh/model/v1` or
`/copilot/dsh/tools`. Leading and trailing slashes in `basePath` are normalized;
explicit URL overrides take precedence.

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
Upgrades now reuse `auth.jwt.secret` and `security.credential_encryption_key`
from the live configuration Secret, just as they reuse the database and bootstrap
credentials. Updating these two Helm values alone does not rotate an existing
installation's keys. Back up the database and Secret before any deliberate key
migration; preserve the previous verification/decryption keys for live credentials.
Offline `helm template` cannot perform a live Secret lookup and therefore only
shows first-installation values.

## CLI session authentication

Device authorization and v2 password sessions are opt-in until the matching
Core, embedded Web and CLI releases have been verified together:

```yaml
config:
  auth:
    cli:
      enabled: true
      publicURL: https://soha.example.com
      allowPassword: false
      accessTTL: 15m
      idleTTL: 168h
      absoluteTTL: 720h
```

`publicURL` is the external console address. Include the deployment prefix when
serving below a path, and build Web for the same prefix. HTTPS is required outside
loopback. Disabling new CLI login leaves existing sessions available for refresh
and revocation. Key authentication and existing Web/App login remain separate.
The chart accepts HTTP only for canonical `localhost`, `127.0.0.0/8` and `[::1]`
addresses; Core performs final URL validation. `config.basePath` is the API path
(normally `/api/v1`), rather than this external console prefix. Render validation
also enforces the Core duration bounds: device lifetime 30s–10m, polling 1s–30s,
and `1s <= accessTTL <= idleTTL <= absoluteTTL <= 8760h`. Durations use integer
`ms`, `s`, `m`, `h` components; zero retains the corresponding Core default.
All replicas must share PostgreSQL and the same persistent signing/encryption
identity. Grant status, polling/attempt budgets, refresh generations and recovery
receipts live in PostgreSQL, so a Pod restart does not reset them. Keep a working
Web administrator session for emergency CLI-session and Key revocation.

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

Optional independent Proxy data plane and scale-only executor: [PROXY.md](PROXY.md). Both are disabled by default.

TLS materials for `config.networkIngestQuery`, `networkRuntime` and `proxyRuntime`
are copied at Pod startup by a non-root init container from read-only Secret sources
into a memory-backed `emptyDir` private child (0700, files 0600). Main containers
mount only that child read-only at the existing TLS paths. The Secret remains the
source of truth; credential changes require a coordinated Pod restart, with no
automatic reload. Proxy identity rotation also requires drain/stop and live template
pin review as described in [PROXY.md](PROXY.md).

`config.networkIngestQuery`、`networkRuntime`、`proxyRuntime` 的 TLS 材料仅在 Pod
启动时由非 root init container 从只读 Secret 复制到内存卷的私有子目录（0700，文件 0600），
主容器按原路径只读挂载。Secret 仍为真实源；轮换后须协调重启，没有自动重载。
Proxy 身份轮换还须按 [PROXY.md](PROXY.md) 排空、停止并核对 live template pin。

## Optional managed RADIUS runtime

`radiusRuntime` and `radiusExecutor` are disabled by default. They require a
verified candidate image containing `/usr/local/bin/radius-runtime` and a Core
image containing `/app/radius-runtime-executor`; image tags in test fixtures are
illustrative and are not published release claims. No cluster upgrade or NAS
acceptance is implied by rendering this chart.

Installation has two phases. First install `radiusRuntime.enabled=true` with
`replicas=0` and independently approved ordered `members`, leaving the executor
disabled. An installer must provision **each** PVC
`data-<radiusRuntime.name>-<ordinal>` (the chart does not create private material)
with its own `snapshot/` and `state/` directories. Keep `runtime.json`, common
control TLS files and locally pre-approved A/B configuration directories beneath
`snapshot/`; the fixed PVC mounts already support these nested directories.
Each ordinal has its own root-owned 0600 JSON and private identities. Use
`installation.configurationCatalog` entries containing the full approved
`material`, `directory`, `treeSHA256`, `hooks`, `environment`, `materials` and
`certificates`. Do not combine this catalog with the legacy top-level single
snapshot fields or `control.configuration`. See the
[configuration catalog example and switch procedure](RADIUS-CATALOG.md).

The installer must verify the common control TLS certificate, key and CA against
`installation.materials` before the client reads them, independently of the
selected catalog entry. Every protected file/directory and **every ancestor** to
`/` must be root owned, non-symlink and not group/other writable; there is no
`/tmp` or sticky-directory exception. Private directories must be
root:freerad-group 0710 and child-readable configuration/material files
root:freerad-group 0640; runtime JSON stays 0600 and state is never group writable.
Use the selected image's actual freerad UID/GID. The chart mounts snapshot read
only and state writable from that ordinal's PVC; it never projects every
member's Secret into every Pod or generates credentials, hashes or attestation.
The installer owns PVC preparation and verification before enabling replicas.

`radius-runtime --configuration-digest DIR` only reads a protected configuration
tree and prints its 64-character SHA-256. It does not sign or approve a tree,
attest hooks, fetch files, or start FreeRADIUS. Pre-approve both A and B locally;
after A has exact stopped/wait proof, a subsequent process epoch may select B
when Core supplies its complete matching approved material. This is not a hot
reload or remote file download and needs no Kubernetes Pod-template change.

The Linux supervisor runs as UID 0 with all capabilities dropped except CHOWN,
SETUID, SETGID and KILL; these support private socket ownership, child privilege
drop and termination. A same-image init container only prepares the independent
native-run and temporary emptyDirs; it cannot access the PVC. Configure the
approved flat tree's native `run_dir` as `/run/freeradius`, with logs to stdout
or a file inside that directory, never the read-only image `/var/log` or private
supervisor state. The chart does not attest that these capabilities or a
particular image have passed real container execution.

Then inspect the installed StatefulSet's actual UID, template digest and service
account and approve a `radiusExecutor.slots` entry. Slots use Core domain JSON:
`id`, `siteId`, `nasBindingId`, `nasId`, `nasName`, `accessMedium` (plus `ssid` for
WiFi), `executorId`, target namespace/name/UID/workloadKind/templateDigest,
`serviceAccount`, `maxReplicas`, independent `members`, and `configurations`
containing `material` references and public `eapServerTrust`. They are mapped to
Core's `runtime.radius_slots` and passed unchanged to the dedicated executor.
Configure its independent existing token Secret, HTTPS `baseUrl` and image;
`start=false` keeps the executor stopped until installer pins are reviewed.
Never reuse Proxy, Outpost or generic runner credentials. No management UI may
supply arbitrary image, YAML or private material. Kubernetes v1 validating
admission policies and bindings are required; the policy fails closed and RBAC
allows get and scale-update only on named approved workloads. The executor also
checks UID, template digest, service account and resourceVersion before scaling.

Every member's endpoint must route directly to that member. The sole headless
Service is for discovery; configure NAS with individual addresses such as
`soha-radius-0.soha-radius-members.<namespace>.svc:1812` only where the NAS can
resolve and reach that address. There is no shared UDP LoadBalancer or
round-robin authentication endpoint. External per-member networking must be
prepared separately before installation approval. Kubernetes readiness is not
RADIUS traffic readiness or proof that a NAS used the member; the chart does
not create a readiness probe that would imply either.

Parallel pod management permits approved member scaling. PVC retention is
`Retain` both on scale-down and StatefulSet deletion/uninstall. Retain PVCs and
private snapshots until the installer explicitly handles recovery or secure
removal. Stop/drain via Core's managed pool lifecycle and observe real member
proof before uninstalling workloads; Helm uninstall is not a proven drain or
safe stop. An upgrade reapplies `radiusRuntime.replicas` and may replace the
Pod template: drain and stop the managed pool before such maintenance, then
renew changed pins before resuming. Do not delete retained PVCs or credentials as an implicit uninstall
 step. A reinstall/replacement UID or template change requires renewed installer
pins; never substitute fixture values from `tests/radius-values.json`.

## Optional Workspace App Hosting gateway (`appGateway`)

`appGateway.enabled` defaults to `false`. When enabled, the chart deploys an
independent `<fullname>-app-gateway` `Deployment` (default `2` replicas),
`Service` (`ClusterIP` on port `8090`), and optional wildcard `Ingress`
(`*.<appsDomain>`) so browser traffic to hosted workspace apps never traverses
the Soha Core control-plane Pod.

Supply an image build containing `/usr/local/bin/soha-app-gateway` (either via
the chart's main `image` or an explicit `appGateway.image` override; releases
through `v0.1.12` predate `soha-app-gateway`) and apply the matching Core
PostgreSQL migrations (`0154_app_hosting.sql`) before enabling the gateway.

All gateway and S3 credentials are Secret-backed only; passing inline secret
values in Helm values fails schema/template validation:

1. `appGateway.existingSecret` (required): dedicated Secret in the release
   namespace holding `gateway-token` (customizable via `gatewayTokenKey`, paired
   with Core's rotated App Hosting gateway token) and `cookie-secret`
   (customizable via `cookieSecretKey`, 32+ random bytes for Host-only session
   and auth-state signing).
2. `appGateway.s3.existingSecret` (required): dedicated Secret holding
   least-privilege read-only object-storage credentials (`access-key-id` and
   `secret-access-key`, customizable via `accessKeyIdKey` and
   `secretAccessKeyKey`).

```yaml
image:
  repository: ghcr.io/opensoha/soha
  tag: local
appGateway:
  enabled: true
  replicas: 2
  appsDomain: apps.example.com
  publicCoreUrl: https://soha.example.com
  trustedProxies:
    - 10.42.0.0/16
  decisionCacheTtl: 0s
  existingSecret: soha-app-gateway-auth
  s3:
    endpoint: https://minio.internal:9000
    bucket: soha-hosted-apps
    region: us-east-1
    prefix: hosted-apps
    pathStyle: true
    insecure: false
    existingSecret: soha-app-gateway-s3
  ingress:
    enabled: true
    className: nginx
    tlsSecretName: soha-apps-wildcard-tls
```

 Key parameters under `appGateway`:

- `replicas` (default `2`), `image` (optional `{repository, tag, pullPolicy}`
  override defaulting to the chart's main image).
- `appsDomain` (bare domain such as `apps.example.com`; wildcard Ingress renders
  `*.<appsDomain>`), `publicScheme` (`https` by default), `httpRedirectPort`
  (`0` disabled by default; when `> 0`, enables `308` HTTP-to-HTTPS redirect).
- `publicCoreUrl` (browser-facing Core URL for SSO login redirects), `coreUrl`
  (internal Core URL for ticket exchange and per-request access checks; defaults
  to `http://<fullname>:<service.port>`), `trustedProxies`, `decisionCacheTtl`
  (`0s` by default for immediate per-request revocation across replicas).
- `existingSecret`, `gatewayTokenKey` (`gateway-token`), `cookieSecretKey`
  (`cookie-secret`), `secretRevision` (bump to roll Pods after in-place Secret
  rotation), and optional direct `tls` (`existingSecret`, `certKey`, `keyKey`).
- `s3` (`endpoint`, `bucket`, `region`, `prefix`, `pathStyle`, `insecure`,
  `existingSecret`, `accessKeyIdKey`, `secretAccessKeyKey`).
- `service` (`type`, `port`), `ingress` (`enabled`, `className`, `annotations`,
  `tlsSecretName`), `resources`, `nodeSelector`, `tolerations`, `affinity`.
- Probes run against the dedicated internal health listener (`:8091` `/healthz`
  and `/readyz`), while Pods run non-root (`10001:10001`), read-only root
  filesystem, `RuntimeDefault` seccomp, all Linux capabilities dropped, and
  `automountServiceAccountToken: false`.
