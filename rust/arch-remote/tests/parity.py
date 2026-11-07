#!/usr/bin/env python3
"""Compare native fast paths with the installed Python contract in isolated homes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
PYTHON = ROOT / "quickshell/scripts/arch-remote/control_center.py"


def run(program, profile, *args):
    env = os.environ.copy()
    env.update(HOME=str(profile), XDG_RUNTIME_DIR=str(profile / "run"))
    command = [sys.executable, str(program)] if program == PYTHON else [str(program)]
    result = subprocess.run([*command, *args], env=env, capture_output=True, text=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def compare(left, right, *, clock_fields=()):
    def normalized(value):
        if isinstance(value, dict):
            return {key: ("<implementation revision>" if key in
                    {"backend_revision", "current_backend_revision", "cached_backend_revision"}
                    else normalized(item)) for key, item in value.items()}
        if isinstance(value, list):
            return [normalized(item) for item in value]
        return value

    for field in clock_fields:
        left_part, right_part = left, right
        parts = field.split(".")
        for part in parts[:-1]:
            left_part, right_part = left_part[part], right_part[part]
        key = parts[-1]
        assert abs(left_part[key] - right_part[key]) < 2, field
        del left_part[key], right_part[key]
    assert normalized(left) == normalized(right), (left, right)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-remote-parity-") as directory:
        profiles = [Path(directory) / name for name in ("python", "rust")]

        def step(command, *args, clock_fields=()):
            outputs = [run(program, profile, command, *args)
                       for program, profile in zip((PYTHON, RUST), profiles)]
            compare(*outputs, clock_fields=clock_fields)
            return outputs

        step("contract")
        step("snapshot-cache")
        for state in (
            {"schema_version": "bad", "ui_contract": "2.4.1"},
            {"schema_version": 3, "ui_contract": "2.4.1"},
            {"schema_version": 2, "ui_contract": "old"},
            {"schema_version": 2, "ui_contract": "2.4.1", "generated_at": "bad"},
            {"schema_version": 2, "ui_contract": "2.4.1", "generation": 42,
             "generated_at": 0, "backend_revision": "old", "opaque": {"keep": ["exact", 1]}},
        ):
            for profile in profiles:
                path = profile / ".local/state/nyvorel/arch-remote/runtime-state.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(state), encoding="utf-8")
            step("snapshot-cache")
        step("operation-status")
        step("operation-status", "another")
        operations = (
            {"id": "alive", "active": True, "pid": os.getpid(), "phase": "running", "unrecognized": "preserved"},
            {"id": "invalid", "active": True, "pid": "bad", "phase": "running"},
            {"id": "dead", "active": True, "pid": 2147483647, "phase": "running"},
        )
        for operation in operations:
            for profile in profiles:
                path = profile / "run/arch-remote/operation.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(operation), encoding="utf-8")
            clock_fields = ("operation.finished_at", "operation.updated_at") if operation["id"] == "dead" else ()
            python, rust = step("operation-status", operation["id"], clock_fields=clock_fields)
            if operation["id"] == "dead":
                assert (profiles[1] / "run/arch-remote/operation.json").stat().st_mode & 0o777 == 0o600
        print("Arch Remote contract, cache, and operation-status parity: passed")


if __name__ == "__main__":
    main()
