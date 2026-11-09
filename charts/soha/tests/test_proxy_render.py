"""Focused Proxy install checks; fixture UIDs are never installation pins."""
import copy
import json
import stat
import subprocess
import tempfile
import textwrap
from pathlib import Path
import unittest
from test_outpost_render import render

FIXTURE = Path(__file__).with_name("proxy-values.json")
class ProxyRender(unittest.TestCase):
    def values(self):
        return json.loads(FIXTURE.read_text())
    def test_core_only(self):
        r = render("soha", {})
        self.assertEqual(r.returncode, 0, r.stderr)
        for absent in ["proxy-runtime", "proxy-executor", "proxy_slots:"]:
            self.assertNotIn(absent, r.stdout)
    def test_installation(self):
        r = render("soha", self.values())
        self.assertEqual(r.returncode, 0, r.stderr)
        for required in ["kind: StatefulSet", "replicas: 0", "subPathExpr: $(POD_NAME)",
                         "whenScaled: Retain", "automountServiceAccountToken: false",
                         "SOHA_PROXY_MANAGED_DEPLOYMENT", "SOHA_PROXY_INGRESS_CERT_FILE",
                         "SOHA_PROXY_HEALTH_LISTEN", "value: 0.0.0.0:9091",
                         "containerPort: 9091", "httpGet:", "path: /readyz", "port: health",
                         "resources: [statefulsets/scale]", "verbs: [get, update]",
                         "has(object.spec.replicas) ? object.spec.replicas : 0",
                         "variables.desiredReplicas <= 2",
                         "proxy_runtime_executors:", "endpoint_id:", "/app/proxy-runtime-executor"]:
            self.assertIn(required, r.stdout)
        runtime = next(doc for doc in r.stdout.split("---") if "kind: StatefulSet" in doc)
        self.assertNotIn("tcpSocket:", runtime)
        for service in (doc for doc in r.stdout.split("---") if "\nkind: Service\n" in doc):
            self.assertNotIn("9091", service)
            self.assertNotIn("name: health", service)
        line = next(x.strip()[len("config.json: "):] for x in r.stdout.splitlines() if x.strip().startswith("config.json: "))
        config = json.loads(json.loads(line))
        self.assertNotIn("endpoints", config["slots"][0])
        self.assertEqual(config["slots"][0]["members"][1]["runtimeId"], "runtime-1")
        self.assertNotIn("verbs: [create", r.stdout)
    def test_slot_policy_exact_targets(self):
        for two_slots in (False, True):
            v = self.values()
            slots = v["proxyExecutor"]["slots"]
            if two_slots:
                second = copy.deepcopy(slots[0])
                second.update(id="second-slot", namespace="other", name="other-proxy", maxReplicas=1)
                second["members"] = [{"instanceId": "other-proxy-0", "runtimeId": "other-runtime", "ordinal": 0}]
                slots.append(second)
            result = render("soha", v)
            self.assertEqual(result.returncode, 0, result.stderr)
            line = next(line.strip()[len("- expression: "):] for line in result.stdout.splitlines()
                        if line.strip().startswith("- expression: ") and "request.namespace" in line)
            expression = json.loads(line)
            expected = [f'(request.namespace == {json.dumps(slot["namespace"])} && request.name == {json.dumps(slot["name"])} && (request.resource.resource == {json.dumps("statefulsets" if slot["workloadKind"] == "StatefulSet" else "deployments")}) && variables.desiredReplicas >= 0 && variables.desiredReplicas <= {slot["maxReplicas"]})' for slot in slots]
            self.assertEqual(expression, " || ".join(expected))

    def test_start_and_scale_zero(self):
        v=self.values();v["proxyExecutor"]["start"]=True
        r=render("soha",v);self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn("replicas: 1",r.stdout)
        self.assertIn("replicas: 0",r.stdout)
    def test_fail_closed(self):
        mutations=[
          lambda v:v["proxyRuntime"].update(replicas=3),
          lambda v:v["proxyRuntime"]["members"][1].update(existingSecret="proxy-member-0"),
          lambda v:v["proxyRuntime"]["members"][1].update(runtimeId="runtime-0"),
          lambda v:v["proxyExecutor"]["slots"][0].update(uid=""),
          lambda v:v["proxyExecutor"]["slots"][0].update(templateDigest="unpinned"),
          lambda v:v["proxyExecutor"]["slots"][0]["members"][1].update(runtimeId="runtime-0"),
          lambda v:v["proxyExecutor"].update(controlPlaneUrl="http://core.example"),
          lambda v:v["proxyExecutor"]["slots"][0].update(maxReplicas=3),
        ]
        for mutate in mutations:
            v=self.values();mutate(v)
            self.assertNotEqual(render("soha",v).returncode,0)
        self.assertNotEqual(render("soha",self.values(),supported=False).returncode,0)

