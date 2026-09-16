---
name: soha-helm
description: Change or review Soha Helm charts, values, schemas, render behavior, and chart releases. Raw deployment manifests belong to their runtime repository.
---

# Soha Helm

## Purpose

Keep chart behavior aligned with the runtime repositories while preserving
three clear workload owners: control plane, generic agent or Identity Outpost,
and Hermes Agent Runtime runner.

## Workflow

1. Read the affected chart files for the task: values and schema for configuration,
   templates and `scripts/test-render.sh` for rendering, `Chart.yaml` for packaging,
   and README for documented behavior. Documentation-only edits need only the relevant text and its source.
2. Synchronize values, schema, templates, and documentation when the changed behavior
   affects them. A documentation or assertion-only edit does not require changes to the other layers.
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
Documentation-only changes need content, link, and diff checks; they do not trigger chart rendering or builds.
