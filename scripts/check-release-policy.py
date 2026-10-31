#!/usr/bin/env python3
"""Check the repository's narrow explicit-publication workflow policy."""
from pathlib import Path
import re


GUARD = "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main' && inputs.publish"


def section(text, header):
    lines = text.splitlines()
    found = [i for i, line in enumerate(lines) if line == header]
    if len(found) != 1:
        raise ValueError("publication policy section is missing or duplicated")
    start = found[0]
    indent = len(header) - len(header.lstrip())
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line.strip() and not line.lstrip().startswith("#") and len(line) - len(line.lstrip()) <= indent:
            break
        end += 1
    return lines[start + 1:end]


def verify_policy(text):
    # GitHub parses the workflow YAML itself. This additional check deliberately
    # accepts only the reviewed direct job guard, never an implicit default.
    job = section(text, "  publish:")
    guards = [line.removeprefix("    if:").strip() for line in job if line.startswith("    if:")]
    if guards != [GUARD]:
        raise ValueError("publish must require manual dispatch, main and the explicit publish input")
    dispatch = "\n".join(section(text, "  workflow_dispatch:"))
    publish_input = "\n".join(section(dispatch, "      publish:"))
    for key, value in (("type", "boolean"), ("default", "false"), ("required", "true")):
        matches = re.findall(r"^        " + key + r":\s*(\S+)\s*$", publish_input, re.M)
        if matches != [value]:
            raise ValueError("publish input must be an explicit boolean defaulting to false")


if __name__ == "__main__":
    workflow = Path(__file__).resolve().parents[1] / ".github/workflows/helm-repo.yml"
    verify_policy(workflow.read_text())
    print("Helm explicit publication policy: PASS")
