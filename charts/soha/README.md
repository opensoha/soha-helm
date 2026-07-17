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
