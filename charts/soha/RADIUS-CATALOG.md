# Local RADIUS configuration catalog

This supplements the [managed runtime installation](README.md#optional-managed-radius-runtime).
The installer, not a management form or remote control response, prepares and
approves every catalog entry in each ordinal's retained PVC. Keep the existing
mounts: `snapshot/` is read only at `/var/lib/soha-radius/snapshot`, and `state/`
is writable at `/var/lib/soha-radius/state`. For example, keep `runtime.json`,
`control/`, `config-A/` and `config-B/` below `snapshot/`. Each configuration
directory contains a complete flat approved FreeRADIUS configuration tree and
its private materials; all file paths must match the final container paths.

Protect runtime JSON as root-owned regular 0600. Every protected path and every
ancestor through `/` must be root owned, non-symlink and not group/other writable.
A root-owned leaf under a replaceable parent is rejected. `/tmp`, a sticky bit,
and a test-directory name provide no exception. Keep native temporary/run files
in the chart's separate emptyDirs, not among protected catalog materials.

## Catalog fields

`installation.configurationCatalog` accepts locally approved entries (at most
64), with unique `material.reference` values. Each `material` contains all seven
configuration contract fields: `reference`, `treeHash`, `nasSharedSecretRef`,
`eapServerCertificateRef`, `eapServerKeyRef`, `eapCARef`, `hooksAttested`. Selection
compares the **entire** material, not only its reference or tree hash. Secret
references are identifiers, not secret values and not a file-download request.
The installer must bind them to the reviewed local files and Core approval.

Each entry also supplies `directory`, unprefixed `treeSHA256`, `hooks`,
`environment`, `materials` (absolute file path to unprefixed SHA-256), and
`certificates` (absolute certificate paths used for validity bounds).
`material.treeHash` is `sha256:` followed by the same digest as `treeSHA256`;
`hooks.configurationSHA256` is the unprefixed digest. The hook attestation must
match the approved socket, routes, nonce attribute and managed environment names.
The boolean in an example does not attest that hooks were actually reviewed.

Common control TLS certificate, key and CA paths must all appear in the base
`installation.materials` allowlist. Their file hashes and protected paths are
checked before the control client consumes them. Entry material hashes augment
that base map and cannot override a common path with a different hash. Each
entry's `SOHA_RADIUS_CONTROL_CERT_FILE`, `SOHA_RADIUS_CONTROL_KEY_FILE` and
`SOHA_RADIUS_CONTROL_CA_FILE` must equal the fixed `control` paths, and
`SOHA_RADIUS_RUNTIME_ID` must equal `control.runtimeId`. The child's
`SOHA_RADIUS_CONTROL_URL` must be a valid HTTPS origin; it may differ from the
supervisor control URL when separately approved. `SOHA_RADIUS_NAS_ID` must match
the selected lease's NAS identity. Include any other child environment required
by the reviewed flat tree; secret values belong in approved files, not inline.

With a catalog, **omit** the legacy base `configurationDir`,
`configurationSHA256`, `hooks`, `environment`, `certificates`, and
`control.configuration`. Mixing non-empty single-snapshot fields with the
catalog is rejected. Keep the base approved owner, binary/binarySHA256,
stateDir/socket, freeradUID/freeradGID, stopGraceSeconds, maxStates and maxPending
settings independently configured; those are not moved into each entry.

## Non-runnable A/B excerpt

The following is a **partial JSON illustration, not an installable runtime.json**.
Every `REPLACE_WITH_*` hash is intentionally invalid. It omits required base
installation settings and contains no certificate, private key or shared secret
bytes. Replace placeholders only after reviewing the real selected image,
protected files, hashes, hook behavior and Core configuration approvals. Do not
copy these identities or `hooksAttested: true` as evidence of approval.

```json
{
  "installation": {
    "materials": {
      "/var/lib/soha-radius/snapshot/control/client.crt": "REPLACE_WITH_CONTROL_CERT_FILE_SHA256",
      "/var/lib/soha-radius/snapshot/control/client.key": "REPLACE_WITH_CONTROL_KEY_FILE_SHA256",
      "/var/lib/soha-radius/snapshot/control/ca.crt": "REPLACE_WITH_CONTROL_CA_FILE_SHA256"
    },
    "configurationCatalog": [
      {
        "material": {
          "reference": "approved-A",
          "treeHash": "sha256:REPLACE_WITH_A_TREE_64_LOWER_HEX",
          "nasSharedSecretRef": "secretref:nas-A",
          "eapServerCertificateRef": "secretref:eap-cert-A",
          "eapServerKeyRef": "secretref:eap-key-A",
          "eapCARef": "secretref:eap-ca-A",
          "hooksAttested": true
        },
        "directory": "/var/lib/soha-radius/snapshot/config-A",
        "treeSHA256": "REPLACE_WITH_A_TREE_64_LOWER_HEX",
        "hooks": {
          "configurationSHA256": "REPLACE_WITH_A_TREE_64_LOWER_HEX",
          "socket": "/var/lib/soha-radius/state/hook.sock",
          "routes": [
            "/admit",
            "/challenge",
            "/finish"
          ],
          "nonceAttribute": "control:Tmp-String-8",
          "controlOnly": true,
          "epochEnvironment": "SOHA_RADIUS_PROCESS_EPOCH",
          "socketEnvironment": "SOHA_RADIUS_HOOK_SOCKET"
        },
        "environment": {
          "SOHA_RADIUS_RUNTIME_ID": "radius-member:installer-member-0",
          "SOHA_RADIUS_NAS_ID": "installer-nas-id",
          "SOHA_RADIUS_CONTROL_URL": "https://control.example.invalid",
          "SOHA_RADIUS_CONTROL_CERT_FILE": "/var/lib/soha-radius/snapshot/control/client.crt",
          "SOHA_RADIUS_CONTROL_KEY_FILE": "/var/lib/soha-radius/snapshot/control/client.key",
          "SOHA_RADIUS_CONTROL_CA_FILE": "/var/lib/soha-radius/snapshot/control/ca.crt"
        },
        "materials": {
          "/var/lib/soha-radius/snapshot/config-A/eap.key": "REPLACE_WITH_A_EAP_KEY_FILE_SHA256"
        },
        "certificates": [
          "/var/lib/soha-radius/snapshot/control/client.crt",
          "/var/lib/soha-radius/snapshot/config-A/eap.crt",
          "/var/lib/soha-radius/snapshot/config-A/eap-ca.crt"
        ]
      },
      {
        "material": {
          "reference": "approved-B",
          "treeHash": "sha256:REPLACE_WITH_B_TREE_64_LOWER_HEX",
          "nasSharedSecretRef": "secretref:nas-B",
          "eapServerCertificateRef": "secretref:eap-cert-B",
          "eapServerKeyRef": "secretref:eap-key-B",
          "eapCARef": "secretref:eap-ca-B",
          "hooksAttested": true
        },
        "directory": "/var/lib/soha-radius/snapshot/config-B",
        "treeSHA256": "REPLACE_WITH_B_TREE_64_LOWER_HEX",
        "hooks": {
          "configurationSHA256": "REPLACE_WITH_B_TREE_64_LOWER_HEX",
          "socket": "/var/lib/soha-radius/state/hook.sock",
          "routes": [
            "/admit",
            "/challenge",
            "/finish"
          ],
          "nonceAttribute": "control:Tmp-String-8",
          "controlOnly": true,
          "epochEnvironment": "SOHA_RADIUS_PROCESS_EPOCH",
          "socketEnvironment": "SOHA_RADIUS_HOOK_SOCKET"
        },
        "environment": {
          "SOHA_RADIUS_RUNTIME_ID": "radius-member:installer-member-0",
          "SOHA_RADIUS_NAS_ID": "installer-nas-id",
          "SOHA_RADIUS_CONTROL_URL": "https://control.example.invalid",
          "SOHA_RADIUS_CONTROL_CERT_FILE": "/var/lib/soha-radius/snapshot/control/client.crt",
          "SOHA_RADIUS_CONTROL_KEY_FILE": "/var/lib/soha-radius/snapshot/control/client.key",
          "SOHA_RADIUS_CONTROL_CA_FILE": "/var/lib/soha-radius/snapshot/control/ca.crt"
        },
        "materials": {
          "/var/lib/soha-radius/snapshot/config-B/eap.key": "REPLACE_WITH_B_EAP_KEY_FILE_SHA256"
        },
        "certificates": [
          "/var/lib/soha-radius/snapshot/control/client.crt",
          "/var/lib/soha-radius/snapshot/config-B/eap.crt",
          "/var/lib/soha-radius/snapshot/config-B/eap-ca.crt"
        ]
      }
    ]
  },
  "control": {
    "url": "https://control.example.invalid",
    "runtimeId": "radius-member:installer-member-0",
    "memberId": "installer-member-0",
    "poolId": "radius-pool:installer-pool",
    "certificateFile": "/var/lib/soha-radius/snapshot/control/client.crt",
    "keyFile": "/var/lib/soha-radius/snapshot/control/client.key",
    "caFile": "/var/lib/soha-radius/snapshot/control/ca.crt",
    "serverName": "control.example.invalid"
  }
}
```

Both entries must be locally pre-approved and pass catalog layout/path validation
at startup, even if A is selected first. The selected tree and material hashes
are checked before its child starts.
Any extra configuration/material references required by the approved tree must
already exist locally and pass validation. This excerpt is not a substitute for
a complete flat configuration or its attestation.

## Digest and A → B transition

Run the read-only helper against the final protected directory, in an environment
where its complete path has the required ownership and permissions:

```sh
/usr/local/bin/radius-runtime --configuration-digest /var/lib/soha-radius/snapshot/config-A
/usr/local/bin/radius-runtime --configuration-digest /var/lib/soha-radius/snapshot/config-B
```

Each command prints 64 lowercase hexadecimal characters. Do not combine
`--configuration-digest` with an explicit `--config`. This mode does not read
runtime JSON, contact Core, execute FreeRADIUS, write files, sign a digest, set
`hooksAttested` or grant approval. The tree hash binds relative file names,
modes and exact bytes; a generic directory checksum is not a substitute.
Independent installer review still approves the complete material and hooks.

Prepare both A and B before the runtime starts. When a process epoch selects A,
subsequent leases must continue to match A. To select B, first drain/stop through
Core and obtain exact child-stopped and wait-completion proof. Then start the
next process epoch with the same pre-approved local catalog; its initial Core
lease may select B only by the complete matching material, tree hash and NAS
identity. Changing the configuration while A is running is not a hot reload.
No remote file pull, runtime JSON rewrite or Kubernetes Pod-template edit is
needed for switching between already approved A and B. Readiness or a Helm
replica change alone is not stopped/wait proof. A newly approved file/catalog
change requires a separate installer maintenance procedure; do not mutate a
running snapshot or retained state to bypass these checks.
