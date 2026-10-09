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

assert data.get("schema") == 2, "unsupported dependency contract schema"
assert data.get("product") == "Nyvorel", "wrong dependency contract product"

platform = data.get("platform")
assert isinstance(platform, dict)
assert platform.get("os_id") == "arch"
assert platform.get("session_type") == "wayland"
assert platform.get("compositor") == "hyprland"

policy = data.get("policy")
assert isinstance(policy, dict)
assert policy.get("automatic_installation") is False

bootstrap = policy.get("bootstrap")
assert isinstance(bootstrap, dict)
assert bootstrap == {
    "mode": "plan-only",
    "package_manager": "pacman",
    "repository_probe": "pacman -Si",
    "default_scope": "required",
    "optional_selection": "explicit-id-only",
    "refresh_sync_database": False,
    "package_mutation": False,
    "aur_helper_invocation": False,
}

classes = ("required", "optional", "test-only")
all_ids: set[str] = set()
by_id: dict[str, dict] = {}

for class_name in classes:
    entries = data.get(class_name)
    assert isinstance(entries, list) and entries, f"{class_name} must be non-empty"

    for entry in entries:
        assert isinstance(entry, dict), class_name

        dep_id = entry.get("id")
        assert isinstance(dep_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]*", dep_id), dep_id
        assert dep_id not in all_ids, f"duplicate dependency id: {dep_id}"
        all_ids.add(dep_id)
        by_id[dep_id] = entry

        command_keys = [
            key
            for key in ("commands_any_of", "commands_all_of", "files_any_of", "files_all_of")
            if isinstance(entry.get(key), list) and entry.get(key)
        ]
        assert len(command_keys) == 1, f"{dep_id}: exactly one runtime selector required"
        commands = entry[command_keys[0]]
        assert len(commands) == len(set(commands)), f"{dep_id}: duplicate command"
        for command in commands:
            assert isinstance(command, str) and command
            if command_keys[0].startswith("files_"):
                assert Path(command).is_absolute() and ".." not in Path(command).parts, dep_id
            else:
                assert "/" not in command, f"{dep_id}: commands must be executable names"

        package_keys = [
            key
            for key in ("arch_packages_any_of", "arch_packages_all_of")
            if isinstance(entry.get(key), list) and entry.get(key)
        ]
        assert len(package_keys) == 1, f"{dep_id}: exactly one package selector required"
        packages = entry[package_keys[0]]
        assert len(packages) == len(set(packages)), f"{dep_id}: duplicate package hint"
        for package in packages:
            assert isinstance(package, str) and package
            assert "/" not in package, f"{dep_id}: invalid package hint"

        evidence = entry.get("evidence")
        assert isinstance(evidence, list) and evidence, f"{dep_id}: evidence"
        for raw in evidence:
            assert isinstance(raw, str) and raw
            assert (root / raw).exists(), f"{dep_id}: evidence path does not exist: {raw}"

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
assert not (required_minimum - required_ids)

assert "commands_any_of" in by_id["quickshell"]
assert by_id["quickshell"]["commands_any_of"] == ["qs", "quickshell"]

assert "commands_all_of" in by_id["coreutils"]
assert "commands_all_of" in by_id["clipboard-wayland"]
assert "commands_all_of" in by_id["screenshots"]
assert "arch_packages_all_of" in by_id["screenshots"]
assert "commands_any_of" in by_id["image-processing"]
assert "commands_all_of" in by_id["process-tools"]

assert "commands_any_of" in by_id["container-runtime"]
assert "commands_all_of" in by_id["clean-machine-bootstrap"]
assert "arch_packages_all_of" in by_id["clean-machine-bootstrap"]

print(f"required_dependencies={len(data['required'])}")
print(f"optional_dependencies={len(data['optional'])}")
print(f"test_only_dependencies={len(data['test-only'])}")
print(f"total_dependencies={len(all_ids)}")
print("contract_schema=2")
print("bootstrap_policy=plan-only")
PY

echo "PASS  dependency contract schema, selectors, evidence, and bootstrap policy"
