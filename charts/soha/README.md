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

When the bundled PostgreSQL deployment is enabled, the Soha Pod waits for the
database to accept connections before starting the control-plane container.
External PostgreSQL deployments remain the operator's responsibility.

## Application data

The chart mounts a persistent volume at `/app/data` for uploaded software
packages and companion data. Set `persistence.storageClass` and
`persistence.size` for a new claim, or set `persistence.existingClaim` to reuse
one. The chart keeps claims when a release is uninstalled.

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
