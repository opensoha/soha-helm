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


class AppHostingDynamic(unittest.TestCase):
    def values(self):
        return {
            "appGateway": {
                "enabled": True,
                "appsDomain": "apps.example.com",
                "publicCoreUrl": "https://soha.example.com",
                "existingSecret": "soha-app-gateway-auth",
                "s3": {"endpoint": "https://minio.internal:9000", "bucket": "apps",
                       "existingSecret": "soha-app-gateway-s3"},
            },
            "appHostingDynamic": {
                "enabled": True,
                "runtimeNamespace": "soha-runtime",
                "buildNamespace": "soha-build",
                "appDataExistingSecret": "soha-app-data",
                "maxPoolBytes": 67108864,
                "appDataCIDR": "10.42.8.16/32",
                "knativePrivateIngress": [
                    {"namespace": "kourier-system", "podLabels": {"app": "3scale-kourier-gateway"}},
                    {"namespace": "knative-serving", "podLabels": {"app": "activator"}},
                ],
                "buildClientImage": "registry.example/build-client@sha256:" + "a" * 64,
                "nodeBaseImage": "registry.example/node@sha256:" + "b" * 64,
                "pythonBaseImage": "registry.example/python@sha256:" + "c" * 64,
                "registryRepository": "registry.example/apps",
                "buildRegistrySecret": "soha-build-registry",
                "buildkitAddress": "tcp://buildkit.soha-build:1234",
                "buildkitTLSSecret": "soha-buildkit-tls",
                "buildSourceOrigin": "https://minio.example.com",
            },
        }

    def test_disabled_by_default(self):
        result = render({})
        self.assertEqual(result.returncode, 0, result.stderr)
        for absent in ("app-hosting", "SOHA_APP_HOSTING_", "SOHA_APP_GATEWAY_RUNTIME_NAMESPACE"):
            self.assertNotIn(absent, result.stdout)

    def test_enabled_wires_env_rbac_and_network_policy(self):
        result = render(self.values())
        self.assertEqual(result.returncode, 0, result.stderr)
        for required in (
            "kind: ServiceAccount", "kind: Role", "kind: RoleBinding", "kind: NetworkPolicy",
            "serviceAccountName: soha-app-hosting", "automountServiceAccountToken: true",
            'namespace: "soha-runtime"', 'namespace: "soha-build"',
            "resources: [\"services\"]", "resources: [\"jobs\"]", "resources: [\"pods\"]",
            'cidr: "10.42.8.16/32"', 'kubernetes.io/metadata.name: "knative-serving"',
            'namespace: "kourier-system"', "app: 3scale-kourier-gateway", "app: activator",
            "app.kubernetes.io/component: app-gateway", "name: soha-app-hosting-private-0",
            'value: "67108864"', "SOHA_APP_GATEWAY_RUNTIME_NAMESPACE",
            "SOHA_APP_GATEWAY_RUNTIME_CLUSTER_DOMAIN",
        ):
            self.assertIn(required, result.stdout)
        for env in ("SOHA_APP_HOSTING_RUNTIME_NAMESPACE", "SOHA_APP_HOSTING_BUILD_NAMESPACE",
                    "SOHA_APP_HOSTING_BUILD_CLIENT_IMAGE", "SOHA_APP_HOSTING_NODE_BASE_IMAGE",
                    "SOHA_APP_HOSTING_PYTHON_BASE_IMAGE", "SOHA_APP_HOSTING_REGISTRY_REPOSITORY",
                    "SOHA_APP_HOSTING_BUILD_REGISTRY_SECRET", "SOHA_APP_HOSTING_BUILDKIT_ADDRESS",
                    "SOHA_APP_HOSTING_BUILDKIT_TLS_SECRET", "SOHA_APP_HOSTING_BUILD_SOURCE_ORIGIN",
                    "SOHA_APP_HOSTING_APP_DATA_ADMIN_DSN", "SOHA_APP_HOSTING_APP_DATA_KEY",
                    "SOHA_APP_HOSTING_APP_DATA_MAX_POOL_BYTES"):
            self.assertIn(env, result.stdout)
        self.assertNotIn("SOHA_APP_HOSTING_BUILD_RUNTIME_CLASS", result.stdout)
        self.assertIn("secretKeyRef:", result.stdout)

    def test_network_policies_are_retained_by_helm(self):
        result = render(self.values())
        self.assertEqual(result.returncode, 0, result.stderr)
        policies = [doc for doc in result.stdout.split("\n---\n")
                    if "kind: NetworkPolicy\n" in doc]
        self.assertEqual(len(policies), 3)
        for policy in policies:
            self.assertIn("helm.sh/resource-policy: keep", policy)

    def test_runtime_policy_scrapes_autoscaler_on_tcp_9090_only(self):
        result = render(self.values())
        self.assertEqual(result.returncode, 0, result.stderr)
        policy = next(doc for doc in result.stdout.split("\n---\n")
                      if "kind: NetworkPolicy\n" in doc
                      and 'namespace: "soha-runtime"' in doc
                      and "app.kubernetes.io/managed-by: soha-app-hosting" in doc)
        ingress = policy.split("  ingress:\n", 1)[1].split("  egress:\n", 1)[0]
        _, routes, metrics = ingress.split("    - from:\n")
        self.assertNotIn("app: autoscaler", routes)
        expected = "".join(
            "        - namespaceSelector:\n"
            "            matchLabels:\n"
            f'              kubernetes.io/metadata.name: "{namespace}"\n'
            "          podSelector:\n"
            "            matchLabels:\n"
            "              app: autoscaler\n"
            "              app.kubernetes.io/component: autoscaler\n"
            "              app.kubernetes.io/name: knative-serving\n"
            for namespace in ("kourier-system", "knative-serving")
        )
        self.assertEqual(metrics, expected + "      ports:\n        - protocol: TCP\n          port: 9090\n")

    def test_fail_closed(self):
        mutations = (
            lambda v: v["appHostingDynamic"].update(appDataExistingSecret=""),
            lambda v: v["appHostingDynamic"].update(buildNamespace="soha-runtime"),
            lambda v: v["appHostingDynamic"].update(runtimeNamespace="default"),
            lambda v: v["appGateway"].update(decisionCacheTtl="5s"),
            lambda v: v["appHostingDynamic"].update(maxPoolBytes=0),
            lambda v: v["appHostingDynamic"].update(appDataCIDR="0.0.0.0/0"),
            lambda v: v["appHostingDynamic"].update(appDataCIDR="10.0.0.0/8"),
            lambda v: v["appHostingDynamic"].update(knativePrivateIngress=[]),
            lambda v: v["appHostingDynamic"].update(knativePrivateIngress=[
                {"namespace": "soha-runtime", "podLabels": {"app": "activator"}}
            ]),
            lambda v: v["appHostingDynamic"].update(buildSourceOrigin="http://git.example.com"),
            lambda v: v["appHostingDynamic"].update(nodeBaseImage="registry.example/node:22"),
        )
        for mutate in mutations:
            values = self.values()
            mutate(values)
            self.assertNotEqual(render(values).returncode, 0)


if __name__ == "__main__":
    unittest.main()
