#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

CONTRACT="dependencies/arch.json"
[[ -s "$CONTRACT" ]] || die "dependency contract missing: $CONTRACT"

python3 - "$CONTRACT" "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys

contract_path = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()
data = json.loads(contract_path.read_text())

assert data.get("schema") == 1, "unsupported dependency contract schema"
assert data.get("product") == "Nyvorel", "wrong dependency contract product"

platform = data.get("platform")
assert isinstance(platform, dict)
assert platform.get("os_id") == "arch"
assert platform.get("session_type") == "wayland"
assert platform.get("compositor") == "hyprland"

policy = data.get("policy")
assert isinstance(policy, dict)
assert policy.get("automatic_installation") is False

classes = ("required", "optional", "test-only")
all_ids: set[str] = set()

for class_name in classes:
    entries = data.get(class_name)
    assert isinstance(entries, list) and entries, f"{class_name} must be non-empty"

    for entry in entries:
        assert isinstance(entry, dict), class_name

        dep_id = entry.get("id")
        assert isinstance(dep_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]*", dep_id), dep_id
        assert dep_id not in all_ids, f"duplicate dependency id: {dep_id}"
        all_ids.add(dep_id)

        commands = entry.get("commands_any_of")
        assert isinstance(commands, list) and commands, f"{dep_id}: commands_any_of"
        assert len(commands) == len(set(commands)), f"{dep_id}: duplicate command"
        for command in commands:
            assert isinstance(command, str) and command
            assert "/" not in command, f"{dep_id}: commands must be executable names"

        packages = entry.get("arch_packages_any_of")
        assert isinstance(packages, list) and packages, f"{dep_id}: arch_packages_any_of"
        assert len(packages) == len(set(packages)), f"{dep_id}: duplicate package hint"
        for package in packages:
            assert isinstance(package, str) and package
            assert "/" not in package, f"{dep_id}: invalid package hint"

        evidence = entry.get("evidence")
        assert isinstance(evidence, list) and evidence, f"{dep_id}: evidence"
        for raw in evidence:
            assert isinstance(raw, str) and raw
            path = root / raw
            assert path.exists(), f"{dep_id}: evidence path does not exist: {raw}"

        if class_name == "optional":
            feature = entry.get("feature")
            assert isinstance(feature, str) and feature.strip(), f"{dep_id}: optional feature missing"
        else:
            reason = entry.get("reason")
            assert isinstance(reason, str) and reason.strip(), f"{dep_id}: reason missing"

required_ids = {entry["id"] for entry in data["required"]}
required_minimum = {
    "bash",
    "python",
    "hyprland",
    "quickshell",
    "systemd-user",
    "dbus-session",
    "git",
}
missing = sorted(required_minimum - required_ids)
assert not missing, f"required core dependency id(s) missing: {missing}"

print(f"required_dependencies={len(data['required'])}")
print(f"optional_dependencies={len(data['optional'])}")
print(f"test_only_dependencies={len(data['test-only'])}")
print(f"total_dependencies={len(all_ids)}")
PY

echo "PASS  dependency contract schema, classes, evidence, and core baseline"
