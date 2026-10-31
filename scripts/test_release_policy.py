import importlib.util
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("release_policy", HERE / "check-release-policy.py")
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)
WORKFLOW = (HERE.parent / ".github/workflows/helm-repo.yml").read_text()


class ReleasePolicyTests(unittest.TestCase):
    def test_current_workflow_requires_explicit_publication(self):
        POLICY.verify_policy(WORKFLOW)

    def test_main_push_cannot_publish(self):
        with self.assertRaises(ValueError):
            POLICY.verify_policy(WORKFLOW.replace(POLICY.GUARD, "github.event_name != 'pull_request'"))

    def test_dispatch_on_arbitrary_branch_cannot_publish(self):
        with self.assertRaises(ValueError):
            POLICY.verify_policy(WORKFLOW.replace(" && github.ref == 'refs/heads/main'", ""))

    def test_dispatch_without_explicit_input_cannot_publish(self):
        with self.assertRaises(ValueError):
            POLICY.verify_policy(WORKFLOW.replace(" && inputs.publish", ""))

    def test_input_cannot_default_to_publication(self):
        with self.assertRaises(ValueError):
            POLICY.verify_policy(WORKFLOW.replace("        default: false", "        default: true"))

    def test_unguarded_publish_is_rejected(self):
        with self.assertRaises(ValueError):
            POLICY.verify_policy(WORKFLOW.replace("    if: " + POLICY.GUARD + "\n", ""))


if __name__ == "__main__":
    unittest.main()
