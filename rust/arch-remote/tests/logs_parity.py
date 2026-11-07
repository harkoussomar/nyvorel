#!/usr/bin/env python3
"""Deterministic journal fixtures for the Arch Remote log reader."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
SECRET = "aVeryPrivatePairingBearer123"


def run(program, env, *args):
    command = [sys.executable, str(program)] if program == PYTHON else [str(program)]
    result = subprocess.run([*command, "logs", *args], env=env, capture_output=True, text=True, check=True, timeout=12)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-logs-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        journal = fake_bin / "journalctl"
        journal.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$ARCH_REMOTE_ARGS"\ncat "$ARCH_REMOTE_FIXTURE"\n', encoding="utf-8")
        journal.chmod(0o755)
        fixture = root / "journal.jsonl"
        args_file = root / "args.txt"
        env = os.environ.copy()
        env.update(PATH=f"{fake_bin}:/usr/bin:/bin", ARCH_REMOTE_FIXTURE=str(fixture), ARCH_REMOTE_ARGS=str(args_file), TZ="UTC")
        records = [
            {"MESSAGE": "Failed password and invalid user", "PRIORITY": "3", "__REALTIME_TIMESTAMP": "1700000000000000", "SYSLOG_IDENTIFIER": "sshd"},
            {"MESSAGE": f"pair_url=https://private.ts.net/pair#t={SECRET}", "PRIORITY": "4", "__REALTIME_TIMESTAMP": "1700000001000000"},
            {"MESSAGE": f"direct https://private.ts.net/pair#t={SECRET} endpoint", "PRIORITY": "5", "__REALTIME_TIMESTAMP": "1700000002000000"},
            {"MESSAGE": f"token fragment #t={SECRET}", "PRIORITY": "6", "__REALTIME_TIMESTAMP": "1700000003000000"},
            {"MESSAGE": "Failed to capture cursor; failed to bind; address already in use", "PRIORITY": "4", "__REALTIME_TIMESTAMP": "1700000004000000"},
            {"MESSAGE": "health(warnable=dns-forward-failing): ok; home derp changing; auth expired", "PRIORITY": "6", "__REALTIME_TIMESTAMP": "1700000005000000"},
            {"MESSAGE": "Traceback: upstream connection refused", "PRIORITY": "2", "__REALTIME_TIMESTAMP": "1700000006000000"},
        ]
        fixture.write_text("\n".join(json.dumps(item) for item in records) + "\nnot-json\n", encoding="utf-8")
        cases = [
            ("sshd", "all", "1h", ""), ("sshd", "warning", "6h", "failed"),
            ("tailscaled", "all", "24h", ""), ("wayvnc", "error", "15m", ""),
            ("wayvnc", "all", "bad-window", ""), ("lan-share", "all", "1h", ""),
            ("sshd", "--errors"), ("unknown",), (),
        ]
        for case in cases:
            python = run(PYTHON, env, *case)
            python_args = args_file.read_text() if args_file.exists() else ""
            rust = run(RUST, env, *case)
            rust_args = args_file.read_text() if args_file.exists() else ""
            assert rust_args == python_args, case
            assert rust == python, (case, rust, python)
            assert SECRET not in json.dumps(rust), case
        empty = root / "empty"
        empty.mkdir()
        (empty / "dirname").symlink_to("/usr/bin/dirname")
        env["PATH"] = str(empty)
        assert run(RUST, env, "sshd") == run(PYTHON, env, "sshd")
        print("Arch Remote bounded logs and secret-redaction parity: passed")


if __name__ == "__main__":
    main()
