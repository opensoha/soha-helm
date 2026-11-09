# Installer-approved Outpost runtime slots

Core-only installs leave `outpostExecutor.enabled=false`. Enabling Identity
Outpost in the Agent chart does not grant the Core server Kubernetes credentials.
The separate executor uses only its in-cluster ServiceAccount and a dedicated
Outpost executor token. An administrator API token or the global execution runner
key is not an executor credential. Provision a dedicated Secret in the Core
release namespace outside Helm and reference its name/key; do not put token
contents in values, ConfigMaps or shell history.

This chart supports the Core and executor installed together in this release.
`controlPlaneUrl` must point to this release's reachable Core API endpoint; this
is not an executor-only chart for an independently configured external Core.
Enabling `outpostExecutor` renders both consumers from the same `slots` and
`executorId` values. Core's `/app/configs/config.yaml` receives
`runtime.outpost_slots` in snake_case and `runtime.outpost_runtime_executors`
with `executor_id` and `token_file: /var/run/soha-outpost-executor/token`.
Both Pods mount the same `existingTokenSecret`/`tokenKey` read-only at that token
path, with Secret mode 0440. Core's dedicated Pod `fsGroup` must be nonzero;
its reader accepts 0440/0640, rejects group-write and all world access. Do not
hand-edit the generated Core config: a Helm upgrade would replace those edits.

Provision a second existing Secret containing the base64-encoded Ed25519 seed
or private key accepted by Core's `SecurityConfig.OutpostSigningKey()`. Set
`signingKey.existingSecret`, `signingKey.key`, and the matching public
`signingKey.keyId`. Helm references that Secret with an environment source;
Core config contains `security.outpost_signing_private_key` as the literal
`${SOHA_OUTPOST_SIGNING_PRIVATE_KEY}` reference, expanded during config loading,
and `security.outpost_signing_key_id` as the supplied key ID. Helm never reads,
generates, or places signing private-key bytes in values or generated config.
The installer must derive/read back the real matching Ed25519 public key through
their approved key-management process, configure that key ID and public key in
the Agent trust map, and verify the match. Neither chart creates an Identity
Outpost record or invents a workload UID, digest or public key.

## Supported target

The target Kubernetes cluster must serve
`admissionregistration.k8s.io/v1/ValidatingAdmissionPolicy` and
`ValidatingAdmissionPolicyBinding`, with admission enforcement enabled. Missing
capabilities cause Helm rendering to fail as unsupported. Offline template tests
pass explicit API versions only to simulate discovery; do not use those flags to
claim a live cluster supports the policy. RBAC `resourceNames` cannot constrain
replicas or Pod templates. The chart therefore installs a fail-closed policy
bound to the executor's exact ServiceAccount username. It allows scale updates
only for the configured namespace/name and `0 <= replicas <= maxReplicas`.
Kubernetes Scale JSON may omit `spec.replicas` when its value is zero. The policy
treats a missing `spec` or `spec.replicas` as zero, matching the Scale default,
so scale-to-zero can pass. This default still uses the same exact target,
executor identity and replica ceiling; omission does not grant unrestricted
scaling or access to another target.
The Role grants only named Deployment `get` and named deployments/scale
`get,update`; it grants no Deployment template mutation, Secret access, exec or
RBAC mutation. The SA must not receive extra grants from other bindings.

Only pre-created Deployment slots are supported. The executor cannot create or
repair a Deployment, storage, RBAC, or Secret. UID and typed PodTemplateSpec
digest are installation pins, checked by the executor. No operator is installed.
Helm output alone does not prove policy compilation or enforcement.

## Installation order and handoff

1. Build and pin the new Core image containing `/app/outpost-runtime-executor`
   and an Agent image supporting runtime control v1, durable instance state and
   trust key overlap. Current chart image defaults are not proof of that feature
   set. Keep the executor disabled during preparation.
2. Pre-create the Outpost with the Agent chart, `mode=outpost` and
   `outpostRuntime.owner=external`. Set its trust keys and control-plane/agent
   credentials. Allocate persistent state before starting it. Helm retains
   `replicaCount` ownership. This does not adopt any existing external Outpost.
