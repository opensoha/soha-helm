# Soha Agent

## Usage

The chart is distributed through the OpenSoha Helm repository.

- Helm Repository: `https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages` with chart `soha-agent`

Install from the Helm repository:

```bash
helm repo add opensoha https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages
helm repo update
helm install soha-agent opensoha/soha-agent \
  --namespace soha-agent \
  --create-namespace \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN"
```