class PrivateTLSRender(unittest.TestCase):
    def documents(self, values):
        result = render("soha", values)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.split("---")

    def assert_private_copy(self, doc, source, private, child, path, keys):
        init, rest = doc.split("      initContainers:", 1)[1].split("      containers:", 1)
        main, volumes = rest.split("      volumes:", 1)
        self.assertIn(f"name: {source}\n              mountPath: /secret-source", init)
        self.assertIn("readOnly: true", init)
        self.assertIn(f"name: {private}\n              mountPath: /private", init)
        self.assertNotIn(f"name: {source}\n", main)
        self.assertIn(f"name: {private}\n              mountPath: {path}\n              subPath: {child}\n              readOnly: true", main)
        self.assertIn(f"name: {private}\n          emptyDir:\n            medium: Memory", volumes)
        for expected in ["umask 077", f"chmod 0700 /private/{child}", 'test -s "/secret-source/$key"',
                         f'chmod 0600 "/private/{child}/$key"', "readOnlyRootFilesystem: true",
                         "allowPrivilegeEscalation: false"]:
            self.assertIn(expected, init)
        self.assertIn("runAsUser: 10001", doc)
        self.assertIn("runAsNonRoot: true", doc)
        self.assertIn("fsGroup: 10001", doc)
        self.assertNotIn("runAsUser: 0", doc)
        self.assertNotIn("privileged: true", doc)
        self.assertNotIn("hostPath:", volumes)
        # Run the rendered shell with disposable dummy material; verify every file
        # mode and fail-closed behavior rather than accepting render text alone.
        script = textwrap.dedent(init.split("            - |\n", 1)[1].split("          volumeMounts:", 1)[0])
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src, dest = root / "source", root / "private"
            src.mkdir(); dest.mkdir()
            for key in keys:
                (src / key).write_text("dummy-" + key)
            (src / "unselected").write_text("must not copy")
            script = script.replace("/secret-source", str(src)).replace("/private", str(dest))
            result = subprocess.run(["/bin/sh", "-ec", script], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = dest / child
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
            self.assertEqual(set(p.name for p in target.iterdir()), set(keys))
            for key in keys:
                self.assertEqual((target / key).read_text(), "dummy-" + key)
                self.assertEqual(stat.S_IMODE((target / key).stat().st_mode), 0o600)
            (src / keys[-1]).unlink()
            result = subprocess.run(["/bin/sh", "-ec", script], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("dummy-", result.stdout + result.stderr)
        return init

    def test_default_disabled_unchanged(self):
        docs = self.documents({})
        app = next(doc for doc in docs if "# Source: soha/templates/app-deployment.yaml" in doc)
        self.assertIn("name: wait-for-postgres", app)
        for absent in ["prepare-query-tls", "network-ingest-query-tls", "medium: Memory", "prepare-runtime-tls"]:
            self.assertNotIn(absent, "".join(docs))
        external = self.documents({"postgres": {"enabled": False, "host": "db.example"}})
        app = next(doc for doc in external if "# Source: soha/templates/app-deployment.yaml" in doc)
        self.assertNotIn("initContainers:", app)

    def test_query_with_bundled_and_external_postgres(self):
        for enabled in [True, False]:
            docs = self.documents({"postgres": {"enabled": enabled, "host": "db.example"},
                "config": {"networkIngestQuery": {"enabled": True, "url": "https://ingest.example:8083",
                    "serverName": "ingest.example", "existingSecret": "query-tls"}}})
            app = next(doc for doc in docs if "# Source: soha/templates/app-deployment.yaml" in doc)
            self.assertEqual("name: wait-for-postgres" in app, enabled)
            self.assert_private_copy(app, "network-ingest-query-tls-source", "network-ingest-query-tls",
                                     "query", "/run/soha-network-ingest-query", ["ca.crt", "tls.crt", "tls.key"])

    def test_network_runtimes(self):
        docs = self.documents({"networkRuntime": {"enabled": True, "existingTLSSecret": "network-tls"}})
        for component, path in [("network-control", "/run/soha-network-control"), ("network-ingest", "/run/soha-ingest")]:
            doc = next(d for d in docs if "kind: Deployment" in d and f"app.kubernetes.io/component: {component}\n" in d)
            self.assert_private_copy(doc, "runtime-tls-source", "runtime-tls", "tls", path,
                                     ["tls.crt", "tls.key", "client-ca.crt"])

    def test_proxy_identity_and_raw_sample(self):
        values = json.loads(FIXTURE.read_text())
        docs = self.documents(values)
        chart = next(doc for doc in docs if "kind: StatefulSet" in doc)
        raw = (Path(__file__).resolve().parents[4] / "soha/deploy/proxy-runtime/statefulset.example.yaml").read_text()
        for doc in [chart, raw]:
            init = self.assert_private_copy(doc, "identity-source", "identities", "identity", "/run/identity",
                ["control.crt", "control.key", "control-ca.crt", "ingest.crt", "ingest.key", "ingest-ca.crt",
                 "ingress.crt", "ingress.key", "controller-secret"])
            self.assertIn("subPathExpr: $(POD_NAME)", init)
            self.assertIn("name: POD_NAME", init)
            self.assertIn("fieldPath: metadata.name", init)
            self.assertNotIn("cp -R", init)
            self.assertIn("whenScaled: Retain", doc)
            self.assertIn("replicas: 0", doc)
            self.assertIn("port: health", doc)

    def test_persistent_state_mount_policy_and_raw_sample(self):
        docs = self.documents(json.loads(FIXTURE.read_text()))
        chart = next(doc for doc in docs if "kind: StatefulSet" in doc)
        raw = (Path(__file__).resolve().parents[4] / "soha/deploy/proxy-runtime/statefulset.example.yaml").read_text()
        for doc in [chart, raw]:
            with self.subTest(source="chart" if doc == chart else "raw"):
                pod_security = doc.split("      securityContext:\n", 1)[1].split("      initContainers:", 1)[0]
                self.assertIn("fsGroup: 10001\n        fsGroupChangePolicy: OnRootMismatch", pod_security)
                self.assertIn("runAsUser: 10001", pod_security)
                self.assertIn("runAsGroup: 10001", pod_security)
                self.assertIn("runAsNonRoot: true", pod_security)
                self.assertIn("- name: SOHA_PROXY_STATE_DIR\n              value: /var/lib/soha-proxy-runtime/state\n", doc)
                self.assertIn("- name: state\n              mountPath: /var/lib/soha-proxy-runtime\n", doc)
                self.assertIn("whenDeleted: Retain\n    whenScaled: Retain", doc)
                self.assertNotIn("fsGroupChangePolicy: Always", doc)
                # Existing state is validated by the runtime, never silently
                # repaired by an init container or discarded during upgrade.
                init = doc.split("      initContainers:", 1)[1].split("      containers:", 1)[0]
                self.assertNotIn("- name: state\n", init)
                self.assertNotIn("configuration-floor.json", init)

if __name__ == "__main__":
    unittest.main()
