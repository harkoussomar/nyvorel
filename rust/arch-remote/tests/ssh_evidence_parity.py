#!/usr/bin/env python3
"""SSH journal and host-key evidence parity with disposable command output."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def rust(path):
    result = subprocess.run([str(RUST), "ssh-evidence", str(path)], capture_output=True, text=True, check=True, timeout=15)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def normalize(value):
    copy = json.loads(json.dumps(value))
    copy["auth"].pop("checked_at")
    return copy


def expected():
    return {"auth": controller.ssh_recent_auth_state(), "fingerprint": controller.ssh_host_fingerprint()}


def main():
    controller.RUST_SSH_EVIDENCE_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-ssh-evidence-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        journal = root / "journal.jsonl"
        journalctl = fake_bin / "journalctl"
        journalctl.write_text('#!/bin/sh\n/bin/cat "$ARCH_REMOTE_JOURNAL"\n', encoding="utf-8")
        journalctl.chmod(0o755)
        keygen = fake_bin / "ssh-keygen"
        keygen.write_text('#!/bin/sh\necho "256 SHA256:testfingerprint root@host (ED25519)"\n', encoding="utf-8")
        keygen.chmod(0o755)
        key = root / "ssh_host_ed25519_key.pub"
        key.write_text("fixture", encoding="utf-8")
        controller.SSH_HOST_ED25519_PUB = key
        old_path = os.environ.get("PATH")
        os.environ["PATH"] = f"{fake_bin}:/usr/bin:/bin"
        os.environ["ARCH_REMOTE_JOURNAL"] = str(journal)
        try:
            cases = [
                [],
                [{"__REALTIME_TIMESTAMP": "10000000", "MESSAGE": "Accepted publickey for test from 100.101.102.103 port 22 ssh2"}],
                [{"__REALTIME_TIMESTAMP": "10000000", "MESSAGE": "Accepted publickey for test from 100.101.102.103 port 22 ssh2"},
                 {"__REALTIME_TIMESTAMP": "20000000", "MESSAGE": "Accepted publickey for test from 2001:db8::1 port 555 ssh2"},
                 {"__REALTIME_TIMESTAMP": "30000000", "MESSAGE": "Failed password for invalid user"}],
            ]
            for case in cases:
                journal.write_text("\n".join(json.dumps(item) for item in case) + "\n", encoding="utf-8")
                assert normalize(rust(key)) == normalize(expected())
                auth, fingerprint = controller.snapshot_ssh_evidence()
                assert normalize({"auth": auth, "fingerprint": fingerprint}) == normalize(expected())
            bad = root / "bad"
            bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
            bad.chmod(0o755)
            controller.RUST_SSH_EVIDENCE_BIN = bad
            auth, fingerprint = controller.snapshot_ssh_evidence()
            assert normalize({"auth": auth, "fingerprint": fingerprint}) == normalize(expected())
        finally:
            if old_path is None:
                os.environ.pop("PATH", None)
            else:
                os.environ["PATH"] = old_path
            os.environ.pop("ARCH_REMOTE_JOURNAL", None)
    print("Arch Remote SSH evidence and fallback parity: passed")


if __name__ == "__main__":
    main()
