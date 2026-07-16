# Soha

## Usage

The chart is distributed through the OpenSoha Helm repository.

- Helm Repository: `https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages` with chart `soha`

Install from the Helm repository:

```bash
helm repo add opensoha https://raw.githubusercontent.com/opensoha/soha-helm/gh-pages
helm repo update
helm install soha opensoha/soha --namespace soha --create-namespace
```
