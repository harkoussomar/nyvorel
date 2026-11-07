#!/usr/bin/env python3
"""Read-only deployment inventory parity, including missing files and fallback."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def rust(path):
    result = subprocess.run([str(RUST), "integrity", str(path)], text=True,
                            capture_output=True, check=True, timeout=12)
    assert not result.stderr, result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_INTEGRITY_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-integrity-") as directory:
        root = Path(directory)
        manifest = root / "deployment.json"
        controller.DEPLOYMENT_MANIFEST = manifest
        assert rust(manifest) == controller.deployment_integrity_posture()
        assert controller.snapshot_deployment_integrity_posture() == controller.deployment_integrity_posture()
        manifest.write_text('{bad', encoding="utf-8")
        assert rust(manifest) == controller.deployment_integrity_posture()
        manifest.write_text(json.dumps({"revision": "test", "files": []}), encoding="utf-8")
        assert rust(manifest) == controller.deployment_integrity_posture()
        good = root / "name with spaces.txt"
        good.write_bytes(b"known content\n")
        digest = hashlib.sha256(good.read_bytes()).hexdigest()
        missing = root / "missing.txt"
        rows = [{"path": str(good), "sha256": digest, "mode": "0644"},
                {"path": str(missing), "sha256": "0" * 64, "mode": "0600"}]
        manifest.write_text(json.dumps({"revision": "test", "files": rows[:1]}), encoding="utf-8")
        assert rust(manifest) == controller.deployment_integrity_posture()
        assert rust(manifest)["ok"] is True
        manifest.write_text(json.dumps({"revision": "test", "files": [{**rows[0], "mode": "0600"}]}),
                            encoding="utf-8")
        assert rust(manifest) == controller.deployment_integrity_posture()
        for changed in (False, True):
            if changed:
                good.write_bytes(b"changed content\n")
            manifest.write_text(json.dumps({"revision": "test", "generated_at": 123.0, "files": rows}),
                                encoding="utf-8")
            expected = controller.deployment_integrity_posture()
            assert rust(manifest) == expected
            assert controller.snapshot_deployment_integrity_posture() == expected
        bad = root / "invalid-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_INTEGRITY_BIN = bad
        assert controller.snapshot_deployment_integrity_posture() == controller.deployment_integrity_posture()
    print("Arch Remote deployment integrity and fallback parity: passed")


if __name__ == "__main__":
    main()