3. Obtain explicit installation authorization and verify the current ownership
   of the exact slot, including newly created slots. For an existing external
   instance, arrange a maintenance handoff: actually stop its prior
   reconciler/HPA/GitOps scaling ownership and old processes, preserve their
   state, and record the handoff evidence. For a new slot, verify and record that
   no other lifecycle controller has ever existed for it; the initial Helm
   replica ownership still has to be relinquished in step 4. Do not invent a
   stop command or receipt. `previousOwnerStopped=true` declares that no previous controller
   is currently active, supported either by this absence evidence or by a real
   stop and handoff. Neither installation flag stops or takes over another owner.
4. Upgrade the Agent chart to `outpostRuntime.owner=soha`. It now enables the
   managed control gate and omits `spec.replicas`; Helm no longer owns that
   field. Review the live replica count after the upgrade: removing a previously
   managed field can reset it to the API default on the handoff upgrade. Do not
   run an HPA or another scaler against the slot. The managed Outpost can remain
   unready until Core supplies a current signed runtime control lease. Confirm
   that replica ownership has actually been handed off before marking the
   installation approved; setting flags cannot substitute for that handoff.
5. After all template/config changes and admission mutation have settled, read
   the **live API-defaulted** Deployment. In the matching Core source checkout:

   ```sh
   kubectl get deployment "$OUTPOST_NAME" -n "$OUTPOST_NAMESPACE" -o json |
     GOWORK=off go run ./deploy/outpost/slot-readback.go
   ```

   This helper decodes `apps/v1.Deployment`, then computes
   `sha256:hex(SHA256(json.Marshal(deployment.Spec.Template)))`. Do not hash raw
   YAML, untyped JSON, Helm output, or an arbitrary canonicalization. Keep the
   resulting live UID/digest as installer evidence. Updating templates later
   requires a reviewed new pin and executor restart, never automatic pin refresh.
6. Fill the following installation values. `LIVE_UID_REQUIRED` and
   `LIVE_TYPED_TEMPLATE_DIGEST_REQUIRED` are pending real readback, not samples
   that can be installed. The latter intentionally fails schema validation.
   This example is for a slot whose ownership checks and replica handoff in
   steps 3–4 are complete: set `allowAdoption=true` and
   `previousOwnerStopped=true` only with that evidence, for both new and existing
   slots. Keep both false until verified. Both false permit binding and reading
   an externally controlled slot, but do not permit lifecycle start or transfer
   ownership to Soha; a later user request cannot bypass these installation gates.

   ```yaml
   # Pin the compatible Core image for the server as well as the executor.
   image:
     repository: YOUR_CORE_IMAGE
     tag: YOUR_VERIFIED_BUILD
   outpostExecutor:
     enabled: true
     start: false
     image:
       repository: YOUR_CORE_IMAGE
       tag: YOUR_VERIFIED_BUILD
     controlPlaneUrl: https://YOUR_CORE_ENDPOINT
     executorId: YOUR_REGISTERED_EXECUTOR_ID
     existingTokenSecret: YOUR_DEDICATED_EXECUTOR_SECRET
     tokenKey: token
     signingKey:
       keyId: YOUR_VERIFIED_SIGNING_KEY_ID
       existingSecret: YOUR_EXISTING_SIGNING_SECRET
       key: private-key
     slots:
       - id: YOUR_APPROVED_SLOT_ID
         outpostId: YOUR_OUTPOST_ID
         executorId: YOUR_REGISTERED_EXECUTOR_ID
         namespace: YOUR_OUTPOST_NAMESPACE
         name: YOUR_OUTPOST_DEPLOYMENT
         uid: LIVE_UID_REQUIRED
         templateDigest: LIVE_TYPED_TEMPLATE_DIGEST_REQUIRED
         maxReplicas: 1
         # Only after the checks and handoff in steps 3–4 are complete.
         allowAdoption: true
         previousOwnerStopped: true
   ```

