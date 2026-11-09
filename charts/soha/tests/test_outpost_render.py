"""Scoped Helm checks; no cluster or additional Python dependencies."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CAPS = ["--api-versions", "admissionregistration.k8s.io/v1/ValidatingAdmissionPolicy",
        "--api-versions", "admissionregistration.k8s.io/v1/ValidatingAdmissionPolicyBinding"]


def render(chart, values, supported=True):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as source:
        json.dump(values, source)
        source.flush()
        args = ["helm", "template", "test", str(ROOT / "charts" / chart), "-n", "control", "-f", source.name]
        if supported:
            args += CAPS
        return subprocess.run(args, capture_output=True, text=True)


class OutpostRender(unittest.TestCase):
    def agent(self, **extra):
        return {"mode": "outpost", "config": {"controlPlane": {"outpost": {
            "trustKeyId": "old", "trustPublicKey": "test",
            "trustPublicKeys": {"next": "test-next"}}}}, **extra}

    def executor(self):
        return {"outpostExecutor": {"enabled": True, "image": {"repository": "example/core", "tag": "candidate"},
            "controlPlaneUrl": "https://core.example", "executorId": "executor-1", "existingTokenSecret": "dedicated-executor-token",
            "signingKey": {"keyId": "outpost-signing-1", "existingSecret": "dedicated-outpost-signing", "key": "private-key"},
            "slots": [{"id": "slot-1", "outpostId": "outpost-1", "executorId": "executor-1", "namespace": "edge",
                       "name": "outpost", "uid": "fixture-uid", "templateDigest": "sha256:" + "a" * 64,
                       "maxReplicas": 3, "allowAdoption": False, "previousOwnerStopped": False}]}}

    def test_default_core_has_no_executor(self):
        result = render("soha", {})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("outpost-runtime-executor", result.stdout)
        self.assertNotIn("ValidatingAdmissionPolicy", result.stdout)
        for disabled in ["outpost_slots:", "outpost_runtime_executors:", "outpost_signing_key_id:",
                         "SOHA_OUTPOST_SIGNING_PRIVATE_KEY", "outpost-executor-token"]:
            self.assertNotIn(disabled, result.stdout)

    def test_core_and_executor_share_installation_and_secret_reference(self):
        values = self.executor()
        result = render("soha", values)
        self.assertEqual(result.returncode, 0, result.stderr)
        documents = {document.split("# Source: ")[1].splitlines()[0]: document
                     for document in result.stdout.split("---") if "# Source: " in document}
        core_config = documents["soha/templates/app-secret.yaml"]
        core_pod = documents["soha/templates/app-deployment.yaml"]
        slot = values["outpostExecutor"]["slots"][0]
        for field, value in [("id", slot["id"]), ("outpost_id", slot["outpostId"]),
                             ("executor_id", slot["executorId"]), ("namespace", slot["namespace"]),
                             ("name", slot["name"]), ("uid", slot["uid"]),
                             ("template_digest", slot["templateDigest"])]:
            self.assertIn(f'{field}: "{value}"', core_config)
        for field in ["max_replicas: 3", "allow_adoption: false", "previous_owner_stopped: false",
                      "outpost_runtime_executors:", "outpost_slots:",
                      "token_file: /var/run/soha-outpost-executor/token",
                      'outpost_signing_key_id: "outpost-signing-1"',
                      'outpost_signing_private_key: "${SOHA_OUTPOST_SIGNING_PRIVATE_KEY}"']:
            self.assertIn(field, core_config)
        self.assertNotIn('outpostId:', core_config)
        self.assertNotIn('templateDigest:', core_config)
        for reference in ['secretName: "dedicated-executor-token"', 'key: "token"', 'defaultMode: 0440',
                          'mountPath: /var/run/soha-outpost-executor', 'readOnly: true',
                          'name: SOHA_OUTPOST_SIGNING_PRIVATE_KEY', 'name: "dedicated-outpost-signing"',
                          'key: "private-key"', 'fsGroup: 10001']:
            self.assertIn(reference, core_pod)
        self.assertEqual(result.stdout.count('secretName: "dedicated-executor-token"'), 2)
        executor_json_line = next(line.strip().removeprefix("config.json: ") for line in result.stdout.splitlines()
                                  if line.strip().startswith("config.json: "))
        executor_config = json.loads(json.loads(executor_json_line))
        self.assertEqual(executor_config["slots"], values["outpostExecutor"]["slots"])
        self.assertEqual(executor_config["executorId"], values["outpostExecutor"]["executorId"])

    def test_core_signing_reference_and_readonly_group_are_required(self):
        for field in ["keyId", "existingSecret", "key"]:
            values = self.executor()
            values["outpostExecutor"]["signingKey"][field] = ""
            self.assertNotEqual(render("soha", values).returncode, 0)
        values = self.executor()
        values["outpostExecutor"]["signingKey"]["privateKey"] = "forbidden-inline-input"
        self.assertNotEqual(render("soha", values).returncode, 0)
        values = self.executor()
        values["podSecurityContext"] = {"fsGroup": 0}
        self.assertNotEqual(render("soha", values).returncode, 0)

    def test_external_and_soha_replica_ownership(self):
        for owner in ["external", "soha"]:
            with self.subTest(owner=owner):
                result = render("soha-agent", self.agent(replicaCount=2, outpostRuntime={"owner": owner, "accessMode": "ReadWriteMany"}))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("  replicas: 2" in result.stdout, owner == "external")
                self.assertIn("runtime_control_enabled: " + str(owner == "soha").lower(), result.stdout)
                for expected in ["kind: Service", "kind: Deployment", "metadata.uid", "chmod 0700", ".soha/outpost",
                                 "kind: PersistentVolumeClaim", "ReadWriteMany", "trust_public_keys:", "next"]:
                    self.assertIn(expected, result.stdout)
                self.assertNotIn("kind: ClusterRole", result.stdout)
                self.assertNotIn("kind: ClusterRoleBinding", result.stdout)
                self.assertIn("automountServiceAccountToken: false", result.stdout)

    def test_state_and_trust_fail_closed(self):
        for values in [self.agent(persistence={"enabled": False}), self.agent(replicaCount=2, outpostRuntime={"accessMode": "ReadWriteOnce"}),
                       {"mode": "outpost"}]:
            self.assertNotEqual(render("soha-agent", values).returncode, 0)
        values = self.agent()
        values["config"]["controlPlane"]["outpost"] = {"trustPublicKeys": {"next": "test"}}
        self.assertEqual(render("soha-agent", values).returncode, 0)
        values = self.agent(persistence={"enabled": False}, outpostRuntime={"existingStateClaim": "existing-rwx"})
        result = render("soha-agent", values)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kind: PersistentVolumeClaim", result.stdout)
        self.assertIn('claimName: "existing-rwx"', result.stdout)
        result = render("soha-agent", self.agent(outpostRuntime={"owner": "soha", "accessMode": "ReadWriteOnce"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("type: Recreate", result.stdout)

    def test_executor_is_staged_before_start(self):
        values = self.executor()
        result = render("soha", values)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("  replicas: 0", result.stdout)
        values["outpostExecutor"]["start"] = True
        result = render("soha", values)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("  replicas: 0", result.stdout)

    def test_executor_exact_rbac_and_admission(self):
        result = render("soha", self.executor())
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = result.stdout.split("# Source: soha/templates/outpost-executor.yaml")
        selected = "\n".join(part.split("---")[0] for part in manifest[1:])
        for expected in ["resources: [deployments]", "resources: [deployments/scale]", 'resourceNames: ["outpost"]',
                         "verbs: [get, update]", "kind: ValidatingAdmissionPolicy", "failurePolicy: Fail", "validationActions: [Deny]",
                         "system:serviceaccount:control:soha-outpost-executor", 'request.namespace == "edge"',
                         'request.name == "outpost"', "name: desiredReplicas",
                         'expression: "has(object.spec) && has(object.spec.replicas) ? object.spec.replicas : 0"',
                         '(request.namespace == "edge" && request.name == "outpost" && variables.desiredReplicas >= 0 && variables.desiredReplicas <= 3)',
                         'command: ["/app/outpost-runtime-executor"]']:
            self.assertIn(expected, selected)
        for forbidden in ["verbs: [create", "verbs: [patch", "resources: [secrets]", "pods/exec", "ClusterRole"]:
            self.assertNotIn(forbidden, selected)

    def test_executor_rejects_incomplete_or_unsupported_installation(self):
        self.assertNotEqual(render("soha", self.executor(), supported=False).returncode, 0)
        for key, value in [("slots", []), ("controlPlaneUrl", "http://insecure"), ("tokenKey", "execution-runner-token")]:
            values = self.executor()
            values["outpostExecutor"][key] = value
            self.assertNotEqual(render("soha", values).returncode, 0)
        for key, value in [("uid", ""), ("templateDigest", "yaml-hash"), ("maxReplicas", 0), ("executorId", "other")]:
            values = self.executor()
            values["outpostExecutor"]["slots"][0][key] = value
            self.assertNotEqual(render("soha", values).returncode, 0)
        values = self.executor()
        values["outpostExecutor"]["slots"] *= 2
        self.assertNotEqual(render("soha", values).returncode, 0)


if __name__ == "__main__":
    unittest.main()
