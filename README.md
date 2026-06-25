# OpenSoha Helm Charts

This repository is the static Helm repository for OpenSoha charts.

## Usage

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

- `soha`: OpenSoha control plane with embedded web console and optional PostgreSQL.
- `soha-agent`: OpenSoha cluster agent for remote Kubernetes operations.
- `soha-hermes-agent`: OpenSoha Hermes Agent Runtime runner.

The `soha-cli` artifact is published as a Docker tool image at `yshanchui/soha-cli`. It is not a Helm workload. Use it from multi-stage builds when a container needs the `soha` CLI:

```Dockerfile
COPY --from=yshanchui/soha-cli:v0.1.0 /usr/local/bin/soha /usr/local/bin/soha
```

## Publishing

Generate the repository contents from the main `soha` repository:

```bash
make deploy-helm-repo HELM_REPO_URL=https://opensoha.github.io/soha-helm
```

Then copy `dist/helm-repo/*` into this repository root and publish it through GitHub Pages. Artifact Hub indexes `https://opensoha.github.io/soha-helm`; it does not host the chart archives.
