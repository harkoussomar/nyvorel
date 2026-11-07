#!/usr/bin/env python3
"""LAN Share security contract parity with a disposable executable."""
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


def rust(binary):
    result = subprocess.run([str(RUST), "lan-share-security", str(binary or "")],
                            text=True, capture_output=True, check=True, timeout=8)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_LAN_SHARE_SECURITY_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-share-security-") as directory:
        root = Path(directory)
        binary = root / "lan-share"
        selected = None
        controller.resolve_lan_share_binary = lambda: selected

        def check():
            expected = controller.lan_share_security_posture()
            assert rust(selected) == expected
            assert controller.snapshot_lan_share_security_posture() == expected
            return expected

        assert check()["ok"] is False
        payload = {"ok": True, "security_revision": "2.1-phase1b1", "session_required": True,
                   "query_token_auth": False, "pairing_requires_verified_private_serve": True,
                   "pin_rate_limit": {"client_max_failures": 3}, "protected_paths": [".ssh", ".config"]}
        selected = str(binary)
        for value in (payload, {**payload, "query_token_auth": True},
                      {**payload, "pin_rate_limit": {"client_max_failures": "4"}}):
            binary.write_text("#!/bin/sh\ncat <<'JSON'\n" + json.dumps(value) + "\nJSON\n", encoding="utf-8")
            binary.chmod(0o755)
            check()
        binary.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        assert check()["ok"] is False
        binary.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        assert check()["ok"] is False
        invalid = root / "invalid-rust"
        invalid.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        invalid.chmod(0o755)
        controller.RUST_LAN_SHARE_SECURITY_BIN = invalid
        assert controller.snapshot_lan_share_security_posture() == controller.lan_share_security_posture()
    print("Arch Remote LAN Share security contract and fallback parity: passed")


if __name__ == "__main__":
    main()
