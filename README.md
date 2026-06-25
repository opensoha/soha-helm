# OpenSoha Helm Charts

This repository owns and publishes the OpenSoha Helm charts.

## Usage

```bash
helm repo add opensoha https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages
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

- `soha`: OpenSoha control plane with embedded web console and optional PostgreSQL.
- `soha-agent`: OpenSoha cluster agent for remote Kubernetes operations.
- `soha-hermes-agent`: OpenSoha Hermes Agent Runtime runner.

The `soha-cli` artifact is published as a Docker tool image at `yshanchui/soha-cli`. It is not a Helm workload. Use it from multi-stage builds when a container needs the `soha` CLI:

```Dockerfile
COPY --from=yshanchui/soha-cli:v0.1.0 /usr/local/bin/soha /usr/local/bin/soha
```

## Publishing

Chart sources live under `charts/`. On every push to `main` that changes chart sources, GitHub Actions runs:

```bash
make verify
```

If a chart version changed, the workflow uploads chart archives to GitHub Releases and updates `index.yaml` on the `gh-pages` branch. Artifact Hub indexes `https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages`; it does not host the chart archives.

## Artifact Hub

Add a Helm repository in Artifact Hub with:

- Kind: `Helm charts`
- Name: `opensoha`
- URL: `https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages`

Ownership metadata lives in `artifacthub-repo.yml`. Keep the owner email current so Artifact Hub can verify the repository claim.
