# OpenSoha Helm Charts

This repository owns and publishes the OpenSoha Helm charts.

## Usage

### Helm Repository

```bash
helm repo add opensoha https://opensoha.github.io/soha-helm
helm repo update
helm search repo opensoha
```

Install the control plane:

```bash
helm install soha opensoha/soha --namespace soha --create-namespace
```

Install the generic cluster agent:

```bash
helm install soha-agent opensoha/soha-agent \
  --namespace soha-agent \
  --create-namespace \
  --set-string secrets.agentBearerToken="$SOHA_AGENT_BEARER_TOKEN" \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN" \
  --set-string config.controlPlane.baseUrl="https://soha.example.com"
```

Install the Hermes Agent Runtime runner:

```bash
helm install soha-hermes-agent opensoha/soha-hermes-agent \
  --namespace soha-agent \
  --create-namespace \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN" \
  --set-string controlPlane.baseUrl="https://soha.example.com"
```

## Published Charts

- `soha`: OpenSoha control plane with embedded web console and optional PostgreSQL 18.4 + pgvector 0.8.5.
- `soha-agent`: OpenSoha cluster agent for remote Kubernetes operations.
- `soha-hermes-agent`: OpenSoha Hermes Agent Runtime runner.

The `soha-cli` artifact is available as a Docker Hub tool image at `yshanchui/soha-cli`. It is not a Helm workload. Use it from multi-stage builds when a container needs the `soha` CLI:

```Dockerfile
COPY --from=yshanchui/soha-cli:v0.1.0 /usr/local/bin/soha /usr/local/bin/soha
```

The bundled database uses `pgvector/pgvector:0.8.5-pg18-trixie`, enables
`vector` and `pg_trgm`, and preloads `pg_stat_statements`. When
`postgres.enabled=false`, the external PostgreSQL 18 server must provide
`vector` and `pg_trgm` unless the Soha migration user can create extensions.
`pg_stat_statements` is optional for external databases and must be configured
and restarted by their administrator.

## Publishing

Chart sources live under `charts/`. On every push to `main` that changes chart sources, GitHub Actions runs:

```bash
make verify
```

If a chart version changed, the workflow publishes it through both supported channels:

- GitHub Releases plus `index.yaml` on the `gh-pages` branch, published through GitHub Pages at `https://opensoha.github.io/soha-helm`.
- GHCR OCI artifacts below `oci://ghcr.io/opensoha/charts`; publish them as public packages before documenting them as an installation channel.

The workflow deploys the `gh-pages` branch as a GitHub Pages site after each successful chart release. Enable GitHub Pages for this repository once in **Settings -> Pages** (source: GitHub Actions); subsequent releases appear under the workflow's `github-pages` environment with the site URL.

The raw `gh-pages` URL remains available as a compatibility endpoint for existing installations.

## Artifact Hub

Add a Helm repository in Artifact Hub with:

- Kind: `Helm charts`
- Name: `opensoha`
- URL: `https://opensoha.github.io/soha-helm`

Ownership metadata lives in `artifacthub-repo.yml`. Keep the owner email current so Artifact Hub can verify the repository claim.
