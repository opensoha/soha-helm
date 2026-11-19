# Soha Hermes Agent

## Usage

The chart is distributed through the OpenSoha Helm repository.

- Helm Repository: `https://opensoha.github.io/soha-helm` with chart `soha-hermes-agent`

Install from the Helm repository:

```bash
helm repo add opensoha https://opensoha.github.io/soha-helm
helm repo update
helm install soha-hermes-agent opensoha/soha-hermes-agent \
  --namespace soha-agent \
  --create-namespace \
  --set-string secrets.controlPlaneBearerToken="$SOHA_EXECUTION_RUNNER_TOKEN"
```

## Rotate an existing Secret

Set `secrets.controlPlaneExistingSecret.name` and `key` to use a Secret in the
release namespace, and leave `secrets.controlPlaneBearerToken` empty. After
rotating the referenced token in place, pass its new revision to Helm. The
revision changes the Pod template and rolls the runner so its environment
picks up the updated token.

```bash
revision="$(kubectl -n soha-agent get secret soha-config -o jsonpath='{.metadata.resourceVersion}')"
helm upgrade soha-hermes-agent opensoha/soha-hermes-agent \
  --namespace soha-agent --reuse-values \
  --set-string secrets.controlPlaneExistingSecret.revision="$revision"
kubectl -n soha-agent rollout status deployment/soha-hermes-agent
```

For GitOps, publish a new non-secret revision in the Helm values with each
rotation. Leaving the revision empty or reusing it keeps the Pod template
stable. For the chart-managed token, changing `secrets.controlPlaneBearerToken`
updates the Pod template checksum during the Helm upgrade.
