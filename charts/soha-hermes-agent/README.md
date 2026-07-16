# Soha Hermes Agent

## Usage

The chart is distributed through the OpenSoha Helm repository.

- Helm Repository: `https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages` with chart `soha-hermes-agent`

Install from the Helm repository:

```bash
helm repo add opensoha https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages
helm repo update
helm install soha-hermes-agent opensoha/soha-hermes-agent \
  --namespace soha-agent \
  --create-namespace \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN"
```