7. Install with `start=false` first. This also configures Core with the exact
   slot set, dedicated token file and signing-key references above, even while
   the executor has zero replicas. Both existing Secrets must already exist in
   the release namespace. Confirm Core starts successfully with its private
   token file and signing key; do not print Secret contents or resolved signing
   environment values as evidence. Inspect the live policy's
   `status.observedGeneration`, `status.typeChecking.expressionWarnings` and
   binding. Require current generation with no warnings, and perform authorized
   server-side dry-run scale checks as the executor SA: allowed target/count
   succeeds; over-limit and unapproved targets fail. Verify other bindings do not
   broaden SA permissions. This requires installer privileges; no such cluster
   checks were run by rendering the chart. If policy enforcement cannot be
   demonstrated, the installation is unsupported: keep `start=false`.
8. Verify that Core accepted the chart-rendered immutable slot and dedicated
   executor credential configuration, including the verified
   `allowAdoption=true` and `previousOwnerStopped=true` declarations. The same
   chart values supply Core and executor allowlists; no manual Core file patch
   or separate credential registration command is needed. Upgrade with
   `start=true` to start the single executor
   only after step 7 succeeds. This starts the executor process; it does not
   adopt or issue a lifecycle start for the Outpost.
9. Using the normal authenticated Core API and an authorized user, read
   `GET /identity/outposts/{identityOutpostID}/runtime`. Then call
   `PUT /identity/outposts/{identityOutpostID}/runtime` with `slotId` set to the
   approved slot, `expectedGeneration` set to the generation just read, a fresh
   `requestId`, and **`explicitAdoption=true`**. This explicit user decision is
   required for new slots as well as existing external instances. Read the
   returned/current runtime and require `owner=soha` before proceeding. The Agent
   chart's `owner=soha` only configures its control gate and replica field; it is
   not this Core ownership transition. With both installer flags false, a bind
   without explicit adoption may succeed but remains external; requesting
   adoption is rejected and lifecycle start remains unavailable.
10. After confirming the executor's dedicated claim/status/callback path and
    the exact bound slot identity, call
    `POST /identity/outposts/{identityOutpostID}/runtime/control` with
    `action=start`, the latest runtime generation as `expectedGeneration`, and a
    new `requestId`. On a generation conflict, reread and reassess before
    submitting; retry an identical request with its original `requestId`.
    Observe the returned task and runtime state rather than treating acceptance
    as readiness. Stop uses `action=stop`, scales to zero, and keeps the
    Deployment and persistent state. API paths above are relative to the Core
    API base URL; never use the executor credential for these user operations.

For a single-replica RWO state claim, `maxReplicas` **must be 1**. The Agent
chart uses Recreate to avoid upgrade surge attachment conflicts. For multiple
replicas across nodes, provision and verify RWX storage, set Agent
`outpostRuntime.accessMode=ReadWriteMany`, and select a matching ceiling. An
`existingStateClaim` is an installer assertion; rendering cannot verify its
actual access modes or filesystem semantics. Unsupported storage must not be
treated as safe multi-replica operation.

## State, restart and rotation

Every Outpost Pod receives its real Pod UID as `instance_id`. A writable retained
PVC stores `data/instances/<Pod UID>/.soha/outpost`, created with mode 0700.
Container restarts in the same Pod reuse that state; replacement Pods get separate
directories and never share the instance lock. Old directories remain for
installer-controlled retention and recovery. Chart-created Outpost PVCs have
`helm.sh/resource-policy: keep`; uninstallation and scale-to-zero are not state
cleanup. Existing claims remain installer-owned. Preserve any legacy replay
floor when migrating an older installation; do not erase it to bypass a managed
state fence. Outpost is not stateless.

`trustKeyId`/`trustPublicKey` remain compatible. `trustPublicKeys` accepts an
overlap map of key IDs to public keys. Add the next key, roll the Outpost Pods,
then change the Core signer, verify signed leases, and only later remove the old
key with another controlled rollout. Config files are not hot-reloaded. Restart
both Core and the executor after slot or dedicated token changes, and restart
Core after signing-Secret content changes. Core loads its credential and signing
key at startup; external Secret content changes do not automatically roll either
workload. Referencing a new Secret name/key changes the Pod template, but updating
content under the same reference requires an explicit controlled restart. Keep the admission policy and
binding until the executor has stopped and its token is revoked.
