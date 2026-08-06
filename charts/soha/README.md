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

## Prometheus and Grafana migration

The chart no longer accepts the legacy `config.monitoring.prometheusUrl`,
`prometheusBearerToken`, `prometheusDefaultRangeMinutes`,
`prometheusStepSeconds`, `prometheusClusterLabel`, or `grafanaBaseUrl` values.
Helm schema validation fails when any of these keys remain, rather than silently
discarding them. Remove them from the release values before upgrading, then
configure Prometheus and Grafana for each cluster through the Soha console or
API. Existing Helm values are not migrated automatically.
