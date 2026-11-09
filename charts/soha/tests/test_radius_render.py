"""RADIUS render checks; fixture pins/material are not installation approval."""
import json
from pathlib import Path
import unittest
from test_outpost_render import render

class RadiusRender(unittest.TestCase):
    def values(self):
        return json.loads(Path(__file__).with_name("radius-values.json").read_text())

    def test_disabled_unchanged(self):
        result = render("soha", {})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("radius", result.stdout.lower())

    def test_private_members_and_pins(self):
        values = self.values()
        result = render("soha", values)
        self.assertEqual(result.returncode, 0, result.stderr)
        runtime = next(d for d in result.stdout.split("\n---\n") if "kind: StatefulSet" in d)
        for required in ["replicas: 0", "podManagementPolicy: Parallel", "whenDeleted: Retain", "whenScaled: Retain",
                         "automountServiceAccountToken: false", "subPath: snapshot", "subPath: state",
                         "readOnly: true", "name: data", "drop: [ALL]", "add: [CHOWN, SETUID, SETGID, KILL]"]:
            self.assertIn(required, runtime)
        for absent in ["secretName:", "projected:", "readinessProbe:", "hostPath:", "hostNetwork:"]:
            self.assertNotIn(absent, runtime)
        init = runtime.split("      initContainers:", 1)[1].split("      containers:", 1)[0]
        self.assertNotIn("name: data", init)
        self.assertIn('chown "$(id -u freerad):$(id -g freerad)" /run/freeradius', init)
        self.assertLess(init.index("chmod 0700 /run/freeradius"), init.index("chown "))
        self.assertIn("chmod 1777 /tmp", init)
        services = [d for d in result.stdout.split("\n---\n") if "kind: Service\n" in d and "radius" in d]
        self.assertEqual(len(services), 1)
        self.assertIn("clusterIP: None", services[0])
        executor = next(d for d in result.stdout.split("\n---\n") if "config.json:" in d)
        line = next(l.strip()[len("config.json: "):] for l in executor.splitlines() if l.strip().startswith("config.json:"))
        cfg = json.loads(json.loads(line))
        self.assertEqual(cfg["slots"], values["radiusExecutor"]["slots"])
        self.assertEqual(cfg["baseUrl"], values["radiusExecutor"]["baseUrl"])
        for required in ["radius_runtime_executors:", "radius_slots:", "service_account:", "credential_ref:", "tree_hash:",
                         "nas_binding_id:", "resources: [statefulsets/scale]", "resourceNames: [\"soha-radius\"]",
                         "variables.desiredReplicas <= 2", "failurePolicy: Fail", "validationActions: [Deny]",
                         "/app/radius-runtime-executor", 'args: ["--config", "/etc/soha-radius-executor/config.json"]']:
            self.assertIn(required, result.stdout)
        self.assertNotIn("verbs: [create", result.stdout)

    def test_failure_boundaries(self):
        mutations = [
            lambda v: v["radiusRuntime"].update(replicas=3),
            lambda v: v["radiusRuntime"]["members"][1].update(runtimeId="radius-member:lab-0"),
            lambda v: v["radiusRuntime"]["members"][1].update(credentialRef="secretref:radius-0"),
            lambda v: v["radiusExecutor"]["slots"][0].update(uid=""),
            lambda v: v["radiusExecutor"]["slots"][0].update(templateDigest="unpinned"),
            lambda v: v["radiusExecutor"]["slots"][0].update(serviceAccount="other"),
            lambda v: v["radiusExecutor"]["slots"][0].update(maxReplicas=3),
            lambda v: v["radiusExecutor"]["slots"][0]["members"][1].update(endpoint="shared:1812"),
            lambda v: v["radiusExecutor"].update(baseUrl="http://core.example"),
            lambda v: v["radiusExecutor"]["slots"][0]["configurations"][0]["material"].update(hooksAttested=False),
        ]
        for mutate in mutations:
            v = self.values(); mutate(v)
            self.assertNotEqual(render("soha", v).returncode, 0, str(v))
        self.assertNotEqual(render("soha", self.values(), supported=False).returncode, 0)

    def test_dedicated_token(self):
        v = self.values()
        from test_outpost_render import OutpostRender
        v.update(OutpostRender().executor())
        v["radiusExecutor"]["existingTokenSecret"] = v["outpostExecutor"]["existingTokenSecret"]
        self.assertNotEqual(render("soha", v).returncode, 0)

    def test_proxy_and_generic_token_isolation(self):
        v = self.values()
        v.update(json.loads(Path(__file__).with_name("proxy-values.json").read_text()))
        v["radiusExecutor"]["existingTokenSecret"] = v["proxyExecutor"]["existingTokenSecret"]
        self.assertNotEqual(render("soha", v).returncode, 0)
        v = self.values(); v["radiusExecutor"]["existingTokenSecret"] = "soha-config"
        self.assertNotEqual(render("soha", v).returncode, 0)

    def test_executor_only_and_start(self):
        v = self.values(); v["radiusRuntime"]["enabled"] = False; v["radiusExecutor"]["start"] = True
        result = render("soha", v)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("replicas: 1", result.stdout)
        self.assertNotIn("kind: StatefulSet", result.stdout)

if __name__ == "__main__":
    unittest.main()
