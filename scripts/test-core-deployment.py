#!/usr/bin/env python3
"""Offline Core probes, PostgreSQL TLS and dsh URL render regressions."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


CHART = Path(__file__).resolve().parents[1] / "charts" / "soha"


def render(values):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as source:
        json.dump(values, source)
        source.flush()
        return subprocess.run(
            ["helm", "template", "test", str(CHART), "-f", source.name],
            capture_output=True, text=True,
        )


class CoreDeployment(unittest.TestCase):
    def documents(self, values):
        result = render(values)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.split("---")

    def deployment(self, documents, container):
        return next(doc for doc in documents
                    if "kind: Deployment\n" in doc and f"- name: {container}\n" in doc)

    def assert_probes(self, core):
        self.assertIn("livenessProbe:\n            tcpSocket:\n              port: http", core)
        self.assertIn("readinessProbe:\n            httpGet:\n              path: /readyz\n              port: http", core)
        self.assertIn("startupProbe:\n            httpGet:\n              path: /readyz\n              port: http\n            periodSeconds: 5\n            failureThreshold: 60", core)
        self.assertNotIn("path: /healthz", core)

    def test_default_probes_and_no_ca(self):
        docs = self.documents({})
        core = self.deployment(docs, "soha")
        self.assert_probes(core)
        self.assertIn('sslmode: "disable"', "\n".join(docs))
        self.assertNotIn("PGSSLROOTCERT", core)
        self.assertNotIn("postgres-ca", core)
        self.assertIn("checksum/config:", core)
        self.assertIn("claimName: soha-data", core)

    def test_supported_external_tls_modes(self):
        for mode in ("disable", "allow", "prefer", "require", "verify-ca", "verify-full"):
            with self.subTest(mode=mode):
                docs = self.documents({"postgres": {"enabled": False, "host": "db.example", "sslMode": mode}})
                self.assertIn(f'sslmode: "{mode}"', "\n".join(docs))
                core = self.deployment(docs, "soha")
                self.assert_probes(core)
                self.assertNotIn("wait-for-postgres", core)
                self.assertNotIn("PGSSLROOTCERT", core)

    def test_external_ca_shared_only_with_network_control(self):
        docs = self.documents({
            "postgres": {"enabled": False, "host": "db.example", "sslMode": "verify-full",
                         "existingCASecret": "external-postgres-ca", "caKey": "root.pem"},
            "networkRuntime": {"enabled": True, "existingTLSSecret": "network-runtime-tls"},
        })
        for container in ("soha", "network-control"):
            deployment = self.deployment(docs, container)
            self.assertIn("name: PGSSLROOTCERT\n              value: /run/soha-postgres/ca.crt", deployment)
            self.assertIn("mountPath: /run/soha-postgres\n              readOnly: true", deployment)
            self.assertIn('secretName: "external-postgres-ca"', deployment)
            self.assertIn('items: [{key: "root.pem", path: ca.crt}]', deployment)
        control = self.deployment(docs, "network-control")
        self.assertIn('SOHA_NETWORK_CONTROL_DATABASE_SSLMODE\n              value: "verify-full"', control)
        ingest = self.deployment(docs, "ingest")
        self.assertNotIn("PGSSLROOTCERT", ingest)
        self.assertNotIn("postgres-ca", ingest)
        self.assertNotIn("SOHA_INGEST_DATABASE_SSLMODE", ingest)
        self.assertIn('SOHA_INGEST_DATABASE_HOST\n              value: "soha-ingest-postgres"', ingest)

    def test_invalid_tls_values_rejected(self):
        for values in ({"sslMode": "invalid"}, {"sslMode": ""}, {"sslMode": True}, {"caKey": ""}):
            with self.subTest(values=values):
                result = render({"postgres": values})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("schema", result.stderr)

    def dsh(self, base_path, **overrides):
        docs = self.documents({
            "image": {"tag": "candidate"},
            "config": {"basePath": base_path, "security": {"protectedDurableStorage": True}},
            "dshRuntime": {"enabled": True, "image": "example.invalid/dsh:test",
                           "existingSecret": "dsh-token", "allowInsecureHTTP": True, **overrides},
        })
        return self.deployment(docs, "dsh")

    def test_dsh_urls_follow_base_path(self):
        for base_path, normalized in (("/api/v1", "/api/v1"), ("/custom/v2/", "/custom/v2"),
                                      ("custom/v2", "/custom/v2"), ("///custom/v2///", "/custom/v2"),
                                      ("/", ""), ("", "")):
            with self.subTest(base_path=base_path):
                dsh = self.dsh(base_path)
                for suffix in ("model/v1", "tools"):
                    self.assertIn(f'"http://soha:8080{normalized}/copilot/dsh/{suffix}"', dsh)

    def test_dsh_explicit_overrides_win_independently(self):
        dsh = self.dsh("/custom/", gatewayURL="https://gateway.example/model")
        self.assertIn('SOHA_DSH_GATEWAY_URL, value: "https://gateway.example/model"', dsh)
        self.assertIn('SOHA_DSH_CORE_CALLBACK_URL, value: "http://soha:8080/custom/copilot/dsh/tools"', dsh)
        dsh = self.dsh("/custom/", callbackURL="https://callback.example/tools")
        self.assertIn('SOHA_DSH_GATEWAY_URL, value: "http://soha:8080/custom/copilot/dsh/model/v1"', dsh)
        self.assertIn('SOHA_DSH_CORE_CALLBACK_URL, value: "https://callback.example/tools"', dsh)


if __name__ == "__main__":
    unittest.main()
