---
name: soha-helm
description: >-
  Implement or review OpenSoha Helm charts, values, JSON schemas, templates,
  render tests, chart metadata, repository index packaging, and Artifact Hub
  metadata. Use when changing the `soha`, `soha-agent`, or
  `soha-hermes-agent` installation and release behavior.
---

# Soha Helm

## Purpose

Keep chart behavior aligned with the runtime repositories while preserving
three clear workload owners: control plane, generic agent or Identity Outpost,
and Hermes Agent Runtime runner.

## Workflow

1. Read the affected chart's `Chart.yaml`, `values.yaml`,
   `values.schema.json`, templates, README, and `scripts/test-render.sh`.
2. Change values, schema, templates, and chart documentation together.
3. Preserve the owning runtime's configuration names and security validation;
   do not invent a Helm-only application contract.
4. Add render assertions for branches, rollouts, mounts, secrets, selectors,
   and failure cases affected by the change.
5. Bump a chart version only when publishing a changed chart artifact, then run
   the complete repository verification.

## Chart Boundaries

- `charts/soha` owns the control plane, embedded console, and optional
  PostgreSQL dependency.
- `charts/soha-agent` owns generic agent and `mode=outpost` deployment
  behavior.
- `charts/soha-hermes-agent` owns the Hermes runner.
- CLI images and standalone docs are not Helm workloads.
- Keep secret values in Secret-backed paths and out of ConfigMaps, rendered
  logs, chart notes, and committed examples.
- Keep selector labels stable across upgrades and make configuration changes
  trigger the intended workload rollout.
- Chart templates consume released image and config contracts; they do not
  import sibling source trees.

## Verification

```bash
make verify
```

Use focused `helm lint`, `helm template`, or
`./scripts/test-render.sh` while iterating. `make verify` is the release
gate for all three charts and the local repository index.
